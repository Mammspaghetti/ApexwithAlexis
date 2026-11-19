/**
 * Moteur de calcul de pricing — reproduit à l'identique les formules de
 * pricing-tool/pricing-tool.html (lignes ~192-262, bloc "Calculator").
 * Classe pure : aucun DML, aucune requête SOQL. Toutes les valeurs de configuration
 * (jours travaillés, % markup, seuils par défaut) sont injectées via Context/ThresholdPercents
 * par l'appelant (AR_PricingMatrixService), qui les lit depuis AR_Settings__mdt / AR_Account_Corridor__c.
 *
 * Convention Percent (cf. docs/02-modele-de-donnees.md §7.2) : les pourcentages qui transitent
 * par ce moteur (rfaPercent, ThresholdPercents.*, mc2PercentHuman du résultat) sont en valeur
 * humaine (23.5 = 23,5 %). Le moteur les convertit en fraction en interne pour les calculs.
 */
public class AR_PricingCalculator {

    // Défauts alignés sur pricing-tool.html (JOURS_TRAVAIL, calcThresholds, getCorridorSegment)
    public static final Decimal JOURS_TRAVAIL_DEFAULT = 218;
    public static final Decimal MARKUP_PERCENT_DEFAULT = 18;
    public static final Decimal MARKUP_MAX_DEFAULT = 60;
    public static final Decimal FLOOR_PERCENT_DEFAULT = 20;
    public static final Decimal TARGET_PERCENT_DEFAULT = 25;
    public static final Decimal IDEAL_PERCENT_DEFAULT = 30;

    // Coefficient salaire -> CJM pour CDI/CDD (session 28) : historiquement le littéral 1,01 * 2 = 2,02
    // figé dans calcCJM. Rendu administrable (AR_General_Setting__c.AR_CDI_Coefficient__c /
    // AR_CDD_Coefficient__c, cf. CLAUDE.md "aucun paramètre métier ne doit demander un déploiement") ;
    // ce défaut ne sert que si l'appelant ne fournit pas Context.contractCoefficient (non-régression
    // des cas de la suite de parité, qui ne le renseignent pas).
    public static final Decimal CONTRACT_COEFFICIENT_DEFAULT = 2.02;

    // Robustesse (session 18) : plancher du dénominateur des seuils TJM_x = coût / (1 - %RFA - x).
    // Envoyé hors bornes côté serveur (RFA 150 %, ou même RFA + palier = 100 % pile), ce dénominateur
    // atteint 0 ou devient négatif — division par zéro (MathException) ou seuil négatif absurde. Les
    // bornes UI (0-20 % sur % RFA) empêchent ce cas depuis le LWC, mais un appel Apex direct (API,
    // Anonymous Apex, futur intégrateur) les contourne : la garde doit vivre ici, pas seulement côté
    // client. Valeur choisie arbitrairement petite (résultat très grand mais fini plutôt qu'un crash).
    private static final Decimal MIN_THRESHOLD_DENOMINATOR = 0.01;

    public class Context {
        public String contractType; // CDI / CDD / INDEP / VIE / NEARSHORE
        public Decimal annualSalary;
        // Coefficient CDI/CDD (session 28) : null = défaut moteur CONTRACT_COEFFICIENT_DEFAULT (2,02).
        // Figé sur la matrice une fois calculé, cf. AR_PricingResult.contractCoefficientApplied.
        public Decimal contractCoefficient;
        public Decimal cjmBeforeMarkup;
        public Decimal markupApplied;
        public Decimal cjmVie;
        public Decimal cjmNearshore;
        public Decimal feeIk = 0;
        public Decimal feeMeals = 0;
        public Decimal feeLodging = 0;
        public Decimal feeOmOther = 0;
        public Decimal gratuityDays = 0;
        public Decimal feeComputer = 0;
        public Decimal feePhone = 0;
        // Autres frais mensuels (pass transport…) : même unité que le téléphone.
        public Decimal feeMonthlyOther = 0;
        public Decimal feeTraining = 0;
        public Decimal feeEpi = 0;
        public Decimal feeOfiiTax = 0;
        public Decimal feeOther = 0;
        public Decimal workingDaysPerYear = JOURS_TRAVAIL_DEFAULT;
        public Decimal missionDays = 0;
        // Congés prévus sur la mission : retranchés des jours de mission (hors régie sans régule).
        public Decimal plannedLeaveDays = 0;
        public Decimal markupPercentSetting = MARKUP_PERCENT_DEFAULT;
        public Decimal markupMaxSetting = MARKUP_MAX_DEFAULT;
        // Périodes de frais OM ajoutées à la période 1 (docs/239) : null ou vide = aucune période.
        public List<FeePeriod> feePeriods;
        // Périodes de TJM ajoutées à la période 1 (docs/254) : null ou vide = aucune évolution de TJM.
        public List<TjmPeriod> tjmPeriods;
        // Périodes de salaire ajoutées à la période 1 (CDI/CDD seulement) : null ou vide = salaire unique.
        public List<SalaryPeriod> salaryPeriods;
        // Régie sans régule (docs/265 §4.4) : Σ jours produits ÷ Σ jours vendus. Null ou nul = mode éteint.
        public Decimal rplsrRatio;
    }

