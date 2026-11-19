import { LightningElement, wire } from "lwc";
import { getPicklistValuesByRecordType } from "lightning/uiObjectInfoApi";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getNearshoreReferentials from "@salesforce/apex/AR_AdminReferentialService.getNearshoreReferentials";
import saveNearshoreReferentialApex from "@salesforce/apex/AR_AdminReferentialService.saveNearshoreReferential";
import deleteNearshoreReferentialApex from "@salesforce/apex/AR_AdminReferentialService.deleteNearshoreReferential";
import { pluralLabel } from "c/arI18n";
import LBL_AR_ANR_AddCountry from "@salesforce/label/c.AR_ANR_AddCountry";
import LBL_AR_ANR_DailyCost from "@salesforce/label/c.AR_ANR_DailyCost";
import LBL_AR_ANR_Deleted from "@salesforce/label/c.AR_ANR_Deleted";
import LBL_AR_ANR_Empty from "@salesforce/label/c.AR_ANR_Empty";
import LBL_AR_ANR_Seniority from "@salesforce/label/c.AR_ANR_Seniority";
import LBL_AR_ANR_SeniorityDefault from "@salesforce/label/c.AR_ANR_SeniorityDefault";
import LBL_AR_ANR_Saved from "@salesforce/label/c.AR_ANR_Saved";
import LBL_AR_ANR_Title from "@salesforce/label/c.AR_ANR_Title";
import LBL_AR_Common_Country from "@salesforce/label/c.AR_Common_Country";
import LBL_AR_Common_CountryCountMany from "@salesforce/label/c.AR_Common_CountryCountMany";
import LBL_AR_Common_CountryCountOne from "@salesforce/label/c.AR_Common_CountryCountOne";
import LBL_AR_Common_Currency from "@salesforce/label/c.AR_Common_Currency";
import LBL_AR_Common_Delete from "@salesforce/label/c.AR_Common_Delete";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_NoCountry from "@salesforce/label/c.AR_Common_NoCountry";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";

const I18N = {
  AR_ANR_AddCountry: LBL_AR_ANR_AddCountry,
  AR_ANR_DailyCost: LBL_AR_ANR_DailyCost,
  AR_ANR_Deleted: LBL_AR_ANR_Deleted,
  AR_ANR_Empty: LBL_AR_ANR_Empty,
  AR_ANR_Saved: LBL_AR_ANR_Saved,
  AR_ANR_Seniority: LBL_AR_ANR_Seniority,
  AR_ANR_SeniorityDefault: LBL_AR_ANR_SeniorityDefault,
  AR_ANR_Title: LBL_AR_ANR_Title,
  AR_Common_Country: LBL_AR_Common_Country,
  AR_Common_CountryCountMany: LBL_AR_Common_CountryCountMany,
  AR_Common_CountryCountOne: LBL_AR_Common_CountryCountOne,
  AR_Common_Currency: LBL_AR_Common_Currency,
  AR_Common_Delete: LBL_AR_Common_Delete,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_NoCountry: LBL_AR_Common_NoCountry,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle
};
// Valeur stockée de la séniorité « Défaut » : technique, indépendante de la langue.
const DEFAULT_SENIORITY = "DEFAULT";
// Même source que la séniorité de la matrice (arPriceMatrixSimulator, wiredSeniorityPicklist).
const SENIORITY_OBJECT_API_NAME = "cxsrec__cxsCandidate__c";
const SENIORITY_RECORD_TYPE_ID = "01209000000NPmDAAW";
const CURRENCY_OPTIONS = [
  { label: "EUR", value: "EUR" },
  { label: "GBP", value: "GBP" },
  { label: "CHF", value: "CHF" },
  { label: "CAD", value: "CAD" },
  { label: "MAD", value: "MAD" }
];

/** Onglet « Nearshore » (session 23) : CRUD de AR_Nearshore_Referential__c, objet déjà livré
 * (session 2), écran manquant jusqu'à cette session. Devise par pays (session 24) : le CJM n'est
 * plus implicitement en euros, cf. AR_PricingMatrixService (bloque si incohérente avec la matrice). */
export default class ArAdminNearshoreReferential extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  rows = [];
  currencyOptions = CURRENCY_OPTIONS;

  showForm = false;
  formId;
  formCountry;
  formSeniority;
  formDailyRate;
  formCurrencyCode = "EUR";

  seniorityValues = [];

  @wire(getPicklistValuesByRecordType, {
    objectApiName: SENIORITY_OBJECT_API_NAME,
    recordTypeId: SENIORITY_RECORD_TYPE_ID
  })
  wiredSeniorityPicklist({ data }) {
    if (data) {
      this.seniorityValues = (
        data.picklistFieldValues.TP_Seniority__c.values || []
      ).map((v) => ({ label: v.label, value: v.value }));
    }
  }

  get seniorityOptions() {
    return [
      { label: I18N.AR_ANR_SeniorityDefault, value: DEFAULT_SENIORITY },
      ...this.seniorityValues
    ];
  }

  seniorityLabel(value) {
    if (value === DEFAULT_SENIORITY) {
      return I18N.AR_ANR_SeniorityDefault;
    }
    return value || "";
  }

  get displayRows() {
    return this.rows.map((r) => ({
      ...r,
      seniorityDisplay: this.seniorityLabel(r.seniority)
    }));
  }

  connectedCallback() {
    this.loadRows();
  }

  async loadRows() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      this.rows = await getNearshoreReferentials();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  // Compte les pays distincts, pas les lignes : une ligne = un pays × une séniorité.
  get countLabel() {
    const n = new Set(this.rows.map((r) => r.country).filter(Boolean)).size;
    return n === 0
      ? I18N.AR_Common_NoCountry
      : pluralLabel(
          n,
          I18N.AR_Common_CountryCountOne,
          I18N.AR_Common_CountryCountMany
        );
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.rows.length === 0;
  }

  handleAdd() {
    this.formId = undefined;
    this.formCountry = undefined;
    this.formSeniority = DEFAULT_SENIORITY;
    this.formDailyRate = undefined;
    this.formCurrencyCode = "EUR";
    this.showForm = true;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.rows.find((r) => r.id === id);
    if (!row) {
      return;
    }
    this.formId = row.id;
    this.formCountry = row.country;
    this.formSeniority = row.seniority;
    this.formDailyRate = row.dailyRate;
    this.formCurrencyCode = row.currencyCode || "EUR";
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleCountryChange(event) {
    this.formCountry = event.target.value;
  }
  handleSeniorityChange(event) {
    this.formSeniority = event.detail.value;
  }
  handleRateChange(event) {
    this.formDailyRate = event.target.value;
  }
  handleCurrencyChange(event) {
    this.formCurrencyCode = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveNearshoreReferentialApex({
        recordId: this.formId,
        country: this.formCountry,
        seniority: this.formSeniority,
        dailyRate: this.formDailyRate,
        currencyCode: this.formCurrencyCode
      });
      this.showForm = false;
      await this.loadRows();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_ANR_Saved, "success");
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

  async handleDelete(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.rows.find((r) => r.id === id);
    // Rien n'est appelé côté serveur sans confirmation.
    if (
      !row ||
      !(await confirmAdminDelete(
        `${row.country} · ${this.seniorityLabel(row.seniority)}`
      ))
    ) {
      return;
    }
    try {
      await deleteNearshoreReferentialApex({ recordId: id });
      await this.loadRows();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_ANR_Deleted,
        "success"
      );
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}