import { LightningElement, api, wire } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getMatrices from "@salesforce/apex/AR_MatrixListService.getMatrices";
import {
  formatMoney,
  formatPercent,
  formatTjmPeriodsDetail
} from "c/arPricingEngine";
import LBL_AR_TJM_Weighted_Label from "@salesforce/label/c.AR_TJM_Weighted_Label";
import LBL_AR_RPLSR_Badge from "@salesforce/label/c.AR_RPLSR_Badge";
import { formatLabel, pluralLabel, matrixStatusLabel } from "c/arI18n";
import LBL_AR_App_BreadcrumbMatrices from "@salesforce/label/c.AR_App_BreadcrumbMatrices";
import LBL_AR_Common_BM from "@salesforce/label/c.AR_Common_BM";
import LBL_AR_Common_Date from "@salesforce/label/c.AR_Common_Date";
import LBL_AR_Common_Duplicate from "@salesforce/label/c.AR_Common_Duplicate";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_PTF from "@salesforce/label/c.AR_Common_PTF";
import LBL_AR_Common_SortBy from "@salesforce/label/c.AR_Common_SortBy";
import LBL_AR_Common_SortedAsc from "@salesforce/label/c.AR_Common_SortedAsc";
import LBL_AR_Common_SortedDesc from "@salesforce/label/c.AR_Common_SortedDesc";
import LBL_AR_Common_Status from "@salesforce/label/c.AR_Common_Status";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_DQ_AllBms from "@salesforce/label/c.AR_DQ_AllBms";
import LBL_AR_DQ_SegmentBelowFloor from "@salesforce/label/c.AR_DQ_SegmentBelowFloor";
import LBL_AR_ML_AllStatuses from "@salesforce/label/c.AR_ML_AllStatuses";
import LBL_AR_ML_CheckAll from "@salesforce/label/c.AR_ML_CheckAll";
import LBL_AR_ML_ColClientNeed from "@salesforce/label/c.AR_ML_ColClientNeed";
import LBL_AR_ML_ColCorridor from "@salesforce/label/c.AR_ML_ColCorridor";
import LBL_AR_ML_ColMargin from "@salesforce/label/c.AR_ML_ColMargin";
import LBL_AR_ML_ColProfile from "@salesforce/label/c.AR_ML_ColProfile";
import LBL_AR_ML_DisplayedMany from "@salesforce/label/c.AR_ML_DisplayedMany";
import LBL_AR_ML_DisplayedOne from "@salesforce/label/c.AR_ML_DisplayedOne";
import LBL_AR_ML_FilterByStatus from "@salesforce/label/c.AR_ML_FilterByStatus";
import LBL_AR_ML_MatrixCountMany from "@salesforce/label/c.AR_ML_MatrixCountMany";
import LBL_AR_ML_MatrixCountOne from "@salesforce/label/c.AR_ML_MatrixCountOne";
import LBL_AR_ML_MatrixCreated from "@salesforce/label/c.AR_ML_MatrixCreated";
import LBL_AR_ML_NewMatrix from "@salesforce/label/c.AR_ML_NewMatrix";
import LBL_AR_ML_NoMatrixFound from "@salesforce/label/c.AR_ML_NoMatrixFound";
import LBL_AR_ML_NoMatrixFoundHelp from "@salesforce/label/c.AR_ML_NoMatrixFoundHelp";
import LBL_AR_ML_NoMatrixYet from "@salesforce/label/c.AR_ML_NoMatrixYet";
import LBL_AR_ML_NoMatrixYetHelp from "@salesforce/label/c.AR_ML_NoMatrixYetHelp";
import LBL_AR_ML_NoStatus from "@salesforce/label/c.AR_ML_NoStatus";
import LBL_AR_ML_OpenOnPtf from "@salesforce/label/c.AR_ML_OpenOnPtf";
import LBL_AR_ML_PtfAfterValidation from "@salesforce/label/c.AR_ML_PtfAfterValidation";
import LBL_AR_ML_Search from "@salesforce/label/c.AR_ML_Search";
import LBL_AR_ML_SearchPlaceholder from "@salesforce/label/c.AR_ML_SearchPlaceholder";
import LBL_AR_ML_StatusCount from "@salesforce/label/c.AR_ML_StatusCount";
import LBL_AR_Won_Badge from "@salesforce/label/c.AR_Won_Badge";
import LBL_AR_Won_Action from "@salesforce/label/c.AR_Won_Action";
import LBL_AR_Won_Dlg_Price1 from "@salesforce/label/c.AR_Won_Dlg_Price1";
import LBL_AR_Won_Dlg_Price2 from "@salesforce/label/c.AR_Won_Dlg_Price2";
import LBL_AR_Won_Dlg_Price3 from "@salesforce/label/c.AR_Won_Dlg_Price3";
import LBL_AR_Won_Dlg_OffGrid from "@salesforce/label/c.AR_Won_Dlg_OffGrid";
import LBL_AR_PMS_SegmentLowMargin from "@salesforce/label/c.AR_PMS_SegmentLowMargin";
import LBL_AR_PMS_SegmentRecommended from "@salesforce/label/c.AR_PMS_SegmentRecommended";
import LBL_AR_PMS_SegmentSuperstar from "@salesforce/label/c.AR_PMS_SegmentSuperstar";

