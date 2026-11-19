import { LightningElement, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import {
  compute,
  calcBusinessDays,
  formatMoney,
  formatPercent,
  computeOfiiTax
} from "c/arPricingEngine";
import getAvenantContext from "@salesforce/apex/AR_AvenantService.getAvenantContext";
import createAvenantApex from "@salesforce/apex/AR_AvenantService.createAvenant";
import { generateAvenantDocument } from "c/arAvenantGeneration";
import getMatrixInput from "@salesforce/apex/AR_PricingMatrixService.getMatrixInput";
import getReasonOptions from "@salesforce/apex/AR_ReasonService.getReasonOptions";
import LBL_SEGMENT_BELOW_FLOOR from "@salesforce/label/c.AR_PMS_SegmentBelowFloor";
import LBL_SEGMENT_LOW_MARGIN from "@salesforce/label/c.AR_PMS_SegmentLowMargin";
import LBL_SEGMENT_RECOMMENDED from "@salesforce/label/c.AR_PMS_SegmentRecommended";
import LBL_SEGMENT_SUPERSTAR from "@salesforce/label/c.AR_PMS_SegmentSuperstar";
import { formatLabel } from "c/arI18n";
import LBL_AR_AVN_AmendedPtf from "@salesforce/label/c.AR_AVN_AmendedPtf";
import LBL_AR_AVN_AnnualSalary from "@salesforce/label/c.AR_AVN_AnnualSalary";
import LBL_AR_AVN_AnswerYesToSeeImpact from "@salesforce/label/c.AR_AVN_AnswerYesToSeeImpact";
import LBL_AR_AVN_AppliedMarkup from "@salesforce/label/c.AR_AVN_AppliedMarkup";
import LBL_AR_AVN_Avenant from "@salesforce/label/c.AR_AVN_Avenant";
import LBL_AR_AVN_ChooseAtLeastOneReason from "@salesforce/label/c.AR_AVN_ChooseAtLeastOneReason";
import LBL_AR_AVN_Computer from "@salesforce/label/c.AR_AVN_Computer";
import LBL_AR_AVN_CurrentEnd from "@salesforce/label/c.AR_AVN_CurrentEnd";
import LBL_AR_AVN_CurrentRate from "@salesforce/label/c.AR_AVN_CurrentRate";
import LBL_AR_AVN_CurrentTerms from "@salesforce/label/c.AR_AVN_CurrentTerms";
import LBL_AR_AVN_DailyFees from "@salesforce/label/c.AR_AVN_DailyFees";
import LBL_AR_AVN_EffectiveBeforeMissionStart from "@salesforce/label/c.AR_AVN_EffectiveBeforeMissionStart";
import LBL_AR_AVN_EffectiveDate from "@salesforce/label/c.AR_AVN_EffectiveDate";
import LBL_AR_AVN_EffectiveOutsideMission from "@salesforce/label/c.AR_AVN_EffectiveOutsideMission";
import LBL_AR_AVN_EndBeforeEffective from "@salesforce/label/c.AR_AVN_EndBeforeEffective";
import LBL_AR_AVN_FillEffectiveDate from "@salesforce/label/c.AR_AVN_FillEffectiveDate";
import LBL_AR_AVN_FillNewEndDate from "@salesforce/label/c.AR_AVN_FillNewEndDate";
import LBL_AR_AVN_FillNewRate from "@salesforce/label/c.AR_AVN_FillNewRate";
import LBL_AR_AVN_FreelanceEditableHint from "@salesforce/label/c.AR_AVN_FreelanceEditableHint";
import LBL_AR_AVN_Gap from "@salesforce/label/c.AR_AVN_Gap";
import LBL_AR_AVN_GeneratingDocument from "@salesforce/label/c.AR_AVN_GeneratingDocument";
import LBL_AR_AVN_GratuityDays from "@salesforce/label/c.AR_AVN_GratuityDays";
import LBL_AR_AVN_ImpactTitle from "@salesforce/label/c.AR_AVN_ImpactTitle";
import LBL_AR_AVN_Mc2OverPeriod from "@salesforce/label/c.AR_AVN_Mc2OverPeriod";
import LBL_AR_AVN_Mc2Percent from "@salesforce/label/c.AR_AVN_Mc2Percent";
import LBL_AR_AVN_ModalIntro from "@salesforce/label/c.AR_AVN_ModalIntro";
import LBL_AR_AVN_ModalTitleWithSource from "@salesforce/label/c.AR_AVN_ModalTitleWithSource";
import LBL_AR_AVN_NewEndDate from "@salesforce/label/c.AR_AVN_NewEndDate";
import LBL_AR_AVN_NoWorkingDay from "@salesforce/label/c.AR_AVN_NoWorkingDay";
import LBL_AR_AVN_OneTimeFeesReamortized from "@salesforce/label/c.AR_AVN_OneTimeFeesReamortized";
import LBL_AR_AVN_OtherDailyFees from "@salesforce/label/c.AR_AVN_OtherDailyFees";
import LBL_AR_AVN_OtherOneTimeFees from "@salesforce/label/c.AR_AVN_OtherOneTimeFees";
import LBL_AR_AVN_PeriodSummary from "@salesforce/label/c.AR_AVN_PeriodSummary";
import LBL_AR_AVN_PointsDelta from "@salesforce/label/c.AR_AVN_PointsDelta";
import LBL_AR_AVN_ProfitabilityDown from "@salesforce/label/c.AR_AVN_ProfitabilityDown";
import LBL_AR_AVN_ProfitabilityKept from "@salesforce/label/c.AR_AVN_ProfitabilityKept";
import LBL_AR_AVN_PurchaseRateBeforeMarkup from "@salesforce/label/c.AR_AVN_PurchaseRateBeforeMarkup";
import LBL_AR_AVN_Q1NewRate from "@salesforce/label/c.AR_AVN_Q1NewRate";
import LBL_AR_AVN_Q2NewPeriod from "@salesforce/label/c.AR_AVN_Q2NewPeriod";
import LBL_AR_AVN_Q3FinancialTerms from "@salesforce/label/c.AR_AVN_Q3FinancialTerms";
import LBL_AR_AVN_Reasons from "@salesforce/label/c.AR_AVN_Reasons";
import LBL_AR_AVN_StoredMc2Reminder from "@salesforce/label/c.AR_AVN_StoredMc2Reminder";
import LBL_AR_AVN_TotalCostPerDay from "@salesforce/label/c.AR_AVN_TotalCostPerDay";
import LBL_AR_AVN_ValidateAvenant from "@salesforce/label/c.AR_AVN_ValidateAvenant";
import LBL_AR_AVN_Validating from "@salesforce/label/c.AR_AVN_Validating";
import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_Common_DailyRate from "@salesforce/label/c.AR_Common_DailyRate";
import LBL_AR_Common_LoadingEllipsis from "@salesforce/label/c.AR_Common_LoadingEllipsis";
import LBL_AR_Common_No from "@salesforce/label/c.AR_Common_No";
import LBL_AR_Common_NotProvidedFemLower from "@salesforce/label/c.AR_Common_NotProvidedFemLower";
import LBL_AR_Common_Yes from "@salesforce/label/c.AR_Common_Yes";
import LBL_AR_PMS_Mc2PerDayLabel from "@salesforce/label/c.AR_PMS_Mc2PerDayLabel";
import LBL_AR_PMS_RecapFeeLodging from "@salesforce/label/c.AR_PMS_RecapFeeLodging";
import LBL_AR_PMS_RecapFeeMeals from "@salesforce/label/c.AR_PMS_RecapFeeMeals";
import LBL_AR_PMS_RecapFeeOfiiTax from "@salesforce/label/c.AR_PMS_RecapFeeOfiiTax";
import LBL_AR_PMS_RecapFeePhone from "@salesforce/label/c.AR_PMS_RecapFeePhone";
import LBL_AR_PMS_RecapFeeTraining from "@salesforce/label/c.AR_PMS_RecapFeeTraining";
import LBL_AR_PTF_CreateAvenant from "@salesforce/label/c.AR_PTF_CreateAvenant";
import LBL_AR_PTF_NewDailyRate from "@salesforce/label/c.AR_PTF_NewDailyRate";

/** Périodes de salaire enregistrées (JSON) ; illisible ou absent → aucune période (le serveur a déjà validé). */
function parseSalaryPeriodsJson(raw) {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    console.error("Périodes de salaire illisibles", e);
    return [];
  }
}

