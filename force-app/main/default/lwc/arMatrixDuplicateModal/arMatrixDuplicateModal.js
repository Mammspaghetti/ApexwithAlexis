import { LightningElement, api } from "lwc";
import searchPositions from "@salesforce/apex/AR_PricingMatrixService.searchPositions";
import duplicateMatrixApex from "@salesforce/apex/AR_MatrixChainService.duplicateMatrixWithPrice";
import getNegotiationPrices from "@salesforce/apex/AR_MatrixChainService.getNegotiationPrices";
import { formatMoney } from "c/arPricingEngine";

import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_Common_Duplicate from "@salesforce/label/c.AR_Common_Duplicate";
import LBL_AR_MDM_BackToSourceNeed from "@salesforce/label/c.AR_MDM_BackToSourceNeed";
import LBL_AR_MDM_CommentOptional from "@salesforce/label/c.AR_MDM_CommentOptional";
import LBL_AR_MDM_CreateNextVersion from "@salesforce/label/c.AR_MDM_CreateNextVersion";
import LBL_AR_MDM_DuplicateSimulation from "@salesforce/label/c.AR_MDM_DuplicateSimulation";
import LBL_AR_MDM_DuplicateToOtherNeed from "@salesforce/label/c.AR_MDM_DuplicateToOtherNeed";
import LBL_AR_MDM_DuplicationFailed from "@salesforce/label/c.AR_MDM_DuplicationFailed";
import LBL_AR_MDM_NewTjmKeep from "@salesforce/label/c.AR_MDM_NewTjmKeep";
import LBL_AR_MDM_NewTjmTitle from "@salesforce/label/c.AR_MDM_NewTjmTitle";
import LBL_AR_PMS_NegoColPrice2 from "@salesforce/label/c.AR_PMS_NegoColPrice2";
import LBL_AR_PMS_NegoColPrice3 from "@salesforce/label/c.AR_PMS_NegoColPrice3";
import LBL_AR_MDM_NoNeedFound from "@salesforce/label/c.AR_MDM_NoNeedFound";
import LBL_AR_MDM_OtherNeed from "@salesforce/label/c.AR_MDM_OtherNeed";
import LBL_AR_MDM_ReasonRequired from "@salesforce/label/c.AR_MDM_ReasonRequired";
import LBL_AR_MDM_SearchOtherNeed from "@salesforce/label/c.AR_MDM_SearchOtherNeed";
import LBL_AR_MDM_SearchPlaceholder from "@salesforce/label/c.AR_MDM_SearchPlaceholder";
import LBL_AR_MDM_SourceNeed from "@salesforce/label/c.AR_MDM_SourceNeed";
import LBL_AR_MDM_Subtitle from "@salesforce/label/c.AR_MDM_Subtitle";
import LBL_AR_MDM_TargetNeed from "@salesforce/label/c.AR_MDM_TargetNeed";
import LBL_AR_MDM_VersionChangeReasons from "@salesforce/label/c.AR_MDM_VersionChangeReasons";

const I18N = {
  AR_Common_Cancel: LBL_AR_Common_Cancel,
  AR_Common_Duplicate: LBL_AR_Common_Duplicate,
  AR_MDM_BackToSourceNeed: LBL_AR_MDM_BackToSourceNeed,
  AR_MDM_CommentOptional: LBL_AR_MDM_CommentOptional,
  AR_MDM_CreateNextVersion: LBL_AR_MDM_CreateNextVersion,
  AR_MDM_DuplicateSimulation: LBL_AR_MDM_DuplicateSimulation,
  AR_MDM_DuplicateToOtherNeed: LBL_AR_MDM_DuplicateToOtherNeed,
  AR_MDM_DuplicationFailed: LBL_AR_MDM_DuplicationFailed,
  AR_MDM_NewTjmKeep: LBL_AR_MDM_NewTjmKeep,
  AR_MDM_NewTjmTitle: LBL_AR_MDM_NewTjmTitle,
  AR_PMS_NegoColPrice2: LBL_AR_PMS_NegoColPrice2,
  AR_PMS_NegoColPrice3: LBL_AR_PMS_NegoColPrice3,
  AR_MDM_NoNeedFound: LBL_AR_MDM_NoNeedFound,
  AR_MDM_OtherNeed: LBL_AR_MDM_OtherNeed,
  AR_MDM_ReasonRequired: LBL_AR_MDM_ReasonRequired,
  AR_MDM_SearchOtherNeed: LBL_AR_MDM_SearchOtherNeed,
  AR_MDM_SearchPlaceholder: LBL_AR_MDM_SearchPlaceholder,
  AR_MDM_SourceNeed: LBL_AR_MDM_SourceNeed,
  AR_MDM_Subtitle: LBL_AR_MDM_Subtitle,
  AR_MDM_TargetNeed: LBL_AR_MDM_TargetNeed,
  AR_MDM_VersionChangeReasons: LBL_AR_MDM_VersionChangeReasons
};
const LABEL_SEPARATOR = " — ";
const KEEP_CURRENT_TJM = "KEEP";

