import { LightningElement, wire, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import listDerogations from "@salesforce/apex/AR_DerogationService.listDerogations";
import isCurrentUserValidator from "@salesforce/apex/AR_DerogationService.isCurrentUserValidator";
import getCurrentUserIdentity from "@salesforce/apex/AR_DerogationService.getCurrentUserIdentity";
import decideApex from "@salesforce/apex/AR_DerogationService.decide";
import { logNotificationFailure } from "c/arNotificationLog";
import {
  generateAvenantDocument,
  avenantGenerationToast
} from "c/arAvenantGeneration";
import {
  formatMoney,
  formatPercent,
  formatTjmPeriodsDetail
} from "c/arPricingEngine";
import LBL_AR_TJM_Weighted_Label from "@salesforce/label/c.AR_TJM_Weighted_Label";
import { formatLabel } from "c/arI18n";
import { buildReasonView } from "c/arDerogationReasonView";
import { buildRfaLine } from "c/arDerogationRfaView";
import LBL_AR_Common_BM from "@salesforce/label/c.AR_Common_BM";
import LBL_AR_Common_Client from "@salesforce/label/c.AR_Common_Client";
import LBL_AR_Common_CreatedOn from "@salesforce/label/c.AR_Common_CreatedOn";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Pending from "@salesforce/label/c.AR_Common_Pending";
import LBL_AR_Common_ProposedRate from "@salesforce/label/c.AR_Common_ProposedRate";
import LBL_AR_Common_Reject from "@salesforce/label/c.AR_Common_Reject";
import LBL_AR_Common_Reset from "@salesforce/label/c.AR_Common_Reset";
import LBL_AR_Common_SortBy from "@salesforce/label/c.AR_Common_SortBy";
import LBL_AR_Common_SortedAsc from "@salesforce/label/c.AR_Common_SortedAsc";
import LBL_AR_Common_SortedDesc from "@salesforce/label/c.AR_Common_SortedDesc";
import LBL_AR_Common_Status from "@salesforce/label/c.AR_Common_Status";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_Type from "@salesforce/label/c.AR_Common_Type";
import LBL_AR_Common_Validator from "@salesforce/label/c.AR_Common_Validator";
import LBL_AR_DQ_AgencyBu from "@salesforce/label/c.AR_DQ_AgencyBu";
import LBL_AR_DQ_AllAgencies from "@salesforce/label/c.AR_DQ_AllAgencies";
import LBL_AR_DQ_AllBms from "@salesforce/label/c.AR_DQ_AllBms";
import LBL_AR_DQ_AllClients from "@salesforce/label/c.AR_DQ_AllClients";
import LBL_AR_DQ_AllValidators from "@salesforce/label/c.AR_DQ_AllValidators";
import LBL_AR_DQ_Approve from "@salesforce/label/c.AR_DQ_Approve";
import LBL_AR_DQ_Approved from "@salesforce/label/c.AR_DQ_Approved";
import LBL_AR_DQ_ApprovedToast from "@salesforce/label/c.AR_DQ_ApprovedToast";
import LBL_AR_DQ_ColClientProfile from "@salesforce/label/c.AR_DQ_ColClientProfile";
import LBL_AR_DQ_ColIndicator from "@salesforce/label/c.AR_DQ_ColIndicator";
import LBL_AR_DQ_ColMc2Segment from "@salesforce/label/c.AR_DQ_ColMc2Segment";
import LBL_AR_DQ_ColRequester from "@salesforce/label/c.AR_DQ_ColRequester";
import LBL_AR_DQ_CommentMandatory from "@salesforce/label/c.AR_DQ_CommentMandatory";
import LBL_AR_DQ_CommentPlaceholder from "@salesforce/label/c.AR_DQ_CommentPlaceholder";
import LBL_AR_DQ_ConnectedAs from "@salesforce/label/c.AR_DQ_ConnectedAs";
import LBL_AR_DQ_DecisionRequired from "@salesforce/label/c.AR_DQ_DecisionRequired";
import LBL_AR_DQ_DerogationReason from "@salesforce/label/c.AR_DQ_DerogationReason";
import LBL_AR_DQ_FloorPrefix from "@salesforce/label/c.AR_DQ_FloorPrefix";
import LBL_AR_DQ_IdealPrefix from "@salesforce/label/c.AR_DQ_IdealPrefix";
import LBL_AR_DQ_MandatoryComment from "@salesforce/label/c.AR_DQ_MandatoryComment";
import LBL_AR_DQ_Mc2Prefix from "@salesforce/label/c.AR_DQ_Mc2Prefix";
import LBL_AR_DQ_Mc2WithPerDay from "@salesforce/label/c.AR_DQ_Mc2WithPerDay";
import LBL_AR_DQ_NoPending from "@salesforce/label/c.AR_DQ_NoPending";
import LBL_AR_DQ_None from "@salesforce/label/c.AR_DQ_None";
import LBL_AR_DQ_NoneForYou from "@salesforce/label/c.AR_DQ_NoneForYou";
import LBL_AR_DQ_NoneYet from "@salesforce/label/c.AR_DQ_NoneYet";
import LBL_AR_DQ_NoneYetHelp from "@salesforce/label/c.AR_DQ_NoneYetHelp";
import LBL_AR_DQ_NotFoundMessage from "@salesforce/label/c.AR_DQ_NotFoundMessage";
import LBL_AR_DQ_NotFoundTitle from "@salesforce/label/c.AR_DQ_NotFoundTitle";
import LBL_AR_DQ_NotifiedValidatorPrefix from "@salesforce/label/c.AR_DQ_NotifiedValidatorPrefix";
import LBL_AR_DQ_PendingForOthers from "@salesforce/label/c.AR_DQ_PendingForOthers";
import LBL_AR_DQ_PillApproved from "@salesforce/label/c.AR_DQ_PillApproved";
import LBL_AR_DQ_PillPending from "@salesforce/label/c.AR_DQ_PillPending";
import LBL_AR_DQ_PillRejected from "@salesforce/label/c.AR_DQ_PillRejected";
import LBL_AR_DQ_ProcessedBy from "@salesforce/label/c.AR_DQ_ProcessedBy";
import LBL_AR_DQ_ProfitabilityIndicators from "@salesforce/label/c.AR_DQ_ProfitabilityIndicators";
import LBL_AR_DQ_ProposedRatePrefix from "@salesforce/label/c.AR_DQ_ProposedRatePrefix";
import LBL_AR_DQ_Rejected from "@salesforce/label/c.AR_DQ_Rejected";
import LBL_AR_DQ_RejectedToast from "@salesforce/label/c.AR_DQ_RejectedToast";
import LBL_AR_DQ_SeeAll from "@salesforce/label/c.AR_DQ_SeeAll";
import LBL_AR_DQ_SegmentBelowFloor from "@salesforce/label/c.AR_DQ_SegmentBelowFloor";
import LBL_AR_DQ_SegmentPrefix from "@salesforce/label/c.AR_DQ_SegmentPrefix";
import LBL_AR_DQ_Subtitle from "@salesforce/label/c.AR_DQ_Subtitle";
import LBL_AR_DQ_TabAll from "@salesforce/label/c.AR_DQ_TabAll";
import LBL_AR_DQ_TabApproved from "@salesforce/label/c.AR_DQ_TabApproved";
import LBL_AR_DQ_TabMine from "@salesforce/label/c.AR_DQ_TabMine";
import LBL_AR_DQ_TabRejected from "@salesforce/label/c.AR_DQ_TabRejected";
import LBL_AR_DQ_TargetPrefix from "@salesforce/label/c.AR_DQ_TargetPrefix";
import LBL_AR_DQ_Title from "@salesforce/label/c.AR_DQ_Title";
import LBL_AR_DQ_TypeAT from "@salesforce/label/c.AR_DQ_TypeAT";
import LBL_AR_DQ_ValidatorComment from "@salesforce/label/c.AR_DQ_ValidatorComment";
import LBL_AR_DQ_ViewMatrix from "@salesforce/label/c.AR_DQ_ViewMatrix";
import LBL_AR_DQ_YouCanProcess from "@salesforce/label/c.AR_DQ_YouCanProcess";
import LBL_AR_PMS_SegmentLowMargin from "@salesforce/label/c.AR_PMS_SegmentLowMargin";
import LBL_AR_PMS_SegmentRecommended from "@salesforce/label/c.AR_PMS_SegmentRecommended";
import LBL_AR_PMS_SegmentSuperstar from "@salesforce/label/c.AR_PMS_SegmentSuperstar";

const I18N = {
  AR_Common_BM: LBL_AR_Common_BM,
  AR_Common_Client: LBL_AR_Common_Client,
  AR_Common_CreatedOn: LBL_AR_Common_CreatedOn,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Pending: LBL_AR_Common_Pending,
  AR_Common_ProposedRate: LBL_AR_Common_ProposedRate,
  AR_Common_Reject: LBL_AR_Common_Reject,
  AR_Common_Reset: LBL_AR_Common_Reset,
  AR_Common_SortBy: LBL_AR_Common_SortBy,
  AR_Common_SortedAsc: LBL_AR_Common_SortedAsc,
  AR_Common_SortedDesc: LBL_AR_Common_SortedDesc,
  AR_Common_Status: LBL_AR_Common_Status,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_Type: LBL_AR_Common_Type,
  AR_Common_Validator: LBL_AR_Common_Validator,
  AR_DQ_AgencyBu: LBL_AR_DQ_AgencyBu,
  AR_DQ_AllAgencies: LBL_AR_DQ_AllAgencies,
  AR_DQ_AllBms: LBL_AR_DQ_AllBms,
  AR_DQ_AllClients: LBL_AR_DQ_AllClients,
  AR_DQ_AllValidators: LBL_AR_DQ_AllValidators,
  AR_DQ_Approve: LBL_AR_DQ_Approve,
  AR_DQ_Approved: LBL_AR_DQ_Approved,
  AR_DQ_ApprovedToast: LBL_AR_DQ_ApprovedToast,
  AR_DQ_ColClientProfile: LBL_AR_DQ_ColClientProfile,
  AR_DQ_ColIndicator: LBL_AR_DQ_ColIndicator,
  AR_DQ_ColMc2Segment: LBL_AR_DQ_ColMc2Segment,
  AR_DQ_ColRequester: LBL_AR_DQ_ColRequester,
  AR_DQ_CommentMandatory: LBL_AR_DQ_CommentMandatory,
  AR_DQ_CommentPlaceholder: LBL_AR_DQ_CommentPlaceholder,
  AR_DQ_ConnectedAs: LBL_AR_DQ_ConnectedAs,
  AR_DQ_DecisionRequired: LBL_AR_DQ_DecisionRequired,
  AR_DQ_DerogationReason: LBL_AR_DQ_DerogationReason,
  AR_DQ_FloorPrefix: LBL_AR_DQ_FloorPrefix,
  AR_DQ_IdealPrefix: LBL_AR_DQ_IdealPrefix,
  AR_DQ_MandatoryComment: LBL_AR_DQ_MandatoryComment,
  AR_DQ_Mc2Prefix: LBL_AR_DQ_Mc2Prefix,
  AR_DQ_Mc2WithPerDay: LBL_AR_DQ_Mc2WithPerDay,
  AR_DQ_NoPending: LBL_AR_DQ_NoPending,
  AR_DQ_None: LBL_AR_DQ_None,
  AR_DQ_NoneForYou: LBL_AR_DQ_NoneForYou,
  AR_DQ_NoneYet: LBL_AR_DQ_NoneYet,
  AR_DQ_NoneYetHelp: LBL_AR_DQ_NoneYetHelp,
  AR_DQ_NotFoundMessage: LBL_AR_DQ_NotFoundMessage,
  AR_DQ_NotFoundTitle: LBL_AR_DQ_NotFoundTitle,
  AR_DQ_NotifiedValidatorPrefix: LBL_AR_DQ_NotifiedValidatorPrefix,
  AR_DQ_PendingForOthers: LBL_AR_DQ_PendingForOthers,
  AR_DQ_PillApproved: LBL_AR_DQ_PillApproved,
  AR_DQ_PillPending: LBL_AR_DQ_PillPending,
  AR_DQ_PillRejected: LBL_AR_DQ_PillRejected,
  AR_DQ_ProcessedBy: LBL_AR_DQ_ProcessedBy,
  AR_DQ_ProfitabilityIndicators: LBL_AR_DQ_ProfitabilityIndicators,
  AR_DQ_ProposedRatePrefix: LBL_AR_DQ_ProposedRatePrefix,
  AR_DQ_Rejected: LBL_AR_DQ_Rejected,
  AR_DQ_RejectedToast: LBL_AR_DQ_RejectedToast,
  AR_DQ_SeeAll: LBL_AR_DQ_SeeAll,
  AR_DQ_SegmentBelowFloor: LBL_AR_DQ_SegmentBelowFloor,
  AR_DQ_SegmentPrefix: LBL_AR_DQ_SegmentPrefix,
  AR_DQ_Subtitle: LBL_AR_DQ_Subtitle,
  AR_DQ_TabAll: LBL_AR_DQ_TabAll,
  AR_DQ_TabApproved: LBL_AR_DQ_TabApproved,
  AR_DQ_TabMine: LBL_AR_DQ_TabMine,
  AR_DQ_TabRejected: LBL_AR_DQ_TabRejected,
  AR_DQ_TargetPrefix: LBL_AR_DQ_TargetPrefix,
  AR_DQ_Title: LBL_AR_DQ_Title,
  AR_DQ_TypeAT: LBL_AR_DQ_TypeAT,
  AR_DQ_ValidatorComment: LBL_AR_DQ_ValidatorComment,
  AR_DQ_ViewMatrix: LBL_AR_DQ_ViewMatrix,
  AR_DQ_YouCanProcess: LBL_AR_DQ_YouCanProcess,
  AR_PMS_SegmentLowMargin: LBL_AR_PMS_SegmentLowMargin,
  AR_PMS_SegmentRecommended: LBL_AR_PMS_SegmentRecommended,
  AR_PMS_SegmentSuperstar: LBL_AR_PMS_SegmentSuperstar
};
const BASE_TABS = [
  { key: "all", label: I18N.AR_DQ_TabAll },
  { key: "En attente", label: I18N.AR_Common_Pending },
  { key: "Acceptée", label: I18N.AR_DQ_TabApproved },
  { key: "Refusée", label: I18N.AR_DQ_TabRejected }
];

// Session 33 : onglet par défaut à l'ouverture pour un valideur habilité — un directeur ne doit
// pas devoir chercher ses propres dossiers dans la file globale (58 valideurs, 15 entités dans la
// sandbox réelle). N'apparaît jamais pour un non-valideur (comportement inchangé pour lui).
const MINE_TAB = { key: "mine", label: I18N.AR_DQ_TabMine };

const DECISION_META = {
  "En attente": {
    label: I18N.AR_DQ_PillPending,
    cssClass: "decision-pill decision-pending"
  },
  Acceptée: {
    label: I18N.AR_DQ_PillApproved,
    cssClass: "decision-pill decision-accepted"
  },
  Refusée: {
    label: I18N.AR_DQ_PillRejected,
    cssClass: "decision-pill decision-rejected"
  }
};

const SEGMENT_META = {
  below_floor: {
    label: I18N.AR_DQ_SegmentBelowFloor,
    textClass: "segment-text-red"
  },
  low_margin: {
    label: I18N.AR_PMS_SegmentLowMargin,
    textClass: "segment-text-amber"
  },
  recommended: {
    label: I18N.AR_PMS_SegmentRecommended,
    textClass: "segment-text-green"
  },
  superstar: {
    label: I18N.AR_PMS_SegmentSuperstar,
    textClass: "segment-text-green"
  }
};

// Session 116 — tri par colonne, même système que « Matrices de prix » (arMatrixList, session 115) :
// 1er clic décroissant, 2e croissant ; valeurs absentes toujours en fin de liste ; à égalité, la
// plus récente d'abord. La colonne « Type » (toujours « AT ») n'est pas triable.
const SORT_COLUMNS = [
  {
    key: "client",
    label: I18N.AR_DQ_ColClientProfile,
    thClass: "th th-client"
  },
  { key: "tjm", label: I18N.AR_DQ_ColIndicator, thClass: "th th-indicator" },
  { key: "mc2", label: I18N.AR_DQ_ColMc2Segment, thClass: "th th-mc2" },
  { key: "status", label: I18N.AR_Common_Status, thClass: "th th-status" },
  { key: "requester", label: I18N.AR_DQ_ColRequester, thClass: "th th-owner" },
  { key: "date", label: I18N.AR_Common_CreatedOn, thClass: "th th-date" }
];

// Ordre métier du statut pour le tri : en attente → approuvée → refusée.
const DECISION_RANK = { "En attente": 0, Acceptée: 1, Refusée: 2 };

const TEXT_COLLATOR = new Intl.Collator("fr", { sensitivity: "base" });

/**
 * Parité visuelle avec pricing-tool/pricing-tool.html:2272-2460 (DerogationsPage). Une seule ligne
 * dépliée à la fois (expandedId). arDerogationPanel (record page, accès email) reste inchangé —
 * la logique de décision (AR_DerogationService.decide) est partagée, pas le markup.
 */
const ALL_OPTION_VALUE = "all";

/** ID format: 15 or 18 alphanumeric characters. Links may carry 15 char IDs (listDerogations
 * returns 18 char, but a shared link might have been shortened). */
const ID_FORMAT_REGEX = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;

/** Construit les options d'un filtre à partir des valeurs distinctes d'un champ (session 28 §5) :
 * "Tous les X" en tête, puis les valeurs réellement présentes, triées, jamais une liste en dur —
 * une nouvelle entité/valideur/client apparaît dans le filtre dès la première dérogation qui la
 * porte, sans déploiement. */
function distinctOptions(rows, field, allLabel) {
  const values = new Set();
  rows.forEach((row) => {
    if (row[field]) {
      values.add(row[field]);
    }
  });
  const sorted = Array.from(values).sort((a, b) => a.localeCompare(b, "fr"));
  return [
    { label: allLabel, value: ALL_OPTION_VALUE },
    ...sorted.map((v) => ({ label: v, value: v }))
  ];
}

export default class ArDerogationQueue extends LightningElement {
  i18n = I18N;

  @api focusDerogationId;

  activeTab = "all";
  userSelectedTab = false;
  expandedId;
  // Session 156 : _commentsDraft stocke le texte saisi sans réassigner l'objet réactif à chaque
  // frappe — ne se lit qu'au clic (Accepter/Refuser), jamais affiché par le template.
  _commentsDraft = {};
  focusApplied = false;
  // Session 112 : track si on a déjà fait un refreshApex pour une dérogation manquante
  focusRefreshAttempted = false;
  pendingScrollId;

  // Filtres de la file d'approbation (session 28 §5, exigence spec §7.5) : valideur, agence/BU,
  // client, BM — sur le modèle du filtre de statut de arMatrixList (filtrage côté LWC, une seule
  // méthode Apex cacheable).
  validatorFilter = ALL_OPTION_VALUE;
  entityFilter = ALL_OPTION_VALUE;
  accountFilter = ALL_OPTION_VALUE;
  bmFilter = ALL_OPTION_VALUE;

  sortKey = "date";
  sortDescending = true;

  rawDerogations = [];
  wiredResult;
  isLoading = true;
  errorMessage;

  currentUserIsValidator = false;
  currentUserName = "";
  currentUserJobTitle = "";

  connectedCallback() {
    // Session 40 : une seule règle d'habilitation (AR_Approve_Derogation), plus de diagnostic —
    // « l'onglet n'existe pas » pour un non-habilité est déjà assuré en amont par arPricingApp
    // (entrée de menu masquée, vue non rendue) ; cet appel ne sert plus ici qu'à activer l'onglet
    // « À traiter par moi » et les boutons de décision pour un habilité qui a effectivement
    // atteint ce composant. Repli fail-closed en cas d'échec (masque juste ces deux choses) : le
    // serveur revérifie de toute façon dans listDerogations()/decide(), aucun risque à se tromper
    // prudemment (cf. CLAUDE.md, catégorisation des `catch`).
    isCurrentUserValidator()
      .then((isValidator) => {
        this.currentUserIsValidator = isValidator;
        // Ne force l'onglet par défaut que si l'utilisateur n'a pas déjà cliqué un onglet
        // lui-même (chargement asynchrone : ce callback peut résoudre après un premier clic).
        // Session 109 : focusApplied empêche aussi la réinitialisation si un focus était déjà
        // en cours — sinon un focus appliqué puis isCurrentUserValidator qui résout true
        // rebasculait sur l'onglet 'mine' et faisait disparaître la ligne ciblée.
        if (isValidator && !this.userSelectedTab && !this.focusApplied) {
          this.activeTab = "mine";
        }
      })
      .catch((error) => {
        console.error(
          'arDerogationQueue : isCurrentUserValidator a échoué, onglet "À traiter par moi" et décision masqués par défaut.',
          error
        );
        this.currentUserIsValidator = false;
      });
    getCurrentUserIdentity()
      .then((identity) => {
        this.currentUserName = identity.name;
        this.currentUserJobTitle = identity.jobTitle || "—";
      })
      .catch(() => {
        /* En-tête "Connecté" reste vide si l'appel échoue — non bloquant pour la file. */
      });
  }

  renderedCallback() {
    if (this.pendingScrollId) {
      const rowElement = this.template.querySelector(
        `.derogation-row[data-id="${this.pendingScrollId}"]`
      );
      if (rowElement) {
        rowElement.scrollIntoView({ behavior: "smooth", block: "start" });
        this.pendingScrollId = undefined;
      }
    }
  }

  @wire(listDerogations)
  wiredDerogations(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.rawDerogations = data;
      this.errorMessage = undefined;
      this.isLoading = false;
      this.applyFocusIfNeeded();
    } else if (error) {
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
    }
  }

  applyFocusIfNeeded() {
    if (this.focusApplied || !this.focusDerogationId) {
      return;
    }

    if (!ID_FORMAT_REGEX.test(this.focusDerogationId)) {
      this.showFocusNotFoundWarning();
      return;
    }

    const found = this.rawDerogations.find((d) => {
      const full18CharId = d.derogationId;
      const first15Chars = full18CharId.substring(0, 15);
      return (
        full18CharId === this.focusDerogationId ||
        first15Chars === this.focusDerogationId
      );
    });

    if (!found) {
      // Session 112 : première fois que la dérogation n'est pas trouvée → rafraîchir le cache
      // du wire une seule fois. Seconde fois → afficher le toast d'erreur.
      if (!this.focusRefreshAttempted) {
        this.focusRefreshAttempted = true;
        // Revérification explicite après le rafraîchissement : le wire ne se réémet pas
        // forcément si les données n'ont pas changé — sans ce `then`, un lien vers une
        // dérogation réellement absente ne produirait jamais le toast (échec silencieux).
        // Si le wire s'est réémis entre-temps, applyFocusIfNeeded a déjà conclu (focusApplied).
        Promise.resolve(refreshApex(this.wiredResult))
          .then(() => {
            this.applyFocusIfNeeded();
          })
          .catch((error) => {
            console.error("arDerogationQueue: refreshApex a échoué", error);
            if (!this.focusApplied) {
              this.showFocusNotFoundWarning();
            }
          });
        return;
      }
      this.showFocusNotFoundWarning();
      return;
    }

    this.focusApplied = true;
    this.activeTab = "all";
    this.userSelectedTab = true;
    this.validatorFilter = ALL_OPTION_VALUE;
    this.entityFilter = ALL_OPTION_VALUE;
    this.accountFilter = ALL_OPTION_VALUE;
    this.bmFilter = ALL_OPTION_VALUE;
    this.expandedId = found.derogationId;
    this.pendingScrollId = found.derogationId;
    this.emitDerogationSelect(found.derogationId);
  }

  showFocusNotFoundWarning() {
    this.focusApplied = true;
    this.showToast(
      I18N.AR_DQ_NotFoundTitle,
      I18N.AR_DQ_NotFoundMessage,
      "warning"
    );
    this.emitDerogationSelect(null);
  }

  emitDerogationSelect(derogationId) {
    this.dispatchEvent(
      new CustomEvent("derogationselect", {
        detail: { derogationId: derogationId || null }
      })
    );
  }

  /** Dérogations après les 4 filtres (session 28 §5), AVANT le filtre d'onglet — partagé par
   * `tabs` (compteurs qui reflètent les filtres actifs, pas seulement le statut) et `rows`. */
  get filteredByCriteria() {
    let filtered = this.rawDerogations;
    if (this.validatorFilter !== ALL_OPTION_VALUE) {
      filtered = filtered.filter(
        (d) => d.selectedValidatorName === this.validatorFilter
      );
    }
    if (this.entityFilter !== ALL_OPTION_VALUE) {
      filtered = filtered.filter((d) => d.entity === this.entityFilter);
    }
    if (this.accountFilter !== ALL_OPTION_VALUE) {
      filtered = filtered.filter((d) => d.accountName === this.accountFilter);
    }
    if (this.bmFilter !== ALL_OPTION_VALUE) {
      filtered = filtered.filter((d) => d.requesterName === this.bmFilter);
    }
    return filtered;
  }

  countForTab(key) {
    const base = this.filteredByCriteria;
    if (key === "all") {
      return base.length;
    }
    if (key === "mine") {
      return base.filter(
        (d) => d.decision === "En attente" && d.isAddressedToCurrentUser
      ).length;
    }
    return base.filter((d) => d.decision === key).length;
  }

  get tabs() {
    const list = this.currentUserIsValidator
      ? [MINE_TAB, ...BASE_TABS]
      : BASE_TABS;
    return list.map((tab) => {
      const count = this.countForTab(tab.key);
      const highlightsCount =
        (tab.key === "En attente" || tab.key === "mine") && count > 0;
      return {
        ...tab,
        count,
        cssClass: `tab${tab.key === this.activeTab ? " tab-active" : ""}`,
        countClass: `tab-count${highlightsCount ? " tab-count-amber" : ""}`
      };
    });
  }

  get validatorOptions() {
    return distinctOptions(
      this.rawDerogations,
      "selectedValidatorName",
      I18N.AR_DQ_AllValidators
    );
  }

  get entityOptions() {
    return distinctOptions(
      this.rawDerogations,
      "entity",
      I18N.AR_DQ_AllAgencies
    );
  }

  get accountOptions() {
    return distinctOptions(
      this.rawDerogations,
      "accountName",
      I18N.AR_DQ_AllClients
    );
  }

  get bmOptions() {
    return distinctOptions(
      this.rawDerogations,
      "requesterName",
      I18N.AR_DQ_AllBms
    );
  }

  get hasActiveFilters() {
    return (
      this.validatorFilter !== ALL_OPTION_VALUE ||
      this.entityFilter !== ALL_OPTION_VALUE ||
      this.accountFilter !== ALL_OPTION_VALUE ||
      this.bmFilter !== ALL_OPTION_VALUE
    );
  }

  get rows() {
    const base = this.filteredByCriteria;
    let filtered;
    if (this.activeTab === "all") {
      filtered = base;
    } else if (this.activeTab === "mine") {
      filtered = base.filter(
        (d) => d.decision === "En attente" && d.isAddressedToCurrentUser
      );
    } else {
      filtered = base.filter((d) => d.decision === this.activeTab);
    }
    return [...filtered]
      .sort((a, b) => this.compareRows(a, b))
      .map((d) => {
        const segMeta = d.corridorSegment
          ? SEGMENT_META[d.corridorSegment]
          : null;
        const decisionMeta = DECISION_META[d.decision] || {
          label: d.decision,
          cssClass: "decision-pill"
        };
        const isExpanded = d.derogationId === this.expandedId;
        const isPending = d.decision === "En attente";
        return {
          ...d,
          sublabel: [d.positionName, d.accountCountry]
            .filter(Boolean)
            .join(" — "),
          // Devise de la matrice (session 24) : chaque ligne peut porter une devise différente,
          // cette file n'agrège ni ne convertit rien — juste un affichage ligne par ligne.
          formattedTjm: formatMoney(d.proposedTjm, d.currencyCode),
          tjmPeriodsDetail: formatTjmPeriodsDetail(
            d.tjmPeriods,
            d.currencyCode,
            LBL_AR_TJM_Weighted_Label
          ),
          formattedTjmFloor: formatMoney(d.tjmFloor, d.currencyCode),
          formattedTjmTarget: formatMoney(d.tjmTarget, d.currencyCode),
          formattedTjmIdeal: formatMoney(d.tjmIdeal, d.currencyCode),
          formattedMc2: formatPercent(d.mc2PercentHuman),
          // Session 143 : marge par jour en valeur, même helper et même devise que le TJM.
          formattedMc2PerDay: formatMoney(d.mc2PerDay, d.currencyCode),
          mc2WithPerDayLabel: formatLabel(
            I18N.AR_DQ_Mc2WithPerDay,
            formatPercent(d.mc2PercentHuman),
            formatMoney(d.mc2PerDay, d.currencyCode)
          ),
          // Espace initial porté par la valeur : le compilateur de template LWC supprime l'espace
          // en tête d'un nœud texte littéral (« 8,9 %· 44 € / j » à l'écran, session 176c).
          mc2PerDayLabel: ` · ${formatMoney(d.mc2PerDay, d.currencyCode)} / j`,
          // Régie sans régule (docs/265c §7) : mention secondaire, null hors mode actif.
          rplsrMention: d.rplsrMention,
          mc2Class: this.mc2ValueClass(d.corridorSegment),
          segmentLabel: segMeta ? segMeta.label : "—",
          segmentTextClass: segMeta ? segMeta.textClass : "",
          decisionLabel: decisionMeta.label,
          processedByLabel: formatLabel(
            I18N.AR_DQ_ProcessedBy,
            d.effectiveValidatorName
          ),
          decisionClass: decisionMeta.cssClass,
          formattedRequestedAt: this.formatShortDate(d.requestedAt),
          formattedDecidedAt: d.decidedAt
            ? new Date(d.decidedAt).toLocaleString("fr-FR")
            : "",
          chevronIcon: isExpanded ? "utility:chevronup" : "utility:chevrondown",
          isExpanded,
          isPending,
          canDecide:
            isPending && this.currentUserIsValidator && !d.isOwnRequest,
          showInfoOnly:
            isPending && (!this.currentUserIsValidator || d.isOwnRequest),
          reasonView: buildReasonView(d.reasonLabels, d.requesterReason),
          rfaLine: buildRfaLine(d.matrixRfaPercent, d.accountRfaPercent),
          isApproved: d.decision === "Acceptée",
          isRejected: d.decision === "Refusée",
          comment: this._commentsDraft[d.derogationId] || ""
        };
      });
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
          ? formatLabel(
              this.sortDescending
                ? I18N.AR_Common_SortedDesc
                : I18N.AR_Common_SortedAsc,
              col.label
            )
          : formatLabel(I18N.AR_Common_SortBy, col.label)
      };
    });
  }

  /**
   * TJM : comme dans arMatrixList, regroupement par devise (ordre alphabétique fixe) puis montant
   * dans le sens demandé — jamais de comparaison brute EUR/GBP (session 24b).
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
    if (diff === 0 && this.sortKey === "client") {
      diff =
        dir * TEXT_COLLATOR.compare(a.positionName || "", b.positionName || "");
    }
    if (diff === 0) {
      diff = new Date(b.requestedAt || 0) - new Date(a.requestedAt || 0);
    }
    return diff;
  }

  sortValue(d) {
    switch (this.sortKey) {
      case "client":
        return d.accountName || null;
      case "tjm":
        return d.proposedTjm ? Number(d.proposedTjm) : null;
      case "mc2":
        return d.mc2PercentHuman != null ? Number(d.mc2PercentHuman) : null;
      case "status":
        return d.decision in DECISION_RANK ? DECISION_RANK[d.decision] : null;
      case "requester":
        return d.requesterName || null;
      default:
        return d.requestedAt ? new Date(d.requestedAt).getTime() : null;
    }
  }

  handleSortClick(event) {
    const key = event.currentTarget.dataset.key;
    if (key === this.sortKey) {
      this.sortDescending = !this.sortDescending;
    } else {
      this.sortKey = key;
      this.sortDescending = true;
    }
  }

  get isEmpty() {
    return !this.isLoading && this.rows.length === 0;
  }

  get hasNoDerogationsAtAll() {
    return !this.isLoading && this.rawDerogations.length === 0;
  }

  get isEmptyPendingTab() {
    return this.activeTab === "En attente";
  }

  get isMineTab() {
    return this.activeTab === "mine";
  }

  // Session 40 : plus de diagnostic serveur séparé — calculé directement depuis les lignes déjà
  // chargées par listDerogations() (viewAllRecords donne à un habilité la visibilité sur tout ce
  // qui est "En attente", cf. AR_DerogationService), exclut délibérément les filtres actifs
  // (valideur/agence/client/BM).
  get pendingForOthersLabel() {
    return formatLabel(I18N.AR_DQ_PendingForOthers, this.mineEmptyOthersCount);
  }

  get mineEmptyOthersCount() {
    return this.rawDerogations.filter(
      (d) => d.decision === "En attente" && !d.isAddressedToCurrentUser
    ).length;
  }

  get hasOtherPendingForOthers() {
    return this.mineEmptyOthersCount > 0;
  }

  mc2ValueClass(segment) {
    if (!segment) {
      return "";
    }
    const segmentClass = {
      below_floor: "mc2-red",
      low_margin: "mc2-amber",
      recommended: "mc2-green",
      superstar: "mc2-green"
    };
    return segmentClass[segment] || "";
  }

  formatShortDate(value) {
    if (!value) {
      return "";
    }
    return new Date(value).toLocaleDateString("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      year: "2-digit"
    });
  }

  handleTabClick(event) {
    this.userSelectedTab = true;
    this.activeTab = event.currentTarget.dataset.key;
  }

  handleGoToAllTab() {
    this.userSelectedTab = true;
    this.activeTab = "all";
  }

  handleValidatorFilterChange(event) {
    this.validatorFilter = event.detail.value;
  }

  handleEntityFilterChange(event) {
    this.entityFilter = event.detail.value;
  }

  handleAccountFilterChange(event) {
    this.accountFilter = event.detail.value;
  }

  handleBmFilterChange(event) {
    this.bmFilter = event.detail.value;
  }

  handleResetFilters() {
    this.validatorFilter = ALL_OPTION_VALUE;
    this.entityFilter = ALL_OPTION_VALUE;
    this.accountFilter = ALL_OPTION_VALUE;
    this.bmFilter = ALL_OPTION_VALUE;
  }

  handleRowClick(event) {
    const id = event.currentTarget.dataset.id;
    this.expandedId = this.expandedId === id ? undefined : id;
    this.emitDerogationSelect(this.expandedId);
  }

  // Session 113 : ouvre la matrice liée dans la Matrice AT (arPricingApp.handleOpenMatrix) —
  // même contrat `openmatrix` que arMatrixList/arPricingDashboard.
  handleOpenDerogation(event) {
    event.stopPropagation();
    const matrixId = event.currentTarget.dataset.matrixId;
    if (!matrixId) {
      return;
    }
    this.dispatchEvent(new CustomEvent("openmatrix", { detail: { matrixId } }));
  }

  // oninput, pas onchange (session 31 §1) : onchange sur un <textarea> natif n'attend que la
  // perte de focus, pas la frappe — un clic direct sur Approuver après la saisie dépendait de
  // l'ordre blur/click et échouait par intermittence avec "commentaire obligatoire".
  // Session 156 : mutation directe sans réassignment — évite le re-rendu complet de la file.
  handleCommentInput(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    this._commentsDraft[id] = event.target.value;
  }

  handleCommentClick(event) {
    event.stopPropagation();
  }

  async handleApprove(event) {
    event.stopPropagation();
    await this.decide(event.currentTarget.dataset.id, "Acceptée");
  }

  async handleReject(event) {
    event.stopPropagation();
    await this.decide(event.currentTarget.dataset.id, "Refusée");
  }

  async decide(derogationId, decision) {
    const comment = (this._commentsDraft[derogationId] || "").trim();
    if (!comment) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        I18N.AR_DQ_CommentMandatory,
        "error"
      );
      return;
    }
    try {
      const warning = await decideApex({ derogationId, decision, comment });
      const matrix = this.rawDerogations.find(
        (d) => d.derogationId === derogationId
      );
      const label = formatLabel(
        decision === "Acceptée"
          ? I18N.AR_DQ_ApprovedToast
          : I18N.AR_DQ_RejectedToast,
        matrix ? matrix.matrixName : ""
      ).trim();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        label,
        decision === "Acceptée" ? "success" : "warning"
      );
      logNotificationFailure("decision", warning && warning.detail);
      this.expandedId = undefined;
      this.emitDerogationSelect(null);
      delete this._commentsDraft[derogationId];
      if (decision === "Acceptée" && matrix && matrix.matrixId) {
        await this.generateAvenantAfterAcceptance(matrix.matrixId);
      }
      await refreshApex(this.wiredResult);
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    }
  }

  /**
   * Session 180d (Q10 B) : une dérogation acceptée sur une matrice AVENANT génère aussitôt le
   * document, par le navigateur du valideur (le rendu PDF ne peut pas se faire en asynchrone).
   * Sans effet pour une matrice ordinaire (le serveur renvoie « rien à faire »). La décision est
   * déjà enregistrée : un échec de génération est AFFICHÉ (toast durable, motif nommé) sans jamais
   * défaire la décision ; le BM reprend par « Générer l'avenant » dans le panneau PTF.
   */
  async generateAvenantAfterAcceptance(matrixId) {
    const result = await generateAvenantDocument(matrixId);
    const toast = avenantGenerationToast(result);
    if (toast) {
      this.dispatchEvent(new ShowToastEvent(toast));
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}