const I18N = {
  AR_AVN_AmendedPtf: LBL_AR_AVN_AmendedPtf,
  AR_AVN_AnnualSalary: LBL_AR_AVN_AnnualSalary,
  AR_AVN_AnswerYesToSeeImpact: LBL_AR_AVN_AnswerYesToSeeImpact,
  AR_AVN_AppliedMarkup: LBL_AR_AVN_AppliedMarkup,
  AR_AVN_Avenant: LBL_AR_AVN_Avenant,
  AR_AVN_ChooseAtLeastOneReason: LBL_AR_AVN_ChooseAtLeastOneReason,
  AR_AVN_Computer: LBL_AR_AVN_Computer,
  AR_AVN_CurrentEnd: LBL_AR_AVN_CurrentEnd,
  AR_AVN_CurrentRate: LBL_AR_AVN_CurrentRate,
  AR_AVN_CurrentTerms: LBL_AR_AVN_CurrentTerms,
  AR_AVN_DailyFees: LBL_AR_AVN_DailyFees,
  AR_AVN_EffectiveBeforeMissionStart: LBL_AR_AVN_EffectiveBeforeMissionStart,
  AR_AVN_EffectiveDate: LBL_AR_AVN_EffectiveDate,
  AR_AVN_EffectiveOutsideMission: LBL_AR_AVN_EffectiveOutsideMission,
  AR_AVN_EndBeforeEffective: LBL_AR_AVN_EndBeforeEffective,
  AR_AVN_FillEffectiveDate: LBL_AR_AVN_FillEffectiveDate,
  AR_AVN_FillNewEndDate: LBL_AR_AVN_FillNewEndDate,
  AR_AVN_FillNewRate: LBL_AR_AVN_FillNewRate,
  AR_AVN_FreelanceEditableHint: LBL_AR_AVN_FreelanceEditableHint,
  AR_AVN_Gap: LBL_AR_AVN_Gap,
  AR_AVN_GeneratingDocument: LBL_AR_AVN_GeneratingDocument,
  AR_AVN_GratuityDays: LBL_AR_AVN_GratuityDays,
  AR_AVN_ImpactTitle: LBL_AR_AVN_ImpactTitle,
  AR_AVN_Mc2OverPeriod: LBL_AR_AVN_Mc2OverPeriod,
  AR_AVN_Mc2Percent: LBL_AR_AVN_Mc2Percent,
  AR_AVN_ModalIntro: LBL_AR_AVN_ModalIntro,
  AR_AVN_ModalTitleWithSource: LBL_AR_AVN_ModalTitleWithSource,
  AR_AVN_NewEndDate: LBL_AR_AVN_NewEndDate,
  AR_AVN_NoWorkingDay: LBL_AR_AVN_NoWorkingDay,
  AR_AVN_OneTimeFeesReamortized: LBL_AR_AVN_OneTimeFeesReamortized,
  AR_AVN_OtherDailyFees: LBL_AR_AVN_OtherDailyFees,
  AR_AVN_OtherOneTimeFees: LBL_AR_AVN_OtherOneTimeFees,
  AR_AVN_PeriodSummary: LBL_AR_AVN_PeriodSummary,
  AR_AVN_PointsDelta: LBL_AR_AVN_PointsDelta,
  AR_AVN_ProfitabilityDown: LBL_AR_AVN_ProfitabilityDown,
  AR_AVN_ProfitabilityKept: LBL_AR_AVN_ProfitabilityKept,
  AR_AVN_PurchaseRateBeforeMarkup: LBL_AR_AVN_PurchaseRateBeforeMarkup,
  AR_AVN_Q1NewRate: LBL_AR_AVN_Q1NewRate,
  AR_AVN_Q2NewPeriod: LBL_AR_AVN_Q2NewPeriod,
  AR_AVN_Q3FinancialTerms: LBL_AR_AVN_Q3FinancialTerms,
  AR_AVN_Reasons: LBL_AR_AVN_Reasons,
  AR_AVN_StoredMc2Reminder: LBL_AR_AVN_StoredMc2Reminder,
  AR_AVN_TotalCostPerDay: LBL_AR_AVN_TotalCostPerDay,
  AR_AVN_ValidateAvenant: LBL_AR_AVN_ValidateAvenant,
  AR_AVN_Validating: LBL_AR_AVN_Validating,
  AR_Common_Cancel: LBL_AR_Common_Cancel,
  AR_Common_DailyRate: LBL_AR_Common_DailyRate,
  AR_Common_LoadingEllipsis: LBL_AR_Common_LoadingEllipsis,
  AR_Common_No: LBL_AR_Common_No,
  AR_Common_NotProvidedFemLower: LBL_AR_Common_NotProvidedFemLower,
  AR_Common_Yes: LBL_AR_Common_Yes,
  AR_PMS_Mc2PerDayLabel: LBL_AR_PMS_Mc2PerDayLabel,
  AR_PMS_RecapFeeLodging: LBL_AR_PMS_RecapFeeLodging,
  AR_PMS_RecapFeeMeals: LBL_AR_PMS_RecapFeeMeals,
  AR_PMS_RecapFeeOfiiTax: LBL_AR_PMS_RecapFeeOfiiTax,
  AR_PMS_RecapFeePhone: LBL_AR_PMS_RecapFeePhone,
  AR_PMS_RecapFeeTraining: LBL_AR_PMS_RecapFeeTraining,
  AR_PTF_CreateAvenant: LBL_AR_PTF_CreateAvenant,
  AR_PTF_NewDailyRate: LBL_AR_PTF_NewDailyRate
};
const YES_NO_OPTIONS = [
  { label: I18N.AR_Common_No, value: "no" },
  { label: I18N.AR_Common_Yes, value: "yes" }
];