    // Une période ajoutée (P2, P3…) : jours ouvrés et frais OM par jour, comme la période 1 du Context.
    public class FeePeriod {
        public Decimal days;
        public Decimal feeIk;
        public Decimal feeMeals;
        public Decimal feeLodging;
        public Decimal feeOmOther;
    }

    public class FeePeriodsResult {
        public List<AR_PricingResult.FeeOmPeriod> periods = new List<AR_PricingResult.FeeOmPeriod>();
        public Decimal smoothedPerDay;
        public Boolean exceedMission = false;
        public Boolean missionUnknown = false;
    }

    public class ThresholdPercents {
        public Decimal floorPercent;
        public Decimal targetPercent;
        public Decimal idealPercent;
        public ThresholdPercents(Decimal floorPercent, Decimal targetPercent, Decimal idealPercent) {
            this.floorPercent = floorPercent;
            this.targetPercent = targetPercent;
            this.idealPercent = idealPercent;
        }
    }

    // Apex n'autorise pas les méthodes static sur une classe interne : fabrique au niveau de la classe englobante.
    private static ThresholdPercents defaultThresholdPercents() {
        return new ThresholdPercents(FLOOR_PERCENT_DEFAULT, TARGET_PERCENT_DEFAULT, IDEAL_PERCENT_DEFAULT);
    }

    public class MarkupResult {
        public Decimal markupCalcule;
        public Boolean markupMismatch;
    }

    public class Thresholds {
        public Decimal floorValue;
        public Decimal targetValue;
        public Decimal idealValue;
        public Decimal top10Value;
    }

    public class MC2Result {
        public Decimal mc2PerDay;
        public Decimal mc2PercentFraction;
    }

    /**
     * Bornage défensif (session 18) : un salaire/CJM négatif n'a pas de sens métier et se propagerait
     * en coût journalier négatif, puis en MC2/seuils aberrants. `null` traverse tel quel (signal
     * « pas encore renseigné », distinct de 0 — cf. `AR_PricingMatrixService.calculateAndPopulate`,
     * qui teste `ctx.cjmVie == null` pour savoir s'il doit charger le référentiel).
     */
    private static Decimal nonNegative(Decimal value) {
        if (value == null) {
            return null;
        }
        return value < 0 ? 0 : value;
    }

    // Variante qui traite aussi `null` comme 0 — pour les champs où l'absence de saisie doit se
    // traduire par un coût nul plutôt qu'un crash arithmétique (salaire CDI, mark-up INDEP, frais).
    // Reproduit `num()` côté arPricingEngine.js, qui default déjà ainsi ; l'Apex ne le faisait pas
    // (risque de NullPointerException sur un Brouillon sauvegardé avant saisie du salaire).
    private static Decimal nonNegativeOrZero(Decimal value) {
        return value == null || value < 0 ? 0 : value;
    }

    /**
     * Détermine le divisor pour les frais ponctuels (session 121) : nombre de jours de la mission
     * s'il est connu et > 0, sinon repli sur jours travaillés/an. Retourne aussi la source du
     * divisor ('mission' | 'year_fallback') pour l'affichage d'une mention au besoin.
     */
    public class FeePonctuelsDivisorResult {
        public Decimal days;
        public String source; // 'mission' | 'year_fallback'
    }

    /**
     * Jours facturables : jours de mission moins les congés prévus, plancher 0. En régie sans régule,
     * les congés sont ignorés (le prévisionnel mensuel porte déjà les absences).
     */
    public static Decimal calcBillableDays(Context ctx) {
        Decimal days = nonNegativeOrZero(ctx.missionDays);
        if (ctx.rplsrRatio != null) {
            return days;
        }
        Decimal billable = days - nonNegativeOrZero(ctx.plannedLeaveDays);
        return billable > 0 ? billable : 0;
    }

    private static FeePonctuelsDivisorResult calcFeePonctuelsDivisor(Context ctx) {
        FeePonctuelsDivisorResult result = new FeePonctuelsDivisorResult();
        Decimal billableDays = calcBillableDays(ctx);
        if (billableDays > 0) {
            result.days = billableDays;
            result.source = 'mission';
        } else {
            result.days = ctx.workingDaysPerYear != null ? ctx.workingDaysPerYear : JOURS_TRAVAIL_DEFAULT;
            result.source = 'year_fallback';
        }
        return result;
    }

