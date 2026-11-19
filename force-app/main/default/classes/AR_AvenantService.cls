/**
 * Avenant piloté par la matrice (session 180b, docs/180-avenant-depuis-la-matrice.md, décisions du
 * 14/10/2026 en §9bis qui remplacent les défauts proposés).
 *
 * Un avenant est une matrice `AR_Price_Matrix__c` de la chaîne (AR_Version_Type__c = 'Avenant') : même
 * moteur de calcul, même snapshot, même circuit de dérogation que toute version de négociation. Ce
 * service prépare l'écran (getAvenantContext) puis crée la matrice avenant et prend la décision
 * (createAvenant). Il ne génère PAS le document (session 180d) et ne touche jamais la matrice source.
 *
 * Règles retenues (§9bis) :
 *  - Q1    : dérogation si, et seulement si, la MC2 % de l'avenant est strictement inférieure à celle de la
 *            matrice amendée recalculée par le même moteur (au centième de point) ; sinon validation d'office.
 *            Le plancher du corridor n'entre plus en jeu. La règle vit dans UNE méthode,
 *            requiresHumanValidation ; AR_PricingMatrixService.validateInput la réapplique à la validation
 *            d'un avenant (le serveur fait foi, y compris pour un Brouillon validé depuis l'écran).
 *  - Q2 B  : frais ponctuels et jours de gratuité REPRIS de la source et réamortis sur la période de
 *            l'avenant (le nombre de jours ouvrés de la matrice avenant est le diviseur du moteur).
 *  - Q3    : « TJM » des conditions financières = AR_Proposed_TJM__c (même champ que « Nouveau tarif »).
 *            La question 3 porte salaire annuel + frais ; pour un INDEP, le CJM d'achat
 *            (AR_CJM_Before_Markup__c) et le markup restent modifiables (non tranché par le client).
 *  - Q4 B  : toute combinaison de réponses (coût seul compris) donne une version « Avenant ».
 *  - Q8 A  : avenant d'avenant autorisé ; la PTF amendée est toujours la PTF initiale (jamais un avenant).
 *  - Q9 A  : motif(s) obligatoire(s), choisis dans la liste (la présélection est un sujet d'écran, 180c).
 *
 * `with sharing` : le BM ne peut amender qu'une matrice qu'il peut voir. Les écritures de champs
 * système (type d'avenant, PTF amendée, calculs) se font en SYSTEM_MODE, comme AR_MatrixChainService.
 */
