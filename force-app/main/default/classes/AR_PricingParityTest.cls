/**
 * Le seul test qui protège vraiment ce projet (session 27, prompts/session-27-filet-de-tests.md §1) :
 * AR_PricingCalculator (Apex, moteur qui sauvegarde/fige/imprime) et arPricingEngine (JS, aperçu
 * temps réel) calculent la même chose sur le papier, mais rien ne garantissait qu'ils restent
 * identiques. Ce test et son miroir Jest (arPricingEngine.parity.test.js) lisent le MÊME fichier de
 * cas de référence (static resource AR_PricingParityCases, JSON) — les valeurs attendues y sont
 * calculées à la main depuis les formules de CLAUDE.md, documentées cas par cas, jamais générées par
 * l'un des deux moteurs (un cas dont l'attendu viendrait du code ne prouverait rien).
 *
 * Défaut de parité trouvé et corrigé au passage (pas seulement documenté, cf. règle de session :
 * corriger si évident et sans risque) : `markupMismatch` valait `null` côté Apex pour tout contrat
 * non-INDEP (et pour l'INDEP sans CJM saisi), `false` côté JS — mêmes conséquences dans toute
 * vérification `if`/`&&` (null et false sont tous deux falsy), mais pas la même valeur stockée.
 * Corrigé dans AR_PricingCalculator.compute()/calcMarkup() : initialisation explicite à `false`.
 *
 * Écart NON corrigé, remonté à Alexis (cf. testDocumentedDivergence_vieNearshoreNullCjm) : une
 * matrice VIE/NEARSHORE sans CJM résolu (pays non sélectionné, ou référentiel manquant) fait
 * planter AR_PricingCalculator.calcTotalDailyCost avec un NullPointerException, alors
 * qu'arPricingEngine renvoie 0 dans le même cas — pas une correction "évidente et sans risque"
 * (change un comportement réel, potentiellement voulu), donc non tranché ici.
 */
@IsTest
private class AR_PricingParityTest {

    /**
     * Un seul enregistrement par cas plutôt qu'un test par cas (session 27) : le jeu de cas est un
     * fichier de données externe, pas une liste de méthodes — ajouter un cas au JSON suffit, aucune
     * classe à toucher. `System.assertEquals` avec un message explicite par champ pour qu'un échec
     * pointe directement le champ et le cas en cause, pas juste "assertion failed".
     */
    /**
     * Les attendus viennent d'un JSON (double) et le résultat Apex est un Decimal à 28 chiffres : une
     * fraction non terminante (1500 / 218) n'est jamais égale au chiffre près. Tolérance 1e-9 — bien
     * en deçà de toute erreur de formule (la plus petite unité métier visible est 0,01).
     */
    private static void assertClose(Decimal expected, Decimal actual, String msg) {
        if (expected == null || actual == null) {
            System.assertEquals(expected, actual, msg);
            return;
        }
        System.assert(Math.abs(expected - actual) < 0.000000001, msg + ' — attendu ' + expected + ', obtenu ' + actual);
    }