    // pricing-tool.html:208-213 calcCJM — CDD ajouté en session 28 (même formule que CDI, coefficient
    // administrable au lieu du littéral 1,01 * 2, cf. CONTRACT_COEFFICIENT_DEFAULT ci-dessus).
    // CDI/CDD : CJM pondéré par les périodes de salaire (identique au CJM de la période 1 sans période).
    public static Decimal calcCJM(Context ctx) {
        if (hasSalary(ctx)) {
            return calcSalaryPeriods(ctx).cjmWeighted;
        }
        if (ctx.contractType == 'VIE') {
            return nonNegative(ctx.cjmVie);
        }
        if (ctx.contractType == 'NEARSHORE') {
            return nonNegative(ctx.cjmNearshore);
        }
        // INDEP
        return nonNegativeOrZero(ctx.cjmBeforeMarkup) + nonNegativeOrZero(ctx.markupApplied);
    }

    // Statuts dont le CJM vient d'un salaire saisi.
    public static Boolean hasSalary(Context ctx) {
        return ctx.contractType == 'CDI' || ctx.contractType == 'CDD';
    }

    // CJM d'un salaire annuel : salaire × coefficient du contrat ÷ jours travaillés/an, arrondi à l'euro.
    private static Decimal cjmOfSalary(Context ctx, Decimal salary) {
        Decimal days = ctx.workingDaysPerYear != null ? ctx.workingDaysPerYear : JOURS_TRAVAIL_DEFAULT;
        Decimal coefficient = ctx.contractCoefficient != null ? ctx.contractCoefficient : CONTRACT_COEFFICIENT_DEFAULT;
        return (nonNegativeOrZero(salary) * coefficient / days).setScale(0, RoundingMode.HALF_UP);
    }

    // Une période de salaire ajoutée (P2, P3…) : jours ouvrés et salaire annuel brut.
    public class SalaryPeriod {
        public Decimal days;
        public Decimal salary;
    }

    public class SalaryPeriodsResult {
        public Decimal cjmWeighted;
        public List<AR_PricingResult.SalaryPeriod> periods = new List<AR_PricingResult.SalaryPeriod>();
        public Boolean exceedMission = false;
        public Boolean missionUnknown = false;
    }

    /**
     * CJM pondéré par les périodes de salaire, même règle que le TJM pondéré : un CJM par période, moyenne
     * pondérée par les jours facturables, numérateurs sommés avant une seule division. Sans période (ou
     * statut sans salaire) : CJM de la période 1. Durée inconnue : CJM de la période 1, indicateur levé.
     * Périodes ajoutées ≥ durée : période 1 à 0 jour, indicateur levé.
     */
    public static SalaryPeriodsResult calcSalaryPeriods(Context ctx) {
        SalaryPeriodsResult result = new SalaryPeriodsResult();
        Decimal p1Cjm = cjmOfSalary(ctx, ctx.annualSalary);
        result.cjmWeighted = p1Cjm;
        if (!hasSalary(ctx) || ctx.salaryPeriods == null || ctx.salaryPeriods.isEmpty()) {
            return result;
        }

        Decimal othersDays = 0;
        Decimal othersNumerator = 0;
        for (SalaryPeriod p : ctx.salaryPeriods) {
            othersDays += nonNegativeOrZero(p.days);
            othersNumerator += nonNegativeOrZero(p.days) * cjmOfSalary(ctx, p.salary);
        }

        Decimal missionDays = calcBillableDays(ctx);
        Decimal p1Days = null;
        if (missionDays > 0) {
            p1Days = missionDays - othersDays > 0 ? missionDays - othersDays : 0;
            result.exceedMission = othersDays >= missionDays;
            Decimal totalDays = p1Days + othersDays;
            if (totalDays > 0) {
                result.cjmWeighted = (p1Days * p1Cjm + othersNumerator) / totalDays;
            }
        } else {
            result.missionUnknown = true;
        }

        addSalaryPeriod(result.periods, 1, p1Days, nonNegativeOrZero(ctx.annualSalary), p1Cjm);
        Integer index = 2;
        for (SalaryPeriod p : ctx.salaryPeriods) {
            addSalaryPeriod(result.periods, index, nonNegativeOrZero(p.days), nonNegativeOrZero(p.salary), cjmOfSalary(ctx, p.salary));
            index++;
        }
        return result;
    }

    private static void addSalaryPeriod(List<AR_PricingResult.SalaryPeriod> periods, Integer index, Decimal days, Decimal salary, Decimal cjm) {
        AR_PricingResult.SalaryPeriod period = new AR_PricingResult.SalaryPeriod();
        period.index = index;
        period.days = days;
        period.salary = salary;
        period.cjm = cjm;
        periods.add(period);
    }

