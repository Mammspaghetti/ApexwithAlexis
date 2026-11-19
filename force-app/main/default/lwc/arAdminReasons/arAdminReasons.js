import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAllReasonsForAdmin from "@salesforce/apex/AR_ReasonService.getAllReasonsForAdmin";
import saveReasonApex from "@salesforce/apex/AR_ReasonService.saveReason";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_ARS_AddReason from "@salesforce/label/c.AR_ARS_AddReason";
import LBL_AR_ARS_ApplicableToDerogation from "@salesforce/label/c.AR_ARS_ApplicableToDerogation";
import LBL_AR_ARS_ApplicableToVersionChange from "@salesforce/label/c.AR_ARS_ApplicableToVersionChange";
import LBL_AR_ARS_CountMany from "@salesforce/label/c.AR_ARS_CountMany";
import LBL_AR_ARS_CountOne from "@salesforce/label/c.AR_ARS_CountOne";
import LBL_AR_ARS_Empty from "@salesforce/label/c.AR_ARS_Empty";
import LBL_AR_ARS_Heading from "@salesforce/label/c.AR_ARS_Heading";
import LBL_AR_ARS_NoReason from "@salesforce/label/c.AR_ARS_NoReason";
import LBL_AR_ARS_Saved from "@salesforce/label/c.AR_ARS_Saved";
import LBL_AR_ARS_Subtitle from "@salesforce/label/c.AR_ARS_Subtitle";
import LBL_AR_ARS_Title from "@salesforce/label/c.AR_ARS_Title";
import LBL_AR_Common_Active from "@salesforce/label/c.AR_Common_Active";
import LBL_AR_Common_DisplayOrder from "@salesforce/label/c.AR_Common_DisplayOrder";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Inactive from "@salesforce/label/c.AR_Common_Inactive";
import LBL_AR_Common_LabelField from "@salesforce/label/c.AR_Common_LabelField";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_No from "@salesforce/label/c.AR_Common_No";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_Version from "@salesforce/label/c.AR_Common_Version";
import LBL_AR_Common_Yes from "@salesforce/label/c.AR_Common_Yes";
import LBL_AR_DRG_PanelTitle from "@salesforce/label/c.AR_DRG_PanelTitle";

const I18N = {
  AR_ARS_AddReason: LBL_AR_ARS_AddReason,
  AR_ARS_ApplicableToDerogation: LBL_AR_ARS_ApplicableToDerogation,
  AR_ARS_ApplicableToVersionChange: LBL_AR_ARS_ApplicableToVersionChange,
  AR_ARS_CountMany: LBL_AR_ARS_CountMany,
  AR_ARS_CountOne: LBL_AR_ARS_CountOne,
  AR_ARS_Empty: LBL_AR_ARS_Empty,
  AR_ARS_Heading: LBL_AR_ARS_Heading,
  AR_ARS_NoReason: LBL_AR_ARS_NoReason,
  AR_ARS_Saved: LBL_AR_ARS_Saved,
  AR_ARS_Subtitle: LBL_AR_ARS_Subtitle,
  AR_ARS_Title: LBL_AR_ARS_Title,
  AR_Common_Active: LBL_AR_Common_Active,
  AR_Common_DisplayOrder: LBL_AR_Common_DisplayOrder,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Inactive: LBL_AR_Common_Inactive,
  AR_Common_LabelField: LBL_AR_Common_LabelField,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_No: LBL_AR_Common_No,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_Version: LBL_AR_Common_Version,
  AR_Common_Yes: LBL_AR_Common_Yes,
  AR_DRG_PanelTitle: LBL_AR_DRG_PanelTitle
};
/** Onglet « Motifs » (session 23) : administration du catalogue AR_Reason__c (session 22) — liste
 * complète y compris les motifs désactivés, activer/désactiver plutôt que supprimer. */
export default class ArAdminReasons extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  reasons = [];

  showForm = false;
  formId;
  formLabel;
  formAppliesToDerogation = false;
  formAppliesToVersion = false;
  formActive = true;
  formSortOrder;

  connectedCallback() {
    this.loadReasons();
  }

  async loadReasons() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      this.reasons = await getAllReasonsForAdmin();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get subtitleLabel() {
    return formatLabel(I18N.AR_ARS_Subtitle, this.countLabel);
  }

  get countLabel() {
    const n = this.reasons.length;
    return n === 0
      ? I18N.AR_ARS_NoReason
      : pluralLabel(n, I18N.AR_ARS_CountOne, I18N.AR_ARS_CountMany);
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.reasons.length === 0;
  }

  handleAdd() {
    this.formId = undefined;
    this.formLabel = undefined;
    this.formAppliesToDerogation = true;
    this.formAppliesToVersion = true;
    this.formActive = true;
    this.formSortOrder = undefined;
    this.showForm = true;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.reasons.find((r) => r.id === id);
    if (!row) {
      return;
    }
    this.formId = row.id;
    this.formLabel = row.label;
    this.formAppliesToDerogation = row.appliesToDerogation;
    this.formAppliesToVersion = row.appliesToVersion;
    this.formActive = row.active;
    this.formSortOrder = row.sortOrder;
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleLabelChange(event) {
    this.formLabel = event.target.value;
  }
  handleAppliesToDerogationChange(event) {
    this.formAppliesToDerogation = event.target.checked;
  }
  handleAppliesToVersionChange(event) {
    this.formAppliesToVersion = event.target.checked;
  }
  handleActiveChange(event) {
    this.formActive = event.target.checked;
  }
  handleSortOrderChange(event) {
    this.formSortOrder = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveReasonApex({
        recordId: this.formId,
        label: this.formLabel,
        appliesToDerogation: this.formAppliesToDerogation,
        appliesToVersion: this.formAppliesToVersion,
        active: this.formActive,
        sortOrder: this.formSortOrder
      });
      this.showForm = false;
      await this.loadReasons();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_ARS_Saved, "success");
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