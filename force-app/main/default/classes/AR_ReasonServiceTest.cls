/**
 * Tests AR_ReasonService : filtrage du catalogue par usage (dérogation/version) + actif, et
 * insertion des sélections (jonction) en respectant le contrôle XOR du trigger.
 */
@IsTest
private class AR_ReasonServiceTest {

    @TestSetup
    static void setup() {
        insert new List<AR_Reason__c>{
            new AR_Reason__c(
                Name = 'Motif Dérogation Seule',
                AR_Applies_To_Derogation__c = true,
                AR_Applies_To_Version__c = false,
                AR_Active__c = true,
                AR_Sort_Order__c = 10
            ),
            new AR_Reason__c(
                Name = 'Motif Version Seule',
                AR_Applies_To_Derogation__c = false,
                AR_Applies_To_Version__c = true,
                AR_Active__c = true,
                AR_Sort_Order__c = 20
            ),
            new AR_Reason__c(
                Name = 'Motif Inactif',
                AR_Applies_To_Derogation__c = true,
                AR_Applies_To_Version__c = true,
                AR_Active__c = false,
                AR_Sort_Order__c = 30
            )
        };

        Account acc = new Account(
            Name = 'Client Reason',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Reason', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        insert new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 500
        );
    }

    @IsTest
    static void testGetReasonOptions_derogation_excludesInactiveAndVersionOnly() {
        Test.startTest();
        List<AR_ReasonService.ReasonOption> options = AR_ReasonService.getReasonOptions('derogation');
        Test.stopTest();

        System.assertEquals(1, options.size());
        System.assertEquals('Motif Dérogation Seule', options[0].label);
    }

    @IsTest
    static void testGetReasonOptions_version_excludesInactiveAndDerogationOnly() {
        Test.startTest();
        List<AR_ReasonService.ReasonOption> options = AR_ReasonService.getReasonOptions('version');
        Test.stopTest();

        System.assertEquals(1, options.size());
        System.assertEquals('Motif Version Seule', options[0].label);
    }

    @IsTest
    static void testGetReasonOptions_unknownUsage_throws() {
        Boolean threw = false;
        try {
            AR_ReasonService.getReasonOptions('n_importe_quoi');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Un usage inconnu doit être rejeté explicitement');
    }

    @IsTest
    static void testInsertSelections_onMatrix_createsOneRowPerReason() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        List<Id> reasonIds = new List<Id>();
        for (AR_Reason__c r : [SELECT Id FROM AR_Reason__c WHERE AR_Active__c = true]) {
            reasonIds.add(r.Id);
        }

        Test.startTest();
        AR_ReasonService.insertSelections(matrix.Id, null, reasonIds);
        Test.stopTest();

        List<AR_Reason_Selection__c> selections = [
            SELECT AR_Reason__c, AR_Price_Matrix__c, AR_Derogation__c
            FROM AR_Reason_Selection__c
            WHERE AR_Price_Matrix__c = :matrix.Id
        ];
        System.assertEquals(2, selections.size());
        for (AR_Reason_Selection__c sel : selections) {
            System.assertEquals(null, sel.AR_Derogation__c);
        }
    }

    @IsTest
    static void testInsertSelections_emptyList_isNoOp() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];

        Test.startTest();
        AR_ReasonService.insertSelections(matrix.Id, null, new List<Id>());
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :matrix.Id]
        );
    }

    // ---------------------------------------------------------------------
    // Administration des motifs (session 23)
    // ---------------------------------------------------------------------

    private static User newNonAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'ReasonAdminTest',
            FirstName = 'AR',
            Alias = 'arrat',
            Email = 'ar.reason.admin.test@abylsengroup.com.invalid',
            Username = 'ar.reason.admin.test@abylsengroup.com.invalid.' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.reason.admin.test.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    @IsTest
    static void testGetAllReasonsForAdmin_includesInactive() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Test.startTest();
        List<AR_ReasonService.ReasonAdminDto> all = AR_ReasonService.getAllReasonsForAdmin();
        Test.stopTest();

        System.assertEquals(3, all.size(), 'La vue admin doit inclure le motif inactif, contrairement à getReasonOptions');
        }
    }

    @IsTest
    static void testGetAllReasonsForAdmin_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();

        Test.startTest();
        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_ReasonService.getAllReasonsForAdmin();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'La vue admin des motifs doit être réservée au domaine Référentiels (AR_Admin_Referentials)');
    }

    @IsTest
    static void testSaveReason_createThenUpdate() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Test.startTest();
        Id reasonId = AR_ReasonService.saveReason(null, 'Nouveau motif', true, false, true, 40);
        Id updatedId = AR_ReasonService.saveReason(reasonId, 'Nouveau motif renommé', true, true, false, 41);
        Test.stopTest();

        System.assertEquals(reasonId, updatedId);
        AR_Reason__c reloaded = [
            SELECT Name, AR_Applies_To_Version__c, AR_Active__c
            FROM AR_Reason__c
            WHERE Id = :reasonId
        ];
        System.assertEquals('Nouveau motif renommé', reloaded.Name);
        System.assertEquals(true, reloaded.AR_Applies_To_Version__c);
        System.assertEquals(false, reloaded.AR_Active__c);
        }
    }

    @IsTest
    static void testSaveReason_blankLabel_throws() {
        Boolean threw = false;
        System.runAs(AR_TestPersona.adminReferentiels()) {
            try {
                AR_ReasonService.saveReason(null, '', true, true, true, 1);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Le libellé du motif est obligatoire');
    }

    @IsTest
    static void testSaveReason_nonAdminReferentiels_throws() {
        User nonAdmin = newNonAdminUser();
        Boolean threw = false;
        String thrownMessage = '';

        Test.startTest();
        System.runAs(nonAdmin) {
            try {
                AR_ReasonService.saveReason(null, 'Motif non autorisé', true, true, true, 50);
            } catch (AuraHandledException e) {
                threw = true;
                thrownMessage = e.getMessage();
            }
        }
        Test.stopTest();

        System.assert(threw, 'Un utilisateur sans AR_Admin_Referentials doit être rejeté');
        System.assert(
            thrownMessage.contains('administrateur'),
            'Le message doit inviter à contacter l\'administrateur, reçu : ' + thrownMessage
        );
    }

    @IsTest
    static void testSaveReason_adminReferentiels_createsReason() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
            Test.startTest();
            Id newReasonId = AR_ReasonService.saveReason(null, 'Nouveau motif admin', true, false, true, 100);
            Test.stopTest();

            AR_Reason__c created = [
                SELECT Id, Name, AR_Applies_To_Derogation__c
                FROM AR_Reason__c
                WHERE Id = :newReasonId
            ];
            System.assertEquals('Nouveau motif admin', created.Name);
            System.assertEquals(true, created.AR_Applies_To_Derogation__c);
        }
    }
}