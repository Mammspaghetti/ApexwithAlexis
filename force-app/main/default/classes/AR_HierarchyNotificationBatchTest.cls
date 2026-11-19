/**
 * Tests AR_HierarchyNotificationBatch (session 29 §4). testOverrideIsWeeklyDispatchDay permet de
 * forcer les deux branches de la fréquence Hebdomadaire sans dépendre du jour réel d'exécution.
 */
@IsTest
private class AR_HierarchyNotificationBatchTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Hiérarchie',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Hiérarchie', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
    }

    private static Id positionId() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Hiérarchie' LIMIT 1].Id;
    }

    private static Integer userCounter = 0;

    private static User newUser(String key) {
        userCounter++;
        User u = new User(
            LastName = 'Hierarchie ' + key,
            Email = key + '@example.com.invalid',
            Username = 'ar.hierarchie.' + key + userCounter + Datetime.now().getTime() + '@example.com.invalid',
            Alias = key.left(8),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            ProfileId = AR_TestPersona.standardProfileId(),
            FederationIdentifier = 'ar.hierarchie.' + key + userCounter + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    private static AR_Price_Matrix__c newValidatedMatrix(String name, Id ownerId) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Position_Name__c = name,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Validée',
            AR_Proposed_TJM__c = 480,
            AR_Validated_At__c = System.now(),
            OwnerId = ownerId
        );
        insert m;
        return m;
    }

    private static void setFrequency(String frequency) {
        // AR_Draft_Purge_* et AR_Max_Derogation_Penalty__c sont requis au niveau champ (hérités de
        // sessions antérieures, sans rapport avec ce bloc).
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Hierarchy_Notification_Frequency__c = frequency,
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

    private static void runBatchOnce() {
        AR_HierarchyNotificationBatch batch = new AR_HierarchyNotificationBatch();
        Database.QueryLocator locator = batch.start(null);
        List<AR_Price_Matrix__c> scope = new List<AR_Price_Matrix__c>();
        Database.QueryLocatorIterator it = locator.iterator();
        while (it.hasNext()) {
            scope.add((AR_Price_Matrix__c) it.next());
        }
        batch.execute(null, scope);
        batch.finish(null);
    }

    @IsTest
    static void testFrequencyDisabled_isNoOp() {
        User manager = newUser('mgrdisabled');
        User owner = newUser('ownerdisabled');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        newValidatedMatrix('Matrice désactivée', owner.Id);
        setFrequency('Désactivé');

        Test.startTest();
        runBatchOnce();
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals(false, reloaded.AR_Hierarchy_Notified__c, 'Désactivé : rien ne doit être touché');
    }

    /** Immédiat est géré de façon synchrone par AR_NotificationService, jamais par ce batch — cf.
     * AR_NotificationServiceTest.testSendAutoValidationHierarchyNotificationIfImmediate_*. */
    @IsTest
    static void testFrequencyImmediate_batchNeverProcesses() {
        User manager = newUser('mgrimmediate');
        User owner = newUser('ownerimmediate');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        newValidatedMatrix('Matrice immédiate', owner.Id);
        setFrequency('Immédiat');

        Test.startTest();
        runBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'la fréquence Immédiat ne doit jamais être traitée par ce batch');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals(false, reloaded.AR_Hierarchy_Notified__c, 'laissée à false pour ne pas interférer avec le hook synchrone');
    }

    @IsTest
    static void testFrequencyDaily_sendsDigestAndMarksNotified() {
        User manager = newUser('mgrdaily');
        User owner = newUser('ownerdaily');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        newValidatedMatrix('Matrice quotidienne', owner.Id);
        setFrequency('Quotidien');
        Integer inAppAttemptsBefore = AR_NotificationService.inAppEligibleAttempts;

        Test.startTest();
        runBatchOnce();
        System.assert(Limits.getEmailInvocations() > 0, 'un digest doit être envoyé au manager');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals(true, reloaded.AR_Hierarchy_Notified__c);
        // Session 34 (147 : DA du propriétaire, plus ManagerId) : le destinataire résolu par le batch doit atteindre le canal in-app.
        System.assertEquals(
            inAppAttemptsBefore + 1,
            AR_NotificationService.inAppEligibleAttempts,
            'l\'Id du manager doit atteindre le canal in-app via le digest quotidien'
        );
    }

    @IsTest
    static void testFrequencyWeekly_notDispatchDay_accumulatesWithoutSending() {
        User manager = newUser('mgrweeklyoff');
        User owner = newUser('ownerweeklyoff');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        newValidatedMatrix('Matrice hebdo hors jour', owner.Id);
        setFrequency('Hebdomadaire');

        AR_HierarchyNotificationBatch.testOverrideIsWeeklyDispatchDay = false;
        try {
            Test.startTest();
            runBatchOnce();
            System.assertEquals(0, Limits.getEmailInvocations(), 'hors jour d\'envoi hebdomadaire : rien ne part');
            Test.stopTest();
        } finally {
            AR_HierarchyNotificationBatch.testOverrideIsWeeklyDispatchDay = null;
        }

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals(false, reloaded.AR_Hierarchy_Notified__c, 'doit rester en attente du jour d\'envoi');
    }

    @IsTest
    static void testFrequencyWeekly_dispatchDay_sendsAccumulatedDigest() {
        User manager = newUser('mgrweeklyon');
        User owner = newUser('ownerweeklyon');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        newValidatedMatrix('Matrice hebdo A', owner.Id);
        newValidatedMatrix('Matrice hebdo B', owner.Id);
        setFrequency('Hebdomadaire');

        AR_HierarchyNotificationBatch.testOverrideIsWeeklyDispatchDay = true;
        try {
            Test.startTest();
            runBatchOnce();
            // Une seule matrice validée par manager en une fois : un seul digest, pas un e-mail par
            // matrice, même s'il y a deux matrices concernées.
            System.assertEquals(1, Limits.getEmailInvocations(), 'un seul digest pour le manager, quel que soit le nombre de matrices');
            Test.stopTest();
        } finally {
            AR_HierarchyNotificationBatch.testOverrideIsWeeklyDispatchDay = null;
        }

        Integer notifiedCount = [
            SELECT COUNT()
            FROM AR_Price_Matrix__c
            WHERE AR_Position_Name__c LIKE 'Matrice hebdo%' AND AR_Hierarchy_Notified__c = true
        ];
        System.assertEquals(2, notifiedCount);
    }

    @IsTest
    static void testValidatedByDerogation_neverPickedUp() {
        User manager = newUser('mgrderog');
        User owner = newUser('ownerderog');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        AR_Price_Matrix__c m = newValidatedMatrix('Matrice dérogation', owner.Id);
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Status__c = 'Validée par dérogation');
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        setFrequency('Quotidien');

        Test.startTest();
        runBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'une validation par dérogation a déjà son propre e-mail de résultat, pas celui-ci');
        Test.stopTest();
    }

    @IsTest
    static void testNoManager_marksNotifiedWithoutSending() {
        User owner = newUser('ownernomanager');
        newValidatedMatrix('Matrice sans manager', owner.Id);
        setFrequency('Quotidien');

        Test.startTest();
        runBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'pas de manager => pas d\'envoi');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals(true, reloaded.AR_Hierarchy_Notified__c, 'marquée notifiée malgré tout, pour ne pas rester indéfiniment dans le balayage');
    }

    @IsTest
    static void testAlreadyNotified_neverReprocessed() {
        User manager = newUser('mgralready');
        User owner = newUser('owneralready');
        update new User(Id = owner.Id, TP_DA__c = manager.Id);
        AR_Price_Matrix__c m = newValidatedMatrix('Matrice déjà notifiée', owner.Id);
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Hierarchy_Notified__c = true);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        setFrequency('Quotidien');

        Test.startTest();
        runBatchOnce();
        System.assertEquals(0, Limits.getEmailInvocations(), 'déjà notifiée : plus jamais reprise');
        Test.stopTest();
    }
}