    @IsTest
    static void testAllReferenceCases() {
        List<Object> cases = loadCases();
        System.assert(!cases.isEmpty(), 'Le fichier de cas de référence ne doit jamais être vide.');

        Integer verified = 0;
        for (Object raw : cases) {
            Map<String, Object> c = (Map<String, Object>) raw;
            String caseName = (String) c.get('name');
            AR_PricingCalculator.Context ctx = toContext((Map<String, Object>) c.get('context'));
            Decimal rfaPercent = toDecimal(c.get('rfaPercent'));
            Decimal proposedTjm = toDecimal(c.get('proposedTjm'));
            Decimal top10Comparables = toDecimal(c.get('top10Comparables'));
            AR_PricingCalculator.ThresholdPercents pcts = toThresholdPercents(
                (Map<String, Object>) c.get('thresholdPercents')
            );
            Decimal rateToEur = toDecimal(c.get('rateToEur'));

            AR_PricingResult result = AR_PricingCalculator.compute(
                ctx,
                rfaPercent,
                proposedTjm,
                top10Comparables,
                pcts,
                rateToEur
            );

            Map<String, Object> expected = (Map<String, Object>) c.get('expected');
            String prefix = caseName + ' — ';
            assertClose(toDecimal(expected.get('cjm')), result.cjm, prefix + 'cjm');
            assertClose(toDecimal(expected.get('feeOmPerDay')), result.feeOmPerDay, prefix + 'feeOmPerDay');
            assertClose(toDecimal(expected.get('feePonctuelsPerDay')), result.feePonctuelsPerDay, prefix + 'feePonctuelsPerDay');
            assertClose(toDecimal(expected.get('totalDailyCost')), result.totalDailyCost, prefix + 'totalDailyCost');
            assertClose(toDecimal(expected.get('tjmFloor')), result.tjmFloor, prefix + 'tjmFloor');
            assertClose(toDecimal(expected.get('tjmTarget')), result.tjmTarget, prefix + 'tjmTarget');
            assertClose(toDecimal(expected.get('tjmIdeal')), result.tjmIdeal, prefix + 'tjmIdeal');
            assertClose(toDecimal(expected.get('tjmTop10')), result.tjmTop10, prefix + 'tjmTop10');
            assertClose(toDecimal(expected.get('mc2PerDay')), result.mc2PerDay, prefix + 'mc2PerDay');
            assertClose(toDecimal(expected.get('mc2PercentHuman')), result.mc2PercentHuman, prefix + 'mc2PercentHuman');
            System.assertEquals((String) expected.get('corridorSegment'), result.corridorSegment, prefix + 'corridorSegment');
            assertClose(toDecimal(expected.get('markupCalcule')), result.markupCalcule, prefix + 'markupCalcule');
            System.assertEquals((Boolean) expected.get('markupMismatch'), result.markupMismatch, prefix + 'markupMismatch');
            assertClose(toDecimal(expected.get('contractCoefficientApplied')), result.contractCoefficientApplied, prefix + 'contractCoefficientApplied');
            assertClose(toDecimal(expected.get('workingDaysPerYearApplied')), result.workingDaysPerYearApplied, prefix + 'workingDaysPerYearApplied');
            assertClose(toDecimal(expected.get('currencyRateApplied')), result.currencyRateApplied, prefix + 'currencyRateApplied');
            assertClose(toDecimal(expected.get('totalDailyCostEurEquivalent')), result.totalDailyCostEurEquivalent, prefix + 'totalDailyCostEurEquivalent');
            assertClose(toDecimal(expected.get('mc2PerDayEurEquivalent')), result.mc2PerDayEurEquivalent, prefix + 'mc2PerDayEurEquivalent');
            assertClose(toDecimal(expected.get('tjmEurEquivalent')), result.tjmEurEquivalent, prefix + 'tjmEurEquivalent');
            assertClose(toDecimal(expected.get('feePonctuelsDivisorDays')), result.feePonctuelsDivisorDays, prefix + 'feePonctuelsDivisorDays');
            System.assertEquals((String) expected.get('feePonctuelsDivisorSource'), result.feePonctuelsDivisorSource, prefix + 'feePonctuelsDivisorSource');
            if (expected.containsKey('billableDays')) {
                assertClose(toDecimal(expected.get('billableDays')), AR_PricingCalculator.calcBillableDays(ctx), prefix + 'billableDays');
            }
            if (expected.containsKey('feeBreakdown')) {
                assertFeeBreakdown((List<Object>) expected.get('feeBreakdown'), result.feeBreakdown, prefix);
            }
            if (expected.containsKey('feeOmPeriods')) {
                assertFeeOmPeriods((List<Object>) expected.get('feeOmPeriods'), result.feeOmPeriods, prefix);
                System.assertEquals((Boolean) expected.get('feePeriodsExceedMission'), result.feePeriodsExceedMission, prefix + 'feePeriodsExceedMission');
                System.assertEquals((Boolean) expected.get('feePeriodsMissionUnknown'), result.feePeriodsMissionUnknown, prefix + 'feePeriodsMissionUnknown');
            }
            // TJM pondéré (docs/254) : sans période attendue, le pondéré est le TJM saisi et la liste est vide.
            if (expected.containsKey('tjmWeighted')) {
                assertClose(toDecimal(expected.get('tjmWeighted')), result.tjmWeighted, prefix + 'tjmWeighted');
                assertTjmPeriods((List<Object>) expected.get('tjmPeriods'), result.tjmPeriods, prefix);
                System.assertEquals((Boolean) expected.get('tjmPeriodsExceedMission'), result.tjmPeriodsExceedMission, prefix + 'tjmPeriodsExceedMission');
                System.assertEquals((Boolean) expected.get('tjmPeriodsMissionUnknown'), result.tjmPeriodsMissionUnknown, prefix + 'tjmPeriodsMissionUnknown');
            } else {
                assertClose(proposedTjm, result.tjmWeighted, prefix + 'tjmWeighted (sans période = TJM saisi)');
                System.assert(result.tjmPeriods.isEmpty(), prefix + 'tjmPeriods doit être vide sans période');
            }
            // Périodes de salaire : sans attendu, liste vide et indicateurs à faux.
            if (expected.containsKey('salaryPeriods')) {
                assertSalaryPeriods((List<Object>) expected.get('salaryPeriods'), result.salaryPeriods, prefix);
                System.assertEquals((Boolean) expected.get('salaryPeriodsExceedMission'), result.salaryPeriodsExceedMission, prefix + 'salaryPeriodsExceedMission');
                System.assertEquals((Boolean) expected.get('salaryPeriodsMissionUnknown'), result.salaryPeriodsMissionUnknown, prefix + 'salaryPeriodsMissionUnknown');
            } else {
                System.assert(result.salaryPeriods.isEmpty(), prefix + 'salaryPeriods doit être vide sans période');
            }
            // Régie sans régule (docs/265) : mode éteint = quatre sorties nulles ; mode actif = valeurs attendues.
            if (expected.containsKey('rplsrRatio')) {
                assertClose(toDecimal(expected.get('rplsrRatio')), result.rplsrRatio, prefix + 'rplsrRatio');
                assertClose(toDecimal(expected.get('totalDailyCostPiloted')), result.totalDailyCostPiloted, prefix + 'totalDailyCostPiloted');
                assertClose(toDecimal(expected.get('mc2PerDayTheoretical')), result.mc2PerDayTheoretical, prefix + 'mc2PerDayTheoretical');
                assertClose(toDecimal(expected.get('mc2PercentTheoretical')), result.mc2PercentTheoretical, prefix + 'mc2PercentTheoretical');
            } else {
                System.assertEquals(null, result.rplsrRatio, prefix + 'rplsrRatio doit rester nul hors régie sans régule');
                System.assertEquals(null, result.totalDailyCostPiloted, prefix + 'totalDailyCostPiloted doit rester nul hors régie sans régule');
            }
            verified++;
        }
        // Preuve que la boucle a bien tourné sur l'intégralité du fichier, pas sur une liste vide ou
        // tronquée qui aurait fait "passer" le test sans rien vérifier.
        System.assertEquals(cases.size(), verified, 'Tous les cas du fichier doivent être vérifiés.');
    }

