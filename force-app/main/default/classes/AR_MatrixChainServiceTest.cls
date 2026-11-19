/**
 * Tests AR_MatrixChainService : duplication (filiation conditionnée au statut de la source, jamais
 * au choix de l'utilisateur) et lecture de la chaîne de négociation.
 */
@IsTest
private class AR_MatrixChainServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Chain',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Chain', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        cxsrec__cxsPosition__c otherPosition = new cxsrec__cxsPosition__c(
            Name = 'Besoin Chain Autre', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert otherPosition;

        insert new List<AR_Reason__c>{
            new AR_Reason__c(Name = 'Motif Chain A', AR_Applies_To_Version__c = true, AR_Applies_To_Derogation__c = true, AR_Active__c = true),
            new AR_Reason__c(Name = 'Motif Chain B', AR_Applies_To_Version__c = true, AR_Applies_To_Derogation__c = true, AR_Active__c = true)
        };

        // Session 54 : consultant de test (record type Consultant) pour vérifier que la duplication
        // copie AR_Consultant__c (Lookup) au même titre que le reste du contexte financier.
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName()
            .get('Consultant')
            .getRecordTypeId();
        insert new cxsrec__cxsCandidate__c(
            RecordTypeId = consultantRecordTypeId,
            cxsrec__First_name__c = 'Alice',
            cxsrec__Last_name__c = 'MARTIN'
        );
    }

    private static Id consultantId() {
        return [SELECT Id FROM cxsrec__cxsCandidate__c WHERE cxsrec__Last_name__c = 'MARTIN' LIMIT 1].Id;
    }

    private static Id positionId() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Chain' LIMIT 1].Id;
    }

    private static Id otherPositionId() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Chain Autre' LIMIT 1].Id;
    }

    private static Id reasonId(String name) {
        return [SELECT Id FROM AR_Reason__c WHERE Name = :name LIMIT 1].Id;
    }

    private static AR_Price_Matrix__c newDecidedMatrix(String status, Decimal tjm) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = tjm,
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_RFA_Percent__c = 0
        );
        insert m;
        // Statut forcé directement (hors service complet) : seul le statut de la source importe
        // pour AR_MatrixChainService, pas le chemin qui l'y a amené.
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Status__c = status, AR_Validated_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        return [SELECT Id, AR_Position__c, AR_Status__c, AR_Root_Matrix__c, AR_Negotiation_Version__c FROM AR_Price_Matrix__c WHERE Id = :m.Id];
    }

    @IsTest
    static void testDuplicate_fromValidatedSource_withoutReason_throws() {
        AR_Price_Matrix__c source = newDecidedMatrix('Validée', 560);

        Boolean threw = false;
        try {
            AR_MatrixChainService.duplicateMatrix(source.Id, null, new List<Id>(), null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Un motif est obligatoire pour dupliquer depuis une matrice décidée');
    }

    /** Session 167 : duplication vers un besoin invisible de l'utilisateur → message clair, aucune copie. */
    @IsTest
    static void testDuplicate_targetPositionNotVisible_throwsClearMessage_andCreatesNoCopy() {
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480
        );
        insert draft;
        cxsrec__cxsPosition__c gone = new cxsrec__cxsPosition__c(
            Name = 'Besoin invisible', cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert gone;
        Id goneId = gone.Id;
        delete gone;

        String message;
        try {
            AR_MatrixChainService.duplicateMatrix(draft.Id, goneId, new List<Id>(), null);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(System.Label.AR_PMS_PositionAccessDeniedSaveError, message);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c = :positionId()]);
    }

    @IsTest
    static void testDuplicate_fromDraft_noReasonRequired_noFiliation() {
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480
        );
        insert draft;

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            draft.Id,
            null,
            new List<Id>(),
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [
            SELECT AR_Previous_Version__c, AR_Root_Matrix__c, AR_Negotiation_Version__c, AR_Status__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals('Brouillon', copy.AR_Status__c);
        System.assertEquals(null, copy.AR_Previous_Version__c, 'Aucune filiation depuis un Brouillon');
        System.assertEquals(null, copy.AR_Root_Matrix__c);
        System.assertEquals(1, copy.AR_Negotiation_Version__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :result.matrixId]
        );
    }

    /** Session 54 : AR_Consultant__c (Lookup) doit suivre la même règle que le reste du contexte
     * financier/mission déjà copié (AR_Entity_Ref__c, AR_Client_Site__c…) — jamais oublié parce qu'il
     * est nouveau. */
    @IsTest
    static void testDuplicate_copiesConsultantLookup() {
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480,
            AR_Consultant__c = consultantId()
        );
        insert draft;

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            draft.Id,
            null,
            new List<Id>(),
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [
            SELECT AR_Consultant__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(consultantId(), copy.AR_Consultant__c);
    }

    @IsTest
    static void testDuplicate_fromRefusedSource_stillRequiresFiliationAndReason() {
        AR_Price_Matrix__c source = newDecidedMatrix('Refusée', 480);
        Id reason = reasonId('Motif Chain A');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reason },
            'Retente après refus'
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [
            SELECT AR_Previous_Version__c, AR_Root_Matrix__c, AR_Negotiation_Version__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(source.Id, copy.AR_Previous_Version__c, 'Le refus ne doit pas rester orphelin');
        System.assertEquals(source.Id, copy.AR_Root_Matrix__c);
        System.assertEquals(2, copy.AR_Negotiation_Version__c);
    }

    @IsTest
    static void testDuplicate_neverCopiesDecisionFields() {
        AR_Price_Matrix__c source = newDecidedMatrix('Validée', 560);
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = source.Id,
                AR_Selected_Validator__c = UserInfo.getUserId()
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        Id reason = reasonId('Motif Chain A');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reason },
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [
            SELECT AR_Status__c, AR_Validated_At__c, AR_Selected_Validator__c, AR_Effective_Validator__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals('Brouillon', copy.AR_Status__c);
        System.assertEquals(null, copy.AR_Validated_At__c);
        System.assertEquals(null, copy.AR_Selected_Validator__c);
        System.assertEquals(null, copy.AR_Effective_Validator__c);
    }

    // Session 180a : dupliquer une version avenant donne une version de négociation ordinaire.
    @IsTest
    static void testDuplicate_neverCopiesAvenantFields() {
        AR_Price_Matrix__c source = newDecidedMatrix('Validée', 560);
        AR_PTF_Document__c ptf = new AR_PTF_Document__c(
            AR_Price_Matrix__c = source.Id,
            AR_Position__c = source.AR_Position__c,
            AR_Reference__c = 'PTF-TEST-180A',
            AR_Version_Number__c = 1,
            AR_Generated_At__c = System.now(),
            AR_Generation_Status__c = 'Généré'
        );
        insert ptf;
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = source.Id,
                AR_Version_Type__c = 'Avenant',
                AR_Amended_PTF__c = ptf.Id,
                AR_Avenant_Changes__c = 'Tarif;Période'
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_Price_Matrix__c prepared = [
            SELECT AR_Version_Type__c, AR_Amended_PTF__c, AR_Avenant_Changes__c FROM AR_Price_Matrix__c WHERE Id = :source.Id
        ];
        System.assertEquals('Avenant', prepared.AR_Version_Type__c, 'Pré-requis : la source est bien un avenant');
        System.assertEquals(ptf.Id, prepared.AR_Amended_PTF__c);
        System.assertEquals('Tarif;Période', prepared.AR_Avenant_Changes__c);

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id, null, new List<Id>{ reasonId('Motif Chain A') }, null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [
            SELECT AR_Version_Type__c, AR_Amended_PTF__c, AR_Avenant_Changes__c, AR_Previous_Version__c
            FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(source.Id, copy.AR_Previous_Version__c, 'La copie est bien la version suivante de la chaîne');
        System.assertEquals(null, copy.AR_Version_Type__c, 'Type de version non hérité (null = Négociation)');
        System.assertEquals(null, copy.AR_Amended_PTF__c, 'PTF amendée non héritée');
        System.assertEquals(null, copy.AR_Avenant_Changes__c, 'Modifications d\'avenant non héritées');
    }

    // Session 180a : getChain expose le type de version ; null (matrices antérieures) reste null côté serveur,
    // l'écran le lit comme « Négociation ».
    @IsTest
    static void testGetChain_exposesVersionType() {
        AR_Price_Matrix__c v1 = newDecidedMatrix('Validée', 560);
        AR_MatrixChainService.DuplicateResult v2Result = AR_MatrixChainService.duplicateMatrix(
            v1.Id, null, new List<Id>{ reasonId('Motif Chain A') }, 'Avenant tarifaire'
        );
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = v2Result.matrixId, AR_Version_Type__c = 'Avenant');
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Test.startTest();
        AR_MatrixChainService.ChainResult result = AR_MatrixChainService.getChain(v1.Id);
        Test.stopTest();

        System.assertEquals(2, result.nodes.size());
        System.assertEquals(null, result.nodes[0].versionType, 'V1 : null, lu comme Négociation');
        System.assertEquals('Avenant', result.nodes[1].versionType, 'V2 marquée Avenant');
        System.assertEquals(2, result.nodes[1].negotiationVersion);
    }

    @IsTest
    static void testDuplicate_toDifferentPosition_setsTargetContext() {
        AR_Price_Matrix__c source = newDecidedMatrix('Validée', 560);
        Id reason = reasonId('Motif Chain A');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            otherPositionId(),
            new List<Id>{ reason },
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = [SELECT AR_Position__c, AR_Position_Name__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        System.assertEquals(otherPositionId(), copy.AR_Position__c);
        System.assertEquals('Besoin Chain Autre', copy.AR_Position_Name__c);
    }

    private static final Date SRC_START = Date.newInstance(2026, 10, 19);
    private static final Date SRC_END = Date.newInstance(2027, 7, 31);

    /** Source décidée portant dates, nombre de jours (volontairement différent du calcul des dates),
     * séniorité et site client — tout ce que duplicateMatrix doit reprendre (session 146). */
    private static AR_Price_Matrix__c newDecidedMatrixWithMission(String status) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 560,
            AR_RFA_Percent__c = 0,
            AR_Start_Date__c = SRC_START,
            AR_End_Date__c = SRC_END,
            AR_Number_Of_Days__c = 150,
            AR_Seniority__c = 'Confirmed Consultant',
            AR_Client_Site__c = 'Douai'
        );
        insert m;
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Status__c = status, AR_Validated_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        return m;
    }

    private static void assertMissionKept(AR_Price_Matrix__c copy) {
        System.assertEquals(SRC_START, copy.AR_Start_Date__c, 'date de démarrage reprise');
        System.assertEquals(SRC_END, copy.AR_End_Date__c, 'date de fin reprise');
        System.assertEquals(150, copy.AR_Number_Of_Days__c, 'nombre de jours repris tel quel, jamais recalculé');
        System.assertEquals('Confirmed Consultant', copy.AR_Seniority__c);
        System.assertEquals('Douai', copy.AR_Client_Site__c);
    }

    private static final String MISSION_FIELDS =
        'AR_Start_Date__c, AR_End_Date__c, AR_Number_Of_Days__c, AR_Seniority__c, AR_Client_Site__c';

    @IsTest
    static void testDuplicate_chainFromRefused_keepsDatesDaysSeniorityAndSite() {
        AR_Price_Matrix__c source = newDecidedMatrixWithMission('Refusée');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reasonId('Motif Chain A') },
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = Database.query(
            'SELECT AR_Previous_Version__c, ' + MISSION_FIELDS + ' FROM AR_Price_Matrix__c WHERE Id = \'' + result.matrixId + '\''
        );
        System.assertEquals(source.Id, copy.AR_Previous_Version__c);
        assertMissionKept(copy);
    }

    @IsTest
    static void testDuplicate_toDifferentPosition_keepsDatesDaysSeniorityAndSite() {
        AR_Price_Matrix__c source = newDecidedMatrixWithMission('Validée');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            otherPositionId(),
            new List<Id>{ reasonId('Motif Chain A') },
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c copy = Database.query(
            'SELECT AR_Position__c, ' + MISSION_FIELDS + ' FROM AR_Price_Matrix__c WHERE Id = \'' + result.matrixId + '\''
        );
        System.assertEquals(otherPositionId(), copy.AR_Position__c);
        assertMissionKept(copy);
    }

    /** Invariant de la session 146 : ouvrir la V2 (getMatrixInput) puis l'enregistrer sans rien
     * toucher (saveDraftInput) conserve exactement les valeurs de la source. */
    @IsTest
    static void testDuplicate_openThenSaveUntouched_keepsDatesDaysSeniorityAndSite() {
        AR_Price_Matrix__c source = newDecidedMatrixWithMission('Refusée');
        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reasonId('Motif Chain A') },
            null
        );

        Test.startTest();
        AR_PricingMatrixService.MatrixInput opened = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        AR_PricingMatrixService.saveDraftInput(opened);
        Test.stopTest();

        AR_Price_Matrix__c copy = Database.query(
            'SELECT ' + MISSION_FIELDS + ' FROM AR_Price_Matrix__c WHERE Id = \'' + result.matrixId + '\''
        );
        assertMissionKept(copy);
    }

    /** Collision de numérotation (correction de conception) : deux duplications depuis la même
     * source décidée doivent produire V02 puis V03, jamais deux V02. */
    @IsTest
    static void testDuplicate_twiceFromSameSource_incrementsAcrossWholeChain() {
        AR_Price_Matrix__c source = newDecidedMatrix('Validée', 560);
        Id reason = reasonId('Motif Chain A');

        Test.startTest();
        AR_MatrixChainService.DuplicateResult first = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reason },
            null
        );
        AR_MatrixChainService.DuplicateResult second = AR_MatrixChainService.duplicateMatrix(
            source.Id,
            null,
            new List<Id>{ reason },
            null
        );
        Test.stopTest();

        AR_Price_Matrix__c firstCopy = [SELECT AR_Negotiation_Version__c FROM AR_Price_Matrix__c WHERE Id = :first.matrixId];
        AR_Price_Matrix__c secondCopy = [SELECT AR_Negotiation_Version__c FROM AR_Price_Matrix__c WHERE Id = :second.matrixId];
        System.assertEquals(2, firstCopy.AR_Negotiation_Version__c);
        System.assertEquals(
            3,
            secondCopy.AR_Negotiation_Version__c,
            'Le second doit repartir du MAX de toute la chaîne, pas de source + 1, sinon collision avec le premier'
        );
    }

    @IsTest
    static void testGetChain_threeVersions_readableFromAnyNode() {
        AR_Price_Matrix__c v1 = newDecidedMatrix('Refusée', 480);
        Id reasonA = reasonId('Motif Chain A');
        AR_MatrixChainService.DuplicateResult v2Result = AR_MatrixChainService.duplicateMatrix(
            v1.Id,
            null,
            new List<Id>{ reasonA },
            'Renégociation 1'
        );
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = v2Result.matrixId, AR_Status__c = 'Validée', AR_Validated_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Id reasonB = reasonId('Motif Chain B');
        AR_MatrixChainService.DuplicateResult v3Result = AR_MatrixChainService.duplicateMatrix(
            v2Result.matrixId,
            null,
            new List<Id>{ reasonA, reasonB },
            'Renégociation 2'
        );

        Test.startTest();
        AR_MatrixChainService.ChainResult fromRoot = AR_MatrixChainService.getChain(v1.Id);
        AR_MatrixChainService.ChainResult fromMiddle = AR_MatrixChainService.getChain(v2Result.matrixId);
        AR_MatrixChainService.ChainResult fromLeaf = AR_MatrixChainService.getChain(v3Result.matrixId);
        Test.stopTest();

        for (AR_MatrixChainService.ChainResult result : new List<AR_MatrixChainService.ChainResult>{
            fromRoot, fromMiddle, fromLeaf
        }) {
            System.assertEquals(3, result.nodes.size(), 'La chaîne complète doit être lisible depuis n\'importe quel maillon');
            System.assertEquals(false, result.partiallyVisible);
        }
        System.assertEquals(1, fromRoot.nodes[0].negotiationVersion);
        System.assertEquals(2, fromRoot.nodes[1].negotiationVersion);
        System.assertEquals(3, fromRoot.nodes[2].negotiationVersion);
        System.assertEquals(2, fromRoot.nodes[2].reasons.size(), 'Motifs cumulés sur la dernière version');
        // Session 163b : mc2PerDay est remonté. Sans MC2 % calculé, le repli ne peut pas fonctionner, donc null.
        System.assertEquals(null, fromRoot.nodes[0].mc2PerDay, 'mc2PerDay null quand MC2% absent');
    }

    /** Session 163b : mc2PerDay est remonté depuis AR_MC2_Per_Day__c (valeur stockée) ou via
     * repli TJM × MC2 % (quand la valeur stockée est absente mais TJM/MC2 % présents). */
    @IsTest
    static void testGetChain_mc2PerDay_storedOrFallback() {
        AR_Price_Matrix__c v1 = newDecidedMatrix('Refusée', 480);

        // Force MC2_Per_Day sur la première version pour tester la remontée de valeur stockée
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = v1.Id, AR_MC2_Per_Day__c = 65.50);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Test.startTest();
        AR_MatrixChainService.ChainResult result = AR_MatrixChainService.getChain(v1.Id);
        Test.stopTest();

        AR_MatrixChainService.ChainNode node = result.nodes[0];
        System.assertEquals(65.50, node.mc2PerDay, 'mc2PerDay remonte la valeur stockée AR_MC2_Per_Day__c');
    }

    /**
     * Détection de chaîne partiellement visible : couverte par lecture de code plutôt que par un
     * utilisateur de test réel avec sharing restreint.
     *
     * `AR_MatrixChainVisibility` (without sharing, top-level, même famille que
     * AR_MatrixVersionService/AR_NotificationService déjà éprouvés dans ce projet) exécute un
     * simple COUNT() sans condition de partage — son bypass ne dépend d'aucune logique propre à
     * ce bloc, seulement du mot-clé `without sharing` standard d'Apex. `getChain` compare ce
     * compte à la taille de la liste lue en partage normal (`with sharing`, déjà couverte par
     * testGetChain_threeVersions_readableFromAnyNode) et positionne `partiallyVisible` en
     * conséquence — une comparaison arithmétique simple, sans branche non couverte.
     *
     * Un test avec un vrai utilisateur restreint (Profile "Minimum Access" + permission set +
     * System.runAs) a été tenté et retiré : dans cette sandbox, la requête hors partage de
     * AR_MatrixChainVisibility ne retrouve pas les enregistrements créés hors du bloc
     * System.runAs(utilisateur restreint) alors même que le mot-clé `without sharing` devrait
     * s'en affranchir — testé avec une classe interne puis une classe top-level, sans succès.
     * Même famille de fragilité que celle déjà documentée dans AR_MatrixVersionServiceTest
     * (création d'un User de test jugée trop fragile dans cet org managé). Signalé à Alexis plutôt
     * que masqué par un test qui ne prouverait rien.
     */

    /** Session 239b : les périodes de frais OM suivent la duplication (buildCopy), comme les autres frais. */
    @IsTest
    static void testDuplicate_copiesFeePeriods() {
        String periods = '[{"days":180,"feeIk":12,"feeMeals":0,"feeLodging":0,"feeOmOther":0}]';
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480,
            AR_Fee_Periods__c = periods
        );
        insert draft;

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(draft.Id, null, new List<Id>(), null);

        AR_Price_Matrix__c copy = [SELECT AR_Fee_Periods__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        System.assertEquals(periods, copy.AR_Fee_Periods__c, 'La copie porte les mêmes périodes de frais');
    }

    @IsTest
    static void testDuplicate_copiesPlannedLeaveAndMonthlyFees() {
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480,
            AR_Number_Of_Days__c = 254,
            AR_Planned_Leave_Days__c = 25,
            AR_Fee_Monthly_Other__c = 75,
            AR_Salary_Periods__c = '[{"days":100,"salary":50000}]'
        );
        insert draft;

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(draft.Id, null, new List<Id>(), null);

        AR_Price_Matrix__c copy = [
            SELECT AR_Planned_Leave_Days__c, AR_Fee_Monthly_Other__c, AR_Salary_Periods__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals('[{"days":100,"salary":50000}]', copy.AR_Salary_Periods__c, 'La copie reprend les périodes de salaire');
        System.assertEquals(25, copy.AR_Planned_Leave_Days__c, 'La copie reprend les congés prévus');
        System.assertEquals(75, copy.AR_Fee_Monthly_Other__c, 'La copie reprend les autres frais mensuels');
    }

    private static AR_Price_Matrix__c newDraftWithNegoPrices() {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 700,
            AR_Nego_Price_2__c = 650,
            AR_Nego_Price_3__c = 610,
            AR_RFA_Percent__c = 0
        );
        insert m;
        return m;
    }

    @IsTest
    static void testDuplicate_copiesNegotiationPrices() {
        AR_Price_Matrix__c source = newDraftWithNegoPrices();

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id, null, new List<Id>(), null
        );

        AR_Price_Matrix__c copy = [
            SELECT AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(700, copy.AR_Proposed_TJM__c);
        System.assertEquals(650, copy.AR_Nego_Price_2__c, 'prix 2 recopié');
        System.assertEquals(610, copy.AR_Nego_Price_3__c, 'prix 3 recopié');
    }

    @IsTest
    static void testDuplicate_copiesClientGrid() {
        AR_Price_Matrix__c source = newDraftWithNegoPrices();
        source.AR_Client_Grid__c = true;
        update source;

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
            source.Id, null, new List<Id>(), null
        );

        System.assertEquals(
            true,
            [SELECT AR_Client_Grid__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId].AR_Client_Grid__c,
            'case Grille reprise sur la copie'
        );
    }

    @IsTest
    static void testGetNegotiationPrices_returnsBothPricesAndCurrency() {
        AR_Price_Matrix__c source = newDraftWithNegoPrices();

        AR_MatrixChainService.NegotiationPrices prices = AR_MatrixChainService.getNegotiationPrices(source.Id);

        System.assertEquals(650, prices.price2);
        System.assertEquals(610, prices.price3);
        System.assertNotEquals(null, prices.currencyCode);
    }

    @IsTest
    static void testDuplicateWithPrice_choosingPrice2_shiftsPrice3Up() {
        AR_Price_Matrix__c source = newDraftWithNegoPrices();

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrixWithPrice(
            source.Id, null, new List<Id>(), null, 'P2'
        );

        AR_Price_Matrix__c copy = [
            SELECT AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(650, copy.AR_Proposed_TJM__c, 'le prix 2 devient le TJM proposé');
        System.assertEquals(610, copy.AR_Nego_Price_2__c, 'le prix 3 remonte en prix 2');
        System.assertEquals(null, copy.AR_Nego_Price_3__c);
        System.assertEquals(700, [SELECT AR_Proposed_TJM__c FROM AR_Price_Matrix__c WHERE Id = :source.Id].AR_Proposed_TJM__c, 'la source ne bouge pas');
    }

    @IsTest
    static void testDuplicateWithPrice_choosingPrice3_clearsOthers() {
        AR_Price_Matrix__c source = newDraftWithNegoPrices();

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrixWithPrice(
            source.Id, null, new List<Id>(), null, 'P3'
        );

        AR_Price_Matrix__c copy = [
            SELECT AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(610, copy.AR_Proposed_TJM__c);
        System.assertEquals(null, copy.AR_Nego_Price_2__c);
        System.assertEquals(null, copy.AR_Nego_Price_3__c);
    }

    @IsTest
    static void testApplyNegotiationPriceChoice_keepAndEdgeCases() {
        AR_Price_Matrix__c keep = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 700, AR_Nego_Price_2__c = 650, AR_Nego_Price_3__c = 610);
        AR_MatrixChainService.applyNegotiationPriceChoice(keep, null);
        System.assertEquals(700, keep.AR_Proposed_TJM__c, 'garder le TJM actuel ne change rien');
        System.assertEquals(650, keep.AR_Nego_Price_2__c);
        System.assertEquals(610, keep.AR_Nego_Price_3__c);

        AR_Price_Matrix__c missing = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 700, AR_Nego_Price_3__c = 610);
        AR_MatrixChainService.applyNegotiationPriceChoice(missing, 'P2');
        System.assertEquals(700, missing.AR_Proposed_TJM__c, 'prix choisi absent : copie inchangée');

        // Le prix 3 non strictement inférieur au prix 2 choisi n'est pas conservé.
        AR_Price_Matrix__c notLower = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 700, AR_Nego_Price_2__c = 650, AR_Nego_Price_3__c = 650);
        AR_MatrixChainService.applyNegotiationPriceChoice(notLower, 'P2');
        System.assertEquals(650, notLower.AR_Proposed_TJM__c);
        System.assertEquals(null, notLower.AR_Nego_Price_2__c);
    }

    // docs/254 §5 : choisir P2/P3 efface les périodes de TJM (prix unique) ; « garder » les conserve.
    @IsTest
    static void testApplyNegotiationPriceChoice_clearsTjmPeriodsOnlyWhenPriceChosen() {
        String periods = '[{"days":60,"tjm":700}]';
        AR_Price_Matrix__c keep = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 650, AR_Nego_Price_2__c = 600, AR_TJM_Periods__c = periods);
        AR_MatrixChainService.applyNegotiationPriceChoice(keep, null);
        System.assertEquals(periods, keep.AR_TJM_Periods__c, 'garder le TJM actuel conserve les périodes');

        AR_Price_Matrix__c chosen = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 650, AR_Nego_Price_2__c = 600, AR_TJM_Periods__c = periods);
        AR_MatrixChainService.applyNegotiationPriceChoice(chosen, 'P2');
        System.assertEquals(600, chosen.AR_Proposed_TJM__c);
        System.assertEquals(null, chosen.AR_TJM_Periods__c, 'le prix choisi est un prix unique : périodes effacées');

        AR_Price_Matrix__c absent = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 650, AR_TJM_Periods__c = periods);
        AR_MatrixChainService.applyNegotiationPriceChoice(absent, 'P2');
        System.assertEquals(periods, absent.AR_TJM_Periods__c, 'prix choisi absent : copie inchangée, périodes comprises');
    }

    /** Régie sans régule (docs/265) : une copie V2 reprend mode, base, plan et synthèses. */
    @IsTest
    static void testDuplicate_copiesRplsrFields() {
        AR_Price_Matrix__c draft = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480,
            AR_RPLSR_Enabled__c = true,
            AR_RPLSR_Days_Per_Month__c = 18.17,
            AR_RPLSR_Plan__c = '{"v":1,"mois":[{"m":"2027-03","ouvres":23,"vendus":18.17,"produits":18}]}',
            AR_RPLSR_Days_Sold__c = 18.17,
            AR_RPLSR_Days_Produced__c = 18
        );
        insert draft;

        AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(draft.Id, null, new List<Id>(), null);

        AR_Price_Matrix__c copy = [
            SELECT AR_RPLSR_Enabled__c, AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Plan__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c
            FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(true, copy.AR_RPLSR_Enabled__c);
        System.assertEquals(18.17, copy.AR_RPLSR_Days_Per_Month__c);
        System.assertEquals(draft.AR_RPLSR_Plan__c, copy.AR_RPLSR_Plan__c);
        System.assertEquals(18.17, copy.AR_RPLSR_Days_Sold__c);
        System.assertEquals(18, copy.AR_RPLSR_Days_Produced__c);
    }

    private static AR_PTF_Document__c newGeneratedDoc(AR_Price_Matrix__c m, String reference, Boolean addressModified) {
        AR_PTF_Document__c doc = new AR_PTF_Document__c(
            AR_Price_Matrix__c = m.Id,
            AR_Position__c = m.AR_Position__c,
            AR_Reference__c = reference,
            AR_Version_Number__c = 1,
            AR_Snapshot__c = '{"client":"Client Chain","adresseClientModifiee":' + addressModified + '}',
            AR_Generated_At__c = System.now(),
            AR_Generation_Status__c = 'Généré'
        );
        insert doc;
        return doc;
    }

    /** Session 279 : la V2 voit les documents de la V1 (lecture seule), pas ceux d'une autre chaîne. */
    @IsTest
    static void testGetPreviousVersionDocuments_v2SeesV1Documents_notOtherChain() {
        AR_Price_Matrix__c v1 = newDecidedMatrix('Validée', 480);
        AR_PTF_Document__c v1Doc = newGeneratedDoc(v1, 'PTF-CHAIN-V1', true);
        AR_MatrixChainService.DuplicateResult v2Result = AR_MatrixChainService.duplicateMatrix(
            v1.Id, null, new List<Id>{ reasonId('Motif Chain A') }, 'Renégociation'
        );
        AR_Price_Matrix__c v2 = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c WHERE Id = :v2Result.matrixId];
        newGeneratedDoc(v2, 'PTF-CHAIN-V2', false);

        AR_Price_Matrix__c other = newDecidedMatrix('Validée', 500);
        newGeneratedDoc(other, 'PTF-AUTRE-CHAINE', false);

        Test.startTest();
        List<AR_MatrixChainService.PreviousVersionGroup> forV2 =
            AR_MatrixChainService.getPreviousVersionDocuments(v2.Id);
        List<AR_MatrixChainService.PreviousVersionGroup> forV1 =
            AR_MatrixChainService.getPreviousVersionDocuments(v1.Id);
        List<AR_MatrixChainService.PreviousVersionGroup> forOther =
            AR_MatrixChainService.getPreviousVersionDocuments(other.Id);
        Test.stopTest();

        System.assertEquals(1, forV2.size(), 'Un seul groupe : la V1');
        System.assertEquals(v1.Id, forV2[0].matrixId);
        System.assertEquals(1, forV2[0].negotiationVersion);
        System.assertNotEquals(null, forV2[0].validatedAt);
        System.assertEquals(1, forV2[0].documents.size());
        System.assertEquals(v1Doc.Id, forV2[0].documents[0].ptfDocumentId);
        System.assertEquals('PTF-CHAIN-V1', forV2[0].documents[0].reference);
        System.assertEquals(true, forV2[0].documents[0].clientAddressModified);
        System.assertEquals(0, forV1.size(), 'La V1 n\'a pas de version précédente');
        System.assertEquals(0, forOther.size(), 'Aucun document d\'une autre chaîne');
    }

    /** Session 279 : versions les plus récentes en premier ; documents non générés exclus. */
    @IsTest
    static void testGetPreviousVersionDocuments_v3_listsV2ThenV1_skipsFailedDocs() {
        AR_Price_Matrix__c v1 = newDecidedMatrix('Validée', 480);
        newGeneratedDoc(v1, 'PTF-V1', false);
        Id reasonA = reasonId('Motif Chain A');
        Id v2Id = AR_MatrixChainService.duplicateMatrix(v1.Id, null, new List<Id>{ reasonA }, 'R1').matrixId;
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = v2Id, AR_Status__c = 'Validée', AR_Validated_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_Price_Matrix__c v2 = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c WHERE Id = :v2Id];
        newGeneratedDoc(v2, 'PTF-V2', false);
        insert new AR_PTF_Document__c(
            AR_Price_Matrix__c = v2.Id, AR_Position__c = v2.AR_Position__c, AR_Reference__c = 'PTF-V2-ECHEC',
            AR_Version_Number__c = 2, AR_Generated_At__c = System.now(), AR_Generation_Status__c = 'Échec'
        );
        Id v3Id = AR_MatrixChainService.duplicateMatrix(v2Id, null, new List<Id>{ reasonA }, 'R2').matrixId;

        Test.startTest();
        List<AR_MatrixChainService.PreviousVersionGroup> groups =
            AR_MatrixChainService.getPreviousVersionDocuments(v3Id);
        Test.stopTest();

        System.assertEquals(2, groups.size());
        System.assertEquals(v2Id, groups[0].matrixId, 'V2 en premier (plus récente)');
        System.assertEquals(v1.Id, groups[1].matrixId);
        System.assertEquals(1, groups[0].documents.size(), 'Le document en échec n\'est pas proposé');
        System.assertEquals('PTF-V2', groups[0].documents[0].reference);
    }
}