const I18N = {
  AR_App_BreadcrumbMatrices: LBL_AR_App_BreadcrumbMatrices,
  AR_Common_BM: LBL_AR_Common_BM,
  AR_Common_Date: LBL_AR_Common_Date,
  AR_Common_Duplicate: LBL_AR_Common_Duplicate,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_PTF: LBL_AR_Common_PTF,
  AR_Common_SortBy: LBL_AR_Common_SortBy,
  AR_Common_SortedAsc: LBL_AR_Common_SortedAsc,
  AR_Common_SortedDesc: LBL_AR_Common_SortedDesc,
  AR_Common_Status: LBL_AR_Common_Status,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_DQ_AllBms: LBL_AR_DQ_AllBms,
  AR_DQ_SegmentBelowFloor: LBL_AR_DQ_SegmentBelowFloor,
  AR_Won_Action: LBL_AR_Won_Action,
  AR_ML_AllStatuses: LBL_AR_ML_AllStatuses,
  AR_ML_CheckAll: LBL_AR_ML_CheckAll,
  AR_ML_ColClientNeed: LBL_AR_ML_ColClientNeed,
  AR_ML_ColCorridor: LBL_AR_ML_ColCorridor,
  AR_ML_ColMargin: LBL_AR_ML_ColMargin,
  AR_ML_ColProfile: LBL_AR_ML_ColProfile,
  AR_ML_DisplayedMany: LBL_AR_ML_DisplayedMany,
  AR_ML_DisplayedOne: LBL_AR_ML_DisplayedOne,
  AR_ML_FilterByStatus: LBL_AR_ML_FilterByStatus,
  AR_ML_MatrixCountMany: LBL_AR_ML_MatrixCountMany,
  AR_ML_MatrixCountOne: LBL_AR_ML_MatrixCountOne,
  AR_ML_MatrixCreated: LBL_AR_ML_MatrixCreated,
  AR_ML_NewMatrix: LBL_AR_ML_NewMatrix,
  AR_ML_NoMatrixFound: LBL_AR_ML_NoMatrixFound,
  AR_ML_NoMatrixFoundHelp: LBL_AR_ML_NoMatrixFoundHelp,
  AR_ML_NoMatrixYet: LBL_AR_ML_NoMatrixYet,
  AR_ML_NoMatrixYetHelp: LBL_AR_ML_NoMatrixYetHelp,
  AR_ML_NoStatus: LBL_AR_ML_NoStatus,
  AR_ML_OpenOnPtf: LBL_AR_ML_OpenOnPtf,
  AR_ML_PtfAfterValidation: LBL_AR_ML_PtfAfterValidation,
  AR_ML_Search: LBL_AR_ML_Search,
  AR_ML_SearchPlaceholder: LBL_AR_ML_SearchPlaceholder,
  AR_ML_StatusCount: LBL_AR_ML_StatusCount,
  AR_PMS_SegmentLowMargin: LBL_AR_PMS_SegmentLowMargin,
  AR_PMS_SegmentRecommended: LBL_AR_PMS_SegmentRecommended,
  AR_PMS_SegmentSuperstar: LBL_AR_PMS_SegmentSuperstar
};
// Session 115 : l'ordre de cette liste sert aussi de rang pour le tri de la colonne Statut (cycle de
// vie : brouillon → en dérogation → décidée).
const STATUS_VALUES = [
  "Brouillon",
  "Validée",
  "En dérogation",
  "Validée par dérogation",
  "Refusée"
];

