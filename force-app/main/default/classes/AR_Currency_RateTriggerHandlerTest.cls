/**
 * AR_Currency_RateTriggerHandler : blocage de la suppression des taux de change,
 * garantie de non-rétroactivité (session 50, confirmée session 131b).
 * La suppression est refusée, même pour un administrateur système.
 */
@IsTest
private class AR_Currency_RateTriggerHandlerTest {

    @TestSetup
    static void setup() {
        AR_AdminCommercialService.addCurrencyRate('GBP', 0.85, Date.newInstance(2026, 1, 1));
        AR_AdminCommercialService.addCurrencyRate('CHF', 1.05, Date.newInstance(2026, 1, 1));
    }

    @IsTest
    static void testBeforeDelete_deleteIsBlocked_throwsError() {
        User admin = AR_TestPersona.adminDevises();

        Test.startTest();
        System.runAs(admin) {
            AR_Currency_Rate__c rate = [SELECT Id FROM AR_Currency_Rate__c WHERE AR_Currency_Code__c = 'GBP' LIMIT 1];

            DmlException caught;
            try {
                delete rate;
            } catch (DmlException e) {
                caught = e;
            }

            System.assertNotEquals(null, caught, 'La suppression d\'un taux doit être bloquée');
            System.assert(
                caught.getMessage().contains('Un taux de change ne peut jamais être supprimé'),
                'Le message d\'erreur doit expliciter l\'interdiction'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testBeforeDelete_multipleRates_allBlockedWithSameMessage() {
        User admin = AR_TestPersona.adminDevises();

        Test.startTest();
        System.runAs(admin) {
            List<AR_Currency_Rate__c> rates = [SELECT Id FROM AR_Currency_Rate__c ORDER BY AR_Currency_Code__c];
            System.assertEquals(2, rates.size(), 'Le setup doit créer deux taux');

            DmlException caught;
            try {
                delete rates;
            } catch (DmlException e) {
                caught = e;
            }

            System.assertNotEquals(null, caught, 'La suppression de plusieurs taux doit être bloquée');
            System.assert(
                caught.getMessage().contains('Un taux de change ne peut jamais être supprimé'),
                'Le message d\'erreur doit être cohérent pour tous les taux'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testModify_anotherAdminsRate_succeeds() {
        User admin1 = AR_TestPersona.adminDevises();
        User admin2 = AR_TestPersona.adminDevises();

        // Crée un taux sous admin1
        System.runAs(admin1) {
            AR_AdminCommercialService.addCurrencyRate('CAD', 0.73, Date.newInstance(2026, 1, 1));
        }

        Test.startTest();
        System.runAs(admin2) {
            // admin2 doit pouvoir modifier le taux créé par admin1 (modifyAllRecords=true)
            AR_Currency_Rate__c rate = [SELECT Id, AR_Rate_To_EUR__c FROM AR_Currency_Rate__c WHERE AR_Currency_Code__c = 'CAD' LIMIT 1];
            rate.AR_Rate_To_EUR__c = 0.74;
            update rate;
        }
        Test.stopTest();

        AR_Currency_Rate__c updatedRate = [SELECT AR_Rate_To_EUR__c FROM AR_Currency_Rate__c WHERE AR_Currency_Code__c = 'CAD' LIMIT 1];
        System.assertEquals(0.74, updatedRate.AR_Rate_To_EUR__c, 'La modification du taux d\'un autre admin doit réussir');
    }
}