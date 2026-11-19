/**
 * Tests de la durée de vie des entrées « Matrice validée » (session 175) : règle d'éligibilité de la synchro
 * (AR_ValidatedMatrixSyncService.cutoffFor / validatedOn) ET batch d'expiration (AR_ValidatedMatrixExpiryBatch).
 *
 * Pour tester le batch lui-même il faut des entrées DÉJÀ vieilles : la synchro refuse d'en créer, on les fabrique donc
 * avec une durée de vie très large (36500 j), puis on ramène la durée de vie à la valeur testée avant de lancer le batch.
 * Chaque test fabrique ses besoins ; jamais de filtre sur Name (AutoNumber continus de l'org).
 */
@isTest
private class AR_ValidatedMatrixExpiryBatchTest {
    private static final String INTERVIEW2_RT_DEV_NAME = 'Interview2';

    @testSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_Validated_Matrix_Lifetime_Days__c = 36500,
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

    private static void setSettings(Decimal lifetimeDays, Boolean syncEnabled) {
        AR_General_Setting__c settings = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        settings.AR_Validated_Matrix_Lifetime_Days__c = lifetimeDays;
        settings.AR_Validated_Matrix_Sync_Enabled__c = syncEnabled;
        update settings;
    }

    private static cxsrec__cxsPosition__c openPosition(String label) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(Name = 'Besoin ' + label, cxsrec__Status__c = 'Open');
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

    private static AR_Price_Matrix__c validatedDaysAgo(cxsrec__cxsPosition__c position, Integer days) {
        return newMatrix(position, 'Validée', null, 1, Datetime.now().addDays(-days));
    }

    private static AR_Validated_Matrix__c entryOf(Id matrixId) {
        List<AR_Validated_Matrix__c> entries = [
            SELECT Id, Name FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :matrixId
        ];
        System.assert(entries.size() <= 1, 'Une entrée par matrice au maximum');
        return entries.isEmpty() ? null : entries[0];
    }

    private static void runBatch() {
        Test.startTest();
        Database.executeBatch(new AR_ValidatedMatrixExpiryBatch(), 200);
        Test.stopTest();
    }

    private static void updateUnderBypass(AR_Price_Matrix__c changes) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update changes;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    // ---------- Règle de la synchro : N−1 / N / N+1 jours ----------

    @isTest
    static void testSyncKeepsAtNMinusOneAndRefusesAtNPlusOne() {
        setSettings(365, true);
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c recent = validatedDaysAgo(position, 364);
        AR_Price_Matrix__c old = validatedDaysAgo(position, 366);

        System.assertNotEquals(null, entryOf(recent.Id), 'Validée il y a 364 jours (N−1) : entrée présente');
        System.assertEquals(null, entryOf(old.Id), 'Validée il y a 366 jours (N+1) : pas d\'entrée');
    }

    @isTest
    static void testDefaultLifetimeIs365WhenEmpty() {
        setSettings(null, true);
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c recent = validatedDaysAgo(position, 364);
        AR_Price_Matrix__c old = validatedDaysAgo(position, 366);

        System.assertNotEquals(null, entryOf(recent.Id), 'Durée vide = 365 : 364 jours, présente');
        System.assertEquals(null, entryOf(old.Id), 'Durée vide = 365 : 366 jours, absente');
        System.assertEquals(365, AR_ValidatedMatrixSyncService.lifetimeDays(null), 'Sans réglages : 365');
        AR_General_Setting__c invalid = new AR_General_Setting__c(AR_Validated_Matrix_Lifetime_Days__c = 0);
        System.assertEquals(365, AR_ValidatedMatrixSyncService.lifetimeDays(invalid), 'Valeur < 1 saisie en base : 365, jamais « tout expirer »');
    }

    @isTest
    static void testLifetimeModifiedChangesWhatIsEligible() {
        setSettings(30, true);
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c at20 = validatedDaysAgo(position, 20);
        AR_Price_Matrix__c at40 = validatedDaysAgo(position, 40);
        System.assertNotEquals(null, entryOf(at20.Id), 'N = 30 : 20 jours, présente');
        System.assertEquals(null, entryOf(at40.Id), 'N = 30 : 40 jours, absente');

        setSettings(60, true);
        AR_ValidatedMatrixSyncService.resyncAll();

        System.assertNotEquals(null, entryOf(at40.Id), 'N porté à 60 puis reprise : 40 jours, présente');
    }

