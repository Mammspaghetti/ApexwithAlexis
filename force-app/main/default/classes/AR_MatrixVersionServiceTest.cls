/**
 * Tests AR_MatrixVersionService.createSnapshot : dénormalisation correcte, JSON du snapshot,
 * incrémentation du compteur de version. Le comportement `without sharing` (garantir l'écriture
 * même sans droits explicites sur AR_Matrix_Version__c) est une garantie de conception non testée
 * ici par un utilisateur restreint — la création d'un User de test dans cet org managé (licences,
 * hiérarchie de rôles) est jugée trop fragile pour ce jalon.
 */
@IsTest
private class AR_MatrixVersionServiceTest {

    @TestSetup
    static void setup() {
        // AB_Account_industry__c = 'IT / Telecoms' est exempté de la règle de sous-secteur obligatoire ;
        // Shipping* requis par TP_Address_Validation. Aucun lien avec le Pricing Tool.
        Account acc = new Account(
            Name = 'Client Snapshot',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Snapshot', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_Nearshore_Referential__c maroc = new AR_Nearshore_Referential__c(
            Name = 'Maroc',
            AR_Seniority__c = 'DEFAULT',
            AR_Daily_Rate__c = 200
        );
        insert maroc;

        // Session 54 : consultant lié (Lookup), en plus du texte libre historique — les deux doivent
        // se retrouver figés dans le snapshot (cf. testCreateSnapshot_firstVersion_denormalizesFields).
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName()
            .get('Consultant')
            .getRecordTypeId();
        cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
            RecordTypeId = consultantRecordTypeId,
            cxsrec__First_name__c = 'Alice',
            cxsrec__Last_name__c = 'MARTIN'
        );
        insert consultant;