const ALL_OWNERS = "all";

// Nombre de lignes rendues à l'ouverture, puis ajoutées à chaque fois que le bas de liste est atteint.
const PAGE_SIZE = 50;

const STATUS_META = {
  Brouillon: "status-badge status-draft",
  Validée: "status-badge status-validated",
  "En dérogation": "status-badge status-pending",
  "Validée par dérogation": "status-badge status-validated-derog",
  Refusée: "status-badge status-rejected"
};

// Même liste que arPriceMatrixSimulator.CHAIN_SOURCE_STATUSES (session 22, dupliquée ici plutôt que
// partagée via un module commun — les deux composants ne partagent aucun autre état, cf. session 28
// prompt §5 : réutiliser la modale existante, pas la logique de chaîne elle-même qui reste côté Apex
// AR_MatrixChainService, seul point de vérité réel).
const CHAIN_SOURCE_STATUSES = ["Validée", "Validée par dérogation", "Refusée"];

// Seuls statuts où la zone PTF existe dans le simulateur (arPriceMatrixSimulator.isValidatedStatus).
// Niveau de prix signé (valeur de AR_Signed_Price_Level__c) → libellé affiché dans le badge « Gagnée · P2 ».
const WON_LEVEL_LABELS = {
  P1: LBL_AR_Won_Dlg_Price1,
  P2: LBL_AR_Won_Dlg_Price2,
  P3: LBL_AR_Won_Dlg_Price3,
  "Hors grille": LBL_AR_Won_Dlg_OffGrid
};
const PTF_STATUSES = ["Validée", "Validée par dérogation"];

// Rang du corridor, du plus bas au plus haut, pour le tri de la colonne Corridor.
const SEGMENT_RANK = {
  below_floor: 0,
  low_margin: 1,
  recommended: 2,
  superstar: 3
};

/**
 * Session 115 — colonnes triables « à la Excel » : premier clic = décroissant, second = croissant.
 * `thClass` reprend les alignements d'en-tête d'avant la session.
 */
const SORT_COLUMNS = [
  { key: "account", label: I18N.AR_ML_ColClientNeed, thClass: "" },
  { key: "profile", label: I18N.AR_ML_ColProfile, thClass: "" },
  { key: "owner", label: "BM", thClass: "th-center" },
  { key: "tjm", label: "TJM", thClass: "col-num th-center" },
  { key: "margin", label: I18N.AR_ML_ColMargin, thClass: "col-num th-center" },
  { key: "segment", label: I18N.AR_ML_ColCorridor, thClass: "th-center" },
  { key: "status", label: I18N.AR_Common_Status, thClass: "th-center" },
  { key: "date", label: I18N.AR_Common_Date, thClass: "th-center" }
];

const TEXT_COLLATOR = new Intl.Collator("fr", { sensitivity: "base" });

