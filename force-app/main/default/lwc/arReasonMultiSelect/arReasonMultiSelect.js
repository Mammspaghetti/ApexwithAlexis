import { LightningElement, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import getReasonOptions from "@salesforce/apex/AR_ReasonService.getReasonOptions";
import { formatLabel } from "c/arI18n";
import LBL_AR_Common_Reasons from "@salesforce/label/c.AR_Common_Reasons";
import LBL_AR_RMS_LoadError from "@salesforce/label/c.AR_RMS_LoadError";
import LBL_AR_RMS_NoReason from "@salesforce/label/c.AR_RMS_NoReason";

const I18N = {
  AR_Common_Reasons: LBL_AR_Common_Reasons,
  AR_RMS_LoadError: LBL_AR_RMS_LoadError,
  AR_RMS_NoReason: LBL_AR_RMS_NoReason
};
/**
 * Sélecteur de motifs standardisés, cumulable (session 22 — fin de la saisie libre comme seul
 * motif). Réutilisé pour la dérogation ET le changement de version : `usage` filtre le catalogue
 * côté serveur (AR_ReasonService.getReasonOptions). Appel impératif (pas @wire) : `usage` n'est
 * connu qu'une fois le composant monté par son parent, cohérent avec le reste de l'app qui
 * réserve @wire aux listes déjà stables (arMatrixList, arDerogationQueue).
 */
export default class ArReasonMultiSelect extends LightningElement {
  i18n = I18N;

  @api usage; // 'derogation' | 'version'
  @api label = I18N.AR_Common_Reasons;
  @api required = false;
  _selectedIds = [];

  @api
  get selectedIds() {
    return this._selectedIds;
  }

  set selectedIds(value) {
    this._selectedIds = value;
  }

  options = [];
  // Session 34 (revue des .catch silencieux) : un catalogue vide par échec de chargement était
  // auparavant indiscernable d'un catalogue simplement vide côté référentiel — un motif étant
  // souvent obligatoire (cf. `required`), l'utilisateur se heurtait à "un motif est obligatoire"
  // sans jamais savoir pourquoi la liste ne proposait rien.
  loadError;

  get loadErrorMessage() {
    return formatLabel(I18N.AR_RMS_LoadError, this.loadError);
  }

  connectedCallback() {
    getReasonOptions({ usage: this.usage })
      .then((data) => {
        this.options = data.map((opt) => ({
          label: opt.label,
          value: opt.reasonId
        }));
        this.loadError = undefined;
      })
      .catch((error) => {
        this.options = [];
        this.loadError = this.reduceError(error);
        console.error(
          "arReasonMultiSelect : échec du chargement des motifs.",
          error
        );
      });
  }

  get hasOptions() {
    return this.options.length > 0;
  }

  get hasLoadError() {
    return !!this.loadError;
  }

  get showNoOptionsMessage() {
    return !this.hasOptions && !this.hasLoadError;
  }

  reduceError(error) {
    return reduceErrors(error);
  }

  handleChange(event) {
    event.stopPropagation();
    this._selectedIds = event.detail.value;
    this.dispatchEvent(
      new CustomEvent("change", { detail: { selectedIds: this._selectedIds } })
    );
  }
}