    // pricing-tool.html:199-206 calcMarkupCalcule / calcMarkupAlerte
    public static MarkupResult calcMarkup(Decimal cjmAvantMarkup, Decimal markupApplique, Decimal markupPercentSetting, Decimal markupMaxSetting) {
        MarkupResult result = new MarkupResult();
        if (cjmAvantMarkup == null) {
            // Écart de parité (session 27) : arPricingEngine.calcMarkup renvoie markupMismatch=false
            // dans ce cas (CJM avant mark-up pas encore saisi), jamais null — même correctif qu'en
            // tête de compute().
            result.markupMismatch = false;
            return result;
        }
        Decimal pct = markupPercentSetting != null ? markupPercentSetting : MARKUP_PERCENT_DEFAULT;
        Decimal maxVal = markupMaxSetting != null ? markupMaxSetting : MARKUP_MAX_DEFAULT;
        Decimal rawMarkup = (cjmAvantMarkup * pct / 100).setScale(2, RoundingMode.HALF_UP);
        result.markupCalcule = rawMarkup < maxVal ? rawMarkup : maxVal.setScale(2, RoundingMode.HALF_UP);
        result.markupMismatch = markupApplique != null
            && markupApplique.setScale(0, RoundingMode.HALF_UP) != result.markupCalcule.setScale(0, RoundingMode.HALF_UP);
        return result;
    }

    // pricing-tool.html:214-217 calcFraisOMJour
    public static Decimal calcFraisOMJour(Context ctx) {
        return feeOmPerDayOf(ctx.feeIk, ctx.feeMeals, ctx.feeLodging, ctx.feeOmOther);
    }

    private static Decimal feeOmPerDayOf(Decimal feeIk, Decimal feeMeals, Decimal feeLodging, Decimal feeOmOther) {
        return nonNegativeOrZero(feeIk)
            + nonNegativeOrZero(feeMeals)
            + nonNegativeOrZero(feeLodging)
            + nonNegativeOrZero(feeOmOther);
    }

    // Une période de TJM ajoutée (P2, P3…) : jours ouvrés et TJM de la période, comme FeePeriod.
    public class TjmPeriod {
        public Decimal days;
        public Decimal tjm;
    }

    public class TjmWeightedResult {
        public Decimal tjmWeighted;
        public List<AR_PricingResult.TjmPeriod> periods = new List<AR_PricingResult.TjmPeriod>();
        public Boolean exceedMission = false;
        public Boolean missionUnknown = false;
    }

    /**
     * Frais OM lissés sur les périodes (docs/239 §3) : moyenne pondérée par les jours, numérateurs
     * sommés avant une seule division. Sans période : valeur de la période 1 (chemin d'aujourd'hui).
     * Durée de mission inconnue : pas de lissage, valeur de la période 1 et indicateur levé.
     * Somme des autres périodes > durée : période 1 ramenée à 0 jour, indicateur levé.
     */
    public static FeePeriodsResult calcFeePeriods(Context ctx) {
        FeePeriodsResult result = new FeePeriodsResult();
        Decimal p1PerDay = calcFraisOMJour(ctx);
        result.smoothedPerDay = p1PerDay;
        if (ctx.feePeriods == null || ctx.feePeriods.isEmpty()) {
            return result;
        }

        Decimal othersDays = 0;
        Decimal othersNumerator = 0;
        for (FeePeriod p : ctx.feePeriods) {
            Decimal perDay = feeOmPerDayOf(p.feeIk, p.feeMeals, p.feeLodging, p.feeOmOther);
            othersDays += nonNegativeOrZero(p.days);
            othersNumerator += nonNegativeOrZero(p.days) * perDay;
        }

        Decimal missionDays = calcBillableDays(ctx);
        Decimal p1Days = null;
        if (missionDays > 0) {
            p1Days = missionDays - othersDays > 0 ? missionDays - othersDays : 0;
            result.exceedMission = othersDays > missionDays;
            Decimal totalDays = p1Days + othersDays;
            if (totalDays > 0) {
                result.smoothedPerDay = (p1Days * p1PerDay + othersNumerator) / totalDays;
            }
        } else {
            result.missionUnknown = true;
        }

        addFeeOmPeriod(result.periods, 1, p1Days, p1PerDay);
        Integer index = 2;
        for (FeePeriod p : ctx.feePeriods) {
            addFeeOmPeriod(result.periods, index, nonNegativeOrZero(p.days), feeOmPerDayOf(p.feeIk, p.feeMeals, p.feeLodging, p.feeOmOther));
            index++;
        }
        return result;
    }

    private static void addFeeOmPeriod(List<AR_PricingResult.FeeOmPeriod> periods, Integer index, Decimal days, Decimal perDay) {
        AR_PricingResult.FeeOmPeriod period = new AR_PricingResult.FeeOmPeriod();
        period.index = index;
        period.days = days;
        period.perDay = perDay;
        periods.add(period);
    }

