import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getVieReferentials from "@salesforce/apex/AR_AdminReferentialService.getVieReferentials";
import saveVieReferentialApex from "@salesforce/apex/AR_AdminReferentialService.saveVieReferential";
import deleteVieReferentialApex from "@salesforce/apex/AR_AdminReferentialService.deleteVieReferential";
import { pluralLabel } from "c/arI18n";
import LBL_AR_AVR_AddCountry from "@salesforce/label/c.AR_AVR_AddCountry";
import LBL_AR_AVR_DailyAllowance from "@salesforce/label/c.AR_AVR_DailyAllowance";
import LBL_AR_AVR_Deleted from "@salesforce/label/c.AR_AVR_Deleted";
import LBL_AR_AVR_Empty from "@salesforce/label/c.AR_AVR_Empty";
import LBL_AR_AVR_Saved from "@salesforce/label/c.AR_AVR_Saved";
import LBL_AR_AVR_Title from "@salesforce/label/c.AR_AVR_Title";
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
  AR_AVR_AddCountry: LBL_AR_AVR_AddCountry,
  AR_AVR_DailyAllowance: LBL_AR_AVR_DailyAllowance,
  AR_AVR_Deleted: LBL_AR_AVR_Deleted,
  AR_AVR_Empty: LBL_AR_AVR_Empty,
  AR_AVR_Saved: LBL_AR_AVR_Saved,
  AR_AVR_Title: LBL_AR_AVR_Title,
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
const CURRENCY_OPTIONS = [
  { label: "EUR", value: "EUR" },
  { label: "GBP", value: "GBP" },
  { label: "CHF", value: "CHF" },
  { label: "CAD", value: "CAD" },
  { label: "MAD", value: "MAD" }
];

/** Onglet « VIE » (session 23) : CRUD de AR_VIE_Referential__c, objet déjà livré (session 2),
 * écran manquant jusqu'à cette session. Devise par pays (session 24) : l'indemnité n'est plus
 * implicitement en euros, cf. AR_PricingMatrixService (bloque si incohérente avec la matrice). */
export default class ArAdminVieReferential extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  rows = [];
  currencyOptions = CURRENCY_OPTIONS;

  showForm = false;
  formId;
  formCountry;
  formDailyAllowance;
  formCurrencyCode = "EUR";

  connectedCallback() {
    this.loadRows();
  }

  async loadRows() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      this.rows = await getVieReferentials();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get countLabel() {
    const n = this.rows.length;
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
    this.formDailyAllowance = undefined;
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
    this.formDailyAllowance = row.dailyAllowance;
    this.formCurrencyCode = row.currencyCode || "EUR";
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleCountryChange(event) {
    this.formCountry = event.target.value;
  }
  handleAllowanceChange(event) {
    this.formDailyAllowance = event.target.value;
  }
  handleCurrencyChange(event) {
    this.formCurrencyCode = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveVieReferentialApex({
        recordId: this.formId,
        country: this.formCountry,
        dailyAllowance: this.formDailyAllowance,
        currencyCode: this.formCurrencyCode
      });
      this.showForm = false;
      await this.loadRows();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_AVR_Saved, "success");
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
    if (!row || !(await confirmAdminDelete(row.country))) {
      return;
    }
    try {
      await deleteVieReferentialApex({ recordId: id });
      await this.loadRows();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_AVR_Deleted,
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