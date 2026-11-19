/**
 * Costs of sales par poste (9 postes), en montant par jour, pour le tableau de bord (session 285).
 *
 * Correspondance des champs AR_Fee_* vers les 8 postes du plan (docs/283) — tout est calculé par les
 * fonctions du moteur (AR_PricingCalculator), rien n'est recalculé ici :
 *   lodging   Logement                   AR_Fee_Lodging__c (frais OM, €/jour, lissé sur les périodes de frais)
 *   fuel      Carburant (IK)             AR_Fee_IK__c (frais OM, €/jour, lissé sur les périodes de frais)
 *   meals     Repas                      AR_Fee_Meals__c (frais OM, €/jour, lissé sur les périodes de frais)
 *   epi       EPI                        AR_Fee_EPI__c (par mission ÷ jours facturables, repli jours travaillés/an)
 *   it_phone  Informatique & téléphone   AR_Fee_Computer__c (par jour) + AR_Fee_Phone__c (par mois × 12 ÷ jours travaillés/an)
 *   training  Formation                  AR_Fee_Training__c (par mission ÷ jours facturables)
 *   ofii      Taxe OFII                  AR_Fee_OFII_Tax__c (par an ÷ jours travaillés/an)
 *   gratuity  Jours offerts              AR_Gratuity_Days__c × CJM ÷ jours facturables (calcGratuityPerDay, même formule que le moteur)
 *   other     Autres                     champs de frais nommés uniquement : AR_Fee_OM_Other__c (OM, lissé) + AR_Fee_Monthly_Other__c
 *                                        (par mois × 12 ÷ jours travaillés/an) + AR_Fee_Other__c (par mission ÷ jours facturables)
 * Les frais ne comptent que pour CDI / CDD / VIE (le moteur les ignore pour INDEP et NEARSHORE, dont seule la
 * gratuité entre dans le coût, en « Jours offerts »). Le CJM (salaire, indemnité, tarif prestataire) n'est pas un poste. Les postes
 * sont exprimés dans la devise de la matrice ; l'appelant applique AR_Currency_Rate_Applied__c.
 * La somme des 9 postes = coût journalier total − CJM (vérifié par test).
 */