const SEGMENTS = {
  below_floor: {
    label: LBL_SEGMENT_BELOW_FLOOR,
    cssClass: "av-seg av-seg_red"
  },
  low_margin: {
    label: LBL_SEGMENT_LOW_MARGIN,
    cssClass: "av-seg av-seg_amber"
  },
  recommended: {
    label: LBL_SEGMENT_RECOMMENDED,
    cssClass: "av-seg av-seg_green"
  },
  superstar: {
    label: LBL_SEGMENT_SUPERSTAR,
    cssClass: "av-seg av-seg_green-dark"
  }
};

// Motifs « Avenant — … » (docs/180 §7 et §9bis Q9) : créés en donnée (AR_Reason__c), présélectionnés
// ici par NOM selon les réponses. Un nom absent du catalogue = pas de présélection, jamais une erreur.
export const AVENANT_REASON_NAMES = {
  tarif: "Avenant — révision tarifaire",
  periode: "Avenant — prolongation de mission",
  conditions: "Avenant — conditions financières"
};

const SALARIED = ["CDI", "CDD"];
const WITH_OM_AND_ONE_SHOT = ["CDI", "CDD", "VIE"];

// Champs de la question 3 (docs/180 §5), filtrés par statut de contrat. Les noms sont ceux de
// AvenantContext / AvenantInput (AR_AvenantService) ET de l'entrée du moteur (arPricingEngine.compute).
const COST_FIELDS = [
  {
    key: "annualSalary",
    label: I18N.AR_AVN_AnnualSalary,
    group: "cost",
    contracts: SALARIED
  },
  {
    key: "cjmBeforeMarkup",
    label: I18N.AR_AVN_PurchaseRateBeforeMarkup,
    group: "cost",
    contracts: ["INDEP"]
  },
  {
    key: "markupApplied",
    label: I18N.AR_AVN_AppliedMarkup,
    group: "cost",
    contracts: ["INDEP"]
  },
  { key: "feeIk", label: "IK", group: "om", contracts: WITH_OM_AND_ONE_SHOT },
  {
    key: "feeMeals",
    label: I18N.AR_PMS_RecapFeeMeals,
    group: "om",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeLodging",
    label: I18N.AR_PMS_RecapFeeLodging,
    group: "om",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeOmOther",
    label: I18N.AR_AVN_OtherDailyFees,
    group: "om",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "gratuityDays",
    label: I18N.AR_AVN_GratuityDays,
    group: "once",
    contracts: ["CDI", "CDD", "VIE", "INDEP", "NEARSHORE"]
  },
  {
    key: "feeComputer",
    label: I18N.AR_AVN_Computer,
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feePhone",
    label: I18N.AR_PMS_RecapFeePhone,
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeTraining",
    label: I18N.AR_PMS_RecapFeeTraining,
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeEpi",
    label: "EPI",
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeOfiiTax",
    label: I18N.AR_PMS_RecapFeeOfiiTax,
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  },
  {
    key: "feeOther",
    label: I18N.AR_AVN_OtherOneTimeFees,
    group: "once",
    contracts: WITH_OM_AND_ONE_SHOT
  }
];