    /**
     * TJM pondéré sur les périodes (docs/254 §3.1-3.3) : moyenne du TJM par jour de mission, numérateurs
     * sommés avant une seule division. Sans période : tjm1 (chemin d'aujourd'hui). Durée de mission
     * inconnue : tjm1 et indicateur levé. Périodes ajoutées ≥ durée (test ≥ et non > comme les frais) :
     * période 1 ramenée à 0 jour, indicateur levé — le calcul se fait alors sur les périodes ajoutées.
     * tjm1 nul (TJM non saisi) : pondéré nul, sauf si la période 1 n'a aucun jour.
     */
    public static TjmWeightedResult calcTjmPeriods(Context ctx, Decimal tjm1) {
        TjmWeightedResult result = new TjmWeightedResult();
        result.tjmWeighted = tjm1;
        if (ctx.tjmPeriods == null || ctx.tjmPeriods.isEmpty()) {
            return result;
        }

        Decimal othersDays = 0;
        Decimal othersNumerator = 0;
        for (TjmPeriod p : ctx.tjmPeriods) {
            othersDays += nonNegativeOrZero(p.days);
            othersNumerator += nonNegativeOrZero(p.days) * nonNegativeOrZero(p.tjm);
        }

        Decimal missionDays = calcBillableDays(ctx);
        Decimal p1Days = null;
        if (missionDays > 0) {
            p1Days = missionDays - othersDays > 0 ? missionDays - othersDays : 0;
            result.exceedMission = othersDays >= missionDays;
            Decimal totalDays = p1Days + othersDays;
            if (totalDays > 0 && (p1Days == 0 || tjm1 != null)) {
                Decimal p1Numerator = p1Days == 0 ? 0 : p1Days * tjm1;
                result.tjmWeighted = (p1Numerator + othersNumerator) / totalDays;
            }
        } else {
            result.missionUnknown = true;
        }

        addTjmPeriod(result.periods, 1, p1Days, tjm1);
        Integer index = 2;
        for (TjmPeriod p : ctx.tjmPeriods) {
            addTjmPeriod(result.periods, index, nonNegativeOrZero(p.days), nonNegativeOrZero(p.tjm));
            index++;
        }
        return result;
    }

    private static void addTjmPeriod(List<AR_PricingResult.TjmPeriod> periods, Integer index, Decimal days, Decimal tjm) {
        AR_PricingResult.TjmPeriod period = new AR_PricingResult.TjmPeriod();
        period.index = index;
        period.days = days;
        period.tjm = tjm;
        periods.add(period);
    }

    public static Decimal calcFraisOMJourLisse(Context ctx) {
        return calcFeePeriods(ctx).smoothedPerDay;
    }

    private static Decimal workingDaysOf(Context ctx) {
        return ctx.workingDaysPerYear != null && ctx.workingDaysPerYear > 0 ? ctx.workingDaysPerYear : JOURS_TRAVAIL_DEFAULT;
    }

    private static void addFeeLine(
        List<AR_PricingResult.FeeLine> lines, String key, Decimal amount, String unit,
        Decimal multiplier, Decimal divisor, String divisorSource
    ) {
        Decimal value = nonNegativeOrZero(amount);
        if (value == 0) {
            return;
        }
        AR_PricingResult.FeeLine line = new AR_PricingResult.FeeLine();
        line.key = key;
        line.amount = value;
        line.unit = unit;
        line.divisor = divisor;
        line.divisorSource = divisorSource;
        line.perDay = value * multiplier / divisor;
        lines.add(line);
    }

    /**
     * Détail par poste des frais ponctuels ramenés au jour, selon l'unité de saisie de chacun :
     * PC par jour (tel quel) ; téléphone et autres frais mensuels par mois (× 12 ÷ jours travaillés/an) ; formation, EPI et autre
     * par mission (÷ jours de mission, repli sur jours travaillés/an) ; taxe OFII par an (÷ jours
     * travaillés/an, jamais la durée de la mission). La gratuité n'en fait pas partie (cf. calcFraisPonctuelsJour).
     */
    public static List<AR_PricingResult.FeeLine> calcFeeBreakdown(Context ctx) {
        List<AR_PricingResult.FeeLine> lines = new List<AR_PricingResult.FeeLine>();
        Decimal workingDays = workingDaysOf(ctx);
        FeePonctuelsDivisorResult mission = calcFeePonctuelsDivisor(ctx);
        String missionSource = mission.source == 'mission' ? 'mission' : 'working_days';
        addFeeLine(lines, 'feeComputer', ctx.feeComputer, 'day', 1, 1, null);
        addFeeLine(lines, 'feePhone', ctx.feePhone, 'month', 12, workingDays, 'working_days');
        addFeeLine(lines, 'feeMonthlyOther', ctx.feeMonthlyOther, 'month', 12, workingDays, 'working_days');
        addFeeLine(lines, 'feeTraining', ctx.feeTraining, 'mission', 1, mission.days, missionSource);
        addFeeLine(lines, 'feeEpi', ctx.feeEpi, 'mission', 1, mission.days, missionSource);
        addFeeLine(lines, 'feeOfiiTax', ctx.feeOfiiTax, 'year', 1, workingDays, 'working_days');
        addFeeLine(lines, 'feeOther', ctx.feeOther, 'mission', 1, mission.days, missionSource);
        return lines;
    }