public with sharing class AR_DashboardCosts {
    public static final String LODGING = 'lodging';
    public static final String FUEL = 'fuel';
    public static final String MEALS = 'meals';
    public static final String EPI = 'epi';
    public static final String IT_PHONE = 'it_phone';
    public static final String TRAINING = 'training';
    public static final String OFII = 'ofii';
    public static final String GRATUITY = 'gratuity';
    public static final String OTHER = 'other';

    public static final List<String> POSTS = new List<String>{ LODGING, FUEL, MEALS, EPI, IT_PHONE, TRAINING, OFII, GRATUITY, OTHER };

    /** Matrices avec tous les champs que le moteur lit pour ramener les frais au jour. */
    public static Map<Id, AR_Price_Matrix__c> loadForCosts(Set<Id> matrixIds) {
        return new Map<Id, AR_Price_Matrix__c>([
            SELECT Id, AR_Contract_Type__c, AR_Annual_Salary__c, AR_CJM_Before_Markup__c, AR_Markup_Applied__c,
                   AR_CJM_VIE__c, AR_CJM_Nearshore__c, AR_Fee_IK__c, AR_Fee_Meals__c, AR_Fee_Lodging__c,
                   AR_Fee_OM_Other__c, AR_Fee_Periods__c, AR_TJM_Periods__c, AR_Salary_Periods__c,
                   AR_Gratuity_Days__c, AR_Fee_Computer__c, AR_Fee_Phone__c, AR_Fee_Monthly_Other__c,
                   AR_Fee_Training__c, AR_Fee_EPI__c, AR_Fee_OFII_Tax__c, AR_Fee_Other__c,
                   AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c,
                   AR_RPLSR_Days_Produced__c, AR_Working_Days_Applied__c, AR_Contract_Coefficient_Applied__c,
                   AR_Currency_Rate_Applied__c
            FROM AR_Price_Matrix__c
            WHERE Id IN :matrixIds
        ]);
    }

    /** Taux vers l'EUR figé sur la matrice ; 1 pour une matrice antérieure à la multi-devise. */
    public static Decimal rateToEur(AR_Price_Matrix__c m) {
        return m.AR_Currency_Rate_Applied__c != null && m.AR_Currency_Rate_Applied__c > 0 ? m.AR_Currency_Rate_Applied__c : 1;
    }

    /** Jours de mission qui pondèrent la matrice (jours facturables du moteur) ; 0 si la durée est inconnue. */
    public static Decimal weightDays(AR_Price_Matrix__c m) {
        return AR_PricingMatrixService.billableDaysOf(m);
    }

    /** Les 9 postes en montant par jour, devise de la matrice. */
    public static Map<String, Decimal> postsPerDay(AR_Price_Matrix__c m) {
        AR_PricingCalculator.Context ctx = AR_PricingMatrixService.costContextOf(m);
        Map<String, Decimal> byPost = new Map<String, Decimal>();
        for (String post : POSTS) {
            byPost.put(post, 0);
        }
        Decimal cjm = AR_PricingCalculator.calcCJM(ctx);
        Decimal total = AR_PricingCalculator.calcTotalDailyCost(ctx);
        Boolean salariedFees = ctx.contractType == 'CDI' || ctx.contractType == 'CDD' || ctx.contractType == 'VIE';
        if (!salariedFees) {
            byPost.put(GRATUITY, AR_PricingCalculator.calcGratuityPerDay(ctx, cjm));
            return byPost;
        }

        byPost.put(LODGING, omComponentPerDay(ctx, 'lodging'));
        byPost.put(FUEL, omComponentPerDay(ctx, 'ik'));
        byPost.put(MEALS, omComponentPerDay(ctx, 'meals'));
        Decimal omOther = omComponentPerDay(ctx, 'other');

        Map<String, Decimal> breakdown = new Map<String, Decimal>();
        for (AR_PricingResult.FeeLine line : AR_PricingCalculator.calcFeeBreakdown(ctx)) {
            breakdown.put(line.key, line.perDay);
        }
        byPost.put(IT_PHONE, perDayOf(breakdown, 'feeComputer') + perDayOf(breakdown, 'feePhone'));
        byPost.put(TRAINING, perDayOf(breakdown, 'feeTraining'));
        byPost.put(EPI, perDayOf(breakdown, 'feeEpi'));
        byPost.put(OFII, perDayOf(breakdown, 'feeOfiiTax'));

        byPost.put(GRATUITY, AR_PricingCalculator.calcGratuityPerDay(ctx, cjm));
        byPost.put(OTHER, omOther + perDayOf(breakdown, 'feeMonthlyOther') + perDayOf(breakdown, 'feeOther'));
        return byPost;
    }

    private static Decimal perDayOf(Map<String, Decimal> breakdown, String key) {
        return breakdown.containsKey(key) ? breakdown.get(key) : 0;
    }

    /**
     * Part d'un seul des quatre frais OM dans la moyenne lissée du moteur : le moteur est appelé avec un
     * contexte où seul ce composant reste non nul (le lissage est linéaire, la somme des quatre parts
     * redonne exactement calcFraisOMJourLisse).
     */
    private static Decimal omComponentPerDay(AR_PricingCalculator.Context ctx, String component) {
        AR_PricingCalculator.Context only = new AR_PricingCalculator.Context();
        only.contractType = ctx.contractType;
        only.missionDays = ctx.missionDays;
        only.plannedLeaveDays = ctx.plannedLeaveDays;
        only.rplsrRatio = ctx.rplsrRatio;
        pickComponent(only, ctx.feeIk, ctx.feeMeals, ctx.feeLodging, ctx.feeOmOther, component);
        if (ctx.feePeriods != null && !ctx.feePeriods.isEmpty()) {
            only.feePeriods = new List<AR_PricingCalculator.FeePeriod>();
            for (AR_PricingCalculator.FeePeriod p : ctx.feePeriods) {
                AR_PricingCalculator.FeePeriod kept = new AR_PricingCalculator.FeePeriod();
                kept.days = p.days;
                kept.feeIk = 0;
                kept.feeMeals = 0;
                kept.feeLodging = 0;
                kept.feeOmOther = 0;
                if (component == 'ik') {
                    kept.feeIk = p.feeIk;
                } else if (component == 'meals') {
                    kept.feeMeals = p.feeMeals;
                } else if (component == 'lodging') {
                    kept.feeLodging = p.feeLodging;
                } else {
                    kept.feeOmOther = p.feeOmOther;
                }
                only.feePeriods.add(kept);
            }
        }
        return AR_PricingCalculator.calcFraisOMJourLisse(only);
    }

    private static void pickComponent(
        AR_PricingCalculator.Context target, Decimal ik, Decimal meals, Decimal lodging, Decimal other, String component
    ) {
        target.feeIk = component == 'ik' ? ik : 0;
        target.feeMeals = component == 'meals' ? meals : 0;
        target.feeLodging = component == 'lodging' ? lodging : 0;
        target.feeOmOther = component == 'other' ? other : 0;
    }
}