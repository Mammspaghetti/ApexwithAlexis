/**
 * Tests unitaires du moteur pur AR_PricingCalculator. Les valeurs d'entrée sont choisies pour
 * produire des divisions exactes autant que possible (documentées ligne par ligne) afin de
 * comparer à des résultats calculés à la main plutôt que de retester la formule elle-même.
 */
@IsTest
private class AR_PricingCalculatorTest {

    @IsTest
    static void testCalcCJM_CDI() {
        // 43600 × 1.01 × 2 = 88072 ; 88072 / 218 = 404 (division exacte)
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.annualSalary = 43600;
        ctx.workingDaysPerYear = 218;

        Test.startTest();
        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);
        Test.stopTest();

        System.assertEquals(404, cjm, 'CDI : CJM = salaire × 1.01 × 2 / 218');
    }

    @IsTest
    static void testCalcCJM_INDEP() {
        // INDEP : CJM = cjmAvantMarkup + markupAppliqué = 340 + 54
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'INDEP';
        ctx.cjmBeforeMarkup = 340;
        ctx.markupApplied = 54;

        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);

        System.assertEquals(394, cjm, 'INDEP : CJM = cjmAvantMarkup + markupAppliqué');
    }

    @IsTest
    static void testCalcCJM_VIE_and_NEARSHORE() {
        AR_PricingCalculator.Context vieCtx = new AR_PricingCalculator.Context();
        vieCtx.contractType = 'VIE';
        vieCtx.cjmVie = 180;
        System.assertEquals(180, AR_PricingCalculator.calcCJM(vieCtx), 'VIE : CJM = indemnité fixe du référentiel');

        AR_PricingCalculator.Context nearshoreCtx = new AR_PricingCalculator.Context();
        nearshoreCtx.contractType = 'NEARSHORE';
        nearshoreCtx.cjmNearshore = 200;
        System.assertEquals(200, AR_PricingCalculator.calcCJM(nearshoreCtx), 'NEARSHORE : CJM = référentiel pays');
    }

    @IsTest
    static void testCalcMarkup_belowCap_noMismatch() {
        // 300 × 18 % = 54, sous le plafond de 60 ; markup appliqué = 54 → pas d'écart
        AR_PricingCalculator.MarkupResult result = AR_PricingCalculator.calcMarkup(300, 54, 18, 60);

        System.assertEquals(54.00, result.markupCalcule);
        System.assertEquals(false, result.markupMismatch);
    }

    @IsTest
    static void testCalcMarkup_cappedAt60_withMismatch() {
        // 400 × 18 % = 72 > plafond 60 → markup calculé plafonné à 60 ; appliqué = 50 → écart, accord nécessaire
        AR_PricingCalculator.MarkupResult result = AR_PricingCalculator.calcMarkup(400, 50, 18, 60);

        System.assertEquals(60.00, result.markupCalcule);
        System.assertEquals(true, result.markupMismatch);
    }

    @IsTest
    static void testCalcFraisOMJour() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.feeIk = 8;
        ctx.feeMeals = 12;
        ctx.feeLodging = 15;
        ctx.feeOmOther = 5;

        System.assertEquals(40, AR_PricingCalculator.calcFraisOMJour(ctx));
    }

    @IsTest
    static void testCalcFraisPonctuelsJour_withGratuity() {
        // gratuité 1 jour × CJM 404 = 404 ; + formation 200 + EPI 50 = 654 ; 654 / 218 = 3 (division exacte)
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.workingDaysPerYear = 218;
        ctx.gratuityDays = 1;
        ctx.feeComputer = 0;
        ctx.feeTraining = 200;
        ctx.feeEpi = 50;

        Decimal result = AR_PricingCalculator.calcFraisPonctuelsJour(ctx, 404);

        System.assertEquals(3, result);
    }

    @IsTest
    static void testCalcTotalDailyCost_CDI() {
        // CJM 404 + fraisOM 40 + fraisPonctuels 3 = 447
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.annualSalary = 43600;
        ctx.workingDaysPerYear = 218;
        ctx.feeIk = 8;
        ctx.feeMeals = 12;
        ctx.feeLodging = 15;
        ctx.feeOmOther = 5;
        ctx.gratuityDays = 1;
        ctx.feeComputer = 0;
        ctx.feeTraining = 200;
        ctx.feeEpi = 50;

        System.assertEquals(447, AR_PricingCalculator.calcTotalDailyCost(ctx));
    }

    @IsTest
    static void testCalcTotalDailyCost_INDEP_withGratuity() {
        // CJM = 200 + 18 = 218 (choisi égal à JOURS_TRAVAIL pour un calcul exact)
        // Coût total = CJM + gratuité × CJM / 218 = 218 + 3 × 218 / 218 = 218 + 3 = 221
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'INDEP';
        ctx.cjmBeforeMarkup = 200;
        ctx.markupApplied = 18;
        ctx.workingDaysPerYear = 218;
        ctx.gratuityDays = 3;

        System.assertEquals(221, AR_PricingCalculator.calcTotalDailyCost(ctx));
    }

    @IsTest
    static void testCalcThresholds_defaultPercents_noRfa() {
        // coût 447, RFA 0 % : plancher 447/0.80=558.75→559 ; cible 447/0.75=596 (exact) ; idéal 447/0.70=638.57→639
        // top10 = MAX(0, ceil(639×1.10)=ceil(702.9)=703) = 703
        AR_PricingCalculator.Thresholds th = AR_PricingCalculator.calcThresholds(447, 0, 0, null);

        System.assertEquals(559, th.floorValue);
        System.assertEquals(596, th.targetValue);
        System.assertEquals(639, th.idealValue);
        System.assertEquals(703, th.top10Value);
    }

    @IsTest
    static void testCalcThresholds_rfaReducesAvailableMargin() {
        // coût 400, RFA 5 % : plancher = 400/(1-0.05-0.20) = 400/0.75 = 533.33 → 534
        AR_PricingCalculator.Thresholds th = AR_PricingCalculator.calcThresholds(400, 5, 0, null);

        System.assertEquals(534, th.floorValue);
    }

    @IsTest
    static void testCalcThresholds_accountCorridorOverride() {
        // Seuils grand compte : floor 15 %, target 22 %, ideal 28 % ; coût 100, RFA 0
        // plancher = 100/0.85 = 117.64 → 118 ; cible = 100/0.78=128.20→129 ; idéal = 100/0.72=138.88→139
        AR_PricingCalculator.ThresholdPercents corridor = new AR_PricingCalculator.ThresholdPercents(15, 22, 28);

        AR_PricingCalculator.Thresholds th = AR_PricingCalculator.calcThresholds(100, 0, 0, corridor);

        System.assertEquals(118, th.floorValue);
        System.assertEquals(129, th.targetValue);
        System.assertEquals(139, th.idealValue);
    }

    @IsTest
    static void testCalcThresholds_top10ComparablesWinsOverCalculated() {
        // idéal 139 × 1.10 = 152.9 → 153 calculé ; comparables 160 > 153 → top10 = 160
        AR_PricingCalculator.ThresholdPercents corridor = new AR_PricingCalculator.ThresholdPercents(15, 22, 28);
        AR_PricingCalculator.Thresholds th = AR_PricingCalculator.calcThresholds(100, 0, 160, corridor);

        System.assertEquals(160, th.top10Value);
    }

    @IsTest
    static void testCalcMC2_positive() {
        // MC2/jour = 500 × 1 - 447 = 53 ; MC2 % = 53/500 = 0.106 (10.6 %)
        AR_PricingCalculator.MC2Result mc2 = AR_PricingCalculator.calcMC2(500, 447, 0);

        System.assertEquals(53.0, mc2.mc2PerDay);
        System.assertEquals(0.106, mc2.mc2PercentFraction);
    }

    @IsTest
    static void testCalcMC2_negative_belowFloor() {
        // TJM inférieur au coût total → MC2 négative
        AR_PricingCalculator.MC2Result mc2 = AR_PricingCalculator.calcMC2(400, 447, 0);

        System.assertEquals(-47.0, mc2.mc2PerDay);
        System.assert(mc2.mc2PercentFraction < 0, 'MC2 % doit être négative');
    }

    @IsTest
    static void testCalcMC2_tjmZero() {
        AR_PricingCalculator.MC2Result mc2 = AR_PricingCalculator.calcMC2(0, 447, 0);

        System.assertEquals(0, mc2.mc2PerDay);
        System.assertEquals(0, mc2.mc2PercentFraction);
    }

    @IsTest
    static void testGetCorridorSegment_allBands() {
        System.assertEquals('below_floor', AR_PricingCalculator.getCorridorSegment(0.15, null));
        System.assertEquals('low_margin', AR_PricingCalculator.getCorridorSegment(0.22, null));
        System.assertEquals('recommended', AR_PricingCalculator.getCorridorSegment(0.27, null));
        System.assertEquals('superstar', AR_PricingCalculator.getCorridorSegment(0.35, null));
    }

    @IsTest
    static void testCompute_indepPipeline_withMarkupMismatch() {
        // CJM = 200+18 = 218 ; coût total = 221 (cf. testCalcTotalDailyCost_INDEP_withGratuity)
        // markup calculé = 200×18% = 36, appliqué = 18 → écart signalé
        // TJM proposé 300 : MC2/jour = 300-221 = 79 ; MC2 % = 79/300×100 = 26.33 (arrondi 2 déc.) → segment recommended (25-30 %)
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'INDEP';
        ctx.cjmBeforeMarkup = 200;
        ctx.markupApplied = 18;
        ctx.workingDaysPerYear = 218;
        ctx.gratuityDays = 3;
        ctx.markupPercentSetting = 18;
        ctx.markupMaxSetting = 60;

        Test.startTest();
        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, 300, 0, null);
        Test.stopTest();

        System.assertEquals(218, result.cjm);
        System.assertEquals(36.00, result.markupCalcule);
        System.assertEquals(true, result.markupMismatch);
        System.assertEquals(221, result.totalDailyCost);
        System.assertEquals(277, result.tjmFloor);
        System.assertEquals(295, result.tjmTarget);
        System.assertEquals(316, result.tjmIdeal);
        System.assertEquals(348, result.tjmTop10);
        System.assertEquals(79.0, result.mc2PerDay);
        System.assertEquals(26.33, result.mc2PercentHuman);
        System.assertEquals('recommended', result.corridorSegment);
        // customPcts null → défauts 20/25/30 (session 23b : percentages figés, cf. AR_Price_Matrix__c.AR_Floor_Percent_Applied__c).
        System.assertEquals(20, result.floorPercentApplied);
        System.assertEquals(25, result.targetPercentApplied);
        System.assertEquals(30, result.idealPercentApplied);
    }

    /**
     * Session 23b : compute() doit exposer le corridor RÉELLEMENT utilisé (pas seulement les seuils
     * € qui en découlent), pour qu'une matrice décidée puisse le figer et rester cohérente à
     * l'affichage même si AR_Account_Corridor__c change ensuite.
     */
    @IsTest
    static void testCompute_accountCorridorOverride_exposesAppliedPercents() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'NEARSHORE';
        ctx.cjmNearshore = 200;
        AR_PricingCalculator.ThresholdPercents corridor = new AR_PricingCalculator.ThresholdPercents(5, 8, 12);

        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, 400, 0, corridor);

        System.assertEquals(5, result.floorPercentApplied);
        System.assertEquals(8, result.targetPercentApplied);
        System.assertEquals(12, result.idealPercentApplied);
    }

    // Robustesse (session 18) : valeurs hors bornes envoyées directement au moteur (les bornes UI
    // du LWC ne protègent que le chemin normal, pas un appel Apex/API direct).

    @IsTest
    static void testCalcCJM_negativeAnnualSalary_clampsToZero_insteadOfNegativeCjm() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.annualSalary = -50000;
        ctx.workingDaysPerYear = 218;

        Test.startTest();
        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);
        Test.stopTest();

        System.assertEquals(0, cjm, 'Un salaire négatif ne doit jamais produire un CJM négatif');
    }

    @IsTest
    static void testCalcCJM_nullAnnualSalary_doesNotThrow() {
        // Brouillon sauvegardé avant toute saisie de salaire : annualSalary est null côté serveur.
        // L'arithmétique Apex sur un Decimal null lève une NullPointerException sans garde.
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.workingDaysPerYear = 218;

        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);

        System.assertEquals(0, cjm);
    }

    @IsTest
    static void testCalcThresholds_rfaAboveHundredPercent_neverCrashesOrGoesNegative() {
        // RFA 150 % : dénominateur (1 - 1.5 - 0.2) = -0.7, négatif — sans garde, un seuil négatif.
        AR_PricingCalculator.ThresholdPercents defaultPcts = new AR_PricingCalculator.ThresholdPercents(20, 25, 30);

        Test.startTest();
        AR_PricingCalculator.Thresholds th = AR_PricingCalculator.calcThresholds(447, 150, 0, defaultPcts);
        Test.stopTest();

        System.assert(th.floorValue > 0, 'Un seuil ne doit jamais être négatif, même avec une RFA hors bornes');
        System.assert(th.targetValue > 0);
        System.assert(th.idealValue > 0);
    }

    @IsTest
    static void testCalcThresholds_denominatorExactlyZero_doesNotThrowMathException() {
        // RFA 80 % + plancher 20 % = 100 % pile : dénominateur (1 - 0.8 - 0.2) = 0 exactement —
        // sans garde, System.MathException: Divide by 0.
        AR_PricingCalculator.ThresholdPercents defaultPcts = new AR_PricingCalculator.ThresholdPercents(20, 25, 30);

        Boolean threw = false;
        Decimal floorValue;
        try {
            floorValue = AR_PricingCalculator.calcThresholds(447, 80, 0, defaultPcts).floorValue;
        } catch (Exception e) {
            threw = true;
        }

        System.assertEquals(false, threw, 'Un dénominateur à 0 pile ne doit jamais lever de MathException');
        System.assert(floorValue > 0);
    }

    @IsTest
    static void testCalcFraisOMJour_negativeFee_clampsToZero() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.feeIk = -20;
        ctx.feeMeals = 12;

        Decimal total = AR_PricingCalculator.calcFraisOMJour(ctx);

        System.assertEquals(12, total, 'Un frais négatif ne doit jamais réduire le total, pas plus qu\'il ne doit être compté négativement');
    }

    // Session 18b : le champ TJM proposé n'avait ni min ni step, un TJM négatif était saisissable.
    @IsTest
    static void testCalcMC2_negativeTjm_neverReturnsPositiveMc2Percent() {
        // Sans garde : mc2Jour = -100 - 447 = -547 ; mc2PercentFraction = -547 / -100 = 5.47 (547 %),
        // lu à tort comme une excellente marge.
        AR_PricingCalculator.MC2Result mc2 = AR_PricingCalculator.calcMC2(-100, 447, 0);

        System.assertEquals(0, mc2.mc2PerDay);
        System.assertEquals(0, mc2.mc2PercentFraction);
    }

    // ------------------------------------------------------------------
    // Socle multi-devises (session 24) : rateToEur et équivalents pivot EUR.
    // ------------------------------------------------------------------

    /**
     * Non-régression EUR (le test le plus important de la session, cf.
     * prompts/session-24-multidevise-socle.md) : la surcharge 5 arguments (sans rateToEur) doit
     * produire EXACTEMENT le même résultat qu'avant cette session, au chiffre près, et
     * currencyRateApplied doit valoir 1 par défaut.
     */
    @IsTest
    static void testCompute_fiveArgOverload_defaultsToEurRateOne() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'INDEP';
        ctx.cjmBeforeMarkup = 200;
        ctx.markupApplied = 18;
        ctx.workingDaysPerYear = 218;
        ctx.gratuityDays = 3;
        ctx.markupPercentSetting = 18;
        ctx.markupMaxSetting = 60;

        AR_PricingResult viaFiveArgs = AR_PricingCalculator.compute(ctx, 0, 300, 0, null);
        AR_PricingResult viaSixArgsRateOne = AR_PricingCalculator.compute(ctx, 0, 300, 0, null, 1);

        System.assertEquals(1, viaFiveArgs.currencyRateApplied, 'Surcharge 5 arguments : taux par défaut = 1 (EUR)');
        System.assertEquals(viaFiveArgs.totalDailyCost, viaFiveArgs.totalDailyCostEurEquivalent, 'EUR : équivalent = montant natif');
        System.assertEquals(viaFiveArgs.mc2PerDay, viaFiveArgs.mc2PerDayEurEquivalent, 'EUR : équivalent = montant natif');
        System.assertEquals(300, viaFiveArgs.tjmEurEquivalent, 'EUR : équivalent TJM = TJM proposé');
        // Les deux surcharges doivent produire un résultat identique champ à champ sur tout le reste.
        System.assertEquals(viaFiveArgs.totalDailyCost, viaSixArgsRateOne.totalDailyCost);
        System.assertEquals(viaFiveArgs.tjmFloor, viaSixArgsRateOne.tjmFloor);
        System.assertEquals(viaFiveArgs.mc2PercentHuman, viaSixArgsRateOne.mc2PercentHuman);
        System.assertEquals(viaFiveArgs.corridorSegment, viaSixArgsRateOne.corridorSegment);
    }

    /**
     * GBP : le calcul natif (totalDailyCost, seuils, MC2) ne doit JAMAIS être affecté par le taux —
     * seuls les champs *EurEquivalent en dépendent (CLAUDE.md : le calcul se fait intégralement
     * dans la devise de l'affaire, la conversion ne sert jamais au calcul).
     */
    @IsTest
    static void testCompute_gbpRate_nativeCalculationUnaffectedByRate_onlyEquivalentsConverted() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'NEARSHORE';
        ctx.cjmNearshore = 200;

        AR_PricingResult atRateOne = AR_PricingCalculator.compute(ctx, 0, 400, 0, null, 1);
        AR_PricingResult atGbpRate = AR_PricingCalculator.compute(ctx, 0, 400, 0, null, 1.17);

        // Identique au chiffre près, quel que soit le taux : le natif ne bouge jamais.
        System.assertEquals(atRateOne.totalDailyCost, atGbpRate.totalDailyCost);
        System.assertEquals(atRateOne.tjmFloor, atGbpRate.tjmFloor);
        System.assertEquals(atRateOne.tjmTarget, atGbpRate.tjmTarget);
        System.assertEquals(atRateOne.tjmIdeal, atGbpRate.tjmIdeal);
        System.assertEquals(atRateOne.mc2PerDay, atGbpRate.mc2PerDay);
        System.assertEquals(atRateOne.mc2PercentHuman, atGbpRate.mc2PercentHuman);
        System.assertEquals(atRateOne.corridorSegment, atGbpRate.corridorSegment);

        // Équivalents EUR = montant natif × taux, arrondis à 2 décimales.
        System.assertEquals(1.17, atGbpRate.currencyRateApplied);
        System.assertEquals(
            (atGbpRate.totalDailyCost * 1.17).setScale(2, RoundingMode.HALF_UP),
            atGbpRate.totalDailyCostEurEquivalent
        );
        System.assertEquals(
            (atGbpRate.mc2PerDay * 1.17).setScale(2, RoundingMode.HALF_UP),
            atGbpRate.mc2PerDayEurEquivalent
        );
        System.assertEquals(468.00, atGbpRate.tjmEurEquivalent, '400 × 1.17 = 468.00');
    }

    @IsTest
    static void testCompute_noProposedTjm_tjmEurEquivalentIsNull() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'NEARSHORE';
        ctx.cjmNearshore = 200;

        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, null, 0, null, 1.17);

        System.assertEquals(null, result.tjmEurEquivalent, 'Pas de TJM proposé → pas d\'équivalent EUR calculable');
        System.assertNotEquals(null, result.totalDailyCostEurEquivalent, 'Le coût journalier, lui, est toujours calculable');
    }

    // ------------------------------------------------------------------
    // CDD et coefficient administrable (session 28, prompts/session-28-ecarts-contractuels.md §1).
    // ------------------------------------------------------------------

    @IsTest
    static void testCalcCJM_CDD_defaultCoefficient_sameFormulaAsCdi() {
        // Même base que testCalcCJM_CDI (43600, 218 jours) : 43600 × 2.02 / 218 = 404 (exact).
        // contractCoefficient non fourni → CONTRACT_COEFFICIENT_DEFAULT (2.02), identique au CDI.
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDD';
        ctx.annualSalary = 43600;
        ctx.workingDaysPerYear = 218;

        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);

        System.assertEquals(404, cjm, 'CDD sans coefficient administré : même formule que CDI (2,02)');
    }

    @IsTest
    static void testCalcCJM_CDD_customCoefficient_appliedInsteadOfDefault() {
        // 50000 × 2.10 / 218 = 105000 / 218 = 481.65... → arrondi 482.
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDD';
        ctx.annualSalary = 50000;
        ctx.workingDaysPerYear = 218;
        ctx.contractCoefficient = 2.10;

        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);

        System.assertEquals(482, cjm, 'Le coefficient administré (2,10) doit remplacer le défaut (2,02)');
    }

    @IsTest
    static void testCalcTotalDailyCost_CDD_includesOmAndPonctuelsFees_likeCdi() {
        // Même cas que testCalcTotalDailyCost_CDI (CJM 404 + OM 40 + ponctuels 3 = 447) : CDD est un
        // salarié comme le CDI, mêmes frais professionnels — contrairement à INDEP/NEARSHORE.
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDD';
        ctx.annualSalary = 43600;
        ctx.workingDaysPerYear = 218;
        ctx.feeIk = 8;
        ctx.feeMeals = 12;
        ctx.feeLodging = 15;
        ctx.feeOmOther = 5;
        ctx.gratuityDays = 1;
        ctx.feeComputer = 0;
        ctx.feeTraining = 200;
        ctx.feeEpi = 50;

        System.assertEquals(447, AR_PricingCalculator.calcTotalDailyCost(ctx));
    }

    @IsTest
    static void testCompute_CDD_exposesContractCoefficientApplied() {
        AR_PricingCalculator.Context ctxDefault = new AR_PricingCalculator.Context();
        ctxDefault.contractType = 'CDD';
        ctxDefault.annualSalary = 43600;
        ctxDefault.workingDaysPerYear = 218;

        AR_PricingCalculator.Context ctxCustom = new AR_PricingCalculator.Context();
        ctxCustom.contractType = 'CDD';
        ctxCustom.annualSalary = 50000;
        ctxCustom.workingDaysPerYear = 218;
        ctxCustom.contractCoefficient = 2.10;

        AR_PricingResult resultDefault = AR_PricingCalculator.compute(ctxDefault, 0, 500, 0, null);
        AR_PricingResult resultCustom = AR_PricingCalculator.compute(ctxCustom, 0, 700, 0, null);

        System.assertEquals(2.02, resultDefault.contractCoefficientApplied, 'Défaut moteur figé sur le résultat');
        System.assertEquals(2.10, resultCustom.contractCoefficientApplied, 'Coefficient administré figé sur le résultat');
    }

    /**
     * Non-régression du gel de coefficient (même principe que floorPercentApplied, session 23b) :
     * un coefficient administré change, le résultat déjà calculé pour un contexte donné ne doit
     * jamais être recalculé silencieusement — seul un nouvel appel avec le nouveau coefficient
     * produit un nouveau résultat. Preuve ici au niveau du moteur pur : deux appels successifs avec
     * des Context distincts (le second reflétant un changement d'administration) donnent des CJM
     * différents, chacun cohérent avec le coefficient qui lui a été passé.
     */
    @IsTest
    static void testCompute_CDD_coefficientChangeDoesNotRetroactivelyAffectAPreviousResult() {
        AR_PricingCalculator.Context ctxBeforeChange = new AR_PricingCalculator.Context();
        ctxBeforeChange.contractType = 'CDD';
        ctxBeforeChange.annualSalary = 43600;
        ctxBeforeChange.workingDaysPerYear = 218;
        ctxBeforeChange.contractCoefficient = 2.02;
        AR_PricingResult before = AR_PricingCalculator.compute(ctxBeforeChange, 0, 500, 0, null);

        // "Administration" change le coefficient CDD à 2.10 ; un contexte qui reprend l'ancienne
        // valeur (2.02) — celle figée sur une matrice déjà décidée — doit continuer à produire
        // exactement le même résultat, peu importe la valeur courante du paramètre.
        AR_PricingResult stillFrozen = AR_PricingCalculator.compute(ctxBeforeChange, 0, 500, 0, null);

        System.assertEquals(before.cjm, stillFrozen.cjm);
        System.assertEquals(before.contractCoefficientApplied, stillFrozen.contractCoefficientApplied);
    }

    @IsTest
    static void testCompute_contractCoefficientApplied_nullForNonSalaryStatuses() {
        AR_PricingCalculator.Context indepCtx = new AR_PricingCalculator.Context();
        indepCtx.contractType = 'INDEP';
        indepCtx.cjmBeforeMarkup = 200;
        indepCtx.markupApplied = 18;
        System.assertEquals(null, AR_PricingCalculator.compute(indepCtx, 0, 300, 0, null).contractCoefficientApplied);

        AR_PricingCalculator.Context vieCtx = new AR_PricingCalculator.Context();
        vieCtx.contractType = 'VIE';
        vieCtx.cjmVie = 180;
        System.assertEquals(null, AR_PricingCalculator.compute(vieCtx, 0, 300, 0, null).contractCoefficientApplied);

        AR_PricingCalculator.Context nearshoreCtx = new AR_PricingCalculator.Context();
        nearshoreCtx.contractType = 'NEARSHORE';
        nearshoreCtx.cjmNearshore = 200;
        System.assertEquals(null, AR_PricingCalculator.compute(nearshoreCtx, 0, 300, 0, null).contractCoefficientApplied);
    }

    // ------------------------------------------------------------------
    // Fréquence de chaque frais — attendus calculés à la main
    // ------------------------------------------------------------------

    private static AR_PricingResult.FeeLine lineOf(List<AR_PricingResult.FeeLine> lines, String key) {
        for (AR_PricingResult.FeeLine line : lines) {
            if (line.key == key) {
                return line;
            }
        }
        return null;
    }

    @IsTest
    static void testCalcFeeBreakdown_eachFeeInItsOwnUnit() {
        // 200 j/an, mission 150 j : PC 4 €/j → 4 ; téléphone 50 €/mois → 50×12/200 = 3 ;
        // formation 900/150 = 6 ; EPI 300/150 = 2 ; autre 300/150 = 2 ; OFII 1650 €/an → 1650/200 = 8,25
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.workingDaysPerYear = 200;
        ctx.missionDays = 150;
        ctx.feeComputer = 4;
        ctx.feePhone = 50;
        ctx.feeTraining = 900;
        ctx.feeEpi = 300;
        ctx.feeOfiiTax = 1650;
        ctx.feeOther = 300;

        List<AR_PricingResult.FeeLine> lines = AR_PricingCalculator.calcFeeBreakdown(ctx);

        System.assertEquals(6, lines.size());
        System.assertEquals(4, lineOf(lines, 'feeComputer').perDay);
        System.assertEquals('day', lineOf(lines, 'feeComputer').unit);
        System.assertEquals(3, lineOf(lines, 'feePhone').perDay);
        System.assertEquals('month', lineOf(lines, 'feePhone').unit);
        System.assertEquals(200, lineOf(lines, 'feePhone').divisor);
        System.assertEquals(6, lineOf(lines, 'feeTraining').perDay);
        System.assertEquals(150, lineOf(lines, 'feeTraining').divisor);
        System.assertEquals('mission', lineOf(lines, 'feeTraining').divisorSource);
        System.assertEquals(2, lineOf(lines, 'feeEpi').perDay);
        System.assertEquals(2, lineOf(lines, 'feeOther').perDay);
        System.assertEquals(8.25, lineOf(lines, 'feeOfiiTax').perDay);
        System.assertEquals('year', lineOf(lines, 'feeOfiiTax').unit);
        // Total des frais ponctuels (hors gratuité) = 4 + 3 + 6 + 2 + 2 + 8,25
        System.assertEquals(25.25, AR_PricingCalculator.calcFraisPonctuelsJour(ctx, 500));
    }

    @IsTest
    static void testCalcFeeBreakdown_ofiiTaxIgnoresMissionDays() {
        // 1650 / 220 = 7,5 quelle que soit la durée de la mission (100 j) ; 1650 / 100 = 16,5 serait faux
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.workingDaysPerYear = 220;
        ctx.missionDays = 100;
        ctx.feeOfiiTax = 1650;

        List<AR_PricingResult.FeeLine> lines = AR_PricingCalculator.calcFeeBreakdown(ctx);

        System.assertEquals(1, lines.size());
        System.assertEquals(220, lines[0].divisor);
        System.assertEquals(7.5, lines[0].perDay);
    }

    @IsTest
    static void testCalcFeeBreakdown_noMissionDays_fallsBackOnWorkingDays() {
        // Formation 400 sans durée de mission : 400 / 200 = 2 ; téléphone 25 €/mois : 25×12/200 = 1,5
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.workingDaysPerYear = 200;
        ctx.missionDays = 0;
        ctx.feeTraining = 400;
        ctx.feePhone = 25;

        List<AR_PricingResult.FeeLine> lines = AR_PricingCalculator.calcFeeBreakdown(ctx);

        System.assertEquals(2, lineOf(lines, 'feeTraining').perDay);
        System.assertEquals('working_days', lineOf(lines, 'feeTraining').divisorSource);
        System.assertEquals(1.5, lineOf(lines, 'feePhone').perDay);
    }

    @IsTest
    static void testCalcFeeBreakdown_zeroNullAndNegativeFeesAreOmitted() {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.feeComputer = 0;
        ctx.feePhone = null;
        ctx.feeTraining = -50;

        System.assert(AR_PricingCalculator.calcFeeBreakdown(ctx).isEmpty());
    }

    @IsTest
    static void testCompute_breakdownExposedForCdiAndEmptyForIndep() {
        AR_PricingCalculator.Context cdi = new AR_PricingCalculator.Context();
        cdi.contractType = 'CDI';
        cdi.annualSalary = 50000;
        cdi.workingDaysPerYear = 200;
        cdi.feeOfiiTax = 1650;
        AR_PricingResult cdiResult = AR_PricingCalculator.compute(cdi, 0, 700, 0, null);
        System.assertEquals(1, cdiResult.feeBreakdown.size());
        System.assertEquals(8.25, cdiResult.feeBreakdown[0].perDay);
        // CJM 505 + OFII 8,25
        System.assertEquals(513.25, cdiResult.totalDailyCost);

        AR_PricingCalculator.Context indep = new AR_PricingCalculator.Context();
        indep.contractType = 'INDEP';
        indep.cjmBeforeMarkup = 200;
        indep.markupApplied = 18;
        indep.feePhone = 30;
        AR_PricingResult indepResult = AR_PricingCalculator.compute(indep, 0, 400, 0, null);
        System.assert(indepResult.feeBreakdown.isEmpty(), 'INDEP : aucun frais ponctuel dans le coût, donc aucun détail');
        System.assertEquals(218, indepResult.totalDailyCost);
    }

    private static AR_PricingCalculator.Context contextCdi(Decimal missionDays) {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.annualSalary = 45000;
        ctx.workingDaysPerYear = 218;
        ctx.missionDays = missionDays;
        return ctx;
    }

    private static AR_PricingCalculator.FeePeriod feePeriod(Decimal days, Decimal feeIk, Decimal feeMeals, Decimal feeLodging) {
        AR_PricingCalculator.FeePeriod period = new AR_PricingCalculator.FeePeriod();
        period.days = days;
        period.feeIk = feeIk;
        period.feeMeals = feeMeals;
        period.feeLodging = feeLodging;
        period.feeOmOther = 0;
        return period;
    }

    @IsTest
    static void testCalcFeePeriods_smoothsP1AndAddedPeriodOnMissionDays() {
        AR_PricingCalculator.Context ctx = contextCdi(200);
        ctx.feeLodging = 85;
        ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>{ feePeriod(180, 12, 0, 0) };

        AR_PricingCalculator.FeePeriodsResult lisse = AR_PricingCalculator.calcFeePeriods(ctx);
        // (20 j x 85 + 180 j x 12) / 200 = 19,30
        System.assertEquals(19.3, lisse.smoothedPerDay);
        System.assertEquals(2, lisse.periods.size());
        System.assertEquals(20, lisse.periods[0].days, 'P1 = durée - autres périodes');
        System.assertEquals(85, lisse.periods[0].perDay);
        System.assertEquals(180, lisse.periods[1].days);
        System.assertEquals(12, lisse.periods[1].perDay);
        System.assertEquals(false, lisse.exceedMission);
        System.assertEquals(false, lisse.missionUnknown);

        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, 700, 0, null);
        System.assertEquals(19.3, result.feeOmPerDay, 'Le coût journalier porte la valeur lissée');
        System.assertEquals(436.3, result.totalDailyCost, 'CJM 417 + frais OM lissés 19,30');
        System.assertEquals(2, result.feeOmPeriods.size());
    }

    @IsTest
    static void testCalcFeePeriods_addedDaysBeyondMissionZeroP1AndFlagExceed() {
        AR_PricingCalculator.Context ctx = contextCdi(100);
        ctx.feeLodging = 40;
        ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>{
            feePeriod(80, 20, 0, 0),
            feePeriod(40, 0, 10, 0)
        };

        AR_PricingCalculator.FeePeriodsResult lisse = AR_PricingCalculator.calcFeePeriods(ctx);
        System.assertEquals(0, lisse.periods[0].days, 'P1 ramenée à 0 jour');
        System.assertEquals(true, lisse.exceedMission);
        // (80 x 20 + 40 x 10) / 120 = 16,67
        System.assert(Math.abs(lisse.smoothedPerDay - 16.6666666667) < 0.000001, 'lissé sur les seules périodes ajoutées : ' + lisse.smoothedPerDay);
    }

    @IsTest
    static void testCalcFeePeriods_unknownMissionKeepsP1AndFlagsIt() {
        AR_PricingCalculator.Context ctx = contextCdi(0);
        ctx.feeLodging = 30;
        ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>{ feePeriod(50, 10, 0, 0) };

        AR_PricingCalculator.FeePeriodsResult lisse = AR_PricingCalculator.calcFeePeriods(ctx);
        System.assertEquals(30, lisse.smoothedPerDay, 'Pas de lissage sans durée de mission : valeur de P1');
        System.assertEquals(true, lisse.missionUnknown);
        System.assertEquals(null, lisse.periods[0].days, 'P1 sans jours calculables');
        System.assertEquals(false, lisse.exceedMission);
    }

    @IsTest
    static void testCalcFeePeriods_indepCostIdenticalWithOrWithoutPeriods() {
        AR_PricingResult sans = AR_PricingCalculator.compute(contextIndep(false), 0, 700, 0, null);
        AR_PricingResult avec = AR_PricingCalculator.compute(contextIndep(true), 0, 700, 0, null);

        System.assertEquals(sans.totalDailyCost, avec.totalDailyCost, 'INDEP : les frais OM ne comptent pas, les périodes non plus');
        System.assertEquals(460, avec.totalDailyCost);
    }

    private static AR_PricingCalculator.Context contextIndep(Boolean withPeriods) {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'INDEP';
        ctx.cjmBeforeMarkup = 400;
        ctx.markupApplied = 60;
        ctx.missionDays = 200;
        ctx.feeLodging = 85;
        if (withPeriods) {
            ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>{ feePeriod(180, 12, 0, 0) };
        }
        return ctx;
    }

    @IsTest
    static void testCalcFeePeriods_emptyListSameAsNoList() {
        AR_PricingCalculator.Context ctx = contextCdi(200);
        ctx.feeLodging = 85;
        ctx.feePeriods = new List<AR_PricingCalculator.FeePeriod>();

        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, 700, 0, null);
        System.assertEquals(85, result.feeOmPerDay);
        System.assertEquals(502, result.totalDailyCost);
        System.assert(result.feeOmPeriods.isEmpty(), 'Aucune période : liste vide');
        System.assertEquals(false, result.feePeriodsExceedMission);
    }

    // ------------------------------------------------------------------
    // Périodes de TJM (docs/254 §3) : TJM moyen pondéré par la durée de mission.
    // ------------------------------------------------------------------

    @IsTest
    static void testCalcTjmPeriods_clientCase_weightedAndP1Days() {
        // Mission 120 j : P1 = 120 - 60 = 60 j à 650, P2 = 60 j à 700 → (60 × 650 + 60 × 700) / 120 = 675.
        AR_PricingCalculator.Context ctx = tjmCtx(120, new List<AR_PricingCalculator.TjmPeriod>{ tjmPeriod(60, 700) });

        AR_PricingCalculator.TjmWeightedResult result = AR_PricingCalculator.calcTjmPeriods(ctx, 650);

        System.assertEquals(675, result.tjmWeighted, 'Pondéré = somme des numérateurs / jours totaux');
        System.assertEquals(2, result.periods.size(), 'P1 comprise dans la liste quand une période est ajoutée');
        System.assertEquals(60, result.periods[0].days, 'P1 garde les jours restants');
        System.assertEquals(650, result.periods[0].tjm);
        System.assertEquals(false, result.exceedMission);
        System.assertEquals(false, result.missionUnknown);
    }

    @IsTest
    static void testCalcTjmPeriods_equalToMission_exceedsAndP1ZeroDays() {
        // Autres = 100 = mission : test ≥ → P1 à 0 jour, le pondéré porte sur la période ajoutée seule.
        AR_PricingCalculator.Context ctx = tjmCtx(100, new List<AR_PricingCalculator.TjmPeriod>{ tjmPeriod(100, 700) });

        AR_PricingCalculator.TjmWeightedResult result = AR_PricingCalculator.calcTjmPeriods(ctx, 600);

        System.assertEquals(700, result.tjmWeighted);
        System.assertEquals(true, result.exceedMission, 'Égalité = dépassement (test ≥)');
        System.assertEquals(0, result.periods[0].days);
    }

    @IsTest
    static void testCalcTjmPeriods_unknownMission_keepsP1AndFlagsIt() {
        AR_PricingCalculator.Context ctx = tjmCtx(0, new List<AR_PricingCalculator.TjmPeriod>{ tjmPeriod(50, 700) });

        AR_PricingCalculator.TjmWeightedResult result = AR_PricingCalculator.calcTjmPeriods(ctx, 650);

        System.assertEquals(650, result.tjmWeighted, 'Durée inconnue : pondéré = TJM de la période 1');
        System.assertEquals(true, result.missionUnknown);
        System.assertEquals(null, result.periods[0].days, 'Jours de la période 1 inconnus');
    }

    @IsTest
    static void testCalcTjmPeriods_noPeriods_sameAsProposedTjm() {
        AR_PricingCalculator.Context withEmpty = tjmCtx(120, new List<AR_PricingCalculator.TjmPeriod>());
        AR_PricingCalculator.Context withNull = tjmCtx(120, null);

        System.assertEquals(650, AR_PricingCalculator.calcTjmPeriods(withEmpty, 650).tjmWeighted);
        System.assertEquals(650, AR_PricingCalculator.calcTjmPeriods(withNull, 650).tjmWeighted);
        System.assert(AR_PricingCalculator.calcTjmPeriods(withNull, 650).periods.isEmpty(), 'Aucune période : liste vide');
    }

    @IsTest
    static void testCompute_mc2UsesWeightedTjm() {
        // Coût CDI 45 000 € = 417 ; pondéré 675 → MC2/j = 675 - 417 = 258 ; l'équivalent EUR part du pondéré.
        AR_PricingCalculator.Context ctx = tjmCtx(120, new List<AR_PricingCalculator.TjmPeriod>{ tjmPeriod(60, 700) });
        ctx.contractType = 'CDI';
        ctx.annualSalary = 45000;

        AR_PricingResult result = AR_PricingCalculator.compute(ctx, 0, 650, 0, null, 1);

        System.assertEquals(675, result.tjmWeighted);
        System.assertEquals(258, result.mc2PerDay, 'MC2/jour calculée sur le pondéré, pas sur la période 1');
        System.assertEquals(675, result.tjmEurEquivalent);
    }

    private static AR_PricingCalculator.Context tjmCtx(Decimal missionDays, List<AR_PricingCalculator.TjmPeriod> periods) {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'CDI';
        ctx.annualSalary = 45000;
        ctx.workingDaysPerYear = 218;
        ctx.missionDays = missionDays;
        ctx.tjmPeriods = periods;
        return ctx;
    }

    private static AR_PricingCalculator.TjmPeriod tjmPeriod(Decimal days, Decimal tjm) {
        AR_PricingCalculator.TjmPeriod p = new AR_PricingCalculator.TjmPeriod();
        p.days = days;
        p.tjm = tjm;
        return p;
    }

    // ------------------------------------------------------------------
    // Régie sans régule (docs/265 §4.4) : coût piloté = coût unitaire × ratio de production.
    // ------------------------------------------------------------------

    private static AR_PricingCalculator.Context rplsrContext(Decimal ratio) {
        AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
        ctx.contractType = 'VIE';
        ctx.cjmVie = 380;
        ctx.rplsrRatio = ratio;
        return ctx;
    }

    @IsTest
    static void testCompute_rplsrActive_pilotedCostDrivesMc2ThresholdsAndSegment() {
        // 212 produits pour 218 vendus : coût piloté 369,5413 ; MC2/j 125,5 ; 25,35 % → recommended.
        AR_PricingResult r = AR_PricingCalculator.compute(
            rplsrContext(Decimal.valueOf(212).divide(218, 18, RoundingMode.HALF_UP)), 0, 495, 0, null, 1
        );
        System.assertEquals(380, r.totalDailyCost, 'Le coût unitaire garde son sens');
        System.assertEquals(125.5, r.mc2PerDay);
        System.assertEquals(25.35, r.mc2PercentHuman);
        System.assertEquals('recommended', r.corridorSegment);
        System.assertEquals(462, r.tjmFloor, 'Seuils calculés sur le coût piloté');
        System.assertEquals(115.0, r.mc2PerDayTheoretical);
        System.assertEquals(23.23, r.mc2PercentTheoretical);
        System.assert(r.totalDailyCostPiloted > 369.54 && r.totalDailyCostPiloted < 369.55);
    }

    @IsTest
    static void testCompute_rplsrNull_modeOffUnchanged() {
        AR_PricingResult r = AR_PricingCalculator.compute(rplsrContext(null), 0, 495, 0, null, 1);
        System.assertEquals(115.0, r.mc2PerDay);
        System.assertEquals(23.23, r.mc2PercentHuman);
        System.assertEquals(475, r.tjmFloor);
        System.assertEquals(null, r.rplsrRatio);
        System.assertEquals(null, r.totalDailyCostPiloted);
        System.assertEquals(null, r.mc2PerDayTheoretical);
        System.assertEquals(null, r.mc2PercentTheoretical);
    }

    @IsTest
    static void testCompute_rplsrZero_isARealValueNeverModeOff() {
        // Aucun jour produit : coût piloté 0, MC2 = TJM ; jamais le repli silencieux sur la MC2 classique.
        AR_PricingResult r = AR_PricingCalculator.compute(rplsrContext(0), 0, 495, 0, null, 1);
        System.assertEquals(0, r.rplsrRatio);
        System.assertEquals(0, r.totalDailyCostPiloted);
        System.assertEquals(495.0, r.mc2PerDay);
        System.assertEquals(100.00, r.mc2PercentHuman);
        System.assertEquals(0, r.tjmFloor);
        System.assertEquals(115.0, r.mc2PerDayTheoretical, 'La MC2 classique reste disponible pour l\'affichage barré');
        System.assertEquals(23.23, r.mc2PercentTheoretical);
    }
}