/**
 * Découpe un libellé « Besoin — Compte » (format construit par les deux parents,
 * arPriceMatrixSimulator et arMatrixList) en nom de besoin et compte.
 */
function splitLabel(label) {
  const text = label || "";
  const idx = text.lastIndexOf(LABEL_SEPARATOR);
  if (idx < 0) {
    return { name: text, account: "" };
  }
  return {
    name: text.slice(0, idx),
    account: text.slice(idx + LABEL_SEPARATOR.length)
  };
}

/**
 * Modale « Dupliquer » (session 22, refonte visuelle session 114). Le comportement (filiation +
 * motif obligatoire, ou copie libre) est déterminé par le statut de la matrice source —
 * `isChainDuplication`, calculé par le parent — pas par un choix de l'utilisateur ici. Cette
 * modale ne demande que le besoin cible (le besoin d'origine par défaut, ou un autre via la
 * recherche) et, si la source est décidée, les motifs + un commentaire libre optionnel.
 *
 * Session 114 : l'état est réinitialisé à chaque ouverture (setter `open`) et le besoin d'origine
 * est lu en direct depuis `sourcePositionLabel` — la modale du simulateur est montée avant que le
 * contexte du besoin soit chargé, l'ancien instantané pris au connectedCallback restait vide.
 */
export default class ArMatrixDuplicateModal extends LightningElement {
  i18n = I18N;

  // Setter : le parent pose `open` avant `source-matrix-id` (ordre des attributs du gabarit), l'Id peut
  // donc arriver après l'ouverture — la lecture des prix de négociation attend les deux.
  _sourceMatrixId;
  @api
  get sourceMatrixId() {
    return this._sourceMatrixId;
  }
  set sourceMatrixId(value) {
    this._sourceMatrixId = value;
    this.loadNegotiationPrices();
  }
  @api sourcePositionId;
  @api sourcePositionLabel;
  @api isChainDuplication = false;

  _open = false;
  searchTerm = "";
  positionOptions = [];
  hasSearched = false;
  selectedTargetPositionId = null;
  selectedTargetOption = null;
  selectedReasonIds = [];
  changeComment = "";
  isSaving = false;
  errorMessage;
  _searchSeq = 0;
  // Prix de négociation 2 et 3 de la source ({ price2, price3, currencyCode }) et choix du nouveau TJM.
  negotiationPrices = null;
  _pricesLoadedFor = null;
  newTjmChoice = KEEP_CURRENT_TJM;

  @api
  get open() {
    return this._open;
  }
  set open(value) {
    const next = !!value;
    if (next && !this._open) {
      this.resetState();
    }
    this._open = next;
    if (!next) {
      this._pricesLoadedFor = null;
    }
    this.loadNegotiationPrices();
  }

  async loadNegotiationPrices() {
    const matrixId = this.sourceMatrixId;
    if (!this._open || !matrixId || this._pricesLoadedFor === matrixId) {
      return;
    }
    this._pricesLoadedFor = matrixId;
    try {
      const prices = await getNegotiationPrices({ matrixId });
      // Réponse d'une ouverture précédente : ignorée.
      if (this._open && matrixId === this.sourceMatrixId) {
        this.negotiationPrices = prices;
      }
    } catch (error) {
      // Journalisé : le choix de prix est une aide ; sans lui la duplication garde le TJM actuel,
      // comportement historique, sans valeur métier substituée.
      console.error("getNegotiationPrices", error);
    }
  }

  get newTjmOptions() {
    const prices = this.negotiationPrices;
    if (!prices) {
      return [];
    }
    const options = [];
    [
      ["P2", I18N.AR_PMS_NegoColPrice2, prices.price2],
      ["P3", I18N.AR_PMS_NegoColPrice3, prices.price3]
    ].forEach(([value, label, price]) => {
      if (price > 0) {
        options.push({
          value,
          label: `${label}${LABEL_SEPARATOR}${formatMoney(price, prices.currencyCode)}`
        });
      }
    });
    if (options.length) {
      options.push({ value: KEEP_CURRENT_TJM, label: I18N.AR_MDM_NewTjmKeep });
    }
    return options;
  }

  get showNewTjmChoice() {
    return this.newTjmOptions.length > 0;
  }

  handleNewTjmChange(event) {
    this.newTjmChoice = event.detail.value;
  }

