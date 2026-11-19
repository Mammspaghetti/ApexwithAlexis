import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getCurrencyRates from "@salesforce/apex/AR_AdminCommercialService.getCurrencyRates";
import addCurrencyRateApex from "@salesforce/apex/AR_AdminCommercialService.addCurrencyRate";
import updateCurrencyRateApex from "@salesforce/apex/AR_AdminCommercialService.updateCurrencyRate";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_ACR_AddRate from "@salesforce/label/c.AR_ACR_AddRate";
import LBL_AR_ACR_Correct from "@salesforce/label/c.AR_ACR_Correct";
import LBL_AR_ACR_CorrectHelp from "@salesforce/label/c.AR_ACR_CorrectHelp";
import LBL_AR_ACR_CorrectRate from "@salesforce/label/c.AR_ACR_CorrectRate";
import LBL_AR_ACR_Corrected from "@salesforce/label/c.AR_ACR_Corrected";
import LBL_AR_ACR_EmptyState from "@salesforce/label/c.AR_ACR_EmptyState";
import LBL_AR_ACR_EnteredBy from "@salesforce/label/c.AR_ACR_EnteredBy";
import LBL_AR_ACR_ModifiedOnBy from "@salesforce/label/c.AR_ACR_ModifiedOnBy";
import LBL_AR_ACR_NoRate from "@salesforce/label/c.AR_ACR_NoRate";
import LBL_AR_ACR_On from "@salesforce/label/c.AR_ACR_On";
import LBL_AR_ACR_RateAdded from "@salesforce/label/c.AR_ACR_RateAdded";
import LBL_AR_ACR_RateCorrected from "@salesforce/label/c.AR_ACR_RateCorrected";
import LBL_AR_ACR_RateCountMany from "@salesforce/label/c.AR_ACR_RateCountMany";
import LBL_AR_ACR_RateCountOne from "@salesforce/label/c.AR_ACR_RateCountOne";
import LBL_AR_ACR_RateToEur from "@salesforce/label/c.AR_ACR_RateToEur";
import LBL_AR_ACR_StatusInForce from "@salesforce/label/c.AR_ACR_StatusInForce";
import LBL_AR_ACR_StatusReplaced from "@salesforce/label/c.AR_ACR_StatusReplaced";
import LBL_AR_ACR_Subtitle from "@salesforce/label/c.AR_ACR_Subtitle";
import LBL_AR_ACR_Title from "@salesforce/label/c.AR_ACR_Title";
import LBL_AR_App_ComingSoon from "@salesforce/label/c.AR_App_ComingSoon";
import LBL_AR_Common_Add from "@salesforce/label/c.AR_Common_Add";
import LBL_AR_Common_Currency from "@salesforce/label/c.AR_Common_Currency";
import LBL_AR_Common_EffectiveDate from "@salesforce/label/c.AR_Common_EffectiveDate";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Status from "@salesforce/label/c.AR_Common_Status";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";

const I18N = {
  AR_ACR_AddRate: LBL_AR_ACR_AddRate,
  AR_ACR_Correct: LBL_AR_ACR_Correct,
  AR_ACR_CorrectHelp: LBL_AR_ACR_CorrectHelp,
  AR_ACR_CorrectRate: LBL_AR_ACR_CorrectRate,
  AR_ACR_Corrected: LBL_AR_ACR_Corrected,
  AR_ACR_EmptyState: LBL_AR_ACR_EmptyState,
  AR_ACR_EnteredBy: LBL_AR_ACR_EnteredBy,
  AR_ACR_ModifiedOnBy: LBL_AR_ACR_ModifiedOnBy,
  AR_ACR_NoRate: LBL_AR_ACR_NoRate,
  AR_ACR_On: LBL_AR_ACR_On,
  AR_ACR_RateAdded: LBL_AR_ACR_RateAdded,
  AR_ACR_RateCorrected: LBL_AR_ACR_RateCorrected,
  AR_ACR_RateCountMany: LBL_AR_ACR_RateCountMany,
  AR_ACR_RateCountOne: LBL_AR_ACR_RateCountOne,
  AR_ACR_RateToEur: LBL_AR_ACR_RateToEur,
  AR_ACR_StatusInForce: LBL_AR_ACR_StatusInForce,
  AR_ACR_StatusReplaced: LBL_AR_ACR_StatusReplaced,
  AR_ACR_Subtitle: LBL_AR_ACR_Subtitle,
  AR_ACR_Title: LBL_AR_ACR_Title,
  AR_App_ComingSoon: LBL_AR_App_ComingSoon,
  AR_Common_Add: LBL_AR_Common_Add,
  AR_Common_Currency: LBL_AR_Common_Currency,
  AR_Common_EffectiveDate: LBL_AR_Common_EffectiveDate,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Status: LBL_AR_Common_Status,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle
};
const CURRENCY_OPTIONS = [
  { label: "GBP", value: "GBP" },
  { label: "CHF", value: "CHF" },
  { label: "CAD", value: "CAD" },
  { label: "MAD", value: "MAD" }
];

