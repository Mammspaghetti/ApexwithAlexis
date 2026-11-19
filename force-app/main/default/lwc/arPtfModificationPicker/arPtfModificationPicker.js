import { LightningElement, api, wire } from "lwc";
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import MODIFICATION_TYPE_FIELD from "@salesforce/schema/AR_PTF_Document__c.AR_Modification_Type__c";
import { reduceErrors } from "c/arErrorUtils";
import { formatLabel } from "c/arI18n";
import LBL_AR_PTF_ChooseModification from "@salesforce/label/c.AR_PTF_ChooseModification";
import LBL_AR_PTF_ModificationDetail from "@salesforce/label/c.AR_PTF_ModificationDetail";
import LBL_AR_PTF_ModificationDetailPlaceholder from "@salesforce/label/c.AR_PTF_ModificationDetailPlaceholder";
import LBL_AR_PTF_ModificationListUnavailable from "@salesforce/label/c.AR_PTF_ModificationListUnavailable";
import LBL_AR_PTF_ModificationType from "@salesforce/label/c.AR_PTF_ModificationType";

const I18N = {
  AR_PTF_ChooseModification: LBL_AR_PTF_ChooseModification,
  AR_PTF_ModificationDetail: LBL_AR_PTF_ModificationDetail,
  AR_PTF_ModificationDetailPlaceholder:
    LBL_AR_PTF_ModificationDetailPlaceholder,
  AR_PTF_ModificationListUnavailable: LBL_AR_PTF_ModificationListUnavailable,
  AR_PTF_ModificationType: LBL_AR_PTF_ModificationType
};
// AR_PTF_Document__c n'a aucun record type : le record type « maître » est celui de l'UI API.
const MASTER_RECORD_TYPE_ID = "012000000000000AAA";
// Seule valeur de liste connue du code : elle ouvre la saisie libre (règle Apex, session 138).
const OTHER_VALUE = "Autre";
const DETAIL_MAX_LENGTH = 255;
const COUNTER_THRESHOLD = 200;

/**
 * Sélecteur du type de modification d'une version de PTF (session 139, historique 3/3). Réutilisé à
 * l'identique dans le popover du tableau et dans la fenêtre de génération.
 *
 * Contrôlé par le parent : `type`/`detail` en entrée, `modificationchange` ({ type, detail, valid }) à
 * chaque modification, `modificationsubmit` quand Entrée valide une saisie valide dans le champ texte.
 * La validité (type choisi ; « Autre » → détail non vide après trim) est calculée ici ET revérifiée
 * par Apex (AR_PTFHistoryService) — ce composant n'est qu'un confort.
 * Les valeurs de la liste viennent de la picklist AR_Modification_Type__c : une valeur ajoutée dans
 * Setup apparaît sans changer le code.
 */
export default class ArPtfModificationPicker extends LightningElement {
  i18n = I18N;

  _type = "";
  _detail = "";
  options = [];
  loadError;
  _focusDetailPending = false;
  _hasRendered = false;

  @api
  get type() {
    return this._type;
  }
  set type(value) {
    this._type = value || "";
  }

  @api
  get detail() {
    return this._detail;
  }
  set detail(value) {
    this._detail = value || "";
  }

  @api
  get isValid() {
    return this.computeValid(this._type, this._detail);
  }

  @api
  focus() {
    const select = this.template.querySelector("select");
    if (select) {
      select.focus();
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: MASTER_RECORD_TYPE_ID,
    fieldApiName: MODIFICATION_TYPE_FIELD
  })
  wiredPicklist({ data, error }) {
    if (data) {
      this.options = (data.values || []).map((v) => ({
        label: v.label,
        value: v.value
      }));
      this.loadError = undefined;
    } else if (error) {
      // AFFICHER (règle session 34) : sans liste, rien ne peut être choisi — ne jamais laisser une
      // liste vide muette.
      this.loadError = formatLabel(
        I18N.AR_PTF_ModificationListUnavailable,
        reduceErrors(error)
      );
    }
  }

  renderedCallback() {
    if (this._focusDetailPending) {
      const input = this.template.querySelector("input.picker-detail");
      if (input) {
        this._focusDetailPending = false;
        input.focus();
      }
    }
  }

  get selectOptions() {
    return [
      {
        label: I18N.AR_PTF_ChooseModification,
        value: "",
        selected: !this._type
      },
      ...this.options.map((o) => ({ ...o, selected: o.value === this._type }))
    ];
  }

  get isOther() {
    return this._type === OTHER_VALUE;
  }

  get detailMaxLength() {
    return DETAIL_MAX_LENGTH;
  }

  get showCounter() {
    return this._detail.length > COUNTER_THRESHOLD;
  }

  get counterLabel() {
    return `${this._detail.length}/${DETAIL_MAX_LENGTH}`;
  }

  computeValid(type, detail) {
    if (!type) {
      return false;
    }
    return type !== OTHER_VALUE || detail.trim().length > 0;
  }

  notify(eventName) {
    this.dispatchEvent(
      new CustomEvent(eventName, {
        detail: {
          type: this._type,
          detail: this._detail,
          valid: this.computeValid(this._type, this._detail)
        }
      })
    );
  }

  handleTypeChange(event) {
    this._type = event.target.value;
    if (this._type === OTHER_VALUE) {
      this._focusDetailPending = true;
    }
    this.notify("modificationchange");
  }

  handleDetailInput(event) {
    this._detail = event.target.value;
    this.notify("modificationchange");
  }

  handleDetailKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      if (this.computeValid(this._type, this._detail)) {
        this.notify("modificationsubmit");
      }
    }
  }
}