    @isTest
    static void testMissingValidatedAtUsesCreatedDate() {
        setSettings(365, true);
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c matrix = newMatrix(position, 'Validée', null, 1, null);

        System.assertNotEquals(null, entryOf(matrix.Id), 'Sans date de validation : date de création (aujourd\'hui) → présente');
    }

    // Une chaîne dont la dernière version validée est expirée n'a pas d'entrée : on ne retombe pas sur une version plus
    // ancienne qui, elle, serait encore dans la durée de vie (validée tardivement alors qu'elle est de rang inférieur).
    @isTest
    static void testExpiredLatestVersionDoesNotFallBackOnLowerRank() {
        setSettings(365, true);
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = newMatrix(position, 'Brouillon', null, 1, null);
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2, Datetime.now().addDays(-400));
        System.assertEquals(null, entryOf(v2.Id), 'Témoin : V2 expirée, pas d\'entrée');

        updateUnderBypass(new AR_Price_Matrix__c(Id = v1.Id, AR_Status__c = 'Validée', AR_Validated_At__c = Datetime.now().addDays(-1)));

        System.assertEquals(null, entryOf(v1.Id), 'La V1 récente ne remplace pas la V2 (dernière validée) expirée');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Root_Key__c = :String.valueOf(v1.Id)]);
    }

    // ---------- Batch ----------

    @isTest
    static void testBatchDeletesExpiredEntriesAndKeepsTheOthers() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at364 = validatedDaysAgo(position, 364);
        AR_Price_Matrix__c at366 = validatedDaysAgo(position, 366);
        AR_Price_Matrix__c at10 = validatedDaysAgo(position, 10);
        System.assertEquals(3, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c = :position.Id], 'Témoin : trois entrées (durée de vie très large)');

        setSettings(365, true);
        runBatch();

        System.assertNotEquals(null, entryOf(at364.Id), 'N−1 jours : conservée');
        System.assertNotEquals(null, entryOf(at10.Id), '10 jours : conservée');
        System.assertEquals(null, entryOf(at366.Id), 'N+1 jours : supprimée');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :at366.Id], 'La vraie matrice expirée n\'est jamais touchée');
    }

    @isTest
    static void testBatchUsesCreatedDateWhenValidatedAtIsEmpty() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c old = newMatrix(position, 'Validée', null, 1, null);
        AR_Price_Matrix__c recent = newMatrix(position, 'Validée', null, 1, null);
        System.assertNotEquals(null, entryOf(old.Id), 'Témoin : entrée créée (créée aujourd\'hui)');
        Test.setCreatedDate(old.Id, Datetime.now().addDays(-400));

        setSettings(365, true);
        runBatch();

        System.assertEquals(null, entryOf(old.Id), 'Sans date de validation : la date de création (400 jours) fait foi → supprimée');
        System.assertNotEquals(null, entryOf(recent.Id), 'Créée aujourd\'hui, sans date de validation : conservée');
    }

    @isTest
    static void testBatchWithModifiedLifetime() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at40 = validatedDaysAgo(position, 40);
        AR_Price_Matrix__c at20 = validatedDaysAgo(position, 20);

        setSettings(30, true);
        runBatch();

        System.assertEquals(null, entryOf(at40.Id), 'N = 30 : 40 jours, supprimée');
        System.assertNotEquals(null, entryOf(at20.Id), 'N = 30 : 20 jours, conservée');
    }

    @isTest
    static void testBatchIsNoOpWhenSyncIsSwitchedOff() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at400 = validatedDaysAgo(position, 400);
        System.assertNotEquals(null, entryOf(at400.Id), 'Témoin');

        setSettings(365, false);
        runBatch();

        System.assertNotEquals(null, entryOf(at400.Id), 'Interrupteur coupé : le module est gelé, expiration comprise');
    }

    @isTest
    static void testBatchWithoutSettingsDoesNothing() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at400 = validatedDaysAgo(position, 400);
        delete [SELECT Id FROM AR_General_Setting__c];

        runBatch();

        System.assertNotEquals(null, entryOf(at400.Id), 'Sans réglages : aucune suppression');
    }

    @isTest
    static void testBatchIsIdempotent() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at400 = validatedDaysAgo(position, 400);
        AR_Price_Matrix__c at5 = validatedDaysAgo(position, 5);
        setSettings(365, true);

        runBatch();

        // Un second passage ne trouve plus rien à supprimer (un test ne peut appeler startTest qu'une fois : on
        // interroge directement le QueryLocator du batch).
        Database.QueryLocatorIterator second = new AR_ValidatedMatrixExpiryBatch().start(null).iterator();
        System.assertEquals(false, second.hasNext(), 'Second passage : aucune entrée expirée restante');
        System.assertEquals(null, entryOf(at400.Id));
        System.assertNotEquals(null, entryOf(at5.Id));
        System.assertEquals(1, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c = :position.Id]);
    }

    // Un événement ultérieur sur une matrice expirée ne recrée pas l'entrée supprimée par le batch.
    @isTest
    static void testExpiredEntryIsNotRecreatedByALaterMatrixEvent() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c at400 = validatedDaysAgo(position, 400);
        setSettings(365, true);
        runBatch();
        System.assertEquals(null, entryOf(at400.Id), 'Témoin : supprimée par le batch');

        updateUnderBypass(new AR_Price_Matrix__c(Id = at400.Id, AR_Account_Name__c = 'ACME renommée'));

        System.assertEquals(null, entryOf(at400.Id), 'L\'événement sur la matrice ne recrée pas une entrée expirée');
    }

    // Volume : 250 entrées dont 200 expirées → un lot complet de 200 (tout ce qu'un test peut exécuter en un passage).
    @isTest
    static void testBatchOnVolume() {
        List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 250; i++) {
            positions.add(new cxsrec__cxsPosition__c(Name = 'Besoin vol ' + i, cxsrec__Status__c = 'Open'));
        }
        insert positions;
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (Integer i = 0; i < 250; i++) {
            matrices.add(new AR_Price_Matrix__c(
                AR_Position__c = positions[i].Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
                AR_Account_Name__c = 'ACME ' + i, AR_Consultant_Name__c = 'Jean DUPONT', AR_Negotiation_Version__c = 1,
                AR_Version_Number__c = 1,
                AR_Validated_At__c = Datetime.now().addDays(i < 200 ? -400 : -10)
            ));
        }
        insert matrices;
        Set<Id> positionIds = new Map<Id, cxsrec__cxsPosition__c>(positions).keySet();
        System.assertEquals(250, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds], 'Témoin : 250 entrées');

        setSettings(365, true);
        runBatch();

        System.assertEquals(50, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds], '200 expirées supprimées, 50 récentes conservées');
        System.assertEquals(250, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c IN :positionIds], 'Aucune vraie matrice supprimée');
    }

    // ---------- Step : la vraie matrice reste ----------

    @isTest
    static void testStepKeepsItsRealMatrixAfterExpiry() {
        cxsrec__cxsCandidate__c candidate = new cxsrec__cxsCandidate__c(Name = 'Cand E', cxsrec__First_name__c = 'Cand', cxsrec__Last_name__c = 'E');
        insert candidate;
        cxsrec__cxsPosition__c position = openPosition('E');
        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(cxsrec__Position__c = position.Id, cxsrec__Candidate__c = candidate.Id);
        insert jobApp;
        AR_Price_Matrix__c matrix = validatedDaysAgo(position, 400);
        AR_Validated_Matrix__c entry = entryOf(matrix.Id);
        cxsrec__cxsStep__c step = new cxsrec__cxsStep__c(
            cxsrec__Job_application__c = jobApp.Id,
            RecordTypeId = Schema.SObjectType.cxsrec__cxsStep__c.getRecordTypeInfosByDeveloperName().get(INTERVIEW2_RT_DEV_NAME).getRecordTypeId(),
            AR_Validated_Matrix__c = entry.Id
        );
        insert step;
        System.assertEquals(matrix.Id, [SELECT AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :step.Id].AR_Price_Matrix__c, 'Témoin : copie de la vraie matrice');

        setSettings(365, true);
        runBatch();

        System.assertEquals(null, entryOf(matrix.Id), 'Entrée expirée supprimée');
        cxsrec__cxsStep__c after = [SELECT AR_Validated_Matrix__c, AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :step.Id];
        System.assertEquals(null, after.AR_Validated_Matrix__c, 'Champ de la popup vidé par la plateforme (SetNull)');
        System.assertEquals(matrix.Id, after.AR_Price_Matrix__c, 'Le Step garde sa vraie matrice de prix');
    }
}