/**
 * Tests AR_DerogationReminderBatch. Simulation temporelle par écriture directe de
 * AR_Derogation__c.AR_Requested_At__c (champ métier, pas un champ d'audit système) : contrairement à
 * LastModifiedDate (cf. AR_DraftPurgeBatchTest), rien n'empêche de le positionner dans le passé à
 * l'insertion — pas besoin de Test.setCreatedDate ni de seuils à 0 heure.
 *
 * Session 132 (décision d'Alexis, 02/10/2026) : l'escalade suit la hiérarchie du PROPRIÉTAIRE de la
 * matrice — DA → DD → Directeur (User.TP_DA__c / TP_DD__c / TP_Directeur__c, lus au moment du
 * passage), un seul destinataire : le niveau au-dessus du valideur choisi. Aucune vérification de
 * permission, plus aucun cercle par entité ni volet « manager du demandeur ». Les tests identifient
 * le destinataire réel par batch.escalationRecipientIdByEmail (@TestVisible), pas seulement par un
 * nombre d'e-mails.
 */
@IsTest
private class AR_DerogationReminderBatchTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Relance',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Relance', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
    }

    private static Id positionId() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Relance' LIMIT 1].Id;
    }

    // Datetime.now().getTime() seul peut collisionner entre deux insertions rapprochées dans la
    // même méthode de test (plusieurs users créés en quelques millisecondes) : un compteur garantit
    // l'unicité du Username, requis par Salesforce.
    private static Integer userCounter = 0;

    private static User newUser(String key, Boolean active) {
        return newUser(key, active, null, null, null);
    }

    /** Utilisateur, éventuellement avec sa propre hiérarchie (DA/DD/Directeur) — c'est le cas du
     * propriétaire de la matrice. Aucune permission : l'escalade n'en vérifie jamais. */
    private static User newUser(String key, Boolean active, Id da, Id dd, Id directeur) {
        userCounter++;
        User u = new User(
            LastName = 'Relance ' + key,
            Email = key + '@example.com.invalid',
            Username = 'ar.relance.' + key + userCounter + Datetime.now().getTime() + '@example.com.invalid',
            Alias = key.left(8),
            IsActive = active,
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            ProfileId = AR_TestPersona.standardProfileId(),
            FederationIdentifier = 'ar.relance.' + key + userCounter + Datetime.now().getTime(),
            TP_DA__c = da,
            TP_DD__c = dd,
            TP_Directeur__c = directeur
        );
        // MIXED_DML_OPERATION : User est un objet de configuration, isolé dans un System.runAs pour ne
        // pas empoisonner la DML métier (AR_Price_Matrix__c/AR_Derogation__c) plus loin dans le test.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static AR_Price_Matrix__c newMatrix(String name, Id ownerId) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = ownerId,
            AR_Position__c = positionId(),
            AR_Position_Name__c = name,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'En dérogation',
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Proposed_TJM__c = 480
        );
        insert m;
        return m;
    }

    private static AR_Derogation__c newDerogation(String matrixLabel, Integer hoursAgo, Id validatorId, Boolean reminderSent, Id ownerId) {
        AR_Price_Matrix__c m = newMatrix(matrixLabel, ownerId);
        AR_Derogation__c d = new AR_Derogation__c(
            AR_Price_Matrix__c = m.Id,
            AR_Selected_Validator__c = validatorId,
            AR_Requester_Reason__c = 'Motif test',
            AR_Requested_At__c = System.now().addHours(-hoursAgo),
            AR_Reminder_Sent__c = reminderSent,
            AR_Reminder_Sent_Date__c = reminderSent ? System.now().addHours(-hoursAgo + 1) : null
        );
        insert d;
        return d;
    }

    private static void setGeneralSettings(Boolean enabled, Decimal reminderHours, Decimal escalationHours, Decimal maxPerRun) {
        // AR_Draft_Purge_* et AR_Max_Derogation_Penalty__c sont requis au niveau champ (hérités de
        // sessions antérieures, sans rapport avec ce bloc) : le singleton AR_General_Setting__c ne
        // peut jamais s'insérer sans eux, même dans un test qui ne teste pas la purge.
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Derogation_Reminder_Enabled__c = enabled,
            AR_Derogation_Reminder_Hours__c = reminderHours,
            AR_Derogation_Escalation_Hours__c = escalationHours,
            AR_Derogation_Reminder_Max_Per_Run__c = maxPerRun,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Working_Days_Per_Year__c = 218,
            AR_Markup_Percent__c = 18,
            AR_Markup_Max__c = 60,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Draft_Purge_Enabled__c = false,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Warning_Days__c = 5,
            AR_Draft_Purge_Max_Per_Run__c = 200
        );
    }

    /** Même convention que AR_DraftPurgeBatchTest.runPurgeBatchOnce : exécution synchrone, hors
     * Database.executeBatch, pour enchaîner plusieurs passages sous un seul Test.startTest/stopTest.
     * Retourne l'instance pour inspecter les destinataires réels de l'escalade. */
    private static AR_DerogationReminderBatch runReminderBatchOnce() {
        AR_DerogationReminderBatch batch = new AR_DerogationReminderBatch();
        Database.QueryLocator locator = batch.start(null);
        List<AR_Derogation__c> scope = new List<AR_Derogation__c>();
        Database.QueryLocatorIterator it = locator.iterator();
        while (it.hasNext()) {
            scope.add((AR_Derogation__c) it.next());
        }
        batch.execute(null, scope);
        batch.finish(null);
        return batch;
    }

    /** Le seul destinataire attendu d'une escalade : e-mail et Id (l'Id alimente le canal in-app). */
    private static void assertSingleEscalationRecipient(AR_DerogationReminderBatch batch, User expected, String message) {
        System.assertEquals(1, batch.escalationRecipientIdByEmail.size(), message + ' — un seul destinataire attendu');
        System.assertEquals(expected.Id, batch.escalationRecipientIdByEmail.get(expected.Email), message);
    }

    /** Matrice dont le propriétaire a la chaîne complète DA → DD → Directeur ; retourne les quatre. */
    private class Chain {
        User da;
        User dd;
        User directeur;
        User owner;
    }

    private static Chain newChain(String key) {
        Chain c = new Chain();
        c.da = newUser(key + 'da', true);
        c.dd = newUser(key + 'dd', true);
        c.directeur = newUser(key + 'dir', true);
        c.owner = newUser(key + 'own', true, c.da.Id, c.dd.Id, c.directeur.Id);
        return c;
    }

    @IsTest
    static void testDisabled_isNoOp() {
        Chain c = newChain('dis');
        newDerogation('Dérogation désactivée', 100, c.da.Id, false, c.owner.Id);
        setGeneralSettings(false, 12, 48, 200);

        Test.startTest();
        runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Reminder_Sent__c, AR_Escalated__c FROM AR_Derogation__c LIMIT 1];
        System.assertEquals(false, reloaded.AR_Reminder_Sent__c, 'Désactivé : aucune relance');
        System.assertEquals(false, reloaded.AR_Escalated__c, 'Désactivé : aucune escalade');
    }

    @IsTest
    static void testReminderThresholdReached_sendsReminderDigest_marksFlag() {
        Chain c = newChain('rem');
        newDerogation('Dérogation à relancer', 13, c.da.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);
        Integer inAppAttemptsBefore = AR_NotificationService.inAppEligibleAttempts;

        Test.startTest();
        runReminderBatchOnce();
        System.assert(Limits.getEmailInvocations() > 0, 'un digest de relance doit être envoyé au valideur sélectionné');
        Test.stopTest();

        // Session 34 : l'Id du valideur (AR_Selected_Validator__c, déjà connu de la dérogation) doit
        // avoir été transmis jusqu'au canal in-app, pas seulement l'e-mail.
        System.assertEquals(
            inAppAttemptsBefore + 1,
            AR_NotificationService.inAppEligibleAttempts,
            'l\'Id du valideur sélectionné doit atteindre le canal in-app via le digest de relance'
        );

        AR_Derogation__c reloaded = [
            SELECT AR_Reminder_Sent__c, AR_Reminder_Sent_Date__c, AR_Escalated__c
            FROM AR_Derogation__c
        ];
        System.assertEquals(true, reloaded.AR_Reminder_Sent__c);
        System.assertNotEquals(null, reloaded.AR_Reminder_Sent_Date__c);
        System.assertEquals(false, reloaded.AR_Escalated__c, 'palier 1 seulement, pas encore escaladée');
    }

    @IsTest
    static void testBelowReminderThreshold_neverTouched() {
        Chain c = newChain('rec');
        newDerogation('Dérogation récente', 2, c.da.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Reminder_Sent__c FROM AR_Derogation__c LIMIT 1];
        System.assertEquals(false, reloaded.AR_Reminder_Sent__c, 'demandée il y a 2h, seuil 12h : trop tôt');
    }

    // ---------------------------------------------------------------------
    // Escalade par la hiérarchie du propriétaire : niveau AU-DESSUS du valideur choisi.
    // ---------------------------------------------------------------------

    @IsTest
    static void testEscalation_validatorIsDa_goesToDd_withDelayReason() {
        Chain c = newChain('dadd');
        newDerogation('Dérogation DA → DD', 49, c.da.Id, true, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);
        Integer inAppAttemptsBefore = AR_NotificationService.inAppEligibleAttempts;

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        System.assertEquals(1, Limits.getEmailInvocations(), 'un seul digest d\'escalade');
        Test.stopTest();

        assertSingleEscalationRecipient(batch, c.dd, 'valideur = DA : l\'escalade va au DD');
        System.assertEquals(inAppAttemptsBefore + 1, AR_NotificationService.inAppEligibleAttempts, 'l\'Id du destinataire atteint le canal in-app');
        AR_Derogation__c reloaded = [
            SELECT AR_Escalated__c, AR_Escalated_Date__c, AR_Escalation_Reason__c, AR_Reminder_Sent__c
            FROM AR_Derogation__c
        ];
        System.assertEquals(true, reloaded.AR_Escalated__c);
        System.assertNotEquals(null, reloaded.AR_Escalated_Date__c);
        System.assertEquals('Délai dépassé', reloaded.AR_Escalation_Reason__c);
        System.assertEquals(true, reloaded.AR_Reminder_Sent__c, 'la relance avait bien été envoyée avant l\'escalade');
    }

    @IsTest
    static void testEscalation_validatorIsDd_goesToDirecteur() {
        Chain c = newChain('dddir');
        newDerogation('Dérogation DD → Directeur', 49, c.dd.Id, true, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        assertSingleEscalationRecipient(batch, c.directeur, 'valideur = DD : l\'escalade va au Directeur');
        System.assertEquals(true, [SELECT AR_Escalated__c FROM AR_Derogation__c].AR_Escalated__c);
    }

    @IsTest
    static void testEscalation_validatorOutsideChain_goesToDa() {
        Chain c = newChain('hors');
        User matthieu = newUser('matthieu', true); // valideur de la phase de test, hors chaîne
        newDerogation('Dérogation valideur hors chaîne', 49, matthieu.Id, true, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        assertSingleEscalationRecipient(batch, c.da, 'valideur hors chaîne : l\'escalade part du DA');
    }

    @IsTest
    static void testEscalation_emptyLevelIsSkipped() {
        User da = newUser('skda', true);
        User directeur = newUser('skdir', true);
        User owner = newUser('skown', true, da.Id, null, directeur.Id); // DD vide
        newDerogation('Dérogation DD vide', 49, da.Id, true, owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        assertSingleEscalationRecipient(batch, directeur, 'DD vide : on saute au Directeur');
    }

    @IsTest
    static void testEscalation_inactiveLevelIsSkipped() {
        User da = newUser('inda', true);
        User ddInactive = newUser('indd', false);
        User directeur = newUser('indir', true);
        User owner = newUser('inown', true, da.Id, ddInactive.Id, directeur.Id);
        newDerogation('Dérogation DD inactif', 49, da.Id, true, owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        assertSingleEscalationRecipient(batch, directeur, 'DD inactif : on saute au Directeur');
    }

    @IsTest
    static void testEscalation_nothingAbove_alertsAdminAndNeverMarksEscalated() {
        Chain c = newChain('top');
        newDerogation('Dérogation valideur au sommet', 49, c.directeur.Id, true, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        System.assert(
            Limits.getEmailInvocations() > 0,
            'une alerte de configuration doit être envoyée à l\'administrateur (AR_Gating_Admin_Alert_Email)'
        );
        Test.stopTest();

        System.assertEquals(0, batch.escalationRecipientIdByEmail.size(), 'rien au-dessus du Directeur : aucun destinataire');
        AR_Derogation__c reloaded = [SELECT AR_Escalated__c, AR_Escalation_Reason__c FROM AR_Derogation__c];
        System.assertEquals(false, reloaded.AR_Escalated__c, 'jamais marquée escaladée sans destinataire');
        System.assertEquals(null, reloaded.AR_Escalation_Reason__c);
    }

    @IsTest
    static void testEscalation_noHierarchyOnOwner_alertsAdmin_retriedOnNextRun() {
        User owner = newUser('nohier', true); // ni DA, ni DD, ni Directeur
        User validator = newUser('nohierval', true);
        newDerogation('Dérogation sans hiérarchie', 49, validator.Id, true, owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        // Les deux passages dans la même fenêtre startTest/stopTest : Test.startTest() réinitialise
        // Limits.getEmailInvocations() (piège déjà documenté dans AR_NotificationServiceTest). Deux
        // alertes cumulées prouvent directement la réalerte à chaque passage.
        Test.startTest();
        runReminderBatchOnce();
        runReminderBatchOnce();
        System.assertEquals(2, Limits.getEmailInvocations(), 'tant que rien n\'est corrigé, chaque passage réalerte');
        Test.stopTest();

        System.assertEquals(false, [SELECT AR_Escalated__c FROM AR_Derogation__c].AR_Escalated__c);
    }

    @IsTest
    static void testEscalation_hierarchyReadAtPassTime_neverFrozen() {
        Chain c = newChain('live');
        newDerogation('Dérogation hiérarchie changée', 49, c.da.Id, true, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);
        // Le DD du propriétaire change entre la demande et le passage du batch.
        User newDd = newUser('livenewdd', true);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = c.owner.Id, TP_DD__c = newDd.Id);
        }

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        assertSingleEscalationRecipient(batch, newDd, 'la hiérarchie est lue au moment du passage, jamais figée');
    }

    @IsTest
    static void testEscalation_noPermissionCheck_activeValidatorWithoutAnyPermissionIsJustReminded() {
        // Session 132 : l'application ne vérifie jamais la permission AR_Approve_Derogation d'un
        // autre utilisateur (c'est aux administrateurs de la donner au déploiement). Un valideur
        // actif, sans aucun permission set, n'est donc PAS « absent » : relance normale, pas
        // d'escalade immédiate.
        Chain c = newChain('noperm');
        User plain = newUser('noperm', true);
        newDerogation('Dérogation valideur sans permission', 13, plain.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Escalated__c, AR_Reminder_Sent__c FROM AR_Derogation__c];
        System.assertEquals(true, reloaded.AR_Reminder_Sent__c, 'relance envoyée au valideur choisi');
        System.assertEquals(false, reloaded.AR_Escalated__c, 'aucune escalade immédiate pour une permission supposée manquante');
        System.assertEquals(0, batch.escalationRecipientIdByEmail.size());
    }

    @IsTest
    static void testInactiveValidator_escalatesImmediately_withoutWaitingForDelay() {
        Chain c = newChain('inact');
        User inactiveValidator = newUser('valinactive', false);
        // Demandée il y a seulement 1h : bien en-deçà du seuil de relance (12h) ET d'escalade (48h).
        newDerogation('Dérogation valideur absent', 1, inactiveValidator.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c reloaded = [
            SELECT AR_Escalated__c, AR_Escalation_Reason__c, AR_Reminder_Sent__c
            FROM AR_Derogation__c
        ];
        System.assertEquals(true, reloaded.AR_Escalated__c, 'valideur détecté inactif : escalade immédiate, sans attendre le délai');
        System.assertEquals('Valideur absent', reloaded.AR_Escalation_Reason__c);
        System.assertEquals(false, reloaded.AR_Reminder_Sent__c, 'la relance est court-circuitée, pas juste "marquée" sans envoi');
        assertSingleEscalationRecipient(batch, c.da, 'valideur hors chaîne (inactif) : l\'escalade part du DA');
    }

    @IsTest
    static void testNoSelectedValidator_escalatesImmediatelyToDa() {
        Chain c = newChain('nosel');
        newDerogation('Dérogation sans valideur', 1, null, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        AR_DerogationReminderBatch batch = runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Escalated__c, AR_Escalation_Reason__c FROM AR_Derogation__c];
        System.assertEquals(true, reloaded.AR_Escalated__c);
        System.assertEquals('Valideur absent', reloaded.AR_Escalation_Reason__c);
        assertSingleEscalationRecipient(batch, c.da, 'aucun valideur choisi : l\'escalade part du DA');
    }

    @IsTest
    static void testEscalatedDerogation_neverProcessedAgain() {
        Chain c = newChain('once');
        User inactiveValidator = newUser('valonce', false);
        newDerogation('Dérogation traitée une fois', 1, inactiveValidator.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        runReminderBatchOnce();
        AR_Derogation__c afterFirstRun = [SELECT AR_Escalated_Date__c FROM AR_Derogation__c];

        Test.startTest();
        AR_DerogationReminderBatch second = runReminderBatchOnce();
        Test.stopTest();

        AR_Derogation__c afterSecondRun = [SELECT AR_Escalated_Date__c FROM AR_Derogation__c];
        System.assertEquals(
            afterFirstRun.AR_Escalated_Date__c,
            afterSecondRun.AR_Escalated_Date__c,
            'une dérogation déjà escaladée ne doit plus jamais être retraitée'
        );
        System.assertEquals(0, second.escalationRecipientIdByEmail.size(), 'aucune seconde escalade');
    }

    @IsTest
    static void testDecidedDerogation_neverProcessed() {
        Chain c = newChain('dec');
        AR_Derogation__c d = newDerogation('Dérogation déjà décidée', 100, c.da.Id, false, c.owner.Id);
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = d.Id, AR_Decision__c = 'Acceptée', AR_Decided_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        setGeneralSettings(true, 12, 48, 200);

        Test.startTest();
        runReminderBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'une dérogation déjà décidée ne doit générer aucun envoi');
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Reminder_Sent__c, AR_Escalated__c FROM AR_Derogation__c WHERE Id = :d.Id];
        System.assertEquals(false, reloaded.AR_Reminder_Sent__c);
        System.assertEquals(false, reloaded.AR_Escalated__c);
    }

    @IsTest
    static void testMaxPerRun_capsVolumeProcessedInOneExecution() {
        Chain c = newChain('cap');
        newDerogation('Dérogation plafond 1', 13, c.da.Id, false, c.owner.Id);
        newDerogation('Dérogation plafond 2', 13, c.da.Id, false, c.owner.Id);
        newDerogation('Dérogation plafond 3', 13, c.da.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 2);

        Test.startTest();
        runReminderBatchOnce();
        Test.stopTest();

        Integer remindedCount = [SELECT COUNT() FROM AR_Derogation__c WHERE AR_Reminder_Sent__c = true];
        System.assertEquals(2, remindedCount, 'le plafond par exécution doit être respecté même si plus de dérogations sont éligibles');
    }

    @IsTest
    static void testEscalationTarget_skipsRequesterAndOwner() {
        Chain c = newChain('skip');
        User owner = AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ c.owner.Id }).get(c.owner.Id);

        System.assertEquals(c.dd.Id, AR_DerogationReminderBatch.escalationTarget(owner, c.da.Id, null).Id);
        System.assertEquals(c.directeur.Id, AR_DerogationReminderBatch.escalationTarget(owner, c.da.Id, c.dd.Id).Id,
            'Le niveau égal au demandeur est sauté');
        System.assertEquals(c.dd.Id, AR_DerogationReminderBatch.escalationTarget(owner, null, c.da.Id).Id);
        System.assertEquals(null, AR_DerogationReminderBatch.escalationTarget(owner, c.dd.Id, c.directeur.Id),
            'Plus personne au-dessus une fois le demandeur exclu');
    }

    @IsTest
    static void testEscalationTarget_directEntryPoint_nullOwnerGivesNull() {
        System.assertEquals(null, AR_DerogationReminderBatch.escalationTarget(null, null));
    }

    /**
     * Scénario complet : demande à T0, relance à T+13h, escalade à T+49h (DA → DD), décision, puis
     * aucun envoi ne doit suivre. AR_Requested_At__c est un champ métier ordinaire : le repousser
     * dans le temps entre deux passages simule une « transaction ultérieure » sans attendre de vraies
     * heures. AR_TriggerBypass n'est nécessaire que parce qu'AR_DerogationTriggerHandler bloque toute
     * édition hors service.
     */
    @IsTest
    static void testFullLifecycle_t0ReminderT12hEscalationT48hDecisionT50h_noFurtherSendsAfterDecision() {
        Chain c = newChain('life');
        AR_Derogation__c d = newDerogation('Dérogation cycle complet', 0, c.da.Id, false, c.owner.Id);
        setGeneralSettings(true, 12, 48, 200);

        // T+13h : passe le seuil de relance (12h), pas encore celui d'escalade (48h).
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = d.Id, AR_Requested_At__c = System.now().addHours(-13));
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        runReminderBatchOnce();
        AR_Derogation__c afterReminder = [SELECT AR_Reminder_Sent__c, AR_Escalated__c FROM AR_Derogation__c WHERE Id = :d.Id];
        System.assertEquals(true, afterReminder.AR_Reminder_Sent__c, 'T+13h : relance envoyée');
        System.assertEquals(false, afterReminder.AR_Escalated__c, 'T+13h : pas encore escaladée');

        // T+49h : passe le seuil d'escalade (48h).
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = d.Id, AR_Requested_At__c = System.now().addHours(-49));
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_DerogationReminderBatch escalationRun = runReminderBatchOnce();
        AR_Derogation__c afterEscalation = [
            SELECT AR_Escalated__c, AR_Escalation_Reason__c
            FROM AR_Derogation__c
            WHERE Id = :d.Id
        ];
        System.assertEquals(true, afterEscalation.AR_Escalated__c, 'T+49h : escaladée');
        System.assertEquals('Délai dépassé', afterEscalation.AR_Escalation_Reason__c);
        assertSingleEscalationRecipient(escalationRun, c.dd, 'T+49h : valideur = DA, l\'escalade va au DD');

        // T+50h : décision.
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = d.Id, AR_Decision__c = 'Acceptée', AR_Decided_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        // Un passage supplémentaire du batch, largement après T+50h, ne doit plus rien envoyer.
        Test.startTest();
        runReminderBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'dérogation décidée : plus aucun envoi ne doit suivre, quel que soit le retard du batch');
        Test.stopTest();
    }
}