const SEGMENT_META = {
  below_floor: {
    label: I18N.AR_DQ_SegmentBelowFloor,
    cssClass: "segment-pill segment-below-floor"
  },
  low_margin: {
    label: I18N.AR_PMS_SegmentLowMargin,
    cssClass: "segment-pill segment-low-margin"
  },
  recommended: {
    label: I18N.AR_PMS_SegmentRecommended,
    cssClass: "segment-pill segment-recommended"
  },
  superstar: {
    label: I18N.AR_PMS_SegmentSuperstar,
    cssClass: "segment-pill segment-superstar"
  }
};

/**
 * Vue « Matrices de prix » (session 115 : anciennement « Mes matrices » — la liste montre toutes les
 * matrices visibles de l'utilisateur, pas seulement les siennes ; le filtre BM permet de s'y
 * restreindre).
 *
 * Parité visuelle avec pricing-tool/pricing-tool.html:2198-2269 (MatricesPage). "Profil" et
 * "Région" réutilisent AR_Position_Name__c / AR_Account_Country__c : la maquette suppose un champ
 * "profil" distinct du nom du besoin, absent du modèle de données réel (le nom du besoin Connexys
 * EST le profil en pratique, cf. docs/11-matrices-derogations.md).
 */
export default class ArMatrixList extends LightningElement {
  i18n = I18N;

  // Session 115 : filtre de statut multi-sélection. Par défaut toutes les cases sont cochées ;
  // décocher tout n'affiche plus rien (comme un filtre Excel).
  selectedStatuses = [...STATUS_VALUES];
  statusMenuOpen = false;
  ownerFilter = ALL_OWNERS;
  searchText = "";
  sortKey = "date";
  sortDescending = true;

  rawMatrices = [];
  visibleCount = PAGE_SIZE;
  _observer;
  isLoading = true;
  errorMessage;
  // Résultat du wire, transmis à refreshApex pour actualiser la liste.
  wiredMatricesResult;
  refreshOnNextData = false;

  _initialState;
  _initialStateApplied = false;

  // Duplication depuis la liste (session 28, prompt §5) : réutilise arMatrixDuplicateModal, déjà
  // livré et branché depuis le simulateur (session 22) — même contrat, même modale, pas de logique
  // dupliquée.
  showDuplicateModal = false;
  // Fenêtre « Affaire gagnée » (session 284).
  showWonDialog = false;
  wonPositionId;
  wonMatrixId;
  duplicateSourceMatrixId;
  duplicateSourcePositionId;
  duplicateSourcePositionLabel;
  duplicateIsChain = false;

  /**
   * Session 166 : état de recherche/tri/filtres conservé par le shell (arPricingApp) pendant que la
   * liste est démontée, et rendu ici au retour. N'est appliqué qu'une fois, à la création (les
   * changements ultérieurs viennent de la liste elle-même, annoncés par `statechange`) ; chaque
   * valeur est validée — un état inconnu retombe sur le défaut, jamais sur une liste vide muette.
   */
  @api
  get initialState() {
    return this._initialState;
  }
  set initialState(value) {
    this._initialState = value;
    if (!value || this._initialStateApplied) {
      return;
    }
    this._initialStateApplied = true;
    this.visibleCount = PAGE_SIZE;
    if (typeof value.searchText === "string") {
      this.searchText = value.searchText;
    }
    if (SORT_COLUMNS.some((col) => col.key === value.sortKey)) {
      this.sortKey = value.sortKey;
      this.sortDescending = value.sortDescending !== false;
    }
    if (Array.isArray(value.selectedStatuses)) {
      const known = STATUS_VALUES.filter((s) =>
        value.selectedStatuses.includes(s)
      );
      // « Aucun statut » (tableau vide) est un état légitime à restaurer ; une liste non vide sans
      // aucune valeur connue est un état corrompu → défaut (tous les statuts), pas une liste vide.
      if (known.length > 0 || value.selectedStatuses.length === 0) {
        this.selectedStatuses = known;
      }
    }
    if (typeof value.ownerFilter === "string" && value.ownerFilter) {
      this.ownerFilter = value.ownerFilter;
    }
  }