// Même défaut de locale, même famille (session 26 §3, cf. correctif session 23b sur l'onglet Grands
// Comptes) : `CreatedDate` arrivait en ISO brut (2026-08-19T18:56:46.000Z), `AR_Effective_Date__c`
// en AAAA-MM-JJ.
function formatFrenchDateTime(value) {
  if (!value) {
    return "—";
  }
  return new Date(value).toLocaleString("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

// `AR_Effective_Date__c` est un `Date` (pas `Datetime`, pas d'heure) : un `new Date("2026-08-19")`
// est interprété en UTC minuit puis reformaté en fuseau local, ce qui peut faire glisser le jour
// affiché — même piège que documenté dans arPriceMatrixSimulator.js pour le taux de change courant.
// Découpage manuel de la chaîne AAAA-MM-JJ pour l'éviter.
function formatFrenchDate(value) {
  if (!value) {
    return "—";
  }
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric"
  });
}

// Comparaison sur la date (AAAA-MM-JJ), pas sur l'instant : `effectiveDate` est un Date Salesforce,
// jamais d'heure à comparer à "aujourd'hui".
function toIsoDateString(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Onglet « Devises » (session 23, réunion du 10/08/2026 ; corrigible en place depuis la session 50,
 * cf. docs/50-taux-modifiables.md) : table de conversion. Deux gestes distincts et volontairement
 * non interchangeables — « Ajouter un taux » (évolution : nouvelle période) et « Corriger » (une
 * valeur mal saisie sur une période déjà enregistrée, devise et date d'effet non modifiables). La
 * conversion elle-même est hors périmètre (session 24).
 */
export default class ArAdminCurrencyRates extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  rates = [];
  currencyOptions = CURRENCY_OPTIONS;

  showForm = false;
  formMode; // 'add' | 'correct'
  formId;
  formCurrencyCode;
  formRate;
  formEffectiveDate;

  connectedCallback() {
    this.loadRates();
  }

  async loadRates() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      const rows = await getCurrencyRates();
      const todayIso = toIsoDateString(new Date());
      const currentSeen = new Set();
      this.rates = rows.map((row) => {
        let rowStatus;
        if (row.effectiveDate > todayIso) {
          rowStatus = "upcoming";
        } else if (!currentSeen.has(row.currencyCode)) {
          currentSeen.add(row.currencyCode);
          rowStatus = "current";
        } else {
          rowStatus = "replaced";
        }
        const isCorrected =
          !!row.lastModifiedDate &&
          !!row.createdDate &&
          row.lastModifiedDate !== row.createdDate;
        return {
          ...row,
          formattedEffectiveDate: formatFrenchDate(row.effectiveDate),
          formattedCreatedDate: formatFrenchDateTime(row.createdDate),
          formattedLastModifiedDate: formatFrenchDateTime(row.lastModifiedDate),
          rowStatus,
          statusLabel: this.statusLabel(rowStatus),
          statusClass: `rate-status-badge rate-status-${rowStatus}`,
          isCorrected,
          correctedNote: formatLabel(
            I18N.AR_ACR_ModifiedOnBy,
            formatFrenchDateTime(row.lastModifiedDate),
            row.lastModifiedByName
          )
        };
      });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  statusLabel(status) {
    switch (status) {
      case "current":
        return I18N.AR_ACR_StatusInForce;
      case "upcoming":
        return I18N.AR_App_ComingSoon;
      default:
        return I18N.AR_ACR_StatusReplaced;
    }
  }

  get subtitleLabel() {
    return formatLabel(I18N.AR_ACR_Subtitle, this.countLabel);
  }

  get countLabel() {
    const n = this.rates.length;
    return n === 0
      ? I18N.AR_ACR_NoRate
      : pluralLabel(n, I18N.AR_ACR_RateCountOne, I18N.AR_ACR_RateCountMany);
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.rates.length === 0;
  }

  get isCorrectMode() {
    return this.formMode === "correct";
  }

  get isAddMode() {
    return this.formMode === "add";
  }

  get formTitle() {
    return this.isCorrectMode ? I18N.AR_ACR_CorrectRate : I18N.AR_ACR_AddRate;
  }

  get saveButtonLabel() {
    return this.isCorrectMode ? I18N.AR_ACR_Correct : I18N.AR_Common_Add;
  }

  handleAdd() {
    this.formMode = "add";
    this.formId = undefined;
    this.formCurrencyCode = undefined;
    this.formRate = undefined;
    this.formEffectiveDate = undefined;
    this.showForm = true;
  }

  handleCorrect(event) {
    const rateId = event.currentTarget.dataset.id;
    const row = this.rates.find((r) => r.id === rateId);
    if (!row) {
      return;
    }
    this.formMode = "correct";
    this.formId = row.id;
    this.formCurrencyCode = row.currencyCode;
    this.formRate = row.rateToEur;
    this.formEffectiveDate = row.effectiveDate;
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleCurrencyChange(event) {
    this.formCurrencyCode = event.target.value;
  }
  handleRateChange(event) {
    this.formRate = event.target.value;
  }
  handleEffectiveDateChange(event) {
    this.formEffectiveDate = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      if (this.isCorrectMode) {
        await updateCurrencyRateApex({
          rateId: this.formId,
          rateToEur: this.formRate
        });
        this.showToast(
          I18N.AR_Common_SuccessTitle,
          I18N.AR_ACR_RateCorrected,
          "success"
        );
      } else {
        await addCurrencyRateApex({
          currencyCode: this.formCurrencyCode,
          rateToEur: this.formRate,
          effectiveDate: this.formEffectiveDate
        });
        this.showToast(
          I18N.AR_Common_SuccessTitle,
          I18N.AR_ACR_RateAdded,
          "success"
        );
      }
      this.showForm = false;
      await this.loadRates();
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}