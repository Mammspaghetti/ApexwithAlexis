/**
 * Tests de AR_PositionStatusTrigger / AR_ValidatedMatrixSyncService.handlePositions (session 175) : un besoin Connexys
 * qui quitte Open perd ses entrées « Matrice validée », qui reviennent à sa réouverture ; une erreur de notre code ne
 * doit jamais empêcher d'enregistrer le besoin. Les entrées sont créées par la VRAIE synchro (via AR_PriceMatrixTrigger).
 * Chaque test fabrique ses besoins ; jamais de filtre sur Name (AutoNumber continus de l'org).
 */
@isTest
private class AR_PositionStatusTriggerTest {
    private static final String INTERVIEW2_RT_DEV_NAME = 'Interview2';

    @testSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_StepMatrixLink_Auto_Link_Enabled__c = false,
            AR_StepMatrixLink_Check_Enabled__c = false,
            AR_StepMatrixLink_Require_Empty_Enabled__c = false,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Max_Per_Run__c = 100,
            AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Working_Days_Per_Year__c = 218
        );
    }

    // ---------- Fabriques ----------

    private static cxsrec__cxsPosition__c newPosition(String label, String status) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(Name = 'Besoin ' + label, cxsrec__Status__c = status);
        insert position;
        return position;
    }

    private static AR_Price_Matrix__c newMatrix(cxsrec__cxsPosition__c position, String status, Id rootId, Integer version, Datetime validatedAt) {
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Status__c = status,
            AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'ACME',
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Root_Matrix__c = rootId,
            AR_Negotiation_Version__c = version,
            AR_Version_Number__c = 1,
            AR_Validated_At__c = validatedAt
        );
        insert matrix;
        return matrix;
    }

    private static AR_Price_Matrix__c validated(cxsrec__cxsPosition__c position) {
        return newMatrix(position, 'Validée', null, 1, Datetime.now().addDays(-2));
    }

    private static void setStatus(cxsrec__cxsPosition__c position, String status) {
        update new cxsrec__cxsPosition__c(Id = position.Id, cxsrec__Status__c = status);
    }

    private static List<AR_Validated_Matrix__c> entriesOf(Id positionId) {
        return [
            SELECT Id, Name, AR_Price_Matrix__c, AR_Root_Key__c
            FROM AR_Validated_Matrix__c
            WHERE AR_Position__c = :positionId
            ORDER BY Name
        ];
    }

    private static void setSync(Boolean enabled) {
        AR_General_Setting__c settings = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        settings.AR_Validated_Matrix_Sync_Enabled__c = enabled;
        update settings;
    }

    // Entrée posée à la main (sans passer par la synchro) : sert de témoin « le code n'a rien recalculé ».
    private static AR_Validated_Matrix__c plantEntry(cxsrec__cxsPosition__c position, AR_Price_Matrix__c matrix) {
        AR_Validated_Matrix__c entry = new AR_Validated_Matrix__c(
            Name = 'témoin', AR_Price_Matrix__c = matrix.Id, AR_Position__c = position.Id,
            AR_Root_Key__c = String.valueOf(matrix.Id), AR_Matrix_Key__c = String.valueOf(matrix.Id)
        );
        insert entry;
        return entry;
    }

    // ---------- Besoin clos : chaque statut de clôture ----------

    @isTest
    static void testEachClosingStatusRemovesTheEntries() {
        for (String closing : new List<String>{ 'Gagné', 'Perdu', 'Supprimé' }) {
            cxsrec__cxsPosition__c position = newPosition(closing, 'Open');
            AR_Price_Matrix__c matrix = validated(position);
            System.assertEquals(1, entriesOf(position.Id).size(), closing + ' : témoin, l\'entrée existe tant que le besoin est Open');

            setStatus(position, closing);

            System.assertEquals(0, entriesOf(position.Id).size(), 'Besoin ' + closing + ' : ses entrées sont supprimées');
            System.assertNotEquals(null, [SELECT Id FROM AR_Price_Matrix__c WHERE Id = :matrix.Id], 'La vraie matrice n\'est jamais touchée');
        }
    }

    @isTest
    static void testOtherNonOpenStatusesAlsoRemoveEntries() {
        // Les autres statuts non Open (Standby, Pourvu...) : l'éligibilité posée en 174 est « besoin Open » ; le
        // trigger rend la liste conforme à cette règle au lieu de la laisser diverger jusqu'au prochain événement.
        cxsrec__cxsPosition__c position = newPosition('Standby', 'Open');
        validated(position);

        setStatus(position, 'Standby');

        System.assertEquals(0, entriesOf(position.Id).size(), 'Besoin non Open : plus d\'entrée');
    }

    @isTest
    static void testOnlyTheClosedPositionIsAffected() {
        cxsrec__cxsPosition__c closed = newPosition('A', 'Open');
        cxsrec__cxsPosition__c stillOpen = newPosition('B', 'Open');
        validated(closed);
        validated(stillOpen);

        setStatus(closed, 'Perdu');

        System.assertEquals(0, entriesOf(closed.Id).size());
        System.assertEquals(1, entriesOf(stillOpen.Id).size(), 'Les entrées d\'un autre besoin ne sont pas touchées');
    }

    // ---------- Réouverture ----------

    @isTest
    static void testReopeningBringsBackOneEntryPerChainLatestValidatedVersion() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        AR_Price_Matrix__c v1 = newMatrix(position, 'Validée', null, 1, Datetime.now().addDays(-10));
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2, Datetime.now().addDays(-5));
        AR_Price_Matrix__c otherChain = validated(position);
        newMatrix(position, 'Brouillon', null, 1, null);
        System.assertEquals(2, entriesOf(position.Id).size(), 'Témoin : deux chaînes, deux entrées');

        setStatus(position, 'Gagné');
        System.assertEquals(0, entriesOf(position.Id).size());
        setStatus(position, 'Open');

        List<AR_Validated_Matrix__c> entries = entriesOf(position.Id);
        System.assertEquals(2, entries.size(), 'Une entrée par chaîne (jamais V1 ET V2 de la même chaîne, jamais le brouillon)');
        Set<Id> matrixIds = new Set<Id>();
        for (AR_Validated_Matrix__c entry : entries) {
            matrixIds.add(entry.AR_Price_Matrix__c);
        }
        System.assert(matrixIds.contains(v2.Id), 'La dernière version validée de la chaîne revient');
        System.assert(!matrixIds.contains(v1.Id), 'Pas la version précédente');
        System.assert(matrixIds.contains(otherChain.Id), 'La seconde chaîne revient aussi');
    }

    @isTest
    static void testReopenedEntryKeepsItsReadableName() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        AR_Price_Matrix__c matrix = newMatrix(position, 'Validée', null, 1, Datetime.newInstance(2026, 10, 13, 12, 0, 0));
        String nameBefore = entriesOf(position.Id)[0].Name;
        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', nameBefore);

        setStatus(position, 'Perdu');
        setStatus(position, 'Open');

        List<AR_Validated_Matrix__c> entries = entriesOf(position.Id);
        System.assertEquals(1, entries.size());
        System.assertEquals(nameBefore, entries[0].Name, 'Libellé identique après réouverture');
        System.assertEquals(matrix.Id, entries[0].AR_Price_Matrix__c);
    }

    @isTest
    static void testReopeningDoesNotBringBackAnExpiredMatrix() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        // Validée il y a 400 jours (> 365 par défaut) : jamais d'entrée, même après une clôture puis une réouverture.
        newMatrix(position, 'Validée', null, 1, Datetime.now().addDays(-400));
        System.assertEquals(0, entriesOf(position.Id).size(), 'Témoin : une matrice expirée n\'a pas d\'entrée');

        setStatus(position, 'Gagné');
        setStatus(position, 'Open');

        System.assertEquals(0, entriesOf(position.Id).size(), 'Réouverture : la matrice expirée ne revient pas');
    }

    // ---------- Changements sans effet ----------

    @isTest
    static void testTransitionBetweenTwoNonOpenStatusesRecomputesNothing() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Gagné');
        AR_Price_Matrix__c matrix = validated(position);
        AR_Validated_Matrix__c witness = plantEntry(position, matrix);

        setStatus(position, 'Perdu');

        System.assertEquals(1, entriesOf(position.Id).size(), 'Gagné → Perdu : aucun recalcul, l\'entrée témoin est intacte');
        System.assertEquals(witness.Id, entriesOf(position.Id)[0].Id);
    }

    @isTest
    static void testUpdateWithoutStatusChangeRecomputesNothing() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        AR_Price_Matrix__c matrix = validated(position);
        AR_Validated_Matrix__c entry = entriesOf(position.Id)[0];
        // Entrée parasite : un recalcul la supprimerait (c'est la chaîne de `matrix`, dont elle n'est pas la gagnante).
        AR_Price_Matrix__c ghostMatrix = newMatrix(position, 'Brouillon', null, 1, null);
        AR_Validated_Matrix__c witness = plantEntry(position, ghostMatrix);

        update new cxsrec__cxsPosition__c(Id = position.Id, Name = 'Besoin renommé');

        System.assertEquals(2, entriesOf(position.Id).size(), 'Pas de changement de statut : aucun recalcul, l\'entrée témoin (' + witness.Id + ') est intacte');
        System.assertEquals(entry.Id, [SELECT Id FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :matrix.Id].Id);
    }

    @isTest
    static void testSwitchOffLeavesEntriesAlone() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        validated(position);
        setSync(false);

        setStatus(position, 'Gagné');

        System.assertEquals(1, entriesOf(position.Id).size(), 'Interrupteur coupé : aucune écriture');
        setSync(true);
        setStatus(position, 'Open');
        setStatus(position, 'Perdu');
        System.assertEquals(0, entriesOf(position.Id).size(), 'Interrupteur rallumé : le suivi reprend');
    }

    @isTest
    static void testNoSettingsRecordDoesNothingAndPositionIsSaved() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        validated(position);
        delete [SELECT Id FROM AR_General_Setting__c];

        setStatus(position, 'Gagné');

        System.assertEquals('Gagné', [SELECT cxsrec__Status__c FROM cxsrec__cxsPosition__c WHERE Id = :position.Id].cxsrec__Status__c);
        System.assertEquals(1, entriesOf(position.Id).size(), 'Sans réglages : synchro désactivée');
    }

    // ---------- Protection : jamais d'erreur vers Connexys ----------

    @isTest
    static void testTechnicalErrorStillSavesThePosition() {
        cxsrec__cxsPosition__c position = newPosition('A', 'Open');
        validated(position);

        AR_ValidatedMatrixSyncService.throwExceptionForTest = true;
        try {
            setStatus(position, 'Gagné');
        } finally {
            AR_ValidatedMatrixSyncService.throwExceptionForTest = false;
        }

        System.assertEquals('Gagné', [SELECT cxsrec__Status__c FROM cxsrec__cxsPosition__c WHERE Id = :position.Id].cxsrec__Status__c,
            'Erreur simulée dans notre code : le besoin est enregistré quand même');
        System.assertEquals(1, entriesOf(position.Id).size(), 'L\'erreur n\'a rien écrit : l\'entrée est inchangée (rattrapage : resyncAll)');

        AR_ValidatedMatrixSyncService.resyncAll();
        System.assertEquals(0, entriesOf(position.Id).size(), 'Le rattrapage rejouable remet la liste en conformité');
    }

    // ---------- Lot ----------

    @isTest
    static void testBulkOf200PositionsCloseAndReopen() {
        List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 200; i++) {
            positions.add(new cxsrec__cxsPosition__c(Name = 'Besoin lot ' + i, cxsrec__Status__c = 'Open'));
        }
        insert positions;
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (cxsrec__cxsPosition__c position : positions) {
            matrices.add(new AR_Price_Matrix__c(
                AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
                AR_Account_Name__c = 'ACME', AR_Consultant_Name__c = 'Jean DUPONT', AR_Negotiation_Version__c = 1,
                AR_Version_Number__c = 1, AR_Validated_At__c = Datetime.now().addDays(-1)
            ));
        }
        insert matrices;
        Set<Id> positionIds = new Map<Id, cxsrec__cxsPosition__c>(positions).keySet();
        System.assertEquals(200, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds], 'Témoin : 200 entrées');

        List<cxsrec__cxsPosition__c> closing = new List<cxsrec__cxsPosition__c>();
        for (cxsrec__cxsPosition__c position : positions) {
            closing.add(new cxsrec__cxsPosition__c(Id = position.Id, cxsrec__Status__c = 'Perdu'));
        }
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        update closing;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds], '200 besoins clos : 0 entrée');
        // Bulkifié : le coût ne dépend pas du nombre de besoins (un code non bulkifié dépasserait 100 requêtes à 200 besoins).
        System.assert(queriesUsed < 40, 'Lot de 200 besoins : requêtes bornées (' + queriesUsed + ')');
        System.assert(dmlUsed < 10, 'Lot de 200 besoins : DML bornés (' + dmlUsed + ')');

        List<cxsrec__cxsPosition__c> reopening = new List<cxsrec__cxsPosition__c>();
        for (cxsrec__cxsPosition__c position : positions) {
            reopening.add(new cxsrec__cxsPosition__c(Id = position.Id, cxsrec__Status__c = 'Open'));
        }
        update reopening;
        System.assertEquals(200, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds], '200 besoins rouverts : 200 entrées');
    }

    // ---------- Steps : la vraie matrice reste ----------

    @isTest
    static void testStepKeepsItsRealMatrixWhenThePositionClosesAndReopens() {
        cxsrec__cxsCandidate__c candidate = new cxsrec__cxsCandidate__c(Name = 'Cand S', cxsrec__First_name__c = 'Cand', cxsrec__Last_name__c = 'S');
        insert candidate;
        cxsrec__cxsPosition__c position = newPosition('S', 'Open');
        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(cxsrec__Position__c = position.Id, cxsrec__Candidate__c = candidate.Id);
        insert jobApp;
        AR_Price_Matrix__c matrix = validated(position);
        Id entryId = entriesOf(position.Id)[0].Id;
        cxsrec__cxsStep__c step = new cxsrec__cxsStep__c(
            cxsrec__Job_application__c = jobApp.Id,
            RecordTypeId = Schema.SObjectType.cxsrec__cxsStep__c.getRecordTypeInfosByDeveloperName().get(INTERVIEW2_RT_DEV_NAME).getRecordTypeId(),
            AR_Validated_Matrix__c = entryId
        );
        insert step;
        System.assertEquals(matrix.Id, [SELECT AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :step.Id].AR_Price_Matrix__c, 'Témoin : le Step a copié la vraie matrice');

        setStatus(position, 'Gagné');

        cxsrec__cxsStep__c afterClose = [SELECT AR_Validated_Matrix__c, AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :step.Id];
        System.assertEquals(null, afterClose.AR_Validated_Matrix__c, 'Champ de la popup vidé (SetNull) quand l\'entrée est supprimée');
        System.assertEquals(matrix.Id, afterClose.AR_Price_Matrix__c, 'Le Step garde sa vraie matrice de prix (source de vérité durable)');

        setStatus(position, 'Open');

        cxsrec__cxsStep__c afterReopen = [SELECT AR_Validated_Matrix__c, AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :step.Id];
        System.assertEquals(matrix.Id, afterReopen.AR_Price_Matrix__c, 'Réouverture : la référence durable est toujours là');
        System.assertEquals(1, entriesOf(position.Id).size(), 'Réouverture : l\'entrée est revenue pour les prochains choix');
    }
}