    /**
     * Détail par poste : mêmes postes, dans le même ordre, avec montant saisi, unité, diviseur, source du
     * diviseur et valeur/jour identiques à l'attendu écrit à la main dans le fichier de cas.
     */
    private static void assertFeeBreakdown(List<Object> expectedLines, List<AR_PricingResult.FeeLine> actual, String prefix) {
        System.assertNotEquals(null, actual, prefix + 'feeBreakdown absent');
        System.assertEquals(expectedLines.size(), actual.size(), prefix + 'nombre de postes du détail');
        for (Integer i = 0; i < expectedLines.size(); i++) {
            Map<String, Object> e = (Map<String, Object>) expectedLines[i];
            AR_PricingResult.FeeLine a = actual[i];
            String p = prefix + 'feeBreakdown[' + e.get('key') + '] ';
            System.assertEquals((String) e.get('key'), a.key, p + 'key');
            assertClose(toDecimal(e.get('amount')), a.amount, p + 'amount');
            System.assertEquals((String) e.get('unit'), a.unit, p + 'unit');
            assertClose(toDecimal(e.get('divisor')), a.divisor, p + 'divisor');
            System.assertEquals((String) e.get('divisorSource'), a.divisorSource, p + 'divisorSource');
            assertClose(toDecimal(e.get('perDay')), a.perDay, p + 'perDay');
        }
    }

    /**
     * Écart de comportement documenté, PAS un défaut de parité au sens du reste du fichier : les
     * deux moteurs ne peuvent pas être comparés champ à champ ici puisqu'un seul des deux plante.
     * Verrouille le comportement ACTUEL (Apex lève, cf. classe-doc ci-dessus) pour qu'une correction
     * future — dans un sens ou dans l'autre — soit un choix délibéré, jamais une régression
     * silencieuse. cf. arPricingEngine.parity.test.js pour le miroir JS (ne plante pas, renvoie 0).
     */
    @IsTest
    static void testDocumentedDivergence_vieNearshoreNullCjm() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'VIE';
        ctx.cjmVie = null;

