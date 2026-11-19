/**
 * Tests AR_DraftPurgeBatch. Depuis la migration __mdt → objet custom (session 23), les seuils sont
 * pilotés par un vrai `AR_General_Setting__c` inséré par chaque test (setGeneralSettings) — plus
 * besoin de point d'injection dédié.
 *
 * LastModifiedDate ne peut pas être forcé dans le passé en test : les scénarios
 * « avertissement » et « purge » utilisent des seuils à 0 jour (purgeDays/warningDays = 0), ce qui
 * rend un enregistrement fraîchement inséré/modifié immédiatement éligible (System.now() au moment
 * de la requête est toujours postérieur, même de quelques millisecondes, à son LastModifiedDate) —
 * technique standard pour ce type de logique en Apex.
 */
@IsTest
private class AR_DraftPurgeBatchTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Purge',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Purge', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        insert new AR_Reason__c(
            Name = 'Motif Purge',
            AR_Applies_To_Version__c = true,
            AR_Applies_To_Derogation__c = true,
            AR_Active__c = true
        );
    }

    private static Id positionId() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Purge' LIMIT 1].Id;
    }

    private static AR_Price_Matrix__c newDraft(String name) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Position_Name__c = name,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 480
        );
        insert m;
        return m;
    }

    /**
     * Exécute le batch de façon entièrement synchrone, sans passer par Database.executeBatch : un
     * seul Test.startTest()/stopTest() est autorisé par méthode de test, alors que plusieurs
     * scénarios ici ont besoin d'enchaîner deux passages (avertir, puis purger) avec des
     * assertions entre les deux. bc n'est jamais lu par cette implémentation (start/execute/finish),
     * null est donc sans risque.
     */
    private static void runPurgeBatchOnce() {
        AR_DraftPurgeBatch batch = new AR_DraftPurgeBatch();
        Database.QueryLocator locator = batch.start(null);
        List<AR_Price_Matrix__c> scope = new List<AR_Price_Matrix__c>();
        Database.QueryLocatorIterator it = locator.iterator();
        while (it.hasNext()) {
            scope.add((AR_Price_Matrix__c) it.next());
        }
        batch.execute(null, scope);
        batch.finish(null);
    }

    private static void setGeneralSettings(
        Boolean enabled,
        Decimal purgeDays,
        Decimal warningDays,
        Decimal maxPerRun
    ) {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Draft_Purge_Enabled__c = enabled,
            AR_Draft_Purge_Days__c = purgeDays,
            AR_Draft_Purge_Warning_Days__c = warningDays,
            AR_Draft_Purge_Max_Per_Run__c = maxPerRun,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Working_Days_Per_Year__c = 218,
            AR_Markup_Percent__c = 18,
            AR_Markup_Max__c = 60,
            AR_Max_Derogation_Penalty__c = 70
        );
    }

    @IsTest
    static void testDisabled_isNoOp() {
        AR_Price_Matrix__c draft = newDraft('Brouillon disabled');
        setGeneralSettings(false, 0, 0, 200);

        Test.startTest();
        runPurgeBatchOnce();
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Purge_Warning_Sent__c FROM AR_Price_Matrix__c WHERE Id = :draft.Id];
        System.assertEquals(false, reloaded.AR_Purge_Warning_Sent__c, 'Désactivé : aucun brouillon ne doit être touché');
    }

    @IsTest
    static void testHighThreshold_neverEligible() {
        AR_Price_Matrix__c draft = newDraft('Brouillon récent');
        setGeneralSettings(true, 9999, 5, 200);

        Test.startTest();
        runPurgeBatchOnce();
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Purge_Warning_Sent__c FROM AR_Price_Matrix__c WHERE Id = :draft.Id];
        System.assertEquals(false, reloaded.AR_Purge_Warning_Sent__c, 'Un seuil élevé ne doit rien déclencher sur un brouillon récent');
    }

    @IsTest
    static void testValidatedMatrix_neverTouchedEvenWithZeroThreshold() {
        AR_Price_Matrix__c m = newDraft('Matrice décidée');
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Status__c = 'Validée', AR_Validated_At__c = System.now());
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        setGeneralSettings(true, 0, 0, 200);

        Test.startTest();
        runPurgeBatchOnce();
        runPurgeBatchOnce();
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :m.Id],
            'Seul un Brouillon peut être purgé, jamais une matrice décidée'
        );
    }

    @IsTest
    static void testWarnThenPurge_fullLifecycle_logsAndDeletes() {
        AR_Price_Matrix__c draft = newDraft('Brouillon à purger');
        insert new AR_Reason_Selection__c(
            AR_Price_Matrix__c = draft.Id,
            AR_Reason__c = [SELECT Id FROM AR_Reason__c LIMIT 1].Id
        );
        setGeneralSettings(true, 0, 0, 200);

        Test.startTest();
        // Passage 1 : avertissement. Limits.getEmailInvocations() doit être lu dans la même
        // fenêtre startTest/stopTest que l'envoi : après stopTest(), le compteur repart à zéro
        // (même convention que AR_PricingMatrixServiceTest.testRequestDerogation_success...).
        runPurgeBatchOnce();
        System.assert(Limits.getEmailInvocations() > 0, 'Un e-mail de synthèse doit être envoyé au propriétaire');
        Test.stopTest();

        AR_Price_Matrix__c warned = [
            SELECT AR_Purge_Warning_Sent__c, AR_Purge_Warning_Sent_Date__c
            FROM AR_Price_Matrix__c
            WHERE Id = :draft.Id
        ];
        System.assertEquals(true, warned.AR_Purge_Warning_Sent__c);
        System.assertEquals(Date.today(), warned.AR_Purge_Warning_Sent_Date__c);

        // Passage 2 : purge (warningDays = 0, déjà satisfait).
        runPurgeBatchOnce();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :draft.Id],
            'Le brouillon doit être supprimé au second passage'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :draft.Id],
            'Cascade : les sélections de motif liées disparaissent avec la matrice'
        );
        List<AR_Purge_Log__c> logs = [
            SELECT AR_Matrix_Name__c, AR_Position_Name__c, AR_Purged_At__c
            FROM AR_Purge_Log__c
            WHERE AR_Position_Name__c = 'Brouillon à purger'
        ];
        System.assertEquals(1, logs.size(), 'La suppression doit être journalisée avant de disparaître');
        System.assertNotEquals(null, logs[0].AR_Purged_At__c);
    }

    /** Cas explicitement demandé : un brouillon averti puis repris par son propriétaire ne doit
     * pas être purgé plus tard — perte de donnée silencieuse sinon. */
    @IsTest
    static void testWarnedDraft_editedAfterward_resetsWarningAndSurvivesPurge() {
        AR_Price_Matrix__c draft = newDraft('Brouillon repris');
        setGeneralSettings(true, 0, 0, 200);
        runPurgeBatchOnce();

        AR_Price_Matrix__c warned = [SELECT AR_Purge_Warning_Sent__c FROM AR_Price_Matrix__c WHERE Id = :draft.Id];
        System.assertEquals(true, warned.AR_Purge_Warning_Sent__c);

        Test.startTest();
        // Reprise réelle par le propriétaire : simple update, sans bypass (Brouillon = éditable).
        update new AR_Price_Matrix__c(Id = draft.Id, AR_Proposed_TJM__c = 500);
        Test.stopTest();

        AR_Price_Matrix__c afterEdit = [
            SELECT AR_Purge_Warning_Sent__c, AR_Purge_Warning_Sent_Date__c
            FROM AR_Price_Matrix__c
            WHERE Id = :draft.Id
        ];
        System.assertEquals(false, afterEdit.AR_Purge_Warning_Sent__c, 'La reprise doit réinitialiser l\'avertissement');
        System.assertEquals(null, afterEdit.AR_Purge_Warning_Sent_Date__c);

        // Un passage de purge supplémentaire ne fait que réavertir (l'ancien avertissement a été
        // invalidé), il ne supprime pas.
        runPurgeBatchOnce();
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :draft.Id],
            'Un brouillon repris ne doit jamais être supprimé silencieusement'
        );
    }

    @IsTest
    static void testMaxPerRun_capsVolumeProcessedInOneExecution() {
        newDraft('Brouillon plafond 1');
        newDraft('Brouillon plafond 2');
        newDraft('Brouillon plafond 3');
        setGeneralSettings(true, 0, 0, 2);

        Test.startTest();
        runPurgeBatchOnce();
        Test.stopTest();

        Integer warnedCount = [
            SELECT COUNT()
            FROM AR_Price_Matrix__c
            WHERE AR_Position_Name__c LIKE 'Brouillon plafond%' AND AR_Purge_Warning_Sent__c = true
        ];
        System.assertEquals(2, warnedCount, 'Le plafond par exécution doit être respecté, même si plus de brouillons sont éligibles');
    }

    @IsTest
    static void testPurgeLog_rootAndNonRoot_carryOwnerEntityPerimeter() {
        update new cxsrec__cxsPosition__c(Id = positionId(), TP_P_rim_tre__c = 'NEO');
        AR_Price_Matrix__c root = newDraft('Racine');
        AR_Price_Matrix__c child = newDraft('Version 2');
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = child.Id, AR_Root_Matrix__c = root.Id, AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'));
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        String rootName = [SELECT Name FROM AR_Price_Matrix__c WHERE Id = :root.Id].Name;
        String childName = [SELECT Name FROM AR_Price_Matrix__c WHERE Id = :child.Id].Name;
        setGeneralSettings(true, 0, 0, 200);

        Test.startTest();
        runPurgeBatchOnce(); // avertissement
        runPurgeBatchOnce(); // purge
        Test.stopTest();

        Map<String, AR_Purge_Log__c> logs = new Map<String, AR_Purge_Log__c>();
        for (AR_Purge_Log__c l : [SELECT AR_Matrix_Name__c, AR_Owner_Id__c, AR_Entity_Id__c, AR_Entity_Name__c, AR_Perimeter__c, AR_Was_Root__c FROM AR_Purge_Log__c]) {
            logs.put(l.AR_Matrix_Name__c, l);
        }
        System.assertEquals(2, logs.size());
        AR_Purge_Log__c rootLog = logs.get(rootName);
        System.assertNotEquals(null, rootLog, 'Journal de la racine');
        System.assertEquals(true, rootLog.AR_Was_Root__c);
        System.assertEquals(null, rootLog.AR_Entity_Id__c);
        System.assertEquals('NEO', rootLog.AR_Perimeter__c);
        System.assertEquals(String.valueOf(UserInfo.getUserId()), rootLog.AR_Owner_Id__c);
        AR_Purge_Log__c childLog = logs.get(childName);
        System.assertEquals(false, childLog.AR_Was_Root__c);
        System.assertEquals(String.valueOf(AR_TestPersona.entityRefId('Abylsen GAMMA')), childLog.AR_Entity_Id__c);
        System.assertNotEquals(null, childLog.AR_Entity_Name__c);
    }
}