public with sharing class AR_AvenantService {

    private static final Set<String> VALIDATED_STATUSES = new Set<String>{ 'Validée', 'Validée par dérogation' };
    private static final String TYPE_AVENANT = 'Avenant';
    private static final String CHANGE_TARIF = 'Tarif';
    private static final String CHANGE_PERIODE = 'Période';
    private static final String CHANGE_CONDITIONS = 'Conditions financières';
    private static final Set<String> SALARIED_CONTRACTS = new Set<String>{ 'CDI', 'CDD' };

    // ---------- DTO ----------

    public class PtfOption {
        @AuraEnabled public Id ptfId;
        @AuraEnabled public String reference;
        @AuraEnabled public Decimal versionNumber;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public Id matrixId;
    }

    public class AvenantContext {
        @AuraEnabled public Id sourceMatrixId;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String sourceStatus;
        @AuraEnabled public Boolean sourceIsAvenant;
        @AuraEnabled public Id amendedPtfId;
        @AuraEnabled public String amendedPtfReference;
        @AuraEnabled public List<PtfOption> ptfOptions;
        @AuraEnabled public String contractType;
        @AuraEnabled public String currencyCode;
        // Intrants de la source (sa propre unité : pourcentages en nombre, ex. 20 pour 20 %)
        @AuraEnabled public Decimal proposedTjm;
        @AuraEnabled public Decimal rfaPercent;
        // Salaire de départ de l'avenant : celui de la dernière période de salaire de la source (période 1 sans période).
        @AuraEnabled public Decimal annualSalary;
        // Salaire de la période 1 de la source : base de son CJM pondéré (« avant » de l'impact) et de sa taxe OFII.
        @AuraEnabled public Decimal sourceAnnualSalary;
        @AuraEnabled public Decimal cjmBeforeMarkup;
        @AuraEnabled public Decimal markupApplied;
        @AuraEnabled public Decimal feeIk;
        @AuraEnabled public Decimal feeMeals;
        @AuraEnabled public Decimal feeLodging;
        @AuraEnabled public Decimal feeOmOther;
        @AuraEnabled public Decimal gratuityDays;
        @AuraEnabled public Decimal feeComputer;
        @AuraEnabled public Decimal feePhone;
        @AuraEnabled public Decimal feeTraining;
        @AuraEnabled public Decimal feeEpi;
        @AuraEnabled public Decimal feeOfiiTax;
        @AuraEnabled public Decimal feeOther;
        // Seuils figés de la source (grand compte compris) et MC2 stockée, pour mémoire
        @AuraEnabled public Decimal floorPercentApplied;
        @AuraEnabled public Decimal targetPercentApplied;
        @AuraEnabled public Decimal idealPercentApplied;
        @AuraEnabled public Decimal storedMc2Percent;
        // Durée (jours ouvrés) sur laquelle la source amortit ses frais ponctuels : base du « avant » de l'impact
        @AuraEnabled public Decimal sourceNumberOfDays;
        @AuraEnabled public Decimal feeMonthlyOther;
        // Pays de l'entité PTF de la source : calendrier ouvré du comptage des jours (jours fériés France)
        @AuraEnabled public String entityCountry;
        // Dates : début de la mission d'origine, fin actuelle, et date d'effet proposée pour une prolongation
        @AuraEnabled public Date missionStartDate;
        @AuraEnabled public Date currentEndDate;
        @AuraEnabled public Date defaultExtensionEffectiveDate;
        // Taxe OFII calculée (Paramètres généraux) : taux en % du salaire mensuel brut, plafond en euros.
        // Null = calcul indisponible ; l'avenant ne recalcule alors rien.
        @AuraEnabled public Decimal ofiiTaxRate;
        @AuraEnabled public Decimal ofiiTaxCapEur;
    }

    public class AvenantInput {
        public Id sourceMatrixId;
        public Id amendedPtfId; // facultatif : repli sur la PTF proposée par getAvenantContext
        public Boolean tarif;
        public Boolean periode;
        public Boolean conditions;
        public Decimal newTjm;
        public Date effectiveDate;
        public Date newEndDate;
        // Question 3 : null = inchangé. Refusés si `conditions` n'est pas « Oui ».
        public Decimal annualSalary;
        public Decimal cjmBeforeMarkup;
        public Decimal markupApplied;
        public Decimal feeIk;
        public Decimal feeMeals;
        public Decimal feeLodging;
        public Decimal feeOmOther;
        public Decimal gratuityDays;
        public Decimal feeComputer;
        public Decimal feePhone;
        public Decimal feeTraining;
        public Decimal feeEpi;
        public Decimal feeOfiiTax;
        public Decimal feeOther;
        public List<Id> reasonIds;
        public String comment;
    }

    public class AvenantResult {
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String matrixName;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal mc2Percent;
        @AuraEnabled public Decimal mc2PerDay;
        @AuraEnabled public String corridorSegment;
        @AuraEnabled public Boolean derogationRequired;
    }

    // ---------- Règle de décision (une seule méthode, Q1) ----------

    /**
     * Vrai si l'avenant doit passer par un valideur humain : sa MC2 % est strictement inférieure à celle de
     * la matrice amendée (`before`, recalculée par le même moteur — jamais la valeur stockée, calculée avec
     * d'anciennes règles), comparées au centième de point. Un résultat manquant est traité comme une baisse
     * (repli fermé : on ne valide pas d'office ce qu'on n'a pas pu mesurer). createAvenant, validateInput et
     * l'écran ne connaissent pas la règle : ils passent par ici.
     */
    public static Boolean requiresHumanValidation(AR_PricingResult before, AR_PricingResult after) {
        if (before == null || after == null || before.mc2PercentHuman == null || after.mc2PercentHuman == null) {
            return true;
        }
        return after.mc2PercentHuman.setScale(2, RoundingMode.HALF_UP)
            < before.mc2PercentHuman.setScale(2, RoundingMode.HALF_UP);
    }

    public static Boolean isAvenant(Id matrixId) {
        if (matrixId == null) {
            return false;
        }
        List<AR_Price_Matrix__c> rows = [SELECT AR_Version_Type__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
        return !rows.isEmpty() && rows[0].AR_Version_Type__c == TYPE_AVENANT;
    }

    /**
     * Matrice amendée (version précédente de l'avenant) recalculée par le pipeline complet, sans rien écrire :
     * mêmes réglages que le calcul de l'avenant, donc aucune baisse fictive quand un réglage a changé depuis
     * la validation de la source. Elle garde sa propre durée (jours ouvrés) : réduire la période renchérit
     * donc ses frais ponctuels par jour, ce que l'avenant doit refléter.
     */
    public static AR_PricingResult baselineResult(Id avenantId) {
        List<AR_Price_Matrix__c> rows = [
            SELECT AR_Previous_Version__c, AR_Position__c FROM AR_Price_Matrix__c WHERE Id = :avenantId LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].AR_Previous_Version__c == null) {
            throw newAuraException(Label.AR_Msg_AVN_NoAmendedMatrix);
        }
        AR_Price_Matrix__c base = AR_MatrixChainService.buildCopy(
            AR_MatrixChainService.loadSource(rows[0].AR_Previous_Version__c), rows[0].AR_Position__c, false, null
        );
        return AR_PricingMatrixService.evaluateWithoutSaving(base);
    }

    /** MC2 % de la matrice amendée, pour l'écran d'un avenant en Brouillon (bouton Valider ou dérogation). */
    public static Decimal baselineMc2Percent(Id avenantId) {
        return baselineResult(avenantId).mc2PercentHuman;
    }

    // ---------- Préparation de l'écran ----------

    @AuraEnabled(cacheable=false)
    public static AvenantContext getAvenantContext(Id matrixId) {
        try {
            AR_Price_Matrix__c source = requireSource(matrixId);
            List<PtfOption> options = eligiblePtfs(chainRootId(source));
            PtfOption amended = defaultAmendedPtf(source, options);
            if (amended == null) {
                throw newAuraException(
                    Label.AR_Msg_AVN_NothingToAmend
                );
            }

            AvenantContext ctx = new AvenantContext();
            ctx.sourceMatrixId = source.Id;
            ctx.sourceName = source.Name;
            ctx.sourceStatus = source.AR_Status__c;
            ctx.sourceIsAvenant = source.AR_Version_Type__c == TYPE_AVENANT;
            ctx.amendedPtfId = amended.ptfId;
            ctx.amendedPtfReference = amended.reference;
            ctx.ptfOptions = options;
            ctx.contractType = source.AR_Contract_Type__c;
            ctx.currencyCode = source.AR_Currency__c;
            ctx.proposedTjm = source.AR_Proposed_TJM__c;
            ctx.rfaPercent = source.AR_RFA_Percent__c;
            ctx.annualSalary = currentSalary(source);
            ctx.sourceAnnualSalary = source.AR_Annual_Salary__c;
            ctx.cjmBeforeMarkup = source.AR_CJM_Before_Markup__c;
            ctx.markupApplied = source.AR_Markup_Applied__c;
            ctx.feeIk = source.AR_Fee_IK__c;
            ctx.feeMeals = source.AR_Fee_Meals__c;
            ctx.feeLodging = source.AR_Fee_Lodging__c;
            ctx.feeOmOther = source.AR_Fee_OM_Other__c;
            ctx.gratuityDays = source.AR_Gratuity_Days__c;
            ctx.feeComputer = source.AR_Fee_Computer__c;
            ctx.feePhone = source.AR_Fee_Phone__c;
            ctx.feeMonthlyOther = source.AR_Fee_Monthly_Other__c;
            ctx.feeTraining = source.AR_Fee_Training__c;
            ctx.feeEpi = source.AR_Fee_EPI__c;
            ctx.feeOfiiTax = source.AR_Fee_OFII_Tax__c;
            ctx.feeOther = source.AR_Fee_Other__c;
            ctx.floorPercentApplied = source.AR_Floor_Percent_Applied__c;
            ctx.targetPercentApplied = source.AR_Target_Percent_Applied__c;
            ctx.idealPercentApplied = source.AR_Ideal_Percent_Applied__c;
            ctx.storedMc2Percent = source.AR_MC2_Percent__c;
            // Jours facturables de la source (congés retranchés) : diviseur de ses frais ponctuels.
            ctx.sourceNumberOfDays = AR_PricingMatrixService.billableDaysOf(source);
            ctx.entityCountry = source.AR_Entity_Ref__r == null ? null : source.AR_Entity_Ref__r.AR_Country__c;
            ctx.missionStartDate = missionStart(source, amended);
            ctx.currentEndDate = source.AR_End_Date__c;
            ctx.defaultExtensionEffectiveDate = source.AR_End_Date__c != null ? source.AR_End_Date__c.addDays(1) : null;
            List<AR_General_Setting__c> settings = [
                SELECT AR_Ofii_Tax_Rate__c, AR_Ofii_Tax_Cap__c FROM AR_General_Setting__c LIMIT 1
            ];
            if (!settings.isEmpty()) {
                ctx.ofiiTaxRate = settings[0].AR_Ofii_Tax_Rate__c;
                ctx.ofiiTaxCapEur = settings[0].AR_Ofii_Tax_Cap__c;
            }
            return ctx;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_AVN_PrepareAction);
        }
    }

    // ---------- Création + décision ----------

    /** Façade Aura : String JSON (les wrappers Apex en paramètre ne sont pas alimentés, cf. CLAUDE.md). */
    @AuraEnabled
    public static AvenantResult createAvenant(String inputJson) {
        try {
            if (String.isBlank(inputJson)) {
                throw newAuraException(Label.AR_Msg_AVN_EmptyRequest);
            }
            return createAvenantInput((AvenantInput) JSON.deserialize(inputJson, AvenantInput.class));
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_AVN_CreateAction);
        }
    }

    public static AvenantResult createAvenantInput(AvenantInput input) {
        if (input == null || input.sourceMatrixId == null) {
            throw newAuraException(Label.AR_Msg_AVN_SourceMissing);
        }
        Boolean tarif = input.tarif == true;
        Boolean periode = input.periode == true;
        Boolean conditions = input.conditions == true;
        if (!tarif && !periode && !conditions) {
            throw newAuraException(Label.AR_Msg_AVN_AnswerYesToOne);
        }
        if (input.reasonIds == null || input.reasonIds.isEmpty()) {
            throw newAuraException(Label.AR_Msg_AVN_ReasonRequired);
        }

        AR_Price_Matrix__c source = requireSource(input.sourceMatrixId);
        List<PtfOption> options = eligiblePtfs(chainRootId(source));
        PtfOption amended = resolveAmendedPtf(source, options, input.amendedPtfId);
        Date missionStart = missionStart(source, amended);

        validateAnswers(input, source, tarif, periode, conditions);

        // Période de l'avenant : date d'effet → fin (nouvelle ou actuelle)
        Date originEnd = source.AR_End_Date__c;
        Date finalEnd = periode ? input.newEndDate : originEnd;
        if (finalEnd == null) {
            throw newAuraException(Label.AR_Msg_AVN_SourceNoEndDate);
        }
        Date effective = input.effectiveDate;
        if (effective == null && periode && !tarif && !conditions && originEnd != null) {
            effective = originEnd.addDays(1); // prolongation seule : le lendemain de la fin actuelle
        }
        if (effective == null) {
            throw newAuraException(Label.AR_Msg_AVN_EffectiveDateRequired);
        }
        if (periode && finalEnd <= effective) {
            throw newAuraException(Label.AR_Msg_AVN_EndAfterEffective);
        }
        if (missionStart != null && effective < missionStart) {
            throw newAuraException(Label.AR_AVN_EffectiveBeforeMissionStart);
        }
        if (effective > finalEnd) {
            throw newAuraException(Label.AR_AVN_EffectiveOutsideMission);
        }
        Integer days = countBusinessDays(
            effective, finalEnd, source.AR_Entity_Ref__r == null ? null : source.AR_Entity_Ref__r.AR_Country__c
        );
        if (days <= 0) {
            throw newAuraException(Label.AR_AVN_NoWorkingDay);
        }

        // Liste de champs de la copie = celle de duplicateMatrix (un seul endroit : AR_MatrixChainService.loadSource).
        AR_Price_Matrix__c copy = AR_MatrixChainService.buildCopy(
            AR_MatrixChainService.loadSource(source.Id), source.AR_Position__c, true, input.comment
        );
        copy.AR_Version_Type__c = TYPE_AVENANT;
        copy.AR_Amended_PTF__c = amended.ptfId;
        copy.AR_Avenant_Changes__c = changesValue(tarif, periode, conditions);
        copy.AR_Start_Date__c = effective;
        copy.AR_End_Date__c = finalEnd;
        // Régie sans régule : mode et base repris, plan reconstruit par l'enregistrement sur la période de l'avenant.
        copy.AR_RPLSR_Plan__c = null;
        copy.AR_RPLSR_Days_Sold__c = null;
        copy.AR_RPLSR_Days_Produced__c = null;
        copy.AR_Number_Of_Days__c = days; // diviseur des frais ponctuels (Q2 B : réamortis sur la période)
        // Les congés prévus de la mission d'origine ne valent pas pour la période de l'avenant.
        copy.AR_Planned_Leave_Days__c = null;
        // Idem pour les périodes de salaire : comptées depuis le début de la mission d'origine. Au moment de
        // l'avenant, le consultant est payé au salaire de la dernière période : c'est le salaire de l'avenant.
        copy.AR_Annual_Salary__c = currentSalary(source);
        copy.AR_Salary_Periods__c = null;
        if (tarif) {
            copy.AR_Proposed_TJM__c = input.newTjm;
            // Un seul prix à partir de la date d'effet : l'évolution restante est remplacée (docs/254 §6).
            copy.AR_TJM_Periods__c = null;
        }
        if (conditions) {
            applyCostOverrides(copy, input);
        }
        Database.insert(copy, AccessLevel.SYSTEM_MODE);
        AR_ReasonService.insertSelections(copy.Id, null, input.reasonIds);

        // Même chemin que l'écran : enregistrement (le serveur recalcule tout), puis la règle de décision.
        AR_PricingMatrixService.MatrixInput matrixInput = AR_PricingMatrixService.loadMatrixInput(copy.Id, false);
        AR_PricingMatrixService.MatrixSaveResult saved = AR_PricingMatrixService.saveDraftInput(matrixInput);
        AR_PricingResult before = baselineResult(saved.matrixId);
        // Session 237 : une MC2/jour au montant de dispense se valide sans dérogation, même si la MC2 % baisse.
        Boolean derogationRequired = requiresHumanValidation(before, saved.calculation)
            && !AR_PricingMatrixService.isDispensedFromDerogation(saved.calculation);
        if (!derogationRequired) {
            saved = AR_PricingMatrixService.validateInput(matrixInput, before);
        }

        AvenantResult result = new AvenantResult();
        result.matrixId = saved.matrixId;
        result.matrixName = [SELECT Name FROM AR_Price_Matrix__c WHERE Id = :saved.matrixId LIMIT 1].Name;
        result.status = saved.status;
        result.mc2Percent = saved.calculation.mc2PercentHuman;
        result.mc2PerDay = saved.calculation.mc2PerDay;
        result.corridorSegment = saved.calculation.corridorSegment;
        result.derogationRequired = derogationRequired;
        return result;
    }

    // ---------- Validation des réponses ----------

    private static void validateAnswers(
        AvenantInput input, AR_Price_Matrix__c source, Boolean tarif, Boolean periode, Boolean conditions
    ) {
        if (tarif && (input.newTjm == null || input.newTjm <= 0)) {
            throw newAuraException(Label.AR_Msg_AVN_NewRateRequired);
        }
        if (!tarif && input.newTjm != null) {
            throw newAuraException(Label.AR_Msg_AVN_RateGivenButNo);
        }
        if (periode && input.newEndDate == null) {
            throw newAuraException(Label.AR_Msg_AVN_EndDateRequired);
        }
        if (!periode && input.newEndDate != null) {
            throw newAuraException(Label.AR_Msg_AVN_EndGivenButNo);
        }
        Boolean anyCost = hasCostOverride(input);
        if (!conditions && anyCost) {
            throw newAuraException(Label.AR_Msg_AVN_TermsGivenButNo);
        }
        String contract = source.AR_Contract_Type__c;
        if (input.annualSalary != null && !SALARIED_CONTRACTS.contains(contract)) {
            throw newAuraException(AR_I18n.format(Label.AR_Msg_AVN_SalaryOnlySalaried, new List<Object>{ contract }));
        }
        if ((input.cjmBeforeMarkup != null || input.markupApplied != null) && contract != 'INDEP') {
            throw newAuraException(AR_I18n.format(Label.AR_Msg_AVN_PurchaseRateOnlyFreelance, new List<Object>{ contract }));
        }
    }

    /**
     * Salaire en cours à la fin de la source : celui de la dernière période de salaire renseignée (CDI/CDD),
     * sinon le salaire annuel (période 1). Les autres statuts ignorent les périodes, comme le moteur.
     */
    @TestVisible
    private static Decimal currentSalary(AR_Price_Matrix__c source) {
        Decimal salary = source.AR_Annual_Salary__c;
        if (!SALARIED_CONTRACTS.contains(source.AR_Contract_Type__c)) {
            return salary;
        }
        for (AR_PricingCalculator.SalaryPeriod p : AR_PricingMatrixService.parseSalaryPeriods(source.AR_Salary_Periods__c)) {
            if (p.salary != null) {
                salary = p.salary;
            }
        }
        return salary;
    }

    private static Boolean hasCostOverride(AvenantInput i) {
        return i.annualSalary != null || i.cjmBeforeMarkup != null || i.markupApplied != null
            || i.feeIk != null || i.feeMeals != null || i.feeLodging != null || i.feeOmOther != null
            || i.gratuityDays != null || i.feeComputer != null || i.feePhone != null || i.feeTraining != null
            || i.feeEpi != null || i.feeOfiiTax != null || i.feeOther != null;
    }

    private static void applyCostOverrides(AR_Price_Matrix__c copy, AvenantInput i) {
        if (i.annualSalary != null) { copy.AR_Annual_Salary__c = i.annualSalary; }
        if (i.cjmBeforeMarkup != null) { copy.AR_CJM_Before_Markup__c = i.cjmBeforeMarkup; }
        if (i.markupApplied != null) { copy.AR_Markup_Applied__c = i.markupApplied; }
        if (i.feeIk != null) { copy.AR_Fee_IK__c = i.feeIk; }
        if (i.feeMeals != null) { copy.AR_Fee_Meals__c = i.feeMeals; }
        if (i.feeLodging != null) { copy.AR_Fee_Lodging__c = i.feeLodging; }
        if (i.feeOmOther != null) { copy.AR_Fee_OM_Other__c = i.feeOmOther; }
        if (i.gratuityDays != null) { copy.AR_Gratuity_Days__c = i.gratuityDays; }
        if (i.feeComputer != null) { copy.AR_Fee_Computer__c = i.feeComputer; }
        if (i.feePhone != null) { copy.AR_Fee_Phone__c = i.feePhone; }
        if (i.feeTraining != null) { copy.AR_Fee_Training__c = i.feeTraining; }
        if (i.feeEpi != null) { copy.AR_Fee_EPI__c = i.feeEpi; }
        if (i.feeOfiiTax != null) { copy.AR_Fee_OFII_Tax__c = i.feeOfiiTax; }
        if (i.feeOther != null) { copy.AR_Fee_Other__c = i.feeOther; }
    }

    private static String changesValue(Boolean tarif, Boolean periode, Boolean conditions) {
        List<String> values = new List<String>();
        if (tarif) { values.add(CHANGE_TARIF); }
        if (periode) { values.add(CHANGE_PERIODE); }
        if (conditions) { values.add(CHANGE_CONDITIONS); }
        return String.join(values, ';');
    }

    // ---------- Source, chaîne, PTF ----------

    private static AR_Price_Matrix__c requireSource(Id matrixId) {
        AR_Price_Matrix__c source;
        try {
            source = [
                SELECT Id, Name, AR_Status__c, AR_Root_Matrix__c, AR_Version_Type__c, AR_Amended_PTF__c,
                    AR_Start_Date__c, AR_End_Date__c, AR_Position__c, AR_Contract_Type__c, AR_Currency__c,
                    AR_Proposed_TJM__c, AR_RFA_Percent__c, AR_Annual_Salary__c, AR_CJM_Before_Markup__c,
                    AR_Markup_Applied__c, AR_Fee_IK__c, AR_Fee_Meals__c, AR_Fee_Lodging__c, AR_Fee_OM_Other__c,
                    AR_Gratuity_Days__c, AR_Fee_Computer__c, AR_Fee_Phone__c, AR_Fee_Training__c, AR_Fee_EPI__c,
                    AR_Fee_OFII_Tax__c, AR_Fee_Other__c, AR_Floor_Percent_Applied__c, AR_Target_Percent_Applied__c,
                    AR_Ideal_Percent_Applied__c, AR_MC2_Percent__c, AR_Number_Of_Days__c,
                    AR_Fee_Monthly_Other__c, AR_Planned_Leave_Days__c, AR_Salary_Periods__c,
                    AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
                    AR_Entity_Ref__r.AR_Country__c
                FROM AR_Price_Matrix__c
                WHERE Id = :matrixId
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw newAuraException(Label.AR_Msg_AVN_MatrixNotAccessible);
        }
        if (!VALIDATED_STATUSES.contains(source.AR_Status__c)) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_AVN_OnlyValidatedAmendable, new List<Object>{ source.AR_Status__c })
            );
        }
        return source;
    }

    private static Id chainRootId(AR_Price_Matrix__c source) {
        return source.AR_Root_Matrix__c != null ? source.AR_Root_Matrix__c : source.Id;
    }

    /** PTF générées (type PTF, jamais un avenant) de la chaîne, la plus récente d'abord. */
    private static List<PtfOption> eligiblePtfs(Id rootId) {
        List<PtfOption> options = new List<PtfOption>();
        for (AR_PTF_Document__c d : [
            SELECT Id, AR_Reference__c, AR_Version_Number__c, AR_Generated_At__c, AR_Price_Matrix__c
            FROM AR_PTF_Document__c
            WHERE AR_Generation_Status__c = 'Généré'
              AND (AR_Document_Type__c = 'PTF' OR AR_Document_Type__c = null)
              AND (AR_Price_Matrix__c = :rootId OR AR_Price_Matrix__r.AR_Root_Matrix__c = :rootId)
            ORDER BY AR_Generated_At__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            PtfOption o = new PtfOption();
            o.ptfId = d.Id;
            o.reference = d.AR_Reference__c;
            o.versionNumber = d.AR_Version_Number__c;
            o.generatedAt = d.AR_Generated_At__c;
            o.matrixId = d.AR_Price_Matrix__c;
            options.add(o);
        }
        return options;
    }

    /** Source avenant → la PTF qu'elle amende (Q8) ; sinon la plus récente de la chaîne. */
    private static PtfOption defaultAmendedPtf(AR_Price_Matrix__c source, List<PtfOption> options) {
        if (source.AR_Amended_PTF__c != null) {
            for (PtfOption o : options) {
                if (o.ptfId == source.AR_Amended_PTF__c) {
                    return o;
                }
            }
        }
        return options.isEmpty() ? null : options[0];
    }

    private static PtfOption resolveAmendedPtf(AR_Price_Matrix__c source, List<PtfOption> options, Id requested) {
        if (requested == null) {
            PtfOption fallback = defaultAmendedPtf(source, options);
            if (fallback == null) {
                throw newAuraException(
                    Label.AR_Msg_AVN_NothingToAmend
                );
            }
            return fallback;
        }
        for (PtfOption o : options) {
            if (o.ptfId == requested) {
                return o;
            }
        }
        throw newAuraException(Label.AR_Msg_AVN_PtfNotInChain);
    }

    /** Début de la mission d'origine : début de la matrice de la PTF amendée, repli sur la source. */
    private static Date missionStart(AR_Price_Matrix__c source, PtfOption amended) {
        if (amended != null && amended.matrixId != null) {
            List<AR_Price_Matrix__c> rows = [SELECT AR_Start_Date__c FROM AR_Price_Matrix__c WHERE Id = :amended.matrixId LIMIT 1];
            if (!rows.isEmpty() && rows[0].AR_Start_Date__c != null) {
                return rows[0].AR_Start_Date__c;
            }
        }
        return source.AR_Start_Date__c;
    }

    // ---------- Jours ouvrés ----------

    /**
     * Jours ouvrés, bornes incluses : calendrier unique AR_WorkingCalendar (week-ends + jours fériés France
     * selon le pays de l'entité PTF), miroir de c/arWorkingCalendar. Sans pays : week-ends seuls.
     */
    public static Integer countBusinessDays(Date startDate, Date endDate, String country) {
        return AR_WorkingCalendar.workingDays(startDate, endDate, country);
    }

    public static Integer countBusinessDays(Date startDate, Date endDate) {
        return countBusinessDays(startDate, endDate, null);
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}