  emitState() {
    this.dispatchEvent(
      new CustomEvent("statechange", {
        detail: {
          searchText: this.searchText,
          sortKey: this.sortKey,
          sortDescending: this.sortDescending,
          selectedStatuses: [...this.selectedStatuses],
          ownerFilter: this.ownerFilter
        }
      })
    );
  }

  @wire(getMatrices)
  wiredMatrices(result) {
    this.wiredMatricesResult = result;
    const { data, error } = result;
    if (data) {
      this.rawMatrices = data;
      this.errorMessage = undefined;
      this.isLoading = false;
      // Le wire sert le cache client sans toucher au serveur : la première réponse après connexion
      // est donc actualisée une fois, ce qui remplace le cache par la version serveur.
      if (this.refreshOnNextData) {
        this.refreshOnNextData = false;
        this.refreshMatrices();
      }
    } else if (error) {
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
    }
  }

  connectedCallback() {
    this.refreshOnNextData = true;
    document.addEventListener("visibilitychange", this.handleVisibilityChange);
  }

  renderedCallback() {
    if (typeof IntersectionObserver === "undefined") {
      return;
    }
    if (!this._observer) {
      this._observer = new IntersectionObserver(
        (entries) => this.handleSentinel(entries),
        { rootMargin: "200px" }
      );
    }
    // La sentinelle n'existe que s'il reste des lignes : on la ré-observe à chaque rendu, ce qui
    // relance le contrôle si elle est encore visible après l'ajout d'une tranche.
    this._observer.disconnect();
    const sentinel = this.template.querySelector(".list-sentinel");
    if (sentinel) {
      this._observer.observe(sentinel);
    }
  }

  disconnectedCallback() {
    document.removeEventListener(
      "visibilitychange",
      this.handleVisibilityChange
    );
    if (this._observer) {
      this._observer.disconnect();
      this._observer = undefined;
    }
  }

  handleVisibilityChange = () => {
    if (document.visibilityState === "visible") {
      this.refreshMatrices();
    }
  };

  // Actualise les données depuis le serveur sans vider la liste : recherche, filtres, tri et nombre
  // de lignes affichées restent tels quels.
  refreshMatrices() {
    if (this.wiredMatricesResult) {
      refreshApex(this.wiredMatricesResult);
    }
  }

  handleSentinel(entries) {
    if (entries.some((e) => e.isIntersecting) && this.hasMoreRows) {
      this.visibleCount += PAGE_SIZE;
    }
  }

  handleStatusMenuToggle() {
    this.statusMenuOpen = !this.statusMenuOpen;
  }

  handleStatusMenuClose() {
    this.statusMenuOpen = false;
  }

  handleStatusMenuKeydown(event) {
    if (event.key === "Escape") {
      this.statusMenuOpen = false;
    }
  }

  handleStatusToggle(event) {
    const value = event.target.value;
    const selected = new Set(this.selectedStatuses);
    if (event.target.checked) {
      selected.add(value);
    } else {
      selected.delete(value);
    }
    // Conserve l'ordre de STATUS_VALUES, quel que soit l'ordre des clics.
    this.selectedStatuses = STATUS_VALUES.filter((s) => selected.has(s));
    this.visibleCount = PAGE_SIZE;
    this.emitState();
  }

  handleStatusReset() {
    this.selectedStatuses = [...STATUS_VALUES];
    this.visibleCount = PAGE_SIZE;
    this.emitState();
  }

  handleOwnerFilterChange(event) {
    this.ownerFilter = event.detail.value;
    this.visibleCount = PAGE_SIZE;
    this.emitState();
  }

  handleSearchChange(event) {
    this.searchText = event.target.value;
    this.visibleCount = PAGE_SIZE;
    this.emitState();
  }

  // Premier clic sur une colonne = décroissant ; clic suivant sur la même colonne = croissant, puis
  // on alterne.
  handleSortClick(event) {
    const key = event.currentTarget.dataset.key;
    if (key === this.sortKey) {
      this.sortDescending = !this.sortDescending;
    } else {
      this.sortKey = key;
      this.sortDescending = true;
    }
    this.visibleCount = PAGE_SIZE;
    this.emitState();
  }

