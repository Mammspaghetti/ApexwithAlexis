/**
 * Tests de AR_StepMatrixLinkHandler (docs/171, 173, 173b, 173c, session 174).
 *
 * Session 174 : le champ de la popup est AR_Validated_Matrix__c (objet « Matrice validée »). Les entrées sont
 * créées par la VRAIE synchro (AR_ValidatedMatrixSyncService, via AR_PriceMatrixTrigger) à l'insertion des
 * matrices validées : ces tests couvrent donc aussi la chaîne matrice → entrée → Step. Le Step copie la vraie
 * matrice dans AR_Price_Matrix__c.
 *
 * Données : chaque test fabrique SES besoins (position + candidature rattachée à la position). Piège constaté
 * en session 173c : Connexys crée automatiquement une candidature SANS besoin à l'insertion d'un candidat ;
 * `SELECT … FROM cxsrec__cxsJob_application__c LIMIT 1` renvoie celle-là, le handler n'a alors rien à faire et
 * tous les tests « ne rien faire » passent à vide. On n'interroge donc jamais une candidature sans filtre :
 * les Id viennent des fabriques ci-dessous. Les numéros MAT-xxxxx sont des AutoNumber continus de l'org :
 * jamais de filtre sur Name.
 */
@isTest
private class AR_StepMatrixLinkHandlerTest {
    private static final String INTERVIEW2_RT_DEV_NAME = 'Interview2';
    private static final String FIELD = 'AR_Validated_Matrix__c';

    @testSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_StepMatrixLink_Auto_Link_Enabled__c = false,
            AR_StepMatrixLink_Check_Enabled__c = false,
            AR_StepMatrixLink_Require_Empty_Enabled__c = false,
            AR_Validated_Matrix_Sync_Enabled__c = true,
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

    private class Besoin {
        Id positionId;
        Id jobAppId;
    }

    private static void setSwitches(Boolean autoLink, Boolean check, Boolean requireEmpty) {
        AR_General_Setting__c settings = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        settings.AR_StepMatrixLink_Auto_Link_Enabled__c = autoLink;
        settings.AR_StepMatrixLink_Check_Enabled__c = check;
        settings.AR_StepMatrixLink_Require_Empty_Enabled__c = requireEmpty;
        update settings;
    }

    private static Besoin newBesoin(String label) {
        cxsrec__cxsCandidate__c candidate = new cxsrec__cxsCandidate__c(
            Name = 'Cand ' + label,
            cxsrec__First_name__c = 'Cand',
            cxsrec__Last_name__c = label
        );
        insert candidate;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(Name = 'Besoin ' + label, cxsrec__Status__c = 'Open');
        insert position;

        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(
            cxsrec__Position__c = position.Id,
            cxsrec__Candidate__c = candidate.Id
        );
        insert jobApp;

        Besoin besoin = new Besoin();
        besoin.positionId = position.Id;
        besoin.jobAppId = jobApp.Id;
        return besoin;
    }

