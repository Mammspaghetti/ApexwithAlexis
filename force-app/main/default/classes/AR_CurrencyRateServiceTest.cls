/**
 * Tests de AR_CurrencyRateService (session 24, socle multi-devises) : résolution du taux par date
 * d'effet, absence de taux (blocage explicite plutôt qu'un repli sur 1), EUR comme pivot sans
 * lookup.
 */
@IsTest
private class AR_CurrencyRateServiceTest {

    @IsTest
    static void testResolveRate_eur_returnsRateOneWithoutQuery() {
        AR_CurrencyRateService.RateResolution result = AR_CurrencyRateService.resolveRate('EUR', Date.today());

        System.assertEquals(1, result.rateToEur, 'EUR est la devise pivot : taux 1 sans ligne de taux');
        System.assertEquals(null, result.effectiveDate, 'EUR : pas de ligne AR_Currency_Rate__c, donc pas de date d\'effet');
    }

    @IsTest
    static void testResolveRate_blankCurrency_treatedAsEur() {
        AR_CurrencyRateService.RateResolution result = AR_CurrencyRateService.resolveRate(null, Date.today());

        System.assertEquals(1, result.rateToEur);
    }

    /**
     * Résolution par date d'effet (le point le plus sensible de la session) : deux lignes GBP,
     * l'ancienne à 1.15 (effet 01/01), la nouvelle à 1.17 (effet 01/08). Une matrice qui résout à
     * une date antérieure au 01/08 doit obtenir 1.15, pas la ligne la plus récente en base.
     */
    @IsTest
    static void testResolveRate_multipleRates_picksMostRecentEffectiveOnOrBeforeReferenceDate() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.15,
            AR_Effective_Date__c = Date.newInstance(2026, 1, 1)
        );
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.newInstance(2026, 8, 1)
        );

        Test.startTest();
        AR_CurrencyRateService.RateResolution beforeAugust = AR_CurrencyRateService.resolveRate(
            'GBP',
            Date.newInstance(2026, 7, 15)
        );
        AR_CurrencyRateService.RateResolution onOrAfterAugust = AR_CurrencyRateService.resolveRate(
            'GBP',
            Date.newInstance(2026, 8, 1)
        );
        Test.stopTest();

        System.assertEquals(1.15, beforeAugust.rateToEur, 'Avant le 01/08, le taux en vigueur est encore l\'ancien');
        System.assertEquals(Date.newInstance(2026, 1, 1), beforeAugust.effectiveDate);
        System.assertEquals(1.17, onOrAfterAugust.rateToEur, 'À la date d\'effet exacte, la nouvelle ligne s\'applique déjà');
        System.assertEquals(Date.newInstance(2026, 8, 1), onOrAfterAugust.effectiveDate);
    }

    /**
     * Le point critique de la session (prompt) : une devise sans taux ne doit jamais être traitée
     * comme un taux de 1 — bloque bruyamment avec un message actionnable.
     */
    @IsTest
    static void testResolveRate_noRateForCurrency_throwsExplicitException() {
        System.runAs(AR_TestPersona.francais()) {
            Boolean threw = false;
            try {
                AR_CurrencyRateService.resolveRate('MAD', Date.today());
            } catch (AR_CurrencyRateService.NoRateAvailableException e) {
                threw = true;
                System.assert(e.getMessage().contains('MAD'), 'Le message doit nommer la devise en cause');
                System.assert(
                    e.getMessage().contains('Devises'),
                    'Le message doit orienter vers l\'onglet Devises de l\'administration (actionnable)'
                );
            }
            System.assertEquals(true, threw, 'Une devise sans taux doit bloquer, jamais retomber sur 1');
        }
    }

    @IsTest
    static void testResolveRate_rateOnlyInFuture_stillThrowsForPastReferenceDate() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'CHF',
            AR_Rate_To_EUR__c = 1.05,
            AR_Effective_Date__c = Date.today().addDays(30)
        );

        Boolean threw = false;
        try {
            AR_CurrencyRateService.resolveRate('CHF', Date.today());
        } catch (AR_CurrencyRateService.NoRateAvailableException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Une ligne de taux future ne doit jamais être appliquée par anticipation');
    }

    @IsTest
    static void testGetCurrentRates_returnsOnlyCurrenciesWithARate() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        // CHF, CAD, MAD volontairement sans taux.

        Test.startTest();
        List<AR_CurrencyRateService.CurrentRateDto> rates = AR_CurrencyRateService.getCurrentRates();
        Test.stopTest();

        System.assertEquals(1, rates.size(), 'Seul GBP a un taux : les 3 autres devises sont omises, pas un taux fictif de 1');
        System.assertEquals('GBP', rates[0].currencyCode);
        System.assertEquals(1.17, rates[0].rateToEur);
    }

    @IsTest
    static void testGetCurrentRates_noRatesAtAll_returnsEmptyList() {
        Test.startTest();
        List<AR_CurrencyRateService.CurrentRateDto> rates = AR_CurrencyRateService.getCurrentRates();
        Test.stopTest();

        System.assertEquals(0, rates.size());
    }

    /**
     * Persona AR_Pricing_User seul, sans AR_Admin_Currency : la lecture de la table de taux passe
     * pour la page de création de matrice (choix du besoin puis calcul en devise étrangère).
     */
    @IsTest
    static void testResolveRateAndCurrentRates_pricingUserWithoutCurrencyAdmin_readsRate() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        User pricingUser = AR_TestPersona.bm();

        System.runAs(pricingUser) {
            AR_CurrencyRateService.RateResolution result = AR_CurrencyRateService.resolveRate('GBP', Date.today());
            List<AR_CurrencyRateService.CurrentRateDto> rates = AR_CurrencyRateService.getCurrentRates();

            System.assertEquals(1.17, result.rateToEur);
            System.assertEquals(1, rates.size());
            System.assertEquals('GBP', rates[0].currencyCode);
        }
    }
}