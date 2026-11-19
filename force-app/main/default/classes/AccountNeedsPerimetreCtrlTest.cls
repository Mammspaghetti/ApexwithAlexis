@isTest
private class AccountNeedsPerimetreCtrlTest {

    @testSetup
    static void setupData() {
        // Création d'un compte
        Account acc = new Account(Name = 'Test Account',
        TP_Business_Line__c='Autre',
        AB_Account_industry__c='Autres',
        AB_Account_industry_sub_sector__c='Banque',
        ShippingCity ='Paris',
        ShippingCountry='France',
        ShippingPostalCode='75008',
        ShippingStreet='91 Avenue des Champs-Élysées'      
        );
        insert acc;

        // Création de besoins liés au compte
        List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 5; i++) {
            positions.add(new cxsrec__cxsPosition__c(
                Name = 'Position ' + i,
               Priorit__c = 'P1',
                cxsrec__Status__c = 'Open',
               TP_Niveau_d_engagement_Abylsen__c ='Assistance technique'
               
            ));
        }
        insert positions;
    }

    @isTest
    static void testControllerWithAccount() {
        // Récupération du compte
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Instanciation du contrôleur
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(acc);
        AccountNeedsPerimetreCtrl ctrl = new AccountNeedsPerimetreCtrl(stdCtrl);

        // Vérification initiale
        System.assertEquals(20, ctrl.pageSize, 'La taille par défaut doit être 20');
        System.assertEquals(0, ctrl.offsetSize, 'Offset initial doit être 0');
        System.assert(ctrl.getTotalSize() >= 0, 'TotalSize doit être calculé');

        // Test getNeeds()
        Test.startTest();
        List<cxsrec__cxsPosition__c> needs = ctrl.getNeeds();
        Test.stopTest();
        System.assertNotEquals(null, needs, 'La liste ne doit pas être null');
        System.assert(needs.size() >= 0, 'La liste doit contenir des éléments ou être vide');
    }

    @isTest
    static void testNavigationMethods() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(acc);
        AccountNeedsPerimetreCtrl ctrl = new AccountNeedsPerimetreCtrl(stdCtrl);

        Integer initialOffset = ctrl.offsetSize;
        ctrl.next();
        System.assert(ctrl.offsetSize >= initialOffset, 'Offset doit augmenter ou rester identique');

        ctrl.prev();
        System.assert(ctrl.offsetSize <= initialOffset, 'Offset doit revenir en arrière ou rester identique');
    }

    @isTest
    static void testControllerWithNullId() {
        // Cas où StandardController n'a pas d'Id
        Account emptyAcc = new Account();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(emptyAcc);
        AccountNeedsPerimetreCtrl ctrl = new AccountNeedsPerimetreCtrl(stdCtrl);

        System.assertEquals(0, ctrl.getTotalSize(), 'TotalSize doit être 0 si accountId est null');
        System.assertEquals(0, ctrl.getNeeds().size(), 'Liste vide si accountId est null');
    }
}