    // Une chaîne se construit comme AR_MatrixChainService : V1 sans racine, Vn avec racine = Id de la V1.
    private static AR_Price_Matrix__c newMatrix(
        Besoin besoin,
        String status,
        Id rootId,
        Integer version,
        Id jobAppId
    ) {
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = besoin.positionId,
            AR_Status__c = status,
            AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'ACME',
            AR_Root_Matrix__c = rootId,
            AR_Negotiation_Version__c = version,
            // Compteur de snapshots : 1 partout, comme sur les données réelles. Si le handler s'en servait pour
            // désigner la dernière version, toutes les chaînes seraient à égalité et les tests le verraient.
            AR_Version_Number__c = 1,
            AR_Job_Application__c = jobAppId
        );
        insert matrix;
        return matrix;
    }

    private static AR_Price_Matrix__c validatedV1(Besoin besoin) {
        return newMatrix(besoin, 'Validée', null, 1, null);
    }

    // L'entrée « Matrice validée » d'une matrice (créée par la synchro) ; jamais nulle pour une matrice validée d'un besoin Open.
    private static Id entryOf(AR_Price_Matrix__c matrix) {
        List<AR_Validated_Matrix__c> entries = [SELECT Id FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :matrix.Id];
        System.assertEquals(1, entries.size(), 'La synchro doit avoir créé exactement une entrée pour la matrice');
        return entries[0].Id;
    }

    private static cxsrec__cxsStep__c newStep(Id jobAppId, Id entryId) {
        return new cxsrec__cxsStep__c(
            cxsrec__Job_application__c = jobAppId,
            RecordTypeId = interview2RecordTypeId(),
            AR_Validated_Matrix__c = entryId
        );
    }

    private static Id interview2RecordTypeId() {
        return Schema.SObjectType.cxsrec__cxsStep__c.getRecordTypeInfosByDeveloperName()
            .get(INTERVIEW2_RT_DEV_NAME)
            .getRecordTypeId();
    }

    // Champ de la popup (entrée « Matrice validée »).
    private static Id matrixOf(Id stepId) {
        return [SELECT AR_Validated_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :stepId].AR_Validated_Matrix__c;
    }

    // Vraie matrice de prix, copiée par le handler (source de vérité durable).
    private static Id realMatrixOf(Id stepId) {
        return [SELECT AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :stepId].AR_Price_Matrix__c;
    }

    // Libellé de l'entrée, tel que le handler le met dans ses messages.
    private static String label(Id entryId) {
        return [SELECT Name FROM AR_Validated_Matrix__c WHERE Id = :entryId].Name;
    }

    private static String joinedLabels(List<Id> entryIds) {
        List<String> names = new List<String>();
        for (Id entryId : entryIds) {
            names.add(label(entryId));
        }
        names.sort();
        return String.join(names, ' ; ');
    }

    // Refus métier : exactement un refus, sur le champ de la matrice, avec le message exact.
    private static void assertRefused(cxsrec__cxsStep__c step, String expectedMessage) {
        Boolean refused = false;
        try {
            insert step;
        } catch (DmlException e) {
            refused = true;
            System.assertEquals(1, e.getNumDml(), 'Un seul refus attendu');
            System.assertEquals(expectedMessage, e.getDmlMessage(0), 'Message de refus exact');
            System.assertEquals(1, e.getDmlFieldNames(0).size(), 'Refus porté par un seul champ');
            System.assertEquals(FIELD, e.getDmlFieldNames(0)[0], 'Refus porté par le champ Matrice de prix');
        }
        System.assert(refused, 'Le Step aurait dû être refusé');
    }

    // ---------- C : rattachement automatique ----------

    @isTest
    static void testAutoLinkWithExactlyOneMatrix() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c validated = validatedV1(besoin);
        newMatrix(besoin, 'Brouillon', null, 1, null);
        Besoin other = newBesoin('Autre');
        validatedV1(other);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        Test.startTest();
        insert step;
        Test.stopTest();

        System.assertEquals(entryOf(validated), matrixOf(step.Id), 'La seule entrée du besoin doit être liée');
        System.assertEquals(validated.Id, realMatrixOf(step.Id), 'La vraie matrice est recopiée sur le Step');
    }

    @isTest
    static void testNoAutoLinkWithMultipleMatrices() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Deux chaînes validées : rien n\'est choisi à la place du BM');
        System.assertEquals(null, realMatrixOf(step.Id), 'Rien de choisi : aucune matrice recopiée');
    }

    @isTest
    static void testNoAutoLinkWithNoMatrices() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        newMatrix(besoin, 'Brouillon', null, 1, null);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Aucune matrice validée : le champ reste vide, sans erreur');
    }

    @isTest
    static void testRootMatrixVersioning_V1AndV2() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        newMatrix(besoin, 'Validée', v1.Id, 2, null);
        AR_Price_Matrix__c v3 = newMatrix(besoin, 'Validée par dérogation', v1.Id, 3, null);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(entryOf(v3), matrixOf(step.Id), 'Une seule chaîne (V1, V2, V3) : l\'entrée de la V3, dernière version, est posée');
        System.assertEquals(v3.Id, realMatrixOf(step.Id), 'La vraie matrice recopiée est la V3');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c = :besoin.positionId], 'Une seule entrée pour la chaîne');
    }

    @isTest
    static void testRootMatrixVersioning_V2AndV1() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        AR_Price_Matrix__c v2 = newMatrix(besoin, 'Validée', v1.Id, 2, null);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(entryOf(v2), matrixOf(step.Id), 'L\'entrée de la V2 est posée, pas celle de la V1 (qui a pourtant une racine nulle)');
    }

    @isTest
    static void testBatchTwoStepsTwoBesoinsEachGetsOwnMatrix() {
        setSwitches(true, true, false);
        Besoin besoinA = newBesoin('A');
        Besoin besoinB = newBesoin('B');
        AR_Price_Matrix__c matrixA = validatedV1(besoinA);
        AR_Price_Matrix__c matrixB = validatedV1(besoinB);

        cxsrec__cxsStep__c stepA = newStep(besoinA.jobAppId, null);
        cxsrec__cxsStep__c stepB = newStep(besoinB.jobAppId, null);
        Test.startTest();
        insert new List<cxsrec__cxsStep__c>{ stepA, stepB };
        Test.stopTest();

        System.assertEquals(entryOf(matrixA), matrixOf(stepA.Id), 'Le Step du besoin A reçoit l\'entrée de A');
        System.assertEquals(entryOf(matrixB), matrixOf(stepB.Id), 'Le Step du besoin B reçoit l\'entrée de B');
        System.assertEquals(matrixA.Id, realMatrixOf(stepA.Id), 'Vraie matrice de A');
        System.assertEquals(matrixB.Id, realMatrixOf(stepB.Id), 'Vraie matrice de B');
    }

    @isTest
    static void testBulkInsert() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c matrix = validatedV1(besoin);
        Id entryId = entryOf(matrix);

        List<cxsrec__cxsStep__c> steps = new List<cxsrec__cxsStep__c>();
        for (Integer i = 0; i < 200; i++) {
            steps.add(newStep(besoin.jobAppId, null));
        }
        Test.startTest();
        insert steps;
        Test.stopTest();

        List<cxsrec__cxsStep__c> inserted = [
            SELECT AR_Validated_Matrix__c, AR_Price_Matrix__c FROM cxsrec__cxsStep__c WHERE Id IN :steps
        ];
        System.assertEquals(200, inserted.size());
        for (cxsrec__cxsStep__c step : inserted) {
            System.assertEquals(entryId, step.AR_Validated_Matrix__c, 'Chaque Step du lot est lié');
            System.assertEquals(matrix.Id, step.AR_Price_Matrix__c, 'Chaque Step du lot porte la vraie matrice');
        }
    }

    // Preuve « 200 Steps = pas de requête par Step » : le handler appelé seul consomme 3 requêtes
    // (réglages, candidatures, entrées « Matrice validée »), que le lot compte 1 ou 200 Steps, sur 1 ou 2 besoins.
    @isTest
    static void testBulkQueryCount() {
        setSwitches(true, true, false);
        Besoin besoinA = newBesoin('A');
        Besoin besoinB = newBesoin('B');
        AR_Price_Matrix__c matrixA = validatedV1(besoinA);
        AR_Price_Matrix__c matrixB = validatedV1(besoinB);
        Id entryA = entryOf(matrixA);
        Id entryB = entryOf(matrixB);

        List<cxsrec__cxsStep__c> steps = new List<cxsrec__cxsStep__c>();
        for (Integer i = 0; i < 200; i++) {
            steps.add(newStep(i < 100 ? besoinA.jobAppId : besoinB.jobAppId, null));
        }

        Integer queriesBefore = Limits.getQueries();
        AR_StepMatrixLinkHandler.handleStepMatrixLink(steps, null);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;

        System.assertEquals(3, queriesUsed, 'Trois requêtes pour tout le lot');
        for (Integer i = 0; i < 200; i++) {
            System.assertEquals(i < 100 ? entryA : entryB, steps[i].AR_Validated_Matrix__c, 'Step ' + i);
            System.assertEquals(i < 100 ? matrixA.Id : matrixB.Id, steps[i].AR_Price_Matrix__c, 'Vraie matrice, Step ' + i);
        }
    }

    @isTest
    static void testCandidateRefinement() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        AR_Price_Matrix__c forCandidate = newMatrix(besoin, 'Validée', null, 1, besoin.jobAppId);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(entryOf(forCandidate), matrixOf(step.Id), 'Deux chaînes, une seule porte la candidature : celle-là');
        System.assertEquals(forCandidate.Id, realMatrixOf(step.Id));
    }

    @isTest
    static void testCandidateRefinementAmbiguousChoosesNothing() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        newMatrix(besoin, 'Validée', null, 1, besoin.jobAppId);
        newMatrix(besoin, 'Validée', null, 1, besoin.jobAppId);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Deux matrices portent la candidature : aucun choix');
    }

    @isTest
    static void testUserSelectedMatrixIsNeverOverwritten() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        AR_Price_Matrix__c v2 = newMatrix(besoin, 'Validée', v1.Id, 2, null);
        AR_Price_Matrix__c otherRoot = validatedV1(besoin);

        cxsrec__cxsStep__c chosen = newStep(besoin.jobAppId, entryOf(otherRoot));
        insert chosen;
        System.assertEquals(entryOf(otherRoot), matrixOf(chosen.Id), 'Deux chaînes : le choix du BM est conservé');
        System.assertEquals(otherRoot.Id, realMatrixOf(chosen.Id), 'La vraie matrice suit le choix du BM');

        // Une seule chaîne V1 → V2 : la V1 n'a plus d'entrée (remplacée), il ne reste donc que celle de la V2.
        Besoin single = newBesoin('B');
        AR_Price_Matrix__c singleV1 = validatedV1(single);
        AR_Price_Matrix__c singleV2 = newMatrix(single, 'Validée', singleV1.Id, 2, null);
        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :singleV1.Id], 'L\'ancienne version n\'est plus proposée');
        cxsrec__cxsStep__c latest = newStep(single.jobAppId, entryOf(singleV2));
        insert latest;
        System.assertEquals(entryOf(singleV2), matrixOf(latest.Id), 'L\'entrée choisie est conservée');
    }

    @isTest
    static void testFieldClearedTriggersAutoLink() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c matrix = validatedV1(besoin);
        Id entryId = entryOf(matrix);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        System.assertEquals(null, matrixOf(step.Id), 'Interrupteurs coupés : le Step est créé sans matrice');

        // Mises à jour minimales (Id + champ) : renvoyer la candidature/le type d'étape de l'insert déclenche
        // « fields being inaccessible » côté Connexys, sans rapport avec le handler.
        setSwitches(true, true, false);
        update new cxsrec__cxsStep__c(Id = step.Id, AR_Validated_Matrix__c = entryId);
        System.assertEquals(entryId, matrixOf(step.Id), 'Entrée valide saisie : conservée');
        System.assertEquals(matrix.Id, realMatrixOf(step.Id), 'La vraie matrice est recopiée à la saisie');
        Test.startTest();
        update new cxsrec__cxsStep__c(Id = step.Id, AR_Validated_Matrix__c = null);
        Test.stopTest();

        System.assertEquals(entryId, matrixOf(step.Id), 'Champ vidé : l\'entrée unique est reposée');
    }

    // ---------- Copie de la vraie matrice (source de vérité durable) ----------

    @isTest
    static void testRealMatrixCopiedWhenUserChoosesEntry() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        AR_Price_Matrix__c chosen = validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(chosen));
        insert step;

        System.assertEquals(chosen.Id, realMatrixOf(step.Id), 'La vraie matrice de l\'entrée choisie est recopiée');
    }

    @isTest
    static void testRealMatrixCopiedEvenWithSwitchesOff() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c matrix = validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(matrix));
        insert step;

        System.assertEquals(matrix.Id, realMatrixOf(step.Id), 'La copie ne dépend pas des interrupteurs C/D');
    }

    @isTest
    static void testRealMatrixCopiedWithoutSettingsRecord() {
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c matrix = validatedV1(besoin);
        Id entryId = entryOf(matrix);
        delete [SELECT Id FROM AR_General_Setting__c];

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryId);
        insert step;

        System.assertEquals(matrix.Id, realMatrixOf(step.Id), 'Sans réglages : la copie se fait quand même');
    }

    @isTest
    static void testRealMatrixFollowsNewChoiceAndIsNeverCleared() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c first = validatedV1(besoin);
        AR_Price_Matrix__c second = validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(first));
        insert step;
        System.assertEquals(first.Id, realMatrixOf(step.Id));

        update new cxsrec__cxsStep__c(Id = step.Id, AR_Validated_Matrix__c = entryOf(second));
        System.assertEquals(second.Id, realMatrixOf(step.Id), 'Nouveau choix : la vraie matrice suit');

        update new cxsrec__cxsStep__c(Id = step.Id, AR_Validated_Matrix__c = null);
        System.assertEquals(null, matrixOf(step.Id), 'Champ de la popup vidé');
        System.assertEquals(second.Id, realMatrixOf(step.Id), 'La référence durable n\'est jamais effacée par le handler');
    }

    // Le Step garde sa vraie matrice quand l'entrée « Matrice validée » disparaît (purge, besoin gagné, nouvelle version).
    @isTest
    static void testStepKeepsRealMatrixAfterEntryIsDeleted() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c matrix = validatedV1(besoin);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        Id entryId = entryOf(matrix);
        System.assertEquals(entryId, matrixOf(step.Id));
        System.assertEquals(matrix.Id, realMatrixOf(step.Id));

        delete [SELECT Id FROM AR_Validated_Matrix__c WHERE Id = :entryId];

        System.assertEquals(null, matrixOf(step.Id), 'Entrée supprimée : le champ de la popup se vide (SetNull)');
        System.assertEquals(matrix.Id, realMatrixOf(step.Id), 'Le Step garde sa vraie matrice');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :matrix.Id], 'La vraie matrice existe toujours');
    }

    // Session 180a : une nouvelle version validée REPOINTE l'entrée au lieu de la supprimer. Le champ de la popup
    // reste rempli (même entrée) et affiche la version en vigueur ; la matrice qui a qualifié reste la V1.
    @isTest
    static void testStepKeepsEntryWhenNewVersionIsValidated() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        Id entryId = entryOf(v1);
        System.assertEquals(entryId, matrixOf(step.Id));
        System.assertEquals(v1.Id, realMatrixOf(step.Id));
        System.assert(label(entryId).contains(', V1 ('), 'Libellé V1 : ' + label(entryId));

        AR_Price_Matrix__c v2 = newMatrix(besoin, 'Validée', v1.Id, 2, null);

        System.assertEquals(entryId, matrixOf(step.Id), 'Le champ de la popup reste rempli, sur la même entrée');
        System.assert(label(entryId).contains(', V2 ('), 'Libellé suivi sur la V2 : ' + label(entryId));
        System.assertEquals(v2.Id, [SELECT AR_Price_Matrix__c FROM AR_Validated_Matrix__c WHERE Id = :entryId].AR_Price_Matrix__c);
        System.assertEquals(v1.Id, realMatrixOf(step.Id), 'La référence durable du Step reste la matrice qui a qualifié');
    }

    // Idem pour une version avenant : libellé « V3 Avenant », Step toujours lié.
    @isTest
    static void testStepKeepsEntryWhenAvenantVersionIsValidated() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        AR_Price_Matrix__c v2 = newMatrix(besoin, 'Validée', v1.Id, 2, null);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        Id entryId = entryOf(v2);
        System.assertEquals(entryId, matrixOf(step.Id));

        AR_Price_Matrix__c avenant = new AR_Price_Matrix__c(
            AR_Position__c = besoin.positionId, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = 520, AR_Account_Name__c = 'ACME', AR_Root_Matrix__c = v1.Id,
            AR_Negotiation_Version__c = 3, AR_Version_Number__c = 1, AR_Version_Type__c = 'Avenant'
        );
        insert avenant;

        System.assertEquals(entryId, matrixOf(step.Id), 'Le champ de la popup reste rempli après l\'avenant');
        System.assert(label(entryId).contains(', V3 Avenant ('), 'Libellé « V3 Avenant » : ' + label(entryId));
        System.assertEquals(v2.Id, realMatrixOf(step.Id), 'La référence durable du Step reste la matrice qui a qualifié');
    }

    // Pendant une dérogation en cours sur la V2, le Step montre toujours la V1 en vigueur.
    @isTest
    static void testStepStillShowsCurrentVersionDuringPendingDerogation() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        Id entryId = entryOf(v1);

        newMatrix(besoin, 'En dérogation', v1.Id, 2, null);

        System.assertEquals(entryId, matrixOf(step.Id), 'Champ toujours rempli');
        System.assert(label(entryId).contains(', V1 ('), 'Libellé toujours V1 : ' + label(entryId));
        System.assertEquals(v1.Id, [SELECT AR_Price_Matrix__c FROM AR_Validated_Matrix__c WHERE Id = :entryId].AR_Price_Matrix__c);
    }

    // Une entrée retirée (plus de gagnante) vide toujours le champ de la popup ; le Step garde sa vraie matrice.
    @isTest
    static void testStepFieldClearedWhenChainLosesItsWinner() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c v1 = validatedV1(besoin);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;
        System.assertNotEquals(null, matrixOf(step.Id));

        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = v1.Id, AR_Status__c = 'Refusée');
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        System.assertEquals(null, matrixOf(step.Id), 'Chaîne sans gagnante : entrée retirée, champ vidé');
        System.assertEquals(v1.Id, realMatrixOf(step.Id), 'Le Step garde sa vraie matrice');
    }

    // ---------- D : validation de l'entrée saisie ----------

    @isTest
    static void testValidateEntryFromDifferentPosition() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(true, true, false);
            Besoin besoin = newBesoin('A');
            AR_Price_Matrix__c validated = validatedV1(besoin);
            Besoin other = newBesoin('Autre');
            AR_Price_Matrix__c fromOther = validatedV1(other);

            assertRefused(
                newStep(besoin.jobAppId, entryOf(fromOther)),
                'Cette matrice ne correspond pas à ce besoin ou n\'est pas validée. Matrices validées pour ce besoin : '
                    + label(entryOf(validated)) + '.'
            );
        }
    }

    // Entrée sans besoin (champ copié vide) : jamais acceptée pour une candidature, quel que soit son besoin.
    @isTest
    static void testValidateEntryWithoutPosition() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(true, true, false);
            Besoin besoin = newBesoin('A');
            AR_Price_Matrix__c validated = validatedV1(besoin);
            AR_Price_Matrix__c orphanMatrix = newMatrix(newBesoin('Orpheline'), 'Brouillon', null, 1, null);
            AR_Validated_Matrix__c orphan = new AR_Validated_Matrix__c(
                Name = 'Entrée sans besoin', AR_Price_Matrix__c = orphanMatrix.Id,
                AR_Matrix_Key__c = String.valueOf(orphanMatrix.Id), AR_Root_Key__c = String.valueOf(orphanMatrix.Id)
            );
            insert orphan;

            assertRefused(
                newStep(besoin.jobAppId, orphan.Id),
                'Cette matrice ne correspond pas à ce besoin ou n\'est pas validée. Matrices validées pour ce besoin : '
                    + label(entryOf(validated)) + '.'
            );
        }
    }

    @isTest
    static void testValidateEntryWithoutAnyValidatedMatrixOfTheBesoin() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(true, true, false);
            Besoin besoin = newBesoin('A');
            newMatrix(besoin, 'Brouillon', null, 1, null);
            Besoin other = newBesoin('Autre');
            AR_Price_Matrix__c fromOther = validatedV1(other);

            assertRefused(newStep(besoin.jobAppId, entryOf(fromOther)), 'Aucune matrice validée pour ce besoin.');
        }
    }

    @isTest
    static void testValidEntryIsAccepted() {
        setSwitches(true, true, false);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c chosen = validatedV1(besoin);
        validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(chosen));
        insert step;

        System.assertEquals(entryOf(chosen), matrixOf(step.Id), 'Une entrée du besoin est acceptée');
        System.assertEquals(chosen.Id, realMatrixOf(step.Id));
    }

    // Une étape existante modifiée sur un autre champ n'est pas contrôlée (docs/171 §6 : création seulement).
    @isTest
    static void testUnrelatedUpdateIsNotValidated() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        Besoin other = newBesoin('Autre');
        AR_Price_Matrix__c fromOther = validatedV1(other);
        cxsrec__cxsStep__c existing = newStep(besoin.jobAppId, entryOf(fromOther));
        insert existing;

        setSwitches(true, true, true);
        cxsrec__cxsStep__c oldStep = [
            SELECT Id, RecordTypeId, cxsrec__Job_application__c, AR_Validated_Matrix__c, AR_Price_Matrix__c
            FROM cxsrec__cxsStep__c WHERE Id = :existing.Id
        ];
        cxsrec__cxsStep__c newStepVersion = oldStep.clone(true, true, false, false);
        newStepVersion.AR_Price_Matrix__c = null;
        AR_StepMatrixLinkHandler.handleStepMatrixLink(
            new List<cxsrec__cxsStep__c>{ newStepVersion },
            new Map<Id, cxsrec__cxsStep__c>{ oldStep.Id => oldStep }
        );

        System.assertEquals(false, newStepVersion.hasErrors(), 'Entrée inchangée : aucun contrôle');
        System.assertEquals(oldStep.AR_Validated_Matrix__c, newStepVersion.AR_Validated_Matrix__c, 'Entrée inchangée : aucune réécriture');
        System.assertEquals(null, newStepVersion.AR_Price_Matrix__c, 'Entrée inchangée : la vraie matrice n\'est pas recopiée');
    }

    // ---------- D' : champ vide ----------

    @isTest
    static void testRequireWhenEmptyWithNoMatrices() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(false, true, true);
            Besoin besoin = newBesoin('A');
            newMatrix(besoin, 'Brouillon', null, 1, null);

            assertRefused(newStep(besoin.jobAppId, null), 'Aucune matrice validée pour ce besoin.');
        }
    }

    @isTest
    static void testRequireWhenEmptyWithMultipleMatrices() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(false, true, true);
            Besoin besoin = newBesoin('A');
            AR_Price_Matrix__c first = validatedV1(besoin);
            AR_Price_Matrix__c second = validatedV1(besoin);

            assertRefused(
                newStep(besoin.jobAppId, null),
                'Plusieurs matrices validées pour ce besoin : ' + joinedLabels(new List<Id>{ entryOf(first), entryOf(second) })
                    + '. Choisissez-en une.'
            );
        }
    }

    @isTest
    static void testRequireWhenEmptyWithOneMatrixAutoLinksAndPasses() {
        setSwitches(true, true, true);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c only = validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(entryOf(only), matrixOf(step.Id), 'Une seule entrée : liée puis acceptée');
    }

    @isTest
    static void testMessageFormatWithMultipleMatrices() {
        System.runAs(AR_TestPersona.francais()) {
            setSwitches(false, true, true);
            Besoin besoin = newBesoin('A');
            AR_Price_Matrix__c v1 = validatedV1(besoin);
            AR_Price_Matrix__c v2 = newMatrix(besoin, 'Validée', v1.Id, 2, null);
            // Seconde chaîne au rang 5 : son libellé « V5 » ne peut pas être confondu avec la V1 remplacée.
            AR_Price_Matrix__c second = newMatrix(besoin, 'Validée', null, 5, null);

            Boolean refused = false;
            try {
                insert newStep(besoin.jobAppId, null);
            } catch (DmlException e) {
                refused = true;
                String message = e.getDmlMessage(0);
                System.assert(message.startsWith('Plusieurs matrices validées pour ce besoin : '), message);
                System.assert(message.endsWith('. Choisissez-en une.'), message);
                System.assert(message.contains(label(entryOf(v2))), 'L\'entrée de la V2 est nommée : ' + message);
                System.assert(message.contains(', V2 ('), 'Version affichée « V2 » : ' + message);
                System.assert(!message.contains('.0'), 'Pas de « V2.0 » : ' + message);
                System.assert(!message.contains(', V1 ('), 'La V1 (remplacée par la V2) n\'est pas nommée : ' + message);
                System.assert(message.contains(label(entryOf(second))), 'La seconde chaîne est nommée : ' + message);
                System.assert(message.contains(', V5 ('), 'Seconde chaîne en V5 : ' + message);
                System.assertEquals(1, message.countMatches(' ; '), 'Deux entrées séparées par « ; » : ' + message);
            }
            System.assert(refused, 'Le Step aurait dû être refusé');
        }
    }

    // ---------- Interrupteurs, autres types, erreurs ----------

    @isTest
    static void testDisabledInterrupts() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        Besoin other = newBesoin('Autre');
        AR_Price_Matrix__c fromOther = validatedV1(other);

        cxsrec__cxsStep__c withOther = newStep(besoin.jobAppId, entryOf(fromOther));
        cxsrec__cxsStep__c empty = newStep(besoin.jobAppId, null);
        insert new List<cxsrec__cxsStep__c>{ withOther, empty };

        System.assertEquals(entryOf(fromOther), matrixOf(withOther.Id), 'Interrupteurs coupés : l\'entrée d\'un autre besoin est acceptée');
        System.assertEquals(null, matrixOf(empty.Id), 'Interrupteurs coupés : rien n\'est lié alors qu\'une seule entrée existe');
    }

    @isTest
    static void testOnlyCheckEnabledDoesNotAutoLink() {
        setSwitches(false, true, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Rattachement coupé : le champ reste vide');
    }

    @isTest
    static void testOnlyAutoLinkEnabledDoesNotValidate() {
        setSwitches(true, false, false);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        Besoin other = newBesoin('Autre');
        AR_Price_Matrix__c fromOther = validatedV1(other);

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(fromOther));
        insert step;

        System.assertEquals(entryOf(fromOther), matrixOf(step.Id), 'Contrôle coupé : l\'entrée choisie est conservée, sans refus');
    }

    @isTest
    static void testNonInterview2RecordTypeIgnored() {
        setSwitches(true, true, true);
        Besoin besoin = newBesoin('A');
        validatedV1(besoin);
        Besoin other = newBesoin('Autre');
        AR_Price_Matrix__c fromOther = validatedV1(other);

        Id otherRtId = null;
        for (Schema.RecordTypeInfo info : Schema.SObjectType.cxsrec__cxsStep__c.getRecordTypeInfos()) {
            if (info.isAvailable() && !info.isMaster() && info.getRecordTypeId() != interview2RecordTypeId()) {
                otherRtId = info.getRecordTypeId();
                break;
            }
        }
        System.assertNotEquals(null, otherRtId, 'Un autre type d\'étape doit exister pour prouver le filtre');

        cxsrec__cxsStep__c empty = newStep(besoin.jobAppId, null);
        empty.RecordTypeId = otherRtId;
        cxsrec__cxsStep__c withOther = newStep(besoin.jobAppId, entryOf(fromOther));
        withOther.RecordTypeId = otherRtId;
        insert new List<cxsrec__cxsStep__c>{ empty, withOther };

        System.assertEquals(null, matrixOf(empty.Id), 'Autre type d\'étape : jamais de rattachement');
        System.assertEquals(entryOf(fromOther), matrixOf(withOther.Id), 'Autre type d\'étape : jamais de refus');
        System.assertEquals(null, realMatrixOf(withOther.Id), 'Autre type d\'étape : la vraie matrice n\'est jamais recopiée');
    }

    @isTest
    static void testExceptionHandling() {
        setSwitches(true, true, true);
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c only = validatedV1(besoin);

        cxsrec__cxsStep__c witness = newStep(besoin.jobAppId, null);
        insert witness;
        System.assertEquals(entryOf(only), matrixOf(witness.Id), 'Témoin : sans erreur simulée, l\'entrée est liée');

        AR_StepMatrixLinkHandler.throwExceptionForTest = true;
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        try {
            insert step;
        } finally {
            AR_StepMatrixLinkHandler.throwExceptionForTest = false;
        }

        System.assertNotEquals(null, step.Id, 'Erreur technique du handler : le Step est enregistré quand même');
        System.assertEquals(null, matrixOf(step.Id), 'Erreur technique : aucune entrée posée, aucun refus');
        System.assertEquals(null, realMatrixOf(step.Id), 'Erreur technique : aucune matrice recopiée');
    }

    // Le champ candidature est obligatoire en base : le cas ne peut venir que d'un appel direct.
    @isTest
    static void testStepWithoutJobApplicationIsIgnored() {
        setSwitches(true, true, true);
        cxsrec__cxsStep__c step = newStep(null, null);

        AR_StepMatrixLinkHandler.handleStepMatrixLink(new List<cxsrec__cxsStep__c>{ step }, null);

        System.assertEquals(false, step.hasErrors(), 'Sans candidature, donc sans besoin : aucun refus');
        System.assertEquals(null, step.AR_Validated_Matrix__c, 'Sans candidature : rien n\'est lié');
    }

    @isTest
    static void testJobApplicationWithoutPositionIsIgnored() {
        setSwitches(true, true, true);
        cxsrec__cxsCandidate__c candidate = new cxsrec__cxsCandidate__c(
            Name = 'Cand Sans Besoin', cxsrec__First_name__c = 'Cand', cxsrec__Last_name__c = 'SansBesoin'
        );
        insert candidate;
        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(cxsrec__Candidate__c = candidate.Id);
        insert jobApp;

        cxsrec__cxsStep__c step = newStep(jobApp.Id, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Candidature sans besoin : rien à faire, aucun refus');
    }

    @isTest
    static void testNoSettingsRecordDoesNothing() {
        Besoin besoin = newBesoin('A');
        AR_Price_Matrix__c only = validatedV1(besoin);
        System.assertNotEquals(null, entryOf(only), 'Préalable : une entrée existe bien pour le besoin');
        delete [SELECT Id FROM AR_General_Setting__c];

        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, null);
        insert step;

        System.assertEquals(null, matrixOf(step.Id), 'Sans réglages : comportement actuel, rien n\'est lié');
    }

    // ---------- Session 183 : persona « choix de matrice dans Connexys » (AR_Connexys_Matrix_Picker) ----------
    // Persona sans aucun permission set AR_ d'application : le seul droit sur le module vient de AR_Connexys_Matrix_Picker.
    // Les fabriques de données tournent en administrateur AVANT le runAs ; seul le geste de l'utilisateur est exécuté sous lui.

    @isTest
    static void testPickerReadsEntriesChoosesOneAndRealMatrixIsCopiedButPricesStayClosed() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('Picker');
        AR_Price_Matrix__c matrix = validatedV1(besoin);
        Id entryId = entryOf(matrix);
        User picker = AR_TestPersona.matrixPicker();
        Id stepId;

        System.runAs(picker) {
            // Il lit les entrées (le Name porte compte, consultant, version, date).
            List<AR_Validated_Matrix__c> visible = [SELECT Id, Name FROM AR_Validated_Matrix__c WITH USER_MODE];
            System.assert(!visible.isEmpty(), 'Le persona doit lire les entrées « Matrice validée »');
            Set<Id> visibleIds = new Map<Id, AR_Validated_Matrix__c>(visible).keySet();
            System.assert(visibleIds.contains(entryId), 'L\'entrée de la matrice validée est visible');

            // Il pose le champ de la popup sur un Step, avec le contrôle FLS/CRUD de l'utilisateur.
            cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryId);
            Database.insert(step, AccessLevel.USER_MODE);
            stepId = step.Id;
            System.assertEquals(null, AR_StepMatrixLinkHandler.lastTechnicalErrorForTest, 'Aucune erreur technique ne doit être avalée par le handler pour ce persona');

            cxsrec__cxsStep__c saved = [SELECT AR_Validated_Matrix__c FROM cxsrec__cxsStep__c WHERE Id = :stepId WITH USER_MODE];
            System.assertEquals(entryId, saved.AR_Validated_Matrix__c, 'Le choix est enregistré');

            // Les prix restent fermés : ni l'objet ni ses données ne sont accessibles.
            System.assertEquals(false, Schema.SObjectType.AR_Price_Matrix__c.isAccessible(), 'Aucun accès à AR_Price_Matrix__c');
            Boolean blocked = false;
            try {
                Database.query('SELECT Id, AR_Proposed_TJM__c FROM AR_Price_Matrix__c WITH USER_MODE');
            } catch (QueryException e) {
                blocked = true;
            }
            System.assert(blocked, 'La lecture de AR_Price_Matrix__c doit être refusée');
            System.assertEquals(false, Schema.SObjectType.AR_Derogation__c.isAccessible(), 'Aucun accès aux dérogations');
            System.assertEquals(false, Schema.SObjectType.AR_PTF_Document__c.isAccessible(), 'Aucun accès aux PTF');
            System.assertEquals(false, Schema.SObjectType.AR_Validated_Matrix__c.isCreateable(), 'Il ne crée pas d\'entrée');
            System.assertEquals(false, Schema.SObjectType.AR_Validated_Matrix__c.isUpdateable(), 'Il ne modifie pas d\'entrée');
            System.assertEquals(false, Schema.SObjectType.cxsrec__cxsStep__c.fields.AR_Price_Matrix__c.isUpdateable(), 'La vraie matrice reste en lecture seule');
            // Constaté en org : la FLS de lecture de AR_Price_Matrix__c sur l'étape est accordée, mais le champ reste
            // inaccessible à qui n'a pas la lecture de l'objet matrice — le persona ne peut donc même pas lire la référence.
            System.assertEquals(false, Schema.SObjectType.cxsrec__cxsStep__c.fields.AR_Price_Matrix__c.isAccessible(), 'La référence vers la vraie matrice reste fermée');
        }

        // Hors persona (le handler écrit en contexte système) : la vraie matrice a bien été recopiée sur l'étape.
        System.assertEquals(matrix.Id, realMatrixOf(stepId), 'La vraie matrice est recopiée malgré l\'absence de droit sur les matrices');
    }

    @isTest
    static void testPickerCanChangeChoiceOnExistingStep() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('PickerChange');
        AR_Price_Matrix__c first = validatedV1(besoin);
        AR_Price_Matrix__c second = validatedV1(besoin);
        cxsrec__cxsStep__c step = newStep(besoin.jobAppId, entryOf(first));
        insert step;
        Id secondEntry = entryOf(second);
        User picker = AR_TestPersona.matrixPickerWithStepEdit();

        System.runAs(picker) {
            // Objet frais : l'objet en mémoire porte AR_Price_Matrix__c (posé par le handler), champ non modifiable par ce persona.
            Database.update(new cxsrec__cxsStep__c(Id = step.Id, AR_Validated_Matrix__c = secondEntry), AccessLevel.USER_MODE);
        }
        System.assertEquals(secondEntry, matrixOf(step.Id));
        System.assertEquals(second.Id, realMatrixOf(step.Id), 'La vraie matrice suit le nouveau choix');
    }

    @isTest
    static void testWithoutThePermissionSetTheEntriesAreInvisible() {
        setSwitches(false, false, false);
        Besoin besoin = newBesoin('NoPerm');
        Id entryId = entryOf(validatedV1(besoin));
        User plain = AR_TestPersona.sansPermissionSetAR();

        System.runAs(plain) {
            System.assertEquals(false, Schema.SObjectType.AR_Validated_Matrix__c.isAccessible(), 'Sans le permission set, l\'objet est fermé');
            System.assertEquals(false, Schema.SObjectType.cxsrec__cxsStep__c.fields.AR_Validated_Matrix__c.isAccessible(), 'Champ de la popup fermé');
            Boolean blocked = false;
            try {
                Database.query('SELECT Id FROM AR_Validated_Matrix__c WITH USER_MODE');
            } catch (QueryException e) {
                blocked = true;
            }
            System.assert(blocked, 'La lecture des entrées doit être refusée sans le permission set');
        }
        System.assertNotEquals(null, entryId);
    }
}