function costFieldApplies(fields, key, contractType) {
  const field = fields.find((f) => f.key === key);
  return !!field && field.contracts.includes(contractType);
}

const NUMBER_FORMATTER = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1
});

function toNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const n = Number(value);
  return Number.isNaN(n) ? null : n;
}

function signOf(delta) {
  if (delta > 0) return "+";
  if (delta < 0) return "−";
  return "";
}

/** Écart monétaire signé, dans la devise de la matrice (symbole compris : formatMoney). */
function formatMoneyDelta(delta, currency) {
  return `${signOf(Math.round(delta))}${formatMoney(Math.abs(delta), currency)}`;
}

function formatPointsDelta(delta) {
  // Bruit flottant d'abord (46,84 − 42,29 = 4,549999…), puis arrondi à une décimale comme formatPercent.
  const clean = Math.round(delta * 100) / 100;
  const rounded = Math.round(clean * 10) / 10;
  return formatLabel(
    I18N.AR_AVN_PointsDelta,
    `${signOf(rounded)}${NUMBER_FORMATTER.format(Math.abs(rounded))}`
  );
}

/** MC2 % au centième de point, comme la règle serveur (AR_AvenantService.requiresHumanValidation). */
function roundToHundredth(value) {
  return Math.round(value * 100) / 100;
}

function formatDateFr(isoDate) {
  if (!isoDate) return "";
  const [y, m, d] = String(isoDate).split("-");
  return `${d}/${m}/${y}`;
}

/**
 * Modale « Créer un avenant » (session 180c, docs/180-avenant-depuis-la-matrice.md §1, §3, §5 et §9bis).
 * Trois questions (tarif, période, conditions financières), motifs, tableau d'impact avant/après sur la
 * période de l'avenant, puis `AR_AvenantService.createAvenant`. Le serveur décide (règle unique
 * `requiresHumanValidation`) ; l'impact affiché n'est qu'un aperçu calculé par le même moteur
 * (`arPricingEngine.compute`, aucune formule nouvelle) avec les seuils et le coefficient FIGÉS de la
 * matrice source. « Avant » = la matrice amendée telle qu'elle est (sa propre durée) ; dérogation si la
 * MC2 % de l'avenant est strictement inférieure à ce « avant ». Événements : `cancel`, `created` ({ matrixId, status, derogationRequired }).
 */
export default class ArAvenantModal extends LightningElement {
  i18n = I18N;

  @api sourceMatrixId;
  @api preselectedPtfId;

  _open = false;
  context;
  engineInput; // MatrixInput de la source : cjmVie / cjmNearshore / coefficient et jours figés
  isLoading = false;
  loadError;
  isSaving = false;
  isGenerating = false;
  saveError;

  selectedPtfId;
  tarif = "no";
  periode = "no";
  conditions = "no";
  newTjm = "";
  effectiveDate = "";
  newEndDate = "";
  costInputs = {};
  _ofiiTaxEditedByHand = false;
  selectedReasonIds = [];
  reasonOptions = [];
  _reasonsTouched = false;
  _loadSeq = 0;

  yesNoOptions = YES_NO_OPTIONS;

  @api
  get open() {
    return this._open;
  }
  set open(value) {
    const next = !!value;
    if (next && !this._open) {
      this.resetState();
      // Différé d'un micro-cycle : `sourceMatrixId` / `preselectedPtfId` sont posés par le même rendu
      // du parent, parfois après `open` selon l'ordre des attributs.
      Promise.resolve().then(() => this.loadContext());
    }
    this._open = next;
  }

  resetState() {
    this.context = undefined;
    this.engineInput = undefined;
    this.loadError = undefined;
    this.saveError = undefined;
    this.isSaving = false;
    this.selectedPtfId = undefined;
    this.tarif = "no";
    this.periode = "no";
    this.conditions = "no";
    this.newTjm = "";
    this.effectiveDate = "";
    this.newEndDate = "";
    this.costInputs = {};
    this._ofiiTaxEditedByHand = false;
    this.selectedReasonIds = [];
    this._reasonsTouched = false;
  }