    // pricing-tool.html:218-224 calcFraisPonctuelsJour (gratuité = jours × CJM)
    // La gratuité est ramenée au jour par les jours de mission (repli jours travaillés/an) ; chaque autre
    // poste par sa propre unité (cf. calcFeeBreakdown). Les numérateurs qui partagent un même diviseur
    // sont additionnés AVANT la division : une fraction non terminante (404/218 + 200/218 + 50/218)
    // sommée terme à terme dériverait de 1e-30 de la valeur exacte (654/218 = 3).
    public static Decimal calcFraisPonctuelsJour(Context ctx, Decimal cjm) {
        FeePonctuelsDivisorResult mission = calcFeePonctuelsDivisor(ctx);
        Map<String, Decimal> numeratorByDivisor = new Map<String, Decimal>();
        Map<String, Decimal> divisorByKey = new Map<String, Decimal>();
        addNumerator(numeratorByDivisor, divisorByKey, mission.days, nonNegativeOrZero(ctx.gratuityDays) * nonNegativeOrZero(cjm));
        for (AR_PricingResult.FeeLine line : calcFeeBreakdown(ctx)) {
            addNumerator(numeratorByDivisor, divisorByKey, line.divisor, line.unit == 'month' ? line.amount * 12 : line.amount);
        }
        Decimal total = 0;
        for (String key : numeratorByDivisor.keySet()) {
            total += numeratorByDivisor.get(key) / divisorByKey.get(key);
        }
        return total;
    }

    private static void addNumerator(Map<String, Decimal> numeratorByDivisor, Map<String, Decimal> divisorByKey, Decimal divisor, Decimal numerator) {
        String key = divisor.stripTrailingZeros().toPlainString();
        divisorByKey.put(key, divisor);
        numeratorByDivisor.put(key, (numeratorByDivisor.containsKey(key) ? numeratorByDivisor.get(key) : 0) + numerator);
    }

    /** Gratuité ramenée au jour (jours offerts × CJM ÷ jours de mission, repli jours travaillés/an) : même formule que calcTotalDailyCost. */
    public static Decimal calcGratuityPerDay(Context ctx, Decimal cjm) {
        return nonNegativeOrZero(ctx.gratuityDays) * nonNegativeOrZero(cjm) / calcFeePonctuelsDivisor(ctx).days;
    }

    // pricing-tool.html:225-231 calcCoutJournalierTotal
    // CDI/CDD/VIE : CJM + fraisOM + fraisPonctuels ; INDEP/NEARSHORE : CJM + gratuité×CJM/joursMission
    // CDD ajouté en session 28 : salarié comme le CDI, mêmes frais professionnels (OM/ponctuels),
    // à la différence d'INDEP/NEARSHORE qui sont des prestataires.
    // Session 121 : gratuité divisée par jours de mission si connus, sinon jours travaillés/an.
    public static Decimal calcTotalDailyCost(Context ctx) {
        Decimal cjm = calcCJM(ctx);
        if (ctx.contractType == 'CDI' || ctx.contractType == 'CDD' || ctx.contractType == 'VIE') {
            return cjm + calcFraisOMJourLisse(ctx) + calcFraisPonctuelsJour(ctx, cjm);
        }
        FeePonctuelsDivisorResult divisor = calcFeePonctuelsDivisor(ctx);
        Decimal gratuite = nonNegativeOrZero(ctx.gratuityDays) * cjm;
        return cjm + gratuite / divisor.days;
    }

