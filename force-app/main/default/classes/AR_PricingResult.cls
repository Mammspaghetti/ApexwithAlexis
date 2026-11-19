/**
 * Résultat de calcul de pricing, sérialisable — consommé par AR_PricingMatrixService,
 * le LWC arPriceMatrixSimulator (session 4) et le snapshot JSON (AR_MatrixVersionService).
 * Convention Percent : mc2PercentHuman porte la valeur humaine (23.5 = 23,5 %), pas la fraction —
 * cf. docs/02-modele-de-donnees.md §7.2.
 */
public class AR_PricingResult {
    @AuraEnabled public Decimal cjm;
    @AuraEnabled public Decimal markupCalcule;
    @AuraEnabled public Boolean markupMismatch;
    @AuraEnabled public Decimal feeOmPerDay;
    @AuraEnabled public Decimal feePonctuelsPerDay;
    @AuraEnabled public Decimal totalDailyCost;
    @AuraEnabled public Decimal tjmFloor;
    @AuraEnabled public Decimal tjmTarget;
    @AuraEnabled public Decimal tjmIdeal;
    @AuraEnabled public Decimal tjmTop10;
    @AuraEnabled public Decimal mc2PerDay;
    @AuraEnabled public Decimal mc2PercentHuman;
    @AuraEnabled public String corridorSegment;
    // Pourcentages de corridor réellement appliqués à ce calcul (grand compte ou défaut, cf.
    // AR_PricingCalculator.compute) — figés ici pour qu'une matrice décidée puisse réafficher le
    // même corridor même si AR_Account_Corridor__c change ensuite (session 23b).
    @AuraEnabled public Decimal floorPercentApplied;
    @AuraEnabled public Decimal targetPercentApplied;
    @AuraEnabled public Decimal idealPercentApplied;
    // Session 252 : origine des seuils figés (ACCOUNT, ENTITY ou DEFAULT), cf. AR_PricingMatrixService.CorridorResolution.
    @AuraEnabled public String corridorSource;
    @AuraEnabled public String corridorEntityName;
    // Coefficient CDI/CDD (AR_General_Setting__c) effectivement appliqué au calcul du CJM, figé au
    // même titre que les *_Applied ci-dessus (session 28). Null pour INDEP/VIE/NEARSHORE.
    @AuraEnabled public Decimal contractCoefficientApplied;
    // Jours travaillés/an effectivement appliqués (cascade entité → AR_General_Setting__c →
    // AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT, session 48), figés au même titre que
    // contractCoefficientApplied — jamais null, tous les statuts de contrat en dépendent.
    @AuraEnabled public Decimal workingDaysPerYearApplied;
    // Socle multi-devises (session 24) : taux vers EUR effectivement utilisé (1 pour une matrice
    // EUR) et équivalents pivot EUR des montants natifs — jamais réinjectés dans le calcul
    // lui-même (qui reste intégralement dans la devise de la matrice), seulement pour la
    // comparaison/consolidation traitée en session 24b. Figés au même titre que les *_Applied
    // ci-dessus, cf. AR_CurrencyRateService.
    @AuraEnabled public Decimal currencyRateApplied;
    @AuraEnabled public Decimal tjmEurEquivalent;
    @AuraEnabled public Decimal totalDailyCostEurEquivalent;
    @AuraEnabled public Decimal mc2PerDayEurEquivalent;
    // Session 121 : divisor des frais ponctuels (jours de mission ou repli sur jours/an) et sa source.
    @AuraEnabled public Decimal feePonctuelsDivisorDays;
    @AuraEnabled public String feePonctuelsDivisorSource; // 'mission' | 'year_fallback'
    // Détail par poste des frais ramenés au jour (CDI/CDD/VIE, postes non nuls seulement) : consommé
    // tel quel par le récapitulatif des coûts, jamais recalculé côté affichage.
    @AuraEnabled public List<FeeLine> feeBreakdown;
    // Périodes de frais OM (docs/239) : la période 1 puis les périodes ajoutées, vide sans période.
    // feeOmPerDay porte la moyenne lissée sur ces périodes ; les deux indicateurs alimentent les
    // messages de l'écran et le garde de validation.
    @AuraEnabled public List<FeeOmPeriod> feeOmPeriods = new List<FeeOmPeriod>();
    @AuraEnabled public Boolean feePeriodsExceedMission = false;
    @AuraEnabled public Boolean feePeriodsMissionUnknown = false;
    // TJM moyen pondéré (docs/254) : égal à proposedTjm sans période ; nul si TJM non saisi.
    @AuraEnabled public Decimal tjmWeighted;
    @AuraEnabled public List<TjmPeriod> tjmPeriods = new List<TjmPeriod>();
    @AuraEnabled public Boolean tjmPeriodsExceedMission = false;
    @AuraEnabled public Boolean tjmPeriodsMissionUnknown = false;
    // Périodes de salaire (CDI/CDD) : vide sans période ; cjm porte alors le CJM pondéré.
    @AuraEnabled public List<SalaryPeriod> salaryPeriods = new List<SalaryPeriod>();
    @AuraEnabled public Boolean salaryPeriodsExceedMission = false;
    @AuraEnabled public Boolean salaryPeriodsMissionUnknown = false;
    // Régie sans régule (docs/265 §4.4) : tous nuls quand le mode est éteint. totalDailyCost garde son sens (coût unitaire).
    @AuraEnabled public Decimal rplsrRatio;
    @AuraEnabled public Decimal totalDailyCostPiloted;
    @AuraEnabled public Decimal mc2PerDayTheoretical;
    @AuraEnabled public Decimal mc2PercentTheoretical;

    /**
     * Un poste de frais : montant saisi, unité de saisie, diviseur appliqué et valeur par jour.
     * unit : 'day' (déjà par jour, diviseur 1) | 'month' (× 12 puis ÷ diviseur) | 'mission' (÷ diviseur,
     * jours de mission ou repli sur jours travaillés/an) | 'year' (÷ jours travaillés/an).
     * divisorSource : 'mission' | 'working_days' (jours travaillés/an, y compris en repli) | null pour 'day'.
     */
    public class FeeLine {
        @AuraEnabled public String key;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal divisor;
        @AuraEnabled public String divisorSource;
        @AuraEnabled public Decimal perDay;
    }

    /**
     * Une période de frais OM : index (1 = période 1 issue des champs de la matrice), jours retenus
     * (null pour la période 1 quand la durée de mission est inconnue) et frais OM par jour.
     */
    public class FeeOmPeriod {
        @AuraEnabled public Integer index;
        @AuraEnabled public Decimal days;
        @AuraEnabled public Decimal perDay;
    }

    /**
     * Une période de TJM : index (1 = période 1, le TJM saisi), jours retenus (null pour la période 1 à
     * durée inconnue) et TJM de la période. Liste vide quand il n'y a aucune période ajoutée.
     */
    public class TjmPeriod {
        @AuraEnabled public Integer index;
        @AuraEnabled public Decimal days;
        @AuraEnabled public Decimal tjm;
    }

    /** Une période de salaire : index (1 = salaire annuel de la matrice), jours retenus, salaire et CJM. */
    public class SalaryPeriod {
        @AuraEnabled public Integer index;
        @AuraEnabled public Decimal days;
        @AuraEnabled public Decimal salary;
        @AuraEnabled public Decimal cjm;
    }
}