  async loadContext() {
    const seq = ++this._loadSeq;
    this.isLoading = true;
    try {
      const [context, engineInput, reasons] = await Promise.all([
        getAvenantContext({ matrixId: this.sourceMatrixId }),
        getMatrixInput({ matrixId: this.sourceMatrixId }),
        getReasonOptions({ usage: "version" })
      ]);
      if (seq !== this._loadSeq) return;
      this.context = context;
      this.engineInput = engineInput;
      this.reasonOptions = reasons || [];
      const options = context.ptfOptions || [];
      const wanted = options.find((o) => o.ptfId === this.preselectedPtfId);
      this.selectedPtfId = wanted ? wanted.ptfId : context.amendedPtfId;
    } catch (error) {
      if (seq !== this._loadSeq) return;
      // Afficher (CLAUDE.md, classement des catch) : état d'erreur explicite, distinct de tout état métier.
      this.context = undefined;
      this.loadError = reduceErrors(error);
      console.error("arAvenantModal : échec du chargement du contexte.", error);
    } finally {
      if (seq === this._loadSeq) {
        this.isLoading = false;
      }
    }
  }

  // ---------- Affichage général ----------

  get hasContext() {
    return !!this.context;
  }

  get hasLoadError() {
    return !!this.loadError;
  }

  get modalTitle() {
    return this.context
      ? formatLabel(I18N.AR_AVN_ModalTitleWithSource, this.context.sourceName)
      : I18N.AR_PTF_CreateAvenant;
  }

  get currency() {
    return (this.context && this.context.currencyCode) || "EUR";
  }

  get ptfSelectOptions() {
    return ((this.context && this.context.ptfOptions) || []).map((o) => ({
      label: o.reference,
      value: o.ptfId
    }));
  }

  get isTarif() {
    return this.tarif === "yes";
  }
  get isPeriode() {
    return this.periode === "yes";
  }
  get isConditions() {
    return this.conditions === "yes";
  }
  get anyYes() {
    return this.isTarif || this.isPeriode || this.isConditions;
  }

  // La date d'effet s'affiche dans le dernier encart ouvert ; un seul des trois getters est vrai.
  get effectiveDateInPeriod() {
    return this.isPeriode;
  }
  get effectiveDateInConditions() {
    return !this.isPeriode && this.isConditions;
  }
  get effectiveDateInTarif() {
    return !this.isPeriode && !this.isConditions && this.isTarif;
  }

  get currentTjmText() {
    return formatLabel(I18N.AR_AVN_CurrentRate, this.currentTjmLabel);
  }

  get currentEndText() {
    return formatLabel(I18N.AR_AVN_CurrentEnd, this.currentEndLabel);
  }

  get currentTjmLabel() {
    return formatMoney(this.context && this.context.proposedTjm, this.currency);
  }

  get currentEndLabel() {
    return (
      formatDateFr(this.context && this.context.currentEndDate) ||
      I18N.AR_Common_NotProvidedFemLower
    );
  }

  /** Période retenue, rappelée sous la date de fin (visible dès que les deux dates sont connues). */
  get periodSummary() {
    if (
      !this.isPeriode ||
      !this.effectiveDateValue ||
      !this.newEndDate ||
      this.dateError
    ) {
      return "";
    }
    return formatLabel(
      I18N.AR_AVN_PeriodSummary,
      formatDateFr(this.effectiveDateValue),
      formatDateFr(this.newEndDate),
      this.periodDays
    );
  }

  get hasPeriodSummary() {
    return !!this.periodSummary;
  }

  // ---------- Dates ----------

  /** Prolongation seule : le lendemain de la fin actuelle est proposé (même défaut que le serveur). */
  get effectiveDateValue() {
    if (this.effectiveDate) return this.effectiveDate;
    if (this.isPeriode && !this.isTarif && !this.isConditions && this.context) {
      return this.context.defaultExtensionEffectiveDate || "";
    }
    return "";
  }

  get finalEndDate() {
    if (this.isPeriode) return this.newEndDate;
    return (this.context && this.context.currentEndDate) || "";
  }

  get periodDays() {
    const start = this.effectiveDateValue;
    const end = this.finalEndDate;
    if (!start || !end) return 0;
    return calcBusinessDays(
      start,
      end,
      this.context && this.context.entityCountry
    );
  }

  /** Message d'incohérence de dates (les mêmes contrôles que le serveur), ou null. */
  get dateError() {
    const start = this.effectiveDateValue;
    const end = this.finalEndDate;
    if (!this.anyYes || !start) return null;
    const missionStart = this.context && this.context.missionStartDate;
    if (missionStart && start < missionStart) {
      return I18N.AR_AVN_EffectiveBeforeMissionStart;
    }
    if (this.isPeriode && end && end <= start) {
      return I18N.AR_AVN_EndBeforeEffective;
    }
    if (end && start > end) {
      return I18N.AR_AVN_EffectiveOutsideMission;
    }
    if (end && this.periodDays <= 0) {
      return I18N.AR_AVN_NoWorkingDay;
    }
    return null;
  }

  get hasDateError() {
    return !!this.dateError;
  }