  resetState() {
    this.searchTerm = "";
    this.positionOptions = [];
    this.hasSearched = false;
    this.selectedTargetPositionId = null;
    this.selectedTargetOption = null;
    this.selectedReasonIds = [];
    this.changeComment = "";
    this.errorMessage = null;
    this.isSaving = false;
    this.negotiationPrices = null;
    this.newTjmChoice = KEEP_CURRENT_TJM;
  }

  get modalTitle() {
    return this.isChainDuplication
      ? I18N.AR_MDM_CreateNextVersion
      : I18N.AR_MDM_DuplicateSimulation;
  }

  get subtitle() {
    return I18N.AR_MDM_Subtitle;
  }

  get isOtherTarget() {
    return !!this.selectedTargetPositionId;
  }

  get targetName() {
    if (this.selectedTargetOption) {
      return this.selectedTargetOption.name;
    }
    return splitLabel(this.sourcePositionLabel).name || I18N.AR_MDM_SourceNeed;
  }

  get targetAccount() {
    if (this.selectedTargetOption) {
      return this.selectedTargetOption.account;
    }
    return splitLabel(this.sourcePositionLabel).account;
  }

  get targetTagLabel() {
    return this.isOtherTarget ? I18N.AR_MDM_OtherNeed : I18N.AR_MDM_SourceNeed;
  }

  get targetTagClass() {
    return this.isOtherTarget
      ? "dup-tag dup-tag_other"
      : "dup-tag dup-tag_source";
  }

  get enrichedOptions() {
    return (this.positionOptions || []).map((opt) => {
      const parts = splitLabel(opt.label);
      const isSelected = this.selectedTargetPositionId === opt.positionId;
      return {
        positionId: opt.positionId,
        name: opt.positionName || parts.name,
        account: opt.accountName || parts.account,
        isSource: opt.positionId === this.sourcePositionId,
        rowClass: isSelected ? "dup-result dup-result_selected" : "dup-result"
      };
    });
  }

  get showResults() {
    return this.hasSearched;
  }

  get showNoResults() {
    return this.hasSearched && this.positionOptions.length === 0;
  }

  handleSearchInput(event) {
    this.searchTerm = event.target.value;
    const seq = ++this._searchSeq;
    if (!this.searchTerm || this.searchTerm.length < 2) {
      this.positionOptions = [];
      this.hasSearched = false;
      return;
    }
    searchPositions({ searchTerm: this.searchTerm })
      .then((data) => {
        if (seq !== this._searchSeq) return;
        this.positionOptions = data || [];
        this.hasSearched = true;
      })
      .catch(() => {
        // Avalé délibérément (session 34, revue des .catch silencieux) : un typeahead qui échoue
        // rend "aucun résultat", l'utilisateur peut retaper — rien de métier n'est masqué.
        if (seq !== this._searchSeq) return;
        this.positionOptions = [];
        this.hasSearched = true;
      });
  }

  handleSelectPosition(event) {
    const positionId = event.currentTarget.dataset.positionId;
    if (positionId === this.sourcePositionId) {
      this.handleResetToSourcePosition();
    } else {
      const option = this.enrichedOptions.find(
        (opt) => opt.positionId === positionId
      );
      this.selectedTargetPositionId = positionId;
      this.selectedTargetOption = option
        ? { name: option.name, account: option.account }
        : { name: positionId, account: "" };
    }
    this.positionOptions = [];
    this.hasSearched = false;
    this.searchTerm = "";
  }

  handleResetToSourcePosition() {
    this.selectedTargetPositionId = null;
    this.selectedTargetOption = null;
  }

  handleReasonsChange(event) {
    this.selectedReasonIds = Array.isArray(event.detail.selectedIds)
      ? event.detail.selectedIds
      : [];
  }

  handleCommentChange(event) {
    this.changeComment = event.target.value;
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleConfirm() {
    if (
      this.isChainDuplication &&
      (this.selectedReasonIds || []).length === 0
    ) {
      this.errorMessage = I18N.AR_MDM_ReasonRequired;
      return;
    }
    this.errorMessage = null;
    this.isSaving = true;

    duplicateMatrixApex({
      sourceMatrixId: this.sourceMatrixId,
      targetPositionId: this.selectedTargetPositionId,
      reasonIds: this.isChainDuplication ? this.selectedReasonIds : [],
      changeComment: this.isChainDuplication ? this.changeComment : null,
      priceChoice:
        this.showNewTjmChoice && this.newTjmChoice !== KEEP_CURRENT_TJM
          ? this.newTjmChoice
          : null
    })
      .then((result) => {
        this.isSaving = false;
        this.dispatchEvent(
          new CustomEvent("duplicated", {
            detail: { matrixId: result.matrixId }
          })
        );
      })
      .catch((error) => {
        this.isSaving = false;
        this.errorMessage =
          (error && error.body && error.body.message) ||
          I18N.AR_MDM_DuplicationFailed;
      });
  }
}