        Boolean threw = false;
        try {
            AR_PricingCalculator.calcTotalDailyCost(ctx);
        } catch (NullPointerException e) {
            threw = true;
        }
        System.assert(
            threw,
            'Divergence attendue : AR_PricingCalculator plante aujourd\'hui sur un contexte VIE sans ' +
            'CJM résolu (contrairement à arPricingEngine, cf. mirroir Jest). Si cette assertion échoue, ' +
            'le comportement a changé côté Apex sans que le JS ait été revérifié — ne pas ajuster ce ' +
            'test sans relire le mirroir JS et CLAUDE.md.'
        );
    }

    /**
     * Périodes de frais OM (docs/239) : index, jours retenus (null pour la période 1 à durée inconnue)
     * et frais OM par jour de chaque période, dans l'ordre (période 1 d'abord).
     */
    private static void assertFeeOmPeriods(List<Object> expectedPeriods, List<AR_PricingResult.FeeOmPeriod> actual, String prefix) {
        System.assertNotEquals(null, actual, prefix + 'feeOmPeriods absent');
        System.assertEquals(expectedPeriods.size(), actual.size(), prefix + 'nombre de périodes');
        for (Integer i = 0; i < expectedPeriods.size(); i++) {
            Map<String, Object> e = (Map<String, Object>) expectedPeriods[i];
            AR_PricingResult.FeeOmPeriod a = actual[i];
            String p = prefix + 'feeOmPeriods[' + e.get('index') + '] ';
            System.assertEquals(Integer.valueOf(String.valueOf(e.get('index'))), a.index, p + 'index');
            assertClose(toDecimal(e.get('days')), a.days, p + 'days');
            assertClose(toDecimal(e.get('perDay')), a.perDay, p + 'perDay');
        }
    }

    /**
     * Périodes de TJM (docs/254) : index, jours retenus (null pour la période 1 à durée inconnue) et TJM
     * de chaque période, dans l'ordre (période 1 d'abord).
     */
    private static void assertTjmPeriods(List<Object> expectedPeriods, List<AR_PricingResult.TjmPeriod> actual, String prefix) {
        System.assertNotEquals(null, actual, prefix + 'tjmPeriods absent');
        System.assertEquals(expectedPeriods.size(), actual.size(), prefix + 'nombre de périodes de TJM');
        for (Integer i = 0; i < expectedPeriods.size(); i++) {
            Map<String, Object> e = (Map<String, Object>) expectedPeriods[i];
            AR_PricingResult.TjmPeriod a = actual[i];
            String p = prefix + 'tjmPeriods[' + e.get('index') + '] ';
            System.assertEquals(Integer.valueOf(String.valueOf(e.get('index'))), a.index, p + 'index');
            assertClose(toDecimal(e.get('days')), a.days, p + 'days');
            assertClose(toDecimal(e.get('tjm')), a.tjm, p + 'tjm');
        }
    }

    private static void assertSalaryPeriods(List<Object> expectedPeriods, List<AR_PricingResult.SalaryPeriod> actual, String prefix) {
        System.assertEquals(expectedPeriods.size(), actual.size(), prefix + 'nombre de périodes de salaire');
        for (Integer i = 0; i < expectedPeriods.size(); i++) {
            Map<String, Object> e = (Map<String, Object>) expectedPeriods[i];
            AR_PricingResult.SalaryPeriod a = actual[i];
            String p = prefix + 'salaryPeriods[' + e.get('index') + '] ';
            System.assertEquals(Integer.valueOf(String.valueOf(e.get('index'))), a.index, p + 'index');
            assertClose(toDecimal(e.get('days')), a.days, p + 'days');
            assertClose(toDecimal(e.get('salary')), a.salary, p + 'salary');
            assertClose(toDecimal(e.get('cjm')), a.cjm, p + 'cjm');
        }
    }

    private static List<Object> loadCases() {
        StaticResource sr = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'AR_PricingParityCases'
            LIMIT 1
        ];
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(sr.Body.toString());
        return (List<Object>) parsed.get('cases');
    }

    private static AR_PricingCalculator.Context toContext(Map<String, Object> m) {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = (String) m.get('contractType');
        ctx.annualSalary = toDecimal(m.get('annualSalary'));
        ctx.cjmBeforeMarkup = toDecimal(m.get('cjmBeforeMarkup'));
        ctx.markupApplied = toDecimal(m.get('markupApplied'));
        ctx.cjmVie = toDecimal(m.get('cjmVie'));
        ctx.cjmNearshore = toDecimal(m.get('cjmNearshore'));
        if (m.get('contractCoefficient') != null) ctx.contractCoefficient = toDecimal(m.get('contractCoefficient'));
        if (m.get('feeIk') != null) ctx.feeIk = toDecimal(m.get('feeIk'));
        if (m.get('feeMeals') != null) ctx.feeMeals = toDecimal(m.get('feeMeals'));
        if (m.get('feeLodging') != null) ctx.feeLodging = toDecimal(m.get('feeLodging'));
        if (m.get('feeOmOther') != null) ctx.feeOmOther = toDecimal(m.get('feeOmOther'));
        if (m.get('gratuityDays') != null) ctx.gratuityDays = toDecimal(m.get('gratuityDays'));
        if (m.get('feeComputer') != null) ctx.feeComputer = toDecimal(m.get('feeComputer'));
        if (m.get('feePhone') != null) ctx.feePhone = toDecimal(m.get('feePhone'));
        if (m.get('feeMonthlyOther') != null) ctx.feeMonthlyOther = toDecimal(m.get('feeMonthlyOther'));
        if (m.get('plannedLeaveDays') != null) ctx.plannedLeaveDays = toDecimal(m.get('plannedLeaveDays'));
        if (m.get('feeTraining') != null) ctx.feeTraining = toDecimal(m.get('feeTraining'));
        if (m.get('feeEpi') != null) ctx.feeEpi = toDecimal(m.get('feeEpi'));
        if (m.get('feeOfiiTax') != null) ctx.feeOfiiTax = toDecimal(m.get('feeOfiiTax'));
        if (m.get('feeOther') != null) ctx.feeOther = toDecimal(m.get('feeOther'));
        if (m.get('workingDaysPerYear') != null) ctx.workingDaysPerYear = toDecimal(m.get('workingDaysPerYear'));
        if (m.get('missionDays') != null) ctx.missionDays = toDecimal(m.get('missionDays'));
        if (m.get('markupPercentSetting') != null) ctx.markupPercentSetting = toDecimal(m.get('markupPercentSetting'));
        if (m.get('markupMaxSetting') != null) ctx.markupMaxSetting = toDecimal(m.get('markupMaxSetting'));
        if (m.get('rplsrRatio') != null) ctx.rplsrRatio = toDecimal(m.get('rplsrRatio'));
        if (m.get('tjmPeriods') != null) {
            ctx.tjmPeriods = new List<AR_PricingCalculator.TjmPeriod>();
            for (Object raw : (List<Object>) m.get('tjmPeriods')) {
                Map<String, Object> p = (Map<String, Object>) raw;
                AR_PricingCalculator.TjmPeriod period = new AR_PricingCalculator.TjmPeriod();
                period.days = toDecimal(p.get('days'));
                period.tjm = toDecimal(p.get('tjm'));
                ctx.tjmPeriods.add(period);
            }
        }
        if (m.get('salaryPeriods') != null) {
            ctx.salaryPeriods = new List<AR_PricingCalculator.SalaryPeriod>();
            for (Object raw : (List<Object>) m.get('salaryPeriods')) {
                Map<String, Object> p = (Map<String, Object>) raw;
                AR_PricingCalculator.SalaryPeriod period = new AR_PricingCalculator.SalaryPeriod();
                period.days = toDecimal(p.get('days'));
                period.salary = toDecimal(p.get('salary'));
                ctx.salaryPeriods.add(period);
            }
        }
        if (m.get('feePeriods') != null) {
            ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>();
            for (Object raw : (List<Object>) m.get('feePeriods')) {
                Map<String, Object> p = (Map<String, Object>) raw;
                AR_PricingCalculator.FeePeriod period = new AR_PricingCalculator.FeePeriod();
                period.days = toDecimal(p.get('days'));
                period.feeIk = toDecimal(p.get('feeIk'));
                period.feeMeals = toDecimal(p.get('feeMeals'));
                period.feeLodging = toDecimal(p.get('feeLodging'));
                period.feeOmOther = toDecimal(p.get('feeOmOther'));
                ctx.feePeriods.add(period);
            }
        }
        return ctx;
    }

    private static AR_PricingCalculator.ThresholdPercents toThresholdPercents(Map<String, Object> m) {
        if (m == null) {
            return null;
        }
        return new AR_PricingCalculator.ThresholdPercents(
            toDecimal(m.get('floorPercent')),
            toDecimal(m.get('targetPercent')),
            toDecimal(m.get('idealPercent'))
        );
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }
}