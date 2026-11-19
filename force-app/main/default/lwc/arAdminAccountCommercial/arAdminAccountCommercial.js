import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAccountCommercialData from "@salesforce/apex/AR_AdminCommercialService.getAccountCommercialData";
import saveAccountCommercialDataApex from "@salesforce/apex/AR_AdminCommercialService.saveAccountCommercialData";
import deleteAccountCommercialDataApex from "@salesforce/apex/AR_AdminCommercialService.deleteAccountCommercialData";
import getPtfTemplateOptions from "@salesforce/apex/AR_AdminCommercialService.getPtfTemplateOptions";
import searchAccounts from "@salesforce/apex/AR_AdminReferentialService.searchAccounts";
import {
  AUTO_VALUE,
  AUTO_LABEL,
  buildComboOptions,
  fromComboValue,
  isUnknownCode,
  toComboValue
} from "c/arPtfTemplateUtils";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_AAC_AddAccount from "@salesforce/label/c.AR_AAC_AddAccount";
import LBL_AR_AAC_CountMany from "@salesforce/label/c.AR_AAC_CountMany";
import LBL_AR_AAC_CountOne from "@salesforce/label/c.AR_AAC_CountOne";
import LBL_AR_AAC_DefaultRfaColumn from "@salesforce/label/c.AR_AAC_DefaultRfaColumn";
import LBL_AR_AAC_DefaultRfaPercent from "@salesforce/label/c.AR_AAC_DefaultRfaPercent";
import LBL_AR_AAC_Deleted from "@salesforce/label/c.AR_AAC_Deleted";
import LBL_AR_AAC_Empty from "@salesforce/label/c.AR_AAC_Empty";
import LBL_AR_AAC_FrameworkContract from "@salesforce/label/c.AR_AAC_FrameworkContract";
import LBL_AR_AAC_FrameworkContractRef from "@salesforce/label/c.AR_AAC_FrameworkContractRef";
import LBL_AR_AAC_NoAccount from "@salesforce/label/c.AR_AAC_NoAccount";
import LBL_AR_AAC_PriceGrid from "@salesforce/label/c.AR_AAC_PriceGrid";
import LBL_AR_AAC_Saved from "@salesforce/label/c.AR_AAC_Saved";
import LBL_AR_AAC_SpecificParameters from "@salesforce/label/c.AR_AAC_SpecificParameters";
import LBL_AR_AAC_Title from "@salesforce/label/c.AR_AAC_Title";
import LBL_AR_Common_Account from "@salesforce/label/c.AR_Common_Account";
import LBL_AR_Common_Delete from "@salesforce/label/c.AR_Common_Delete";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_PtfTemplateAutoField from "@salesforce/label/c.AR_Common_PtfTemplateAutoField";
import LBL_AR_Common_SearchAccount from "@salesforce/label/c.AR_Common_SearchAccount";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_TemplateListUnavailable from "@salesforce/label/c.AR_Common_TemplateListUnavailable";
import LBL_AR_Common_UnknownTemplateCode from "@salesforce/label/c.AR_Common_UnknownTemplateCode";

const I18N = {
  AR_AAC_AddAccount: LBL_AR_AAC_AddAccount,
  AR_AAC_CountMany: LBL_AR_AAC_CountMany,
  AR_AAC_CountOne: LBL_AR_AAC_CountOne,
  AR_AAC_DefaultRfaColumn: LBL_AR_AAC_DefaultRfaColumn,
  AR_AAC_DefaultRfaPercent: LBL_AR_AAC_DefaultRfaPercent,
  AR_AAC_Deleted: LBL_AR_AAC_Deleted,
  AR_AAC_Empty: LBL_AR_AAC_Empty,
  AR_AAC_FrameworkContract: LBL_AR_AAC_FrameworkContract,
  AR_AAC_FrameworkContractRef: LBL_AR_AAC_FrameworkContractRef,
  AR_AAC_NoAccount: LBL_AR_AAC_NoAccount,
  AR_AAC_PriceGrid: LBL_AR_AAC_PriceGrid,
  AR_AAC_Saved: LBL_AR_AAC_Saved,
  AR_AAC_SpecificParameters: LBL_AR_AAC_SpecificParameters,
  AR_AAC_Title: LBL_AR_AAC_Title,
  AR_Common_Account: LBL_AR_Common_Account,
  AR_Common_Delete: LBL_AR_Common_Delete,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_PtfTemplateAutoField: LBL_AR_Common_PtfTemplateAutoField,
  AR_Common_SearchAccount: LBL_AR_Common_SearchAccount,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_TemplateListUnavailable: LBL_AR_Common_TemplateListUnavailable,
  AR_Common_UnknownTemplateCode: LBL_AR_Common_UnknownTemplateCode
};
/**
 * Onglet « Données client » (session 23, réunion du 10/08/2026) : RFA par défaut (préremplit
 * arPriceMatrixSimulator), contrat-cadre, grille tarifaire, paramètres spécifiques. Administration
 * manuelle assumée — pas de reprise automatique depuis d'autres systèmes.
 */