  // ---------- Question 3 : champs de coût selon le contrat ----------

  costValue(key) {
    const override = this.costInputs[key];
    if (override !== undefined) return override;
    const base = this.context ? this.context[key] : null;
    return base === null || base === undefined ? "" : base;
  }

  buildCostGroup(group) {
    const contract = this.context && this.context.contractType;
    return COST_FIELDS.filter(
      (f) => f.group === group && f.contracts.includes(contract)
    ).map((f) => ({
      key: f.key,
      label: f.label,
      value: this.costValue(f.key)
    }));
  }

  get costFields() {
    return this.buildCostGroup("cost");
  }
  get omFields() {
    return this.buildCostGroup("om");
  }
  get oneShotFields() {
    return this.buildCostGroup("once");
  }
  get hasCostFields() {
    return this.costFields.length > 0;
  }
  get hasOmFields() {
    return this.omFields.length > 0;
  }
  get hasOneShotFields() {
    return this.oneShotFields.length > 0;
  }

  get isIndep() {
    return !!this.context && this.context.contractType === "INDEP";
  }

  /** Surcharges réellement différentes de la source (seules celles-ci partent au serveur). */
  get changedCosts() {
    const changed = {};
    COST_FIELDS.forEach((f) => {
      const raw = this.costInputs[f.key];
      if (raw === undefined) return;
      if (!f.contracts.includes(this.context.contractType)) return;
      const next = toNumber(raw) === null ? 0 : toNumber(raw);
      const base = toNumber(this.context[f.key]) || 0;
      if (next !== base) changed[f.key] = next;
    });
    return changed;
  }

  // ---------- Impact (aperçu, même moteur que l'écran de simulation) ----------

  engineContext(overrides, days) {
    const input = this.engineInput || {};
    const stored = input.storedResult || {};
    const ctx = this.context;
    const merged = {};
    COST_FIELDS.forEach((f) => {
      const o = overrides ? overrides[f.key] : undefined;
      merged[f.key] = o !== undefined ? o : ctx[f.key];
    });
    return {
      contractType: ctx.contractType,
      ...merged,
      cjmVie: input.cjmVie,
      cjmNearshore: input.cjmNearshore,
      workingDaysPerYear: stored.workingDaysPerYearApplied,
      contractCoefficient: stored.contractCoefficientApplied,
      feeMonthlyOther: ctx.feeMonthlyOther,
      missionDays: days
    };
  }

  /**
   * Contexte de la matrice amendée telle qu'enregistrée : salaire de sa période 1 et ses périodes de salaire,
   * donc son CJM pondéré (le salaire de départ de l'avenant est, lui, celui de la dernière période).
   */
  sourceEngineContext() {
    const ctx = this.context;
    const base = this.engineContext({}, toNumber(ctx.sourceNumberOfDays) || 0);
    if (
      ctx.sourceAnnualSalary !== undefined &&
      ctx.sourceAnnualSalary !== null
    ) {
      base.annualSalary = ctx.sourceAnnualSalary;
    }
    base.salaryPeriods = parseSalaryPeriodsJson(
      this.engineInput && this.engineInput.salaryPeriods
    );
    return base;
  }

  get corridorPercents() {
    const c = this.context;
    if (
      !c ||
      c.floorPercentApplied == null ||
      c.targetPercentApplied == null ||
      c.idealPercentApplied == null
    ) {
      return undefined;
    }
    return {
      floorPercent: c.floorPercentApplied,
      targetPercent: c.targetPercentApplied,
      idealPercent: c.idealPercentApplied
    };
  }

  /** Pourquoi le tableau d'impact n'est pas (encore) affiché, ou null s'il l'est. */
  get impactHint() {
    if (!this.anyYes) {
      return I18N.AR_AVN_AnswerYesToSeeImpact;
    }
    if (!this.effectiveDateValue) {
      return I18N.AR_AVN_FillEffectiveDate;
    }
    if (this.isPeriode && !this.newEndDate) {
      return I18N.AR_AVN_FillNewEndDate;
    }
    if (this.isTarif && !(toNumber(this.newTjm) > 0)) {
      return I18N.AR_AVN_FillNewRate;
    }
    if (this.dateError) {
      return this.dateError;
    }
    return null;
  }

  get impact() {
    if (!this.context || this.impactHint) return null;
    const days = this.periodDays;
    const rfa = this.context.rfaPercent;
    const sourceTjm = this.context.proposedTjm;
    const newTjm = this.isTarif ? toNumber(this.newTjm) : sourceTjm;
    const overrides = this.isConditions ? this.changedCosts : {};
    // « Avant » = la matrice amendée telle qu'elle est : ses frais ponctuels restent amortis sur SA durée
    // (0 = repli du moteur, comme le serveur pour une source sans durée).
    const before = compute(
      this.sourceEngineContext(),
      rfa,
      sourceTjm,
      0,
      this.corridorPercents
    );
    const after = compute(
      this.engineContext(overrides, days),
      rfa,
      newTjm,
      0,
      this.corridorPercents
    );
    return { before, after, days, sourceTjm, newTjm };
  }

  get hasImpact() {
    return !!this.impact;
  }

  get impactTitle() {
    const i = this.impact;
    if (!i) return "";
    return formatLabel(
      I18N.AR_AVN_ImpactTitle,
      formatDateFr(this.effectiveDateValue),
      formatDateFr(this.finalEndDate),
      i.days
    );
  }

