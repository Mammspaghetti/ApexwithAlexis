/**
 * Session 289 (reprise 287b) : tests dédiés de AR_DashboardCosts — somme des 9 postes = coût total du moteur
 * moins le CJM (écart 0), périodes de frais, jours offerts, pivot EUR d'une matrice en GBP.
 */
@IsTest
private class AR_DashboardCostsTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Costs', AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001'
        );
        insert acc;
        insert new cxsrec__cxsPosition__c(
            Name = 'Besoin Costs', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
    }

    @IsTest
    static void testPostsPerDay_sumEqualsEngineTotalMinusCjm_withFeePeriodsAndGratuity() {
        AR_Price_Matrix__c m = costMatrix('CDI');
        m.AR_Fee_Periods__c = '[{"days":40,"feeIk":20,"feeMeals":25,"feeLodging":0,"feeOmOther":0}]';
        insert m;
        AR_Price_Matrix__c loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ m.Id }).get(m.Id);
        Map<String, Decimal> posts = AR_DashboardCosts.postsPerDay(loaded);
        AR_PricingCalculator.Context ctx = AR_PricingMatrixService.costContextOf(loaded);
        Decimal expected = AR_PricingCalculator.calcTotalDailyCost(ctx) - AR_PricingCalculator.calcCJM(ctx);
        Decimal sum = 0;
        for (String post : AR_DashboardCosts.POSTS) {
            System.assert(posts.containsKey(post), 'Poste présent : ' + post);
            sum += posts.get(post);
        }
        System.assertEquals(9, AR_DashboardCosts.POSTS.size());
        System.assertEquals(0, (expected - sum).abs().setScale(8, RoundingMode.HALF_UP), 'Écart nul entre la somme des 9 postes et le moteur');
        System.assertEquals((Decimal.valueOf(10 * 60 + 20 * 40) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('fuel').setScale(6, RoundingMode.HALF_UP), 'IK lissées sur la période');
        System.assertEquals((Decimal.valueOf(20 * 60) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('lodging').setScale(6, RoundingMode.HALF_UP));
        System.assertEquals((Decimal.valueOf(2) * AR_PricingCalculator.calcCJM(ctx) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('gratuity').setScale(6, RoundingMode.HALF_UP), 'Jours offerts : 2 × CJM ÷ 100');
        System.assertEquals(6, posts.get('training'));
    }

    @IsTest
    static void testPostsPerDay_nearshoreOnlyGratuity() {
        AR_Price_Matrix__c m = costMatrix('NEARSHORE');
        m.AR_CJM_Nearshore__c = 300;
        insert m;
        AR_Price_Matrix__c loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ m.Id }).get(m.Id);
        Map<String, Decimal> posts = AR_DashboardCosts.postsPerDay(loaded);
        for (String post : AR_DashboardCosts.POSTS) {
            if (post != AR_DashboardCosts.GRATUITY) {
                System.assertEquals(0, posts.get(post), 'Frais ignorés hors CDI/CDD/VIE : ' + post);
            }
        }
        System.assertEquals((Decimal.valueOf(2) * 300 / 100).setScale(6, RoundingMode.HALF_UP), posts.get('gratuity').setScale(6, RoundingMode.HALF_UP));
    }

    @IsTest
    static void testRateToEur_gbpPivotAndFallback() {
        AR_Price_Matrix__c gbp = costMatrix('CDI');
        gbp.AR_Currency_Rate_Applied__c = 1.2;
        AR_Price_Matrix__c legacy = costMatrix('CDI');
        legacy.AR_Currency_Rate_Applied__c = null;
        insert new List<AR_Price_Matrix__c>{ gbp, legacy };
        Map<Id, AR_Price_Matrix__c> loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ gbp.Id, legacy.Id });
        System.assertEquals(1.2, AR_DashboardCosts.rateToEur(loaded.get(gbp.Id)));
        System.assertEquals(1, AR_DashboardCosts.rateToEur(loaded.get(legacy.Id)), 'Matrice antérieure à la multi-devise : taux 1');
        Map<String, Decimal> posts = AR_DashboardCosts.postsPerDay(loaded.get(gbp.Id));
        Decimal gbpTotal = 0;
        for (String post : AR_DashboardCosts.POSTS) {
            gbpTotal += posts.get(post);
        }
        Decimal eurTotal = gbpTotal * AR_DashboardCosts.rateToEur(loaded.get(gbp.Id));
        System.assertEquals((gbpTotal * 1.2).setScale(6, RoundingMode.HALF_UP), eurTotal.setScale(6, RoundingMode.HALF_UP), 'Pivot EUR = montant GBP × taux figé');
        System.assert(eurTotal > gbpTotal, 'Un GBP vaut plus d\'un EUR');
    }

    @IsTest
    static void testWeightDays_billableDays() {
        AR_Price_Matrix__c m = costMatrix('CDI');
        insert m;
        AR_Price_Matrix__c loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ m.Id }).get(m.Id);
        System.assertEquals(AR_PricingMatrixService.billableDaysOf(loaded), AR_DashboardCosts.weightDays(loaded));
        System.assertEquals(100, AR_DashboardCosts.weightDays(loaded), '100 jours, aucun congé planifié');
    }

    private static AR_Price_Matrix__c costMatrix(String contractType) {
        return new AR_Price_Matrix__c(
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1].Id,
            AR_Contract_Type__c = contractType,
            AR_Status__c = 'Brouillon',
            AR_Annual_Salary__c = 50000,
            AR_Fee_IK__c = 10, AR_Fee_Meals__c = 15, AR_Fee_Lodging__c = 20, AR_Fee_OM_Other__c = 5,
            AR_Fee_Computer__c = 2, AR_Fee_Phone__c = 30, AR_Fee_Monthly_Other__c = 20,
            AR_Fee_Training__c = 600, AR_Fee_EPI__c = 218, AR_Fee_OFII_Tax__c = 436, AR_Fee_Other__c = 109,
            AR_Gratuity_Days__c = 2,
            AR_Number_Of_Days__c = 100,
            AR_Planned_Leave_Days__c = 0
        );
    }
}