  handleNewMatrix() {
    this.dispatchEvent(
      new CustomEvent("openmatrix", { detail: { matrixId: null } })
    );
  }

  // La ligne entière est cliquable (ouvre la matrice) ; le bouton PTF stoppe la propagation pour
  // ne pas déclencher aussi la navigation.
  handleRowClick(event) {
    const matrixId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("openmatrix", { detail: { matrixId } }));
  }

  // Session 113 : le bouton PTF ouvre la matrice directement sur la zone « Proposition Technique et
  // Financière » (focusSection "ptf", relayé par arPricingApp au simulateur puis à arPtfPanel) ;
  // sans PTF dans l'historique, le formulaire de génération s'ouvre d'emblée. Le bouton n'est actif
  // que pour une matrice validée — même gate que le simulateur (isValidatedStatus), le seul statut
  // où la zone PTF existe.
  handlePtfClick(event) {
    event.stopPropagation();
    const matrixId = event.currentTarget.dataset.id;
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: { matrixId, focusSection: "ptf" }
      })
    );
  }

  handleDuplicateClick(event) {
    event.stopPropagation();
    const matrixId = event.currentTarget.dataset.id;
    const row = this.rawMatrices.find((m) => m.matrixId === matrixId);
    if (!row) {
      return;
    }
    this.duplicateSourceMatrixId = row.matrixId;
    this.duplicateSourcePositionId = row.positionId;
    this.duplicateSourcePositionLabel = `${row.positionName || ""} — ${row.accountName || "sans compte"}`;
    this.duplicateIsChain = CHAIN_SOURCE_STATUSES.includes(row.status);
    this.showDuplicateModal = true;
  }

  handleWonClick(event) {
    event.stopPropagation();
    const row = this.rawMatrices.find(
      (m) => m.matrixId === event.currentTarget.dataset.id
    );
    if (!row) {
      return;
    }
    this.wonPositionId = row.positionId;
    this.wonMatrixId = row.matrixId;
    this.showWonDialog = true;
  }

  handleWonClose() {
    this.showWonDialog = false;
  }

  // Version gagnante confirmée : on ferme la fenêtre et on rafraîchit la liste (badge « Gagnée · Pn »).
  handleWonConfirmed() {
    this.showWonDialog = false;
    this.refreshMatrices();
  }

  handleCloseDuplicateModal() {
    this.showDuplicateModal = false;
  }

  // Même comportement que arPriceMatrixSimulator.handleMatrixDuplicated (session 22) : on délègue
  // la navigation vers la nouvelle matrice au parent (arPricingApp), même contrat d'événement
  // `openmatrix`. La liste est rafraîchie pour que le clone apparaisse au retour.
  handleMatrixDuplicated(event) {
    this.showDuplicateModal = false;
    this.dispatchEvent(
      new ShowToastEvent({
        title: I18N.AR_Common_SuccessTitle,
        message: I18N.AR_ML_MatrixCreated,
        variant: "success"
      })
    );
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: { matrixId: event.detail.matrixId }
      })
    );
    this.refreshMatrices();
  }

  get sortColumns() {
    return SORT_COLUMNS.map((col) => {
      const active = col.key === this.sortKey;
      return {
        ...col,
        active,
        ariaSort: active
          ? this.sortDescending
            ? "descending"
            : "ascending"
          : "none",
        buttonClass: active ? "sort-header sort-header-active" : "sort-header",
        iconName: this.sortDescending ? "utility:arrowdown" : "utility:arrowup",
        title: active
          ? this.sortDescending
            ? formatLabel(I18N.AR_Common_SortedDesc, col.label)
            : formatLabel(I18N.AR_Common_SortedAsc, col.label)
          : formatLabel(I18N.AR_Common_SortBy, col.label)
      };
    });
  }

  get statusChoices() {
    return STATUS_VALUES.map((value) => ({
      value,
      label: matrixStatusLabel(value),
      checked: this.selectedStatuses.includes(value),
      badgeClass: STATUS_META[value] || "status-badge"
    }));
  }

  get allStatusesSelected() {
    return this.selectedStatuses.length === STATUS_VALUES.length;
  }

  get statusFilterLabel() {
    const n = this.selectedStatuses.length;
    if (this.allStatusesSelected) {
      return I18N.AR_ML_AllStatuses;
    }
    if (n === 0) {
      return I18N.AR_ML_NoStatus;
    }
    if (n === 1) {
      return matrixStatusLabel(this.selectedStatuses[0]);
    }
    return formatLabel(I18N.AR_ML_StatusCount, n);
  }

  get statusTriggerClass() {
    return this.allStatusesSelected
      ? "status-trigger"
      : "status-trigger status-trigger-active";
  }

  get ownerOptions() {
    const names = [
      ...new Set(this.rawMatrices.map((m) => m.ownerName).filter(Boolean))
    ].sort(TEXT_COLLATOR.compare);
    return [
      { label: I18N.AR_DQ_AllBms, value: ALL_OWNERS },
      ...names.map((name) => ({ label: name, value: name }))
    ];
  }

  get matrixCountLabel() {
    const n = this.filteredRows.length;
    return pluralLabel(
      n,
      I18N.AR_ML_MatrixCountOne,
      I18N.AR_ML_MatrixCountMany
    );
  }

  get shownCountLabel() {
    return pluralLabel(
      this.filteredRows.length,
      I18N.AR_ML_DisplayedOne,
      I18N.AR_ML_DisplayedMany
    );
  }

  // Résultat complet (filtre + tri) : les compteurs et la sentinelle s'appuient dessus.
  get filteredRows() {
    const search = this.searchText.trim().toLowerCase();
    const statuses = this.selectedStatuses;
    let rows = this.rawMatrices.filter((m) => {
      if (!statuses.includes(m.status)) {
        return false;
      }
      if (this.ownerFilter !== ALL_OWNERS && m.ownerName !== this.ownerFilter) {
        return false;
      }
      if (!search) {
        return true;
      }
      const haystack =
        `${m.name || ""} ${m.positionName || ""} ${m.accountName || ""} ${m.ownerName || ""} ${m.consultantName || ""}`.toLowerCase();
      return haystack.includes(search);
    });
    return [...rows].sort((a, b) => this.compareRows(a, b));
  }

  get hasMoreRows() {
    return this.filteredRows.length > this.visibleCount;
  }

  // Seules les lignes visibles sont mises en forme et rendues.
  get matrices() {
    return this.filteredRows.slice(0, this.visibleCount).map((m) => {
      // Un segment n'a de sens qu'une fois un TJM saisi : sans TJM, calcMC2 retombe sur 0 %,
      // classé « below_floor » par défaut — trompeur pour un Brouillon jamais renseigné.
      const hasTjm = !!m.proposedTjm;
      const hasSegment = hasTjm && !!m.corridorSegment;
      return {
        ...m,
        accountName: m.accountName || "—",
        ownerName: m.ownerName || "—",
        accountCountry: m.accountCountry || "",
        statusClass: STATUS_META[m.status] || "status-badge",
        statusLabel: matrixStatusLabel(m.status),
        segmentLabel: hasSegment ? SEGMENT_META[m.corridorSegment].label : "—",
        segmentClass: hasSegment
          ? SEGMENT_META[m.corridorSegment].cssClass
          : "segment-pill",
        // Devise propre à chaque matrice (session 24) : cette liste ne convertit ni n'agrège rien,
        // chaque ligne s'affiche dans sa propre devise.
        formattedTjm: formatMoney(m.proposedTjm, m.currencyCode),
        rplsrBadge: m.rplsrActive ? LBL_AR_RPLSR_Badge : null,
        tjmPeriodsDetail: formatTjmPeriodsDetail(
          m.tjmPeriods,
          m.currencyCode,
          LBL_AR_TJM_Weighted_Label
        ),
        formattedMc2: hasTjm ? formatPercent(m.mc2PercentHuman) : "—",
        marginClass: !hasTjm
          ? "margin-neutral"
          : m.corridorSegment === "below_floor"
            ? "margin-negative"
            : "margin-positive",
        formattedDate: this.formatDate(m.createdDate),
        wonBadge: m.won
          ? formatLabel(
              LBL_AR_Won_Badge,
              WON_LEVEL_LABELS[m.signedPriceLevel] || m.signedPriceLevel || ""
            )
          : null,
        showWonAction:
          !m.won && m.positionWon === true && PTF_STATUSES.includes(m.status),
        ptfDisabled: !PTF_STATUSES.includes(m.status),
        ptfTitle: PTF_STATUSES.includes(m.status)
          ? I18N.AR_ML_OpenOnPtf
          : I18N.AR_ML_PtfAfterValidation
      };
    });
  }

  /**
   * Session 115 — tri par colonne. Règles communes :
   * - une valeur absente (pas de TJM, pas de BM…) va toujours en fin de liste, quel que soit le sens ;
   * - à égalité, la matrice la plus récente passe devant (ordre stable et prévisible).
   *
   * TJM : la session 24b interdisait de trier des montants bruts en devises différentes. On trie
   * donc d'abord par devise (ordre alphabétique fixe), puis par montant dans le sens demandé : les
   * montants ne sont jamais comparés d'une devise à l'autre. Marge et corridor sont des grandeurs
   * sans devise, triées directement — et seulement si un TJM est saisi, comme à l'affichage.
   */
  compareRows(a, b) {
    const dir = this.sortDescending ? -1 : 1;
    const va = this.sortValue(a);
    const vb = this.sortValue(b);
    let diff = 0;
    if (this.sortKey === "tjm" && va !== null && vb !== null) {
      diff = TEXT_COLLATOR.compare(a.currencyCode || "", b.currencyCode || "");
      if (diff === 0) {
        diff = dir * (va - vb);
      }
    } else if (va === null || vb === null) {
      diff = va === null ? (vb === null ? 0 : 1) : -1;
    } else if (typeof va === "string") {
      diff = dir * TEXT_COLLATOR.compare(va, vb);
    } else {
      diff = dir * (va - vb);
    }
    if (diff === 0 && this.sortKey === "account") {
      diff =
        dir * TEXT_COLLATOR.compare(a.positionName || "", b.positionName || "");
    }
    if (diff === 0) {
      diff = new Date(b.createdDate) - new Date(a.createdDate);
    }
    return diff;
  }

  sortValue(m) {
    const hasTjm = !!m.proposedTjm;
    switch (this.sortKey) {
      case "account":
        return m.accountName || null;
      case "profile":
        return m.positionName || null;
      case "owner":
        return m.ownerName || null;
      case "tjm":
        return hasTjm ? Number(m.proposedTjm) : null;
      case "margin":
        return hasTjm && m.mc2PercentHuman != null
          ? Number(m.mc2PercentHuman)
          : null;
      case "segment":
        return hasTjm && m.corridorSegment in SEGMENT_RANK
          ? SEGMENT_RANK[m.corridorSegment]
          : null;
      case "status": {
        const rank = STATUS_VALUES.indexOf(m.status);
        return rank >= 0 ? rank : null;
      }
      default:
        return m.createdDate ? new Date(m.createdDate).getTime() : null;
    }
  }

  get isEmpty() {
    return !this.isLoading && this.filteredRows.length === 0;
  }

  get hasNoMatricesAtAll() {
    return !this.isLoading && this.rawMatrices.length === 0;
  }

  formatDate(value) {
    if (!value) {
      return "";
    }
    return new Date(value).toLocaleDateString("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric"
    });
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}