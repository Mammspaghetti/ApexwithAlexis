import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getCorridors from "@salesforce/apex/AR_AdminReferentialService.getCorridors";
import saveCorridorApex from "@salesforce/apex/AR_AdminReferentialService.saveCorridor";
import deleteCorridorApex from "@salesforce/apex/AR_AdminReferentialService.deleteCorridor";
import searchAccounts from "@salesforce/apex/AR_AdminReferentialService.searchAccounts";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_ACO_AddKeyAccount from "@salesforce/label/c.AR_ACO_AddKeyAccount";
import LBL_AR_ACO_CountMany from "@salesforce/label/c.AR_ACO_CountMany";
import LBL_AR_ACO_CountOne from "@salesforce/label/c.AR_ACO_CountOne";
import LBL_AR_ACO_Deleted from "@salesforce/label/c.AR_ACO_Deleted";
import LBL_AR_ACO_Empty from "@salesforce/label/c.AR_ACO_Empty";
import LBL_AR_ACO_Heading from "@salesforce/label/c.AR_ACO_Heading";
import LBL_AR_ACO_NoCorridor from "@salesforce/label/c.AR_ACO_NoCorridor";
import LBL_AR_ACO_Saved from "@salesforce/label/c.AR_ACO_Saved";
import LBL_AR_ACO_Title from "@salesforce/label/c.AR_ACO_Title";
import LBL_AR_Common_Account from "@salesforce/label/c.AR_Common_Account";
import LBL_AR_Common_Delete from "@salesforce/label/c.AR_Common_Delete";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_FloorPercent from "@salesforce/label/c.AR_Common_FloorPercent";
import LBL_AR_Common_IdealPercent from "@salesforce/label/c.AR_Common_IdealPercent";
import LBL_AR_Common_ModifiedBy from "@salesforce/label/c.AR_Common_ModifiedBy";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_SearchAccount from "@salesforce/label/c.AR_Common_SearchAccount";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_TargetPercent from "@salesforce/label/c.AR_Common_TargetPercent";

const I18N = {
  AR_ACO_AddKeyAccount: LBL_AR_ACO_AddKeyAccount,
  AR_ACO_CountMany: LBL_AR_ACO_CountMany,
  AR_ACO_CountOne: LBL_AR_ACO_CountOne,
  AR_ACO_Deleted: LBL_AR_ACO_Deleted,
  AR_ACO_Empty: LBL_AR_ACO_Empty,
  AR_ACO_Heading: LBL_AR_ACO_Heading,
  AR_ACO_NoCorridor: LBL_AR_ACO_NoCorridor,
  AR_ACO_Saved: LBL_AR_ACO_Saved,
  AR_ACO_Title: LBL_AR_ACO_Title,
  AR_Common_Account: LBL_AR_Common_Account,
  AR_Common_Delete: LBL_AR_Common_Delete,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_FloorPercent: LBL_AR_Common_FloorPercent,
  AR_Common_IdealPercent: LBL_AR_Common_IdealPercent,
  AR_Common_ModifiedBy: LBL_AR_Common_ModifiedBy,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_SearchAccount: LBL_AR_Common_SearchAccount,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_TargetPercent: LBL_AR_Common_TargetPercent
};
// Session 252 : « Modifié par <Nom> le JJ/MM/AAAA », sous le nom du compte. Date seule, formatée en
// fr-FR : la date ISO brute n'arrive jamais à l'écran (même défaut que la session 23b).
function formatFrenchDate(value) {
  if (!value) {
    return "—";
  }
  return new Date(value).toLocaleDateString("fr-FR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  });
}

/** Onglet « Grands Comptes » (session 23) : CRUD de AR_Account_Corridor__c, objet déjà livré,
 * écran manquant jusqu'à cette session. */
export default class ArAdminCorridors extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  corridors = [];

  showForm = false;
  formId;
  formAccountId;
  formAccountLabel = "";
  formAccountCity = "";
  formFloor;
  formTarget;
  formIdeal;
  accountSearchTerm = "";
  accountResults = [];
  _searchDebounce;

  connectedCallback() {
    this.loadCorridors();
  }

  async loadCorridors() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      const rows = await getCorridors();
      this.corridors = rows.map((row) => ({
        ...row,
        modifiedLine: formatLabel(
          I18N.AR_Common_ModifiedBy,
          row.lastModifiedByName,
          formatFrenchDate(row.lastModifiedDate)
        )
      }));
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get countLabel() {
    const n = this.corridors.length;
    return n === 0
      ? I18N.AR_ACO_NoCorridor
      : pluralLabel(n, I18N.AR_ACO_CountOne, I18N.AR_ACO_CountMany);
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.corridors.length === 0;
  }

  get hasAccountResults() {
    return this.accountResults.length > 0;
  }

  handleAdd() {
    this.formId = undefined;
    this.formAccountId = undefined;
    this.formAccountLabel = "";
    this.formAccountCity = "";
    this.formFloor = undefined;
    this.formTarget = undefined;
    this.formIdeal = undefined;
    this.accountSearchTerm = "";
    this.accountResults = [];
    this.showForm = true;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.corridors.find((c) => c.id === id);
    if (!row) {
      return;
    }
    this.formId = row.id;
    this.formAccountId = row.accountId;
    this.formAccountLabel = row.accountName;
    this.formAccountCity = "";
    this.formFloor = row.floorPercent;
    this.formTarget = row.targetPercent;
    this.formIdeal = row.idealPercent;
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
          // Avalé délibérément (session 34, revue des .catch silencieux) : même raisonnement que
          // arAdminAccountCommercial — un typeahead qui échoue rend "aucun résultat", rien de métier
          // n'est masqué.
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

  handleFloorChange(event) {
    this.formFloor = event.target.value;
  }
  handleTargetChange(event) {
    this.formTarget = event.target.value;
  }
  handleIdealChange(event) {
    this.formIdeal = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveCorridorApex({
        recordId: this.formId,
        accountId: this.formAccountId,
        floorPercent: this.formFloor,
        targetPercent: this.formTarget,
        idealPercent: this.formIdeal
      });
      this.showForm = false;
      await this.loadCorridors();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_ACO_Saved, "success");
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
    const row = this.corridors.find((r) => r.id === id);
    // Rien n'est appelé côté serveur sans confirmation.
    if (!row || !(await confirmAdminDelete(row.accountName))) {
      return;
    }
    try {
      await deleteCorridorApex({ recordId: id });
      await this.loadCorridors();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_ACO_Deleted,
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