export default class ArAdminAccountCommercial extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  rows = [];

  showForm = false;
  formId;
  formAccountId;
  formAccountLabel = "";
  formAccountCity = "";
  formDefaultRfaPercent;
  formFrameworkAgreementReference;
  formPricingGridNotes;
  formSpecialTerms;
  formPtfTemplateCode;
  // Gabarits de PTF servis par le serveur (même carte que la résolution) ; null tant que non chargés.
  templateOptions = null;
  templateOptionsError;
  accountSearchTerm = "";
  accountResults = [];
  _searchDebounce;

  connectedCallback() {
    this.loadRows();
    this.loadTemplateOptions();
  }

  /** Catch classé « afficher » (CLAUDE.md, session 34) : un échec n'est jamais pris pour une
   * liste vide — le formulaire l'écrit sous le champ, la valeur existante reste conservée. */
  async loadTemplateOptions() {
    this.templateOptionsError = undefined;
    try {
      this.templateOptions = (await getPtfTemplateOptions()) || null;
    } catch (error) {
      this.templateOptions = null;
      this.templateOptionsError = this.reduceError(error);
    }
  }

  get templateComboOptions() {
    if (this.templateOptionsError) {
      const options = [{ value: AUTO_VALUE, label: AUTO_LABEL }];
      if (this.formPtfTemplateCode) {
        options.push({
          value: this.formPtfTemplateCode,
          label: this.formPtfTemplateCode
        });
      }
      return options;
    }
    return buildComboOptions(this.templateOptions, this.formPtfTemplateCode);
  }

  get templateComboValue() {
    return toComboValue(this.formPtfTemplateCode);
  }

  get templateCodeIsUnknown() {
    return (
      !this.templateOptionsError &&
      this.templateOptions !== null &&
      isUnknownCode(this.formPtfTemplateCode, this.templateOptions)
    );
  }

  async loadRows() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      this.rows = await getAccountCommercialData();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get unknownTemplateCodeMessage() {
    return formatLabel(
      I18N.AR_Common_UnknownTemplateCode,
      this.formPtfTemplateCode
    );
  }

  get templateListErrorMessage() {
    return formatLabel(
      I18N.AR_Common_TemplateListUnavailable,
      this.templateOptionsError
    );
  }

  get countLabel() {
    const n = this.rows.length;
    return n === 0
      ? I18N.AR_AAC_NoAccount
      : pluralLabel(n, I18N.AR_AAC_CountOne, I18N.AR_AAC_CountMany);
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.rows.length === 0;
  }

  get hasAccountResults() {
    return this.accountResults.length > 0;
  }

  handleAdd() {
    this.formId = undefined;
    this.formAccountId = undefined;
    this.formAccountLabel = "";
    this.formAccountCity = "";
    this.formDefaultRfaPercent = undefined;
    this.formFrameworkAgreementReference = undefined;
    this.formPricingGridNotes = undefined;
    this.formSpecialTerms = undefined;
    this.formPtfTemplateCode = undefined;
    this.accountSearchTerm = "";
    this.accountResults = [];
    this.showForm = true;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.rows.find((r) => r.id === id);
    if (!row) {
      return;
    }
    this.formId = row.id;
    this.formAccountId = row.accountId;
    this.formAccountLabel = row.accountName;
    this.formAccountCity = "";
    this.formDefaultRfaPercent = row.defaultRfaPercent;
    this.formFrameworkAgreementReference = row.frameworkAgreementReference;
    this.formPricingGridNotes = row.pricingGridNotes;
    this.formSpecialTerms = row.specialTerms;
    this.formPtfTemplateCode = row.ptfTemplateCode;
    this.accountSearchTerm = "";
    this.accountResults = [];
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleAccountSearchChange(event) {
    const term = event.target.value;
    this.accountSearchTerm = term;
    clearTimeout(this._searchDebounce);
    if (term.length < 2) {
      this.accountResults = [];
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce de recherche, même pattern que arPriceMatrixSimulator.
    this._searchDebounce = setTimeout(() => {
      searchAccounts({ searchTerm: term })
        .then((results) => {
          this.accountResults = results;
        })
        .catch(() => {
          // Avalé délibérément (session 34, revue des .catch silencieux) : une recherche de typeahead
          // qui échoue se traduit normalement par "aucun résultat" — l'utilisateur peut retaper, rien
          // de métier n'est masqué (contrairement à une liste de référence qui resterait vide sans
          // explication).
          this.accountResults = [];
        });
    }, 300);
  }

  handleSelectAccount(event) {
    const id = event.currentTarget.dataset.id;
    const opt = this.accountResults.find((a) => a.accountId === id);
    this.formAccountId = id;
    this.formAccountLabel = opt ? opt.label : id;
    // Session 279 : la ville distingue les homonymes (filiales, sites), aussi une fois le compte retenu.
    this.formAccountCity = opt && opt.city ? opt.city : "";
    this.accountResults = [];
    this.accountSearchTerm = "";
  }

  handleRfaChange(event) {
    this.formDefaultRfaPercent = event.target.value;
  }
  handleFrameworkChange(event) {
    this.formFrameworkAgreementReference = event.target.value;
  }
  handleGridNotesChange(event) {
    this.formPricingGridNotes = event.target.value;
  }
  handleSpecialTermsChange(event) {
    this.formSpecialTerms = event.target.value;
  }
  handlePtfTemplateCodeChange(event) {
    this.formPtfTemplateCode = fromComboValue(event.detail.value);
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveAccountCommercialDataApex({
        dtoJson: JSON.stringify({
          id: this.formId,
          accountId: this.formAccountId,
          defaultRfaPercent: this.formDefaultRfaPercent,
          frameworkAgreementReference: this.formFrameworkAgreementReference,
          pricingGridNotes: this.formPricingGridNotes,
          specialTerms: this.formSpecialTerms,
          ptfTemplateCode: this.formPtfTemplateCode
        })
      });
      this.showForm = false;
      await this.loadRows();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_AAC_Saved, "success");
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
    if (!row || !(await confirmAdminDelete(row.accountName))) {
      return;
    }
    try {
      await deleteAccountCommercialDataApex({ recordId: id });
      await this.loadRows();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_AAC_Deleted,
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