        insert new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Annual_Salary__c = 43600,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 700,
            AR_Nego_Price_2__c = 650,
            AR_Nego_Price_3__c = 610,
            AR_Status__c = 'Brouillon',
            // Champs mission Zone 1 (session 17) : doivent être figés dans le snapshot, pas seulement
            // en base sur AR_Price_Matrix__c — sinon la PTF future (buildMatricePrintHTML) ne pourrait
            // pas s'appuyer sur une version immuable pour ces champs.
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Consultant__c = consultant.Id,
            AR_Client_Site__c = 'Paris La Défense',
            AR_Start_Date__c = Date.newInstance(2026, 9, 1),
            AR_End_Date__c = Date.newInstance(2026, 9, 30),
            AR_Number_Of_Days__c = 22,
            // Lookup pays référentiel (session 18) : doit lui aussi être figé dans le snapshot, sinon
            // la traçabilité du pays retenu se perd dès qu'une décision est prise sur la matrice.
            AR_Nearshore_Country__c = maroc.Id
        );
    }

    @IsTest
    static void testCreateSnapshot_firstVersion_denormalizesFields() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_PricingMatrixService.recalculate(matrix.Id);

        Test.startTest();
        Id versionId = AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');
        Test.stopTest();

        AR_Matrix_Version__c version = [
            SELECT AR_Price_Matrix__c, AR_TJM__c, AR_MC2_Percent__c, AR_Corridor_Segment__c, AR_Status__c, AR_Snapshot__c, AR_Snapshot_At__c
            FROM AR_Matrix_Version__c
            WHERE Id = :versionId
        ];
        System.assertEquals(matrix.Id, version.AR_Price_Matrix__c);
        System.assertEquals(700, version.AR_TJM__c);
        System.assertNotEquals(null, version.AR_Snapshot_At__c);
        System.assert(version.AR_Snapshot__c.contains('"snapshotTrigger":"validation"'), 'Le JSON doit porter le déclencheur du snapshot');
        System.assert(version.AR_Snapshot__c.contains('"matrix"'), 'Le JSON doit porter l\'état complet de la matrice');
        System.assert(version.AR_Snapshot__c.contains('"marketReference"'), 'Traçabilité du conseil donné (repères marché affichés à la décision), cf. session 9');
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Consultant_Name__c":"Jean DUPONT"'),
            'Les champs mission Zone 1 (session 17) doivent être figés dans le snapshot, pas seulement en base'
        );
        AR_Price_Matrix__c withConsultant = [SELECT AR_Consultant__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Consultant__c":"' + withConsultant.AR_Consultant__c + '"'),
            'Session 54 : le lookup consultant doit lui aussi être figé dans le snapshot, pas seulement le texte libre historique'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Nego_Price_2__c":650') && version.AR_Snapshot__c.contains('"AR_Nego_Price_3__c":610'),
            'Les prix de négociation 2 et 3 sont figés dans le snapshot avec le reste de la saisie'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Number_Of_Days__c":22'),
            'Les jours ouvrés calculés doivent aussi être figés dans le snapshot'
        );
        AR_Price_Matrix__c withCountry = [SELECT AR_Nearshore_Country__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Nearshore_Country__c":"' + withCountry.AR_Nearshore_Country__c + '"'),
            'Le pays retenu dans le référentiel (session 18) doit être figé dans le snapshot, pas seulement le CJM'
        );

        AR_Price_Matrix__c reloaded = [SELECT AR_Version_Number__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assertEquals(1, reloaded.AR_Version_Number__c);
    }

    @IsTest
    static void testCreateSnapshot_secondCall_incrementsVersionNumber() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];

        AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');

        Test.startTest();
        AR_MatrixVersionService.createSnapshot(matrix.Id, 'derogation_acceptee');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Version_Number__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assertEquals(2, reloaded.AR_Version_Number__c);

        List<AR_Matrix_Version__c> versions = [SELECT Id FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :matrix.Id];
        System.assertEquals(2, versions.size(), 'Chaque validation/décision crée un nouveau snapshot, jamais un écrasement');
    }

    /**
     * Session 22 : la filiation de la chaîne de négociation est figée dans le snapshot, sans que
     * cela change la structure/immutabilité de AR_Matrix_Version__c (décision de conception :
     * pas de remise en cause du modèle existant).
     */
    @IsTest
    static void testCreateSnapshot_includesNegotiationChainFields() {
        AR_Price_Matrix__c root = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_PricingMatrixService.recalculate(root.Id);
        AR_MatrixVersionService.createSnapshot(root.Id, 'validation');
        update new AR_Price_Matrix__c(Id = root.Id, AR_Status__c = 'Validée');

        Id reasonId = insertReasonAndReturnId();
        AR_MatrixChainService.duplicateMatrix(
            root.Id,
            null,
            new List<Id>{ reasonId },
            'Renégociation client'
        );
        AR_Price_Matrix__c child = [
            SELECT Id, AR_Previous_Version__c, AR_Root_Matrix__c, AR_Negotiation_Version__c
            FROM AR_Price_Matrix__c
            WHERE AR_Previous_Version__c = :root.Id
            LIMIT 1
        ];
        AR_PricingMatrixService.recalculate(child.Id);

        Test.startTest();
        Id versionId = AR_MatrixVersionService.createSnapshot(child.Id, 'validation');
        Test.stopTest();

        AR_Matrix_Version__c version = [SELECT AR_Snapshot__c FROM AR_Matrix_Version__c WHERE Id = :versionId];
        System.assert(
            version.AR_Snapshot__c.contains('"previousVersionId":"' + root.Id + '"'),
            'Le snapshot doit porter le lien de filiation'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"negotiationVersion":2'),
            'Le snapshot doit porter le numéro de version de négociation'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"versionChangeReasons"'),
            'Le snapshot doit porter les motifs du changement de version'
        );
    }

    /**
     * Socle multi-devises (session 24) : le taux figé et les équivalents EUR doivent apparaître
     * dans le snapshot au même titre que le reste — `'matrix' => m` dans createSnapshot sérialise
     * l'intégralité des champs du SELECT, donc les ajouter au SELECT suffit à les figer ici aussi.
     */
    @IsTest
    static void testCreateSnapshot_gbpMatrix_freezesRateAndEurEquivalents() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        update new AR_Price_Matrix__c(Id = matrix.Id, AR_Currency__c = 'GBP');
        AR_PricingMatrixService.recalculate(matrix.Id);

        Test.startTest();
        Id versionId = AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');
        Test.stopTest();

        AR_Matrix_Version__c version = [SELECT AR_Snapshot__c FROM AR_Matrix_Version__c WHERE Id = :versionId];
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Currency_Rate_Applied__c":1.17'),
            'Le taux figé doit apparaître dans le snapshot'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"AR_TJM_EUR_Equivalent__c":819'),
            'L\'équivalent EUR du TJM (700 × 1.17 = 819.00) doit être figé dans le snapshot'
        );
    }

    /**
     * Restitution multi-devises (session 24b) : le repère marché figé dans le snapshot doit porter
     * la devise et le taux GELÉS de la matrice (AR_Currency_Rate_Applied__c), pas un taux résolu à
     * nouveau au moment du snapshot — même garantie que le taux lui-même (session 24), appliquée au
     * repère marché qui en dépend maintenant.
     */
    @IsTest
    static void testCreateSnapshot_gbpMatrix_marketReferenceFrozenWithMatrixCurrency() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        update new AR_Price_Matrix__c(Id = matrix.Id, AR_Currency__c = 'GBP');
        AR_PricingMatrixService.recalculate(matrix.Id);

        Test.startTest();
        Id versionId = AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');
        Test.stopTest();

        AR_Matrix_Version__c version = [SELECT AR_Snapshot__c FROM AR_Matrix_Version__c WHERE Id = :versionId];
        System.assert(
            version.AR_Snapshot__c.contains('"marketReference"'),
            'Le repère marché doit toujours être présent dans le snapshot'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"currencyCode":"GBP"'),
            'Le repère marché figé doit porter la devise de la matrice, pas EUR par défaut'
        );
        System.assert(
            version.AR_Snapshot__c.contains('"isConverted":true'),
            'Une matrice GBP implique des repères convertis, marqués comme tels dans le snapshot'
        );
    }

    private static Id insertReasonAndReturnId() {
        AR_Reason__c reason = new AR_Reason__c(
            Name = 'Motif Snapshot',
            AR_Applies_To_Version__c = true,
            AR_Applies_To_Derogation__c = false,
            AR_Active__c = true
        );
        insert reason;
        return reason.Id;
    }

    /** Session 239b : les périodes de frais OM entrent dans le snapshot (requête de AR_MatrixVersionService). */
    @IsTest
    static void testCreateSnapshot_includesFeePeriods() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = matrix.Id,
                AR_Fee_Periods__c = '[{"days":180,"feeIk":12,"feeMeals":0,"feeLodging":0,"feeOmOther":0}]'
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Id versionId = AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');

        AR_Matrix_Version__c version = [SELECT AR_Snapshot__c FROM AR_Matrix_Version__c WHERE Id = :versionId];
        System.assert(
            version.AR_Snapshot__c.contains('"AR_Fee_Periods__c"'),
            'Le snapshot doit porter les périodes de frais OM : ' + version.AR_Snapshot__c
        );
    }

    @IsTest
    static void testCreateSnapshot_freezesRplsrFields() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        matrix.AR_RPLSR_Enabled__c = true;
        matrix.AR_RPLSR_Days_Per_Month__c = 18.17;
        matrix.AR_RPLSR_Days_Sold__c = 208.96;
        matrix.AR_RPLSR_Days_Produced__c = 197;
        matrix.AR_RPLSR_Plan__c = '{"v":1,"mois":[]}';
        update matrix;

        Id versionId = AR_MatrixVersionService.createSnapshot(matrix.Id, 'validation');

        String snapshot = [SELECT AR_Snapshot__c FROM AR_Matrix_Version__c WHERE Id = :versionId].AR_Snapshot__c;
        System.assert(snapshot.contains('"AR_RPLSR_Enabled__c":true'), 'Mode figé');
        System.assert(snapshot.contains('"AR_RPLSR_Days_Per_Month__c":18.17'), 'Base figée');
        System.assert(snapshot.contains('"AR_RPLSR_Days_Sold__c":208.96'), 'Jours vendus figés');
        System.assert(snapshot.contains('"AR_RPLSR_Days_Produced__c":197'), 'Jours produits figés');
        System.assert(snapshot.contains('AR_RPLSR_Plan__c'), 'Plan figé');
    }
}