  get impactRows() {
    const i = this.impact;
    if (!i) return [];
    const cur = this.currency;
    const { before, after } = i;
    const periodBefore = before.mc2PerDay * i.days;
    const periodAfter = after.mc2PerDay * i.days;
    const tjmPct =
      i.sourceTjm > 0 ? ((i.newTjm - i.sourceTjm) / i.sourceTjm) * 100 : 0;
    const tjmDelta = i.newTjm - i.sourceTjm;
    const tjmDeltaLabel =
      tjmDelta === 0
        ? formatMoneyDelta(0, cur)
        : `${formatMoneyDelta(tjmDelta, cur)} (${signOf(tjmDelta)}${formatPercent(Math.abs(tjmPct))})`;
    return [
      {
        key: "tjm",
        label: I18N.AR_Common_DailyRate,
        before: formatMoney(i.sourceTjm, cur),
        after: formatMoney(i.newTjm, cur),
        delta: tjmDeltaLabel
      },
      {
        key: "cost",
        label: I18N.AR_AVN_TotalCostPerDay,
        before: formatMoney(before.totalDailyCost, cur),
        after: formatMoney(after.totalDailyCost, cur),
        delta: formatMoneyDelta(
          after.totalDailyCost - before.totalDailyCost,
          cur
        )
      },
      {
        key: "mc2day",
        label: I18N.AR_PMS_Mc2PerDayLabel,
        before: formatMoney(before.mc2PerDay, cur),
        after: formatMoney(after.mc2PerDay, cur),
        delta: formatMoneyDelta(after.mc2PerDay - before.mc2PerDay, cur)
      },
      {
        key: "mc2pct",
        label: I18N.AR_AVN_Mc2Percent,
        before: formatPercent(before.mc2PercentHuman),
        after: formatPercent(after.mc2PercentHuman),
        delta: formatPointsDelta(
          after.mc2PercentHuman - before.mc2PercentHuman
        ),
        beforeSegment: SEGMENTS[before.corridorSegment],
        afterSegment: SEGMENTS[after.corridorSegment]
      },
      {
        key: "mc2period",
        label: I18N.AR_AVN_Mc2OverPeriod,
        before: formatMoney(periodBefore, cur),
        after: formatMoney(periodAfter, cur),
        delta: formatMoneyDelta(periodAfter - periodBefore, cur)
      }
    ].map((r) => ({
      ...r,
      hasSegment: !!r.afterSegment,
      beforeSegmentLabel: r.beforeSegment ? r.beforeSegment.label : "",
      beforeSegmentClass: r.beforeSegment ? r.beforeSegment.cssClass : "",
      afterSegmentLabel: r.afterSegment ? r.afterSegment.label : "",
      afterSegmentClass: r.afterSegment ? r.afterSegment.cssClass : ""
    }));
  }

  get storedMc2Note() {
    const stored = this.context && this.context.storedMc2Percent;
    if (stored === null || stored === undefined) return "";
    return formatLabel(I18N.AR_AVN_StoredMc2Reminder, formatPercent(stored));
  }

  /** Rentabilité (MC2 %) en baisse par rapport à la matrice amendée, au centième de point. */
  get requiresDerogation() {
    const i = this.impact;
    return (
      !!i &&
      roundToHundredth(i.after.mc2PercentHuman) <
        roundToHundredth(i.before.mc2PercentHuman)
    );
  }

  get decisionText() {
    if (!this.impact) return "";
    return this.requiresDerogation
      ? I18N.AR_AVN_ProfitabilityDown
      : I18N.AR_AVN_ProfitabilityKept;
  }

  get decisionClass() {
    return this.requiresDerogation
      ? "av-decision av-decision_warn"
      : "av-decision av-decision_ok";
  }

  // ---------- Motifs (présélection selon les réponses, modifiable) ----------

  preselectedReasonIds() {
    const wanted = [];
    if (this.isTarif) wanted.push(AVENANT_REASON_NAMES.tarif);
    if (this.isPeriode) wanted.push(AVENANT_REASON_NAMES.periode);
    if (this.isConditions) wanted.push(AVENANT_REASON_NAMES.conditions);
    return this.reasonOptions
      .filter((r) => wanted.includes(r.label))
      .map((r) => r.reasonId);
  }

  syncReasons() {
    if (!this._reasonsTouched) {
      this.selectedReasonIds = this.preselectedReasonIds();
    }
  }

  handleReasonsChange(event) {
    this._reasonsTouched = true;
    this.selectedReasonIds = Array.isArray(event.detail.selectedIds)
      ? event.detail.selectedIds
      : [];
  }

  // ---------- Saisie ----------

  handlePtfChange(event) {
    this.selectedPtfId = event.detail.value;
  }

  handleTarifChange(event) {
    this.tarif = event.detail.value;
    this.syncReasons();
  }
  handlePeriodeChange(event) {
    this.periode = event.detail.value;
    this.syncReasons();
  }
  handleConditionsChange(event) {
    this.conditions = event.detail.value;
    this.syncReasons();
  }

  handleNewTjmChange(event) {
    this.newTjm = event.detail.value;
  }
  handleEffectiveDateChange(event) {
    this.effectiveDate = event.detail.value;
  }
  handleNewEndDateChange(event) {
    this.newEndDate = event.detail.value;
  }