    // pricing-tool.html:232-242 calcThresholds — TJM_x = coût / (1 - %RFA - x), arrondi Math.ceil
    public static Thresholds calcThresholds(Decimal coutTotal, Decimal rfaPercent, Decimal top10Comparables, ThresholdPercents customPcts) {
        ThresholdPercents pcts = customPcts != null ? customPcts : defaultThresholdPercents();
        Decimal rfa = (rfaPercent != null ? rfaPercent : 0) / 100;
        Decimal fp = pcts.floorPercent / 100;
        Decimal tp = pcts.targetPercent / 100;
        Decimal ip = pcts.idealPercent / 100;

        Thresholds th = new Thresholds();
        th.floorValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - fp));
        th.targetValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - tp));
        th.idealValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - ip));
        Decimal top10FromIdeal = ceilToInt(th.idealValue * 1.10);
        Decimal top10Ai = top10Comparables != null ? top10Comparables : 0;
        th.top10Value = top10Ai > top10FromIdeal ? top10Ai : top10FromIdeal;
        return th;
    }

    private static Decimal boundedDenominator(Decimal value) {
        return value < MIN_THRESHOLD_DENOMINATOR ? MIN_THRESHOLD_DENOMINATOR : value;
    }

    // pricing-tool.html:243-248 calcMC2
    // Robustesse (session 18b) : `tjm == 0` ne filtrait pas un TJM négatif — saisissable avant l'ajout
    // de min="0" sur le champ, ou envoyé hors bornes directement. mc2PercentFraction = mc2Jour/tjm
    // devient alors négatif/négatif = un pourcentage positif absurde (ex. TJM -100, coût 447 →
    // mc2Jour -547, mc2% = 547 % — lu comme une marge excellente).
    public static MC2Result calcMC2(Decimal tjm, Decimal coutTotal, Decimal rfaPercent) {
        MC2Result result = new MC2Result();
        if (tjm == null || tjm <= 0) {
            result.mc2PerDay = 0;
            result.mc2PercentFraction = 0;
            return result;
        }
        Decimal rfa = (rfaPercent != null ? rfaPercent : 0) / 100;
        Decimal mc2Jour = tjm * (1 - rfa) - (coutTotal != null ? coutTotal : 0);
        result.mc2PerDay = mc2Jour.setScale(1, RoundingMode.HALF_UP);
        result.mc2PercentFraction = mc2Jour / tjm;
        return result;
    }

    // pricing-tool.html:249-258 getCorridorSegment
    public static String getCorridorSegment(Decimal mc2PercentFraction, ThresholdPercents customPcts) {
        ThresholdPercents pcts = customPcts != null ? customPcts : defaultThresholdPercents();
        Decimal p = (mc2PercentFraction != null ? mc2PercentFraction : 0) * 100;
        if (p < pcts.floorPercent) {
            return 'below_floor';
        }
        if (p < pcts.targetPercent) {
            return 'low_margin';
        }
        if (p < pcts.idealPercent) {
            return 'recommended';
        }
        return 'superstar';
    }

    /**
     * Orchestre l'ensemble du pipeline (CJM → frais → coût total → seuils → MC2 → segment)
     * et retourne le wrapper sérialisable consommé par le service et le LWC.
     * Surcharge rétrocompatible : rateToEur par défaut à 1 (matrice EUR), pour les appelants
     * antérieurs à la session 24 (ex. AR_PricingMatrixService.simulate, non exposé aujourd'hui).
     */
    public static AR_PricingResult compute(Context ctx, Decimal rfaPercent, Decimal proposedTjm, Decimal top10Comparables, ThresholdPercents customPcts) {
        return compute(ctx, rfaPercent, proposedTjm, top10Comparables, customPcts, 1);
    }

    /**
     * rateToEur (session 24) : taux vers EUR déjà résolu par l'appelant (AR_CurrencyRateService),
     * jamais recalculé ici — ce moteur reste une classe pure sans DML/SOQL. Sert uniquement à
     * calculer les équivalents pivot EUR (comparaison/consolidation, session 24b), jamais le calcul
     * natif lui-même qui reste intégralement dans la devise de la matrice (CLAUDE.md).
     */
    public static AR_PricingResult compute(Context ctx, Decimal rfaPercent, Decimal proposedTjm, Decimal top10Comparables, ThresholdPercents customPcts, Decimal rateToEur) {
        AR_PricingResult result = new AR_PricingResult();
        result.cjm = calcCJM(ctx);
        if (hasSalary(ctx)) {
            SalaryPeriodsResult salary = calcSalaryPeriods(ctx);
            result.salaryPeriods = salary.periods;
            result.salaryPeriodsExceedMission = salary.exceedMission;
            result.salaryPeriodsMissionUnknown = salary.missionUnknown;
        }

        // Coefficient CDI/CDD effectivement utilisé (session 28) : figé ici comme floorPercentApplied
        // ci-dessous, pour qu'une matrice décidée garde son coefficient même si l'administration change
        // ensuite AR_General_Setting__c.AR_CDI_Coefficient__c/AR_CDD_Coefficient__c. Null pour les
        // autres statuts de contrat (le coefficient n'a pas de sens pour INDEP/VIE/NEARSHORE).
        result.contractCoefficientApplied = (ctx.contractType == 'CDI' || ctx.contractType == 'CDD')
            ? (ctx.contractCoefficient != null ? ctx.contractCoefficient : CONTRACT_COEFFICIENT_DEFAULT)
            : null;

        // Jours travaillés/an effectivement utilisés (session 48), figés au même titre que le
        // coefficient ci-dessus — contrairement à lui, s'applique à TOUS les statuts de contrat
        // (calcFraisOMJour/calcFraisPonctuelsJour ci-dessous les consomment sans distinction), donc
        // jamais null.
        result.workingDaysPerYearApplied = ctx.workingDaysPerYear != null
            ? ctx.workingDaysPerYear
            : JOURS_TRAVAIL_DEFAULT;

        // Écart de parité trouvé en session 27 (jeu de cas de référence, prompts/session-27-filet-de-tests.md
        // §1) : sans cette initialisation, markupMismatch restait au défaut Apex (null) pour tout
        // contrat non-INDEP, alors qu'arPricingEngine.compute() l'initialise à `false`. Les deux
        // valeurs sont équivalentes dans toute vérification `if`/`&&` (null est falsy comme false),
        // mais un moteur qui renvoie null et l'autre false pour la même entrée n'est pas une parité
        // réelle — correctif évident et sans risque (aucun changement de comportement observable).
        result.markupMismatch = false;

        if (ctx.contractType == 'INDEP') {
            MarkupResult markup = calcMarkup(ctx.cjmBeforeMarkup, ctx.markupApplied, ctx.markupPercentSetting, ctx.markupMaxSetting);
            result.markupCalcule = markup.markupCalcule;
            result.markupMismatch = markup.markupMismatch;
        }

        FeePeriodsResult feePeriods = calcFeePeriods(ctx);
        result.feeOmPerDay = feePeriods.smoothedPerDay;
        result.feeOmPeriods = feePeriods.periods;
        result.feePeriodsExceedMission = feePeriods.exceedMission;
        result.feePeriodsMissionUnknown = feePeriods.missionUnknown;
        result.feePonctuelsPerDay = calcFraisPonctuelsJour(ctx, result.cjm);
        result.totalDailyCost = calcTotalDailyCost(ctx);

        // Session 121 : enregistre le divisor des frais ponctuels pour affichage du contexte (durée).
        FeePonctuelsDivisorResult divisor = calcFeePonctuelsDivisor(ctx);
        result.feePonctuelsDivisorDays = divisor.days;
        result.feePonctuelsDivisorSource = divisor.source;
        result.feeBreakdown = (ctx.contractType == 'CDI' || ctx.contractType == 'CDD' || ctx.contractType == 'VIE')
            ? calcFeeBreakdown(ctx)
            : new List<AR_PricingResult.FeeLine>();

        // Résolu une seule fois ici (grand compte ou défaut) pour rester la même valeur que celle
        // effectivement utilisée par calcThresholds/getCorridorSegment ci-dessous, et pour pouvoir
        // être figée sur la matrice (session 23b) — sinon une matrice décidée n'a aucun moyen de
        // savoir quel corridor a produit ses seuils une fois AR_Account_Corridor__c modifié.
        ThresholdPercents pcts = customPcts != null ? customPcts : defaultThresholdPercents();
        result.floorPercentApplied = pcts.floorPercent;
        result.targetPercentApplied = pcts.targetPercent;
        result.idealPercentApplied = pcts.idealPercent;

        // Régie sans régule : le coût par jour VENDU est le coût unitaire × ratio de production ; mode éteint (ratio
        // absent), rien ne change. Un ratio de 0 (aucun jour produit) est une vraie valeur, calculée telle quelle.
        Boolean rplsrActive = ctx.rplsrRatio != null;
        Decimal costForMargin = result.totalDailyCost;
        if (rplsrActive) {
            result.rplsrRatio = ctx.rplsrRatio;
            result.totalDailyCostPiloted = result.totalDailyCost * ctx.rplsrRatio;
            costForMargin = result.totalDailyCostPiloted;
        }

        Thresholds th = calcThresholds(costForMargin, rfaPercent, top10Comparables, pcts);
        result.tjmFloor = th.floorValue;
        result.tjmTarget = th.targetValue;
        result.tjmIdeal = th.idealValue;
        result.tjmTop10 = th.top10Value;

        // TJM pondéré (docs/254 §3.5) : le MC2 et l'équivalent EUR partent du pondéré, jamais de la période 1.
        TjmWeightedResult tjm = calcTjmPeriods(ctx, proposedTjm);
        result.tjmWeighted = tjm.tjmWeighted;
        result.tjmPeriods = tjm.periods;
        result.tjmPeriodsExceedMission = tjm.exceedMission;
        result.tjmPeriodsMissionUnknown = tjm.missionUnknown;

        MC2Result mc2 = calcMC2(result.tjmWeighted, costForMargin, rfaPercent);
        if (rplsrActive) {
            // Valeurs du mode éteint, pour l'affichage barré et le repère fantôme de la jauge.
            MC2Result theoretical = calcMC2(result.tjmWeighted, result.totalDailyCost, rfaPercent);
            result.mc2PerDayTheoretical = theoretical.mc2PerDay;
            result.mc2PercentTheoretical = (theoretical.mc2PercentFraction * 100).setScale(2, RoundingMode.HALF_UP);
        }
        result.mc2PerDay = mc2.mc2PerDay;
        result.mc2PercentHuman = (mc2.mc2PercentFraction * 100).setScale(2, RoundingMode.HALF_UP);
        result.corridorSegment = getCorridorSegment(mc2.mc2PercentFraction, pcts);

        result.currencyRateApplied = rateToEur != null ? rateToEur : 1;
        result.totalDailyCostEurEquivalent = (result.totalDailyCost * result.currencyRateApplied).setScale(2, RoundingMode.HALF_UP);
        result.mc2PerDayEurEquivalent = (result.mc2PerDay * result.currencyRateApplied).setScale(2, RoundingMode.HALF_UP);
        result.tjmEurEquivalent = result.tjmWeighted != null
            ? (result.tjmWeighted * result.currencyRateApplied).setScale(2, RoundingMode.HALF_UP)
            : null;

        return result;
    }

    private static Decimal ceilToInt(Decimal value) {
        return value.setScale(0, RoundingMode.CEILING);
    }
}