  handleCostChange(event) {
    const key = event.target.dataset.field;
    const value = event.detail.value;
    this.costInputs = { ...this.costInputs, [key]: value };
    if (key === "feeOfiiTax") {
      // Saisie à la main : le salaire ne recalcule plus la taxe.
      this._ofiiTaxEditedByHand = true;
    } else if (key === "annualSalary") {
      this.followOfiiTaxCalculation(value);
    }
  }

  /** Plafond OFII administré, dans la devise de la matrice (taux figé de la source) ; null si indisponible. */
  get ofiiTaxCapInMatrixCurrency() {
    const c = this.context;
    if (!c || !(Number(c.ofiiTaxCapEur) > 0)) return null;
    if (c.currencyCode === "EUR") return Number(c.ofiiTaxCapEur);
    const stored = (this.engineInput && this.engineInput.storedResult) || {};
    const rate = Number(stored.currencyRateApplied);
    if (!(rate > 0)) return null;
    return Math.round((Number(c.ofiiTaxCapEur) / rate) * 100) / 100;
  }

  /**
   * Si la matrice d'origine portait la taxe OFII calculée sur son salaire, un nouveau salaire recalcule
   * la taxe (elle reste modifiable à la main, et une saisie manuelle n'est plus écrasée). Une taxe
   * d'origine qui n'était pas la valeur calculée, ou un calcul indisponible, ne change rien.
   */
  followOfiiTaxCalculation(newSalaryRaw) {
    const c = this.context;
    if (
      !c ||
      this._ofiiTaxEditedByHand ||
      !costFieldApplies(COST_FIELDS, "feeOfiiTax", c.contractType)
    ) {
      return;
    }
    const cap = this.ofiiTaxCapInMatrixCurrency;
    const originalTax = toNumber(c.feeOfiiTax) || 0;
    // La taxe d'origine est calculée sur le salaire de la période 1 de la source.
    const originalSalary =
      c.sourceAnnualSalary !== undefined && c.sourceAnnualSalary !== null
        ? c.sourceAnnualSalary
        : c.annualSalary;
    const originalCalc = computeOfiiTax(originalSalary, c.ofiiTaxRate, cap);
    if (
      originalTax <= 0 ||
      originalCalc === null ||
      Math.abs(originalTax - originalCalc) >= 0.005
    ) {
      return;
    }
    const next = computeOfiiTax(newSalaryRaw, c.ofiiTaxRate, cap);
    this.costInputs = {
      ...this.costInputs,
      feeOfiiTax: next === null ? 0 : next
    };
  }

  // ---------- Validation ----------

  get missingReason() {
    return this.selectedReasonIds.length === 0;
  }

  get isSubmitDisabled() {
    if (this.isSaving || !this.context || !this.anyYes) return true;
    if (!this.effectiveDateValue) return true;
    if (this.isTarif && !(toNumber(this.newTjm) > 0)) return true;
    if (this.isPeriode && !this.newEndDate) return true;
    if (this.hasDateError) return true;
    return this.missingReason;
  }

  get showReasonHint() {
    return this.anyYes && this.missingReason;
  }

  buildPayload() {
    const payload = {
      sourceMatrixId: this.sourceMatrixId,
      amendedPtfId: this.selectedPtfId,
      tarif: this.isTarif,
      periode: this.isPeriode,
      conditions: this.isConditions,
      effectiveDate: this.effectiveDateValue,
      reasonIds: this.selectedReasonIds
    };
    if (this.isTarif) payload.newTjm = toNumber(this.newTjm);
    if (this.isPeriode) payload.newEndDate = this.newEndDate;
    if (this.isConditions) Object.assign(payload, this.changedCosts);
    return payload;
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  async handleSubmit() {
    if (this.isSubmitDisabled) return;
    this.saveError = undefined;
    this.isSaving = true;
    try {
      const result = await createAvenantApex({
        inputJson: JSON.stringify(this.buildPayload())
      });
      // Session 180d : validé d'office → le document est généré dans la foulée (snapshot puis rendu,
      // deux appels distincts). Un échec de génération n'annule rien : la matrice reste validée et
      // l'issue est remise au parent, qui l'affiche (toast nommé + bouton « Générer l'avenant »).
      // En dérogation, aucune génération : elle suivra la décision du valideur.
      let document = { outcome: "skipped" };
      if (!result.derogationRequired) {
        this.isGenerating = true;
        document = await generateAvenantDocument(result.matrixId);
      }
      this.dispatchEvent(
        new CustomEvent("created", {
          detail: {
            matrixId: result.matrixId,
            matrixName: result.matrixName,
            status: result.status,
            derogationRequired: !!result.derogationRequired,
            document
          }
        })
      );
    } catch (error) {
      // Afficher : la création a échoué, la modale reste ouverte avec le message serveur.
      this.saveError = reduceErrors(error);
      console.error(
        "arAvenantModal : échec de la création de l’avenant.",
        error
      );
    } finally {
      this.isSaving = false;
      this.isGenerating = false;
    }
  }

  get submitLabel() {
    if (this.isGenerating) return I18N.AR_AVN_GeneratingDocument;
    return this.isSaving ? I18N.AR_AVN_Validating : I18N.AR_AVN_ValidateAvenant;
  }
}