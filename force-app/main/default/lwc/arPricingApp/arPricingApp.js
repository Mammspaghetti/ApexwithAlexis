import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { loadStyle } from "lightning/platformResourceLoader";
import isCurrentUserValidator from "@salesforce/apex/AR_DerogationService.isCurrentUserValidator";
import countPendingDerogations from "@salesforce/apex/AR_DerogationService.countPendingDerogations";
import getAdminAccess from "@salesforce/apex/AR_AdminAccessGuard.getAdminAccess";
import PRICE_PILOT_LOGOS from "@salesforce/resourceUrl/AR_PricePilot_Logos";
import AR_PRICING_APP_GLOBAL_CSS from "@salesforce/resourceUrl/AR_PricingAppGlobal";
import LBL_AR_App_BreadcrumbAriaLabel from "@salesforce/label/c.AR_App_BreadcrumbAriaLabel";
import LBL_AR_App_BreadcrumbBackAriaLabel from "@salesforce/label/c.AR_App_BreadcrumbBackAriaLabel";
import LBL_AR_App_BreadcrumbMatrices from "@salesforce/label/c.AR_App_BreadcrumbMatrices";
import LBL_AR_App_ValidatorPermissionMissingTitle from "@salesforce/label/c.AR_App_ValidatorPermissionMissingTitle";
import LBL_AR_App_ValidatorPermissionMissingText from "@salesforce/label/c.AR_App_ValidatorPermissionMissingText";

import LBL_AR_App_Administration from "@salesforce/label/c.AR_App_Administration";
import LBL_AR_App_CollapseSidebar from "@salesforce/label/c.AR_App_CollapseSidebar";
import LBL_AR_App_ComingSoon from "@salesforce/label/c.AR_App_ComingSoon";
import LBL_AR_App_DraftCannotBeSaved from "@salesforce/label/c.AR_App_DraftCannotBeSaved";
import LBL_AR_App_ExpandSidebar from "@salesforce/label/c.AR_App_ExpandSidebar";
import LBL_AR_App_InvalidLinkMessage from "@salesforce/label/c.AR_App_InvalidLinkMessage";
import LBL_AR_App_InvalidLinkTitle from "@salesforce/label/c.AR_App_InvalidLinkTitle";
import LBL_AR_App_LeaveWithoutSaving from "@salesforce/label/c.AR_App_LeaveWithoutSaving";
import LBL_AR_App_MatrixAT from "@salesforce/label/c.AR_App_MatrixAT";
import LBL_AR_App_NavApprovalQueue from "@salesforce/label/c.AR_App_NavApprovalQueue";
import LBL_AR_App_NavCandidateProposal from "@salesforce/label/c.AR_App_NavCandidateProposal";
import LBL_AR_App_NavDashboard from "@salesforce/label/c.AR_App_NavDashboard";
import LBL_AR_App_NavFiSheets from "@salesforce/label/c.AR_App_NavFiSheets";
import LBL_AR_App_NavMatrixCDS from "@salesforce/label/c.AR_App_NavMatrixCDS";
import LBL_AR_App_NavNewMatrixAT from "@salesforce/label/c.AR_App_NavNewMatrixAT";
import LBL_AR_App_NavPtfProposals from "@salesforce/label/c.AR_App_NavPtfProposals";
import LBL_AR_App_UnsavedChangesText from "@salesforce/label/c.AR_App_UnsavedChangesText";
import LBL_AR_App_UnsavedChangesTitle from "@salesforce/label/c.AR_App_UnsavedChangesTitle";
import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_PTF_SaveDraft from "@salesforce/label/c.AR_PTF_SaveDraft";
import LANG from "@salesforce/i18n/lang";
import setMyLanguage from "@salesforce/apex/AR_UserLanguageService.setMyLanguage";

// Libellés du sélecteur de langue : volontairement non traduits (convention des sélecteurs).
// Le message du voile est affiché dans la langue cible, avant le rechargement.
const LANGUAGE_TOGGLE_TO_FR = {
  code: "FR",
  title: "Français",
  languageKey: "fr",
  switchingMessage: "Passage en français…"
};
const LANGUAGE_TOGGLE_TO_EN = {
  code: "EN",
  title: "English",
  languageKey: "en_US",
  switchingMessage: "Switching to English…"
};

const I18N = {
  AR_App_Administration: LBL_AR_App_Administration,
  AR_App_BreadcrumbMatrices: LBL_AR_App_BreadcrumbMatrices,
  AR_App_CollapseSidebar: LBL_AR_App_CollapseSidebar,
  AR_App_ComingSoon: LBL_AR_App_ComingSoon,
  AR_App_DraftCannotBeSaved: LBL_AR_App_DraftCannotBeSaved,
  AR_App_ExpandSidebar: LBL_AR_App_ExpandSidebar,
  AR_App_InvalidLinkMessage: LBL_AR_App_InvalidLinkMessage,
  AR_App_InvalidLinkTitle: LBL_AR_App_InvalidLinkTitle,
  AR_App_LeaveWithoutSaving: LBL_AR_App_LeaveWithoutSaving,
  AR_App_MatrixAT: LBL_AR_App_MatrixAT,
  AR_App_NavApprovalQueue: LBL_AR_App_NavApprovalQueue,
  AR_App_NavCandidateProposal: LBL_AR_App_NavCandidateProposal,
  AR_App_NavDashboard: LBL_AR_App_NavDashboard,
  AR_App_NavFiSheets: LBL_AR_App_NavFiSheets,
  AR_App_NavMatrixCDS: LBL_AR_App_NavMatrixCDS,
  AR_App_NavNewMatrixAT: LBL_AR_App_NavNewMatrixAT,
  AR_App_NavPtfProposals: LBL_AR_App_NavPtfProposals,
  AR_App_UnsavedChangesText: LBL_AR_App_UnsavedChangesText,
  AR_App_UnsavedChangesTitle: LBL_AR_App_UnsavedChangesTitle,
  AR_Common_Cancel: LBL_AR_Common_Cancel,
  AR_PTF_SaveDraft: LBL_AR_PTF_SaveDraft
};
// Debounce du recalcul de hauteur au resize (évite de recalculer à chaque pixel).
const RESIZE_DEBOUNCE_MS = 100;

// Seuil de repli automatique de la barre latérale (session 32) : en dessous, repli sans action
// utilisateur ; au-dessus, dépliée par défaut avec repli manuel disponible. Choisi avec une marge
// au-dessus du plancher supporté de 1152px (CLAUDE.md « Périmètre Lot 1 ») plutôt qu'au ras du
// plancher : à 1152px pile sidebar dépliée, la file d'approbation ne laisse qu'une vingtaine de
// pixels de marge une fois l'arithmétique refaite (cf. docs/32-adaptation-ecran.md) — valeur à
// confirmer avec Alexis, pas un dogme.
const SIDEBAR_AUTO_COLLAPSE_WIDTH = 1280;

// Chargée une seule fois pour l'ensemble de la session navigateur (loadStyle l'injecte dans le
// light DOM de la page, hors du shadow DOM : pas besoin de la recharger par instance/vue).
let globalStyleLoaded = false;

// Clé sessionStorage du fallback (session 13, cf. docs/13-navigation-etat.md) : utilisée uniquement
// pour survivre à un F5 si history.replaceState est silencieusement bloqué par LWS — pas de lien
// partageable dans ce cas, juste la persistance de l'onglet courant.
const SESSION_STORAGE_KEY = "arPricingLastView";

// Alias URL (c__view) <-> vue interne (currentView). Les valeurs URL sont celles attendues par les
// liens d'email (AR_NotificationService) et par tout lien partagé.
const URL_VIEW_TO_INTERNAL = {
  dashboard: "dashboard",
  matriceAT: "simulator",
  matrices: "matrices",
  approbations: "derogations",
  admin: "admin"
};
const INTERNAL_TO_URL_VIEW = {
  dashboard: "dashboard",
  simulator: "matriceAT",
  matrices: "matrices",
  derogations: "approbations",
  admin: "admin"
};

/**
 * Lecture pure des paramètres `c__*` (session 164, extraite de getPageReference pour être partagée
 * avec l'écoute `popstate`). Priorité c__matrixId > c__positionId > c__view. `view` vaut la vue
 * interne (« simulator » dès qu'un Id est présent) ou null quand l'URL ne porte aucun état connu
 * (aucun Id et c__view absent ou inconnu — à l'appelant de distinguer les deux cas via `c__view`).
 * `derogationId` n'est retenu que pour la file d'approbation.
 */
function readNavState(params) {
  const { c__positionId, c__matrixId, c__view, c__derogationId } = params || {};
  if (c__matrixId) {
    return {
      view: "simulator",
      matrixId: c__matrixId,
      positionId: null,
      derogationId: null
    };
  }
  if (c__positionId) {
    return {
      view: "simulator",
      matrixId: null,
      positionId: c__positionId,
      derogationId: null
    };
  }
  if (c__view && URL_VIEW_TO_INTERNAL[c__view]) {
    const view = URL_VIEW_TO_INTERNAL[c__view];
    return {
      view,
      matrixId: null,
      positionId: null,
      derogationId: view === "derogations" ? c__derogationId || null : null
    };
  }
  return { view: null, matrixId: null, positionId: null, derogationId: null };
}

// Ordre exact de la maquette (pricing-tool.html:2464-2472) : les 4 entrées « disabled » sont hors
// périmètre Lot 1 (phases 2/3, cf. CLAUDE.md), affichées pour fidélité visuelle uniquement.
const NAV_ITEMS = [
  {
    view: "dashboard",
    label: I18N.AR_App_NavDashboard,
    iconName: "utility:home"
  },
  {
    view: "simulator",
    label: I18N.AR_App_NavNewMatrixAT,
    iconName: "utility:add"
  },
  {
    view: "cds",
    label: I18N.AR_App_NavMatrixCDS,
    iconName: "utility:groups",
    disabled: true
  },
  {
    view: "matrices",
    label: I18N.AR_App_BreadcrumbMatrices,
    iconName: "utility:table"
  },
  {
    view: "derogations",
    label: I18N.AR_App_NavApprovalQueue,
    iconName: "utility:warning"
  },
  {
    view: "fiche-fi",
    label: I18N.AR_App_NavFiSheets,
    iconName: "utility:case",
    disabled: true
  },
  {
    view: "proposition-ptf",
    label: I18N.AR_App_NavPtfProposals,
    iconName: "utility:description",
    disabled: true
  },
  {
    view: "candidat",
    label: I18N.AR_App_NavCandidateProposal,
    iconName: "utility:groups",
    disabled: true
  }
];

const ADMIN_ITEM = {
  view: "admin",
  label: I18N.AR_App_Administration,
  iconName: "utility:settings"
};

/**
 * Conteneur applicatif du Pricing Tool : sidebar + routing interne par état JS (pas de tabs
 * Salesforce). Reprend fidèlement le design de pricing-tool/pricing-tool.html (sidebar blanche,
 * accents rose ABY #D31876) — cf. docs/07-app-shell.md pour le détail des choix. Navigation
 * profonde (URL) et protection des saisies en cours : docs/13-navigation-etat.md.
 */
export default class ArPricingApp extends LightningElement {
  i18n = I18N;

  currentView = "dashboard";
  simulatorRecordId;
  // Session 117 : drapeau de montage du simulateur, pour forcer un vrai démontage/remontage quand
  // on change de matrice en restant sur la vue simulator. Passe par false puis true après le rendu.
  simulatorMounted = true;
  // Session 113 : zone à cibler à l'ouverture du simulateur ("ptf" depuis le bouton PTF de « Mes
  // matrices »). Consigne ponctuelle, jamais écrite dans l'URL : un F5 rouvre la matrice normalement.
  simulatorFocusSection = null;
  // Session 44 (cf. docs/44-url-matrice-creee.md §3) : simulatorRecordId reste la seule cible de
  // montage (record-id passé à l'enfant, sémantique inchangée) — ces deux champs distinguent ce que
  // le shell sait réellement de cette cible, pour écrire le bon paramètre d'URL (jamais un Id de
  // besoin étiqueté comme un Id de matrice, l'inverse du défaut originel). Mutuellement exclusifs :
  // l'un des deux vaut toujours null quand l'autre est renseigné.
  simulatorMatrixId;
  simulatorPositionId;
  selectedDerogationId;
  // Session 166 : libellé « Besoin — Client » annoncé par le simulateur (événement
  // matrixlabelchange) pour le fil d'Ariane ; remis à null dès que la cible du simulateur change.
  simulatorMatrixLabel = null;
  // Session 166 : état de la liste « Matrices de prix » (recherche, tri, filtres), gardé en mémoire
  // du composant pendant que la liste est démontée. Ni sessionStorage ni URL : un F5 repart à zéro.
  matrixListState = null;
  stateApplied = false;
  lastPageRefKey; // session 184a2 : dernière empreinte des c__* reçue par le wire
  pendingDerogationCount = 0;
  // Masque l'entrée « Administration » pour qui ne détient aucune des trois habilitations de
  // domaine (session 23, redécoupée par domaine session 42) — confort d'affichage uniquement, le
  // contrôle réel est côté serveur (AR_AdminAccessGuard.requireGeneralSettings/requireCurrency/
  // requireReferentials, revérifié aussi par arAdminPage lui-même pour un accès direct par l'URL).
  hasAdminAccess = false;
  // Session 40 : une seule règle — qui détient AR_Approve_Derogation voit l'onglet, sinon il
  // n'existe pas pour lui. Confort d'affichage uniquement ici aussi : AR_DerogationService
  // (listDerogations/decide) revérifie côté serveur pour un accès direct par l'URL.
  canApproveDerogations = false;
  // Vrai dès que la réponse de isCurrentUserValidator est arrivée (succès ou échec) : sans ce drapeau,
  // le message « permission manquante » s'afficherait le temps de l'appel, y compris pour un valideur.
  derogationApproverStateLoaded = false;

  // Repli de la barre latérale (session 32). sidebarManualOverride distingue « pas encore de choix
  // enregistré » (null, l'état suit automatiquement la largeur de fenêtre) d'un choix explicite de
  // l'utilisateur (true/false, prioritaire sur l'automatique, mémorisé via le même mécanisme
  // sessionStorage que la navigation — session 13).
  sidebarCollapsed = false;
  isSwitchingLanguage = false;
  languageSwitchMessage = "";
  sidebarManualOverride = null;

  resizeTimeoutId;
  contentResizeObserver;
  bodyMutationObserver;

  showDirtyModal = false;
  pendingNavigation;
  // Session 164 : dernière URL de l'app connue (écrite ou constatée à l'application d'un popstate).
  // Sert de `returnUrl` quand un Précédent/Suivant est annulé depuis une saisie non enregistrée.
  lastKnownUrl;
  dirtyModalCanSaveDraft = true;

  connectedCallback() {
    this.refreshDerogationApproverState();

    getAdminAccess()
      .then((result) => {
        this.hasAdminAccess = !!(
          result &&
          (result.generalSettings ||
            result.currencyAccess ||
            result.referentials ||
            result.ptfEntities)
        );
      })
      .catch((error) => {
        // Repli fail-closed délibéré (avaler, pas afficher) : masquer l'entrée Administration à un
        // admin dont l'appel a échoué est sans risque (confort d'affichage seulement, cf.
        // arAdminPage qui revérifie côté serveur pour un accès direct par l'URL) — jamais l'inverse.
        // Journalisé pour rester diagnosticable si l'appel échoue systématiquement (session 34).
        console.error(
          "arPricingApp : getAdminAccess a échoué, entrée Administration masquée par défaut.",
          error
        );
        this.hasAdminAccess = false;
      });

    this.restoreSidebarManualPreference();
    this.applySidebarAutoState();

    this.loadGlobalStyle();
    window.addEventListener("resize", this.handleResize);
    window.addEventListener("popstate", this.handlePopState);
    this.ensureBodyMutationObserver();
  }

  /**
   * Session 40 : une seule règle d'habilitation — méthode unique (isCurrentUserValidator,
   * @AuraEnabled(cacheable=true), déjà utilisée par arDerogationQueue) pour savoir si l'onglet « File
   * d'approbation » doit exister, jamais plusieurs appels serveur redondants au chargement du shell.
   * Le badge de compteur (countPendingDerogations) n'est appelé que pour un habilité — masqué avec
   * l'onglet pour tout le monde d'autre, cf. navItems. Rafraîchi à l'ouverture de l'app et à chaque
   * navigation vers la file (pas de polling périodique, hors périmètre de cette session).
   */
  refreshDerogationApproverState() {
    isCurrentUserValidator()
      .then((canApprove) => {
        this.canApproveDerogations = canApprove;
        this.derogationApproverStateLoaded = true;
        return canApprove ? countPendingDerogations() : 0;
      })
      .then((count) => {
        this.pendingDerogationCount = count || 0;
      })
      .catch((error) => {
        // Repli fail-closed (masquer l'onglet à un habilité dont l'appel a échoué est sans risque,
        // cf. CLAUDE.md catégorisation des `catch` — le serveur revérifie de toute façon dans
        // AR_DerogationService.listDerogations()/decide()) : journalisé pour rester diagnosticable.
        console.error(
          "arPricingApp : isCurrentUserValidator/countPendingDerogations a échoué, onglet « File d'approbation » masqué par défaut.",
          error
        );
        this.canApproveDerogations = false;
        this.derogationApproverStateLoaded = true;
        this.pendingDerogationCount = 0;
      });
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this.handleResize);
    window.removeEventListener("popstate", this.handlePopState);
    window.clearTimeout(this.resizeTimeoutId);
    if (this.contentResizeObserver) {
      this.contentResizeObserver.disconnect();
      this.contentResizeObserver = undefined;
    }
    if (this.bodyMutationObserver) {
      this.bodyMutationObserver.disconnect();
      this.bodyMutationObserver = undefined;
    }
  }

  renderedCallback() {
    this.recalcShellHeight();
    this.ensureContentResizeObserver();
  }

  /**
   * Session 20e : ni le `resize` de `window` ni le `ResizeObserver` de `.app-content` (§ci-dessous)
   * ne se déclenchent quand un bandeau Salesforce apparaît/disparaît au-dessus de l'app (bandeau
   * sandbox, notification) — `window.innerHeight` ne change pas (ce n'est pas un redimensionnement
   * de fenêtre) et `.app-content` ne change pas de taille non plus (c'est `.app-shell` qui se
   * retrouve décalé vers le bas, donc son `top` mesuré change, sans qu'aucun des deux déclencheurs
   * existants ne le détecte). Un `MutationObserver` sur les enfants directs de `document.body`
   * (portée volontairement étroite : `childList` seul, pas `subtree`, ces bandeaux étant insérés au
   * plus haut niveau de la page) redéclenche le même recalcul que les deux autres déclencheurs —
   * aucun nouveau calcul de hauteur, seulement une occasion de plus d'exécuter le calcul existant
   * avec un `top` frais.
   */
  ensureBodyMutationObserver() {
    if (this.bodyMutationObserver || typeof MutationObserver === "undefined") {
      return;
    }
    this.bodyMutationObserver = new MutationObserver(() => {
      this.scheduleRecalcShellHeight();
    });
    this.bodyMutationObserver.observe(document.body, { childList: true });
  }

  /**
   * Régression session 20c : `renderedCallback` ne se redéclenche que sur les propres props/state
   * réactifs de CE composant (changement de vue, etc.) — pas quand un petit-enfant profondément
   * imbriqué (ex. `c-ar-ptf-panel` dans le simulateur) charge des données en asynchrone après son
   * propre montage et grandit de ~250px : `.app-shell` gardait alors la hauteur calculée avant que
   * ce contenu n'existe, `.app-content` restait scrollé à son maximum interne tout en laissant le
   * bas réel du contenu sous la fenêtre (jauge de corridor invisible, dont sa légende). Un
   * `ResizeObserver` sur `.app-content` observe la taille réellement rendue, indépendamment du
   * cycle de rendu LWC — tout futur bloc ajouté à n'importe quelle vue redéclenche le recalcul de
   * la même façon, sans plomberie d'événements par composant. Un seul observer par instance
   * (démarré une fois `.app-content` monté, jamais recréé à chaque rendu).
   */
  ensureContentResizeObserver() {
    if (this.contentResizeObserver) {
      return;
    }
    if (typeof ResizeObserver === "undefined") {
      // Absent en jsdom (Jest) ; tous les navigateurs cibles de Lightning Experience l'implémentent.
      // Repli silencieux sur le seul recalcul par window.resize déjà en place.
      return;
    }
    const content = this.template.querySelector(".app-content");
    if (!content) {
      return;
    }
    this.contentResizeObserver = new ResizeObserver(() => {
      this.scheduleRecalcShellHeight();
    });
    this.contentResizeObserver.observe(content);
  }

  scheduleRecalcShellHeight() {
    window.clearTimeout(this.resizeTimeoutId);
    // Debounce du recalcul de hauteur (session 12c, étendu session 20c au ResizeObserver), pas un
    // pattern Locker à risque. Correctif lint session 26 : la directive était scindée sur deux
    // lignes de commentaire et ne portait donc que sur la première (`eslint-disable-next-line` ne
    // couvre qu'une seule ligne), jamais sur l'appel réel juste en dessous.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.resizeTimeoutId = window.setTimeout(() => {
      // Session 32 : même debounce que le recalcul de hauteur, pas un second minuteur — l'état
      // automatique de la sidebar n'a besoin d'être réévalué qu'aux mêmes occasions (resize réel).
      this.applySidebarAutoState();
      this.recalcShellHeight();
    }, RESIZE_DEBOUNCE_MS);
  }

  /**
   * Session 32 : sous SIDEBAR_AUTO_COLLAPSE_WIDTH la sidebar se replie sans action utilisateur ;
   * au-dessus elle reste dépliée par défaut. Un choix manuel déjà enregistré (sidebarManualOverride
   * non nul) prime toujours sur ce calcul automatique.
   */
  applySidebarAutoState() {
    this.sidebarCollapsed =
      this.sidebarManualOverride !== null
        ? this.sidebarManualOverride
        : window.innerWidth < SIDEBAR_AUTO_COLLAPSE_WIDTH;
  }

  handleSidebarToggle() {
    this.sidebarCollapsed = !this.sidebarCollapsed;
    this.sidebarManualOverride = this.sidebarCollapsed;
    this.persistFallbackState();
  }

  /**
   * Lu indépendamment du routage (contrairement à restoreFromFallback, qui ne s'exécute que quand
   * l'URL ne porte aucun état de navigation) : le choix de repli doit survivre à un rechargement
   * quelle que soit la vue ciblée par l'URL. Même clé sessionStorage que la navigation (session 13),
   * pas un second mécanisme de persistance.
   */
  restoreSidebarManualPreference() {
    try {
      const raw = window.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (!raw) {
        return;
      }
      const saved = JSON.parse(raw);
      if (typeof saved.sidebarCollapsed === "boolean") {
        this.sidebarManualOverride = saved.sidebarCollapsed;
      }
    } catch {
      // Fallback best-effort, même logique que restoreFromFallback : une entrée corrompue ne doit
      // pas empêcher l'app de démarrer.
    }
  }

  /**
   * `.slds-brand-band`/la région du template appartiennent au light DOM de la page Lightning,
   * hors du shadow DOM de ce composant : impossible à cibler avec le CSS scopé du LWC. Chargée une
   * seule fois (drapeau de module) — cf. AR-BAND-HACK dans arPricingApp.css pour le détail complet
   * (portée, procédure de retrait).
   */
  loadGlobalStyle() {
    if (globalStyleLoaded) {
      return;
    }
    globalStyleLoaded = true;
    loadStyle(this, AR_PRICING_APP_GLOBAL_CSS).catch((error) => {
      console.error(
        "AR_PricingAppGlobal : échec du chargement du CSS global (marge de 12px autour de l'app non neutralisée).",
        error
      );
    });
  }

  handleResize = () => {
    this.scheduleRecalcShellHeight();
  };

  /**
   * `100vh` ignore le chrome Lightning au-dessus de l'app (~150-172px selon la vue) : la hauteur
   * réelle disponible est mesurée directement (`getBoundingClientRect` de `.app-shell`, déjà décalé
   * par AR-BAND-HACK) plutôt que supposée, pour éliminer le double ascenseur (page externe + app).
   * Recalculée à chaque rendu (donc à chaque changement de vue, le header de vue pouvant faire
   * varier la position) et au resize (débouncé).
   *
   * Pose aussi la zone visible (--ar-zone-top / --ar-zone-height) sur `.app-shell` et sur la modale
   * de sortie non sauvegardée, hors de `.app-shell` : les popups des enfants s'y calent, sous
   * l'en-tête Salesforce.
   */
  recalcShellHeight() {
    const shell = this.template.querySelector(".app-shell");
    if (!shell) {
      return;
    }
    const top = Math.max(0, shell.getBoundingClientRect().top);
    const height = `${Math.max(0, window.innerHeight - top - this.measureBottomInset(shell, top))}px`;
    const zoneTop = `${top}px`;
    shell.style.height = height;
    for (const target of [
      shell,
      this.template.querySelector(".dirty-modal-root")
    ]) {
      if (target) {
        target.style.setProperty("--ar-zone-top", zoneTop);
        target.style.setProperty("--ar-zone-height", height);
      }
    }
  }

  /**
   * Hauteur occupée en bas de la fenêtre par la barre utilitaire Lightning (« Create Event »), qui
   * recouvre l'appli sans réduire `window.innerHeight`. La barre n'est pas lisible depuis ce
   * composant (requête au niveau du document interdite) : on mesure le débordement réel de la page
   * avec le shell à pleine hauteur de fenêtre. Barre absente = aucun débordement = 0. Le calcul ne
   * dépend pas de la hauteur précédente du shell, il ne peut donc pas osciller.
   */
  measureBottomInset(shell, top) {
    shell.style.height = `${window.innerHeight - top}px`;
    return Math.max(
      0,
      document.documentElement.scrollHeight - window.innerHeight
    );
  }

  /**
   * Routeur unique (session 13) : l'URL n'est lue par ce wire qu'une seule fois, au premier
   * chargement (deep link ou quick action) ; les Précédent/Suivant suivants passent par
   * `handlePopState` (session 164). Priorité c__matrixId > c__positionId > c__view (cf.
   * readNavState). Si l'URL ne porte aucun état (ex. history.replaceState bloqué par LWS lors d'une
   * navigation précédente), tente le fallback sessionStorage pour au moins survivre à un F5 — cf.
   * docs/13-navigation-etat.md.
   */
  @wire(CurrentPageReference)
  getPageReference(pageRef) {
    if (!pageRef) {
      return;
    }
    const state = pageRef.state || {};
    const nav = readNavState(state);
    // Session 184a2 : un état arrivé APRÈS le premier (le lanceur du besoin navigue vers une page
    // déjà montée, ou le 1er CurrentPageReference arrive sans état) était ignoré par stateApplied →
    // tableau de bord ou rien. On n'agit que si les paramètres c__* ont CHANGÉ depuis la dernière
    // émission : une ré-émission identique de l'état initial ne doit pas ramener l'utilisateur en
    // arrière (pushState n'émet rien, cf. handlePopState).
    const refKey = JSON.stringify([
      state.c__matrixId || null,
      state.c__positionId || null,
      state.c__view || null,
      state.c__derogationId || null
    ]);
    const previousKey = this.lastPageRefKey;
    this.lastPageRefKey = refKey;
    if (this.stateApplied) {
      if (
        previousKey !== undefined &&
        previousKey !== refKey &&
        nav.view &&
        !this.isCurrentNavState(nav)
      ) {
        this.applyExternalNavigation(nav);
      }
      return;
    }

    if (nav.view === "simulator") {
      const recordId = nav.matrixId || nav.positionId;
      this.simulatorRecordId = recordId;
      this.simulatorMatrixId = nav.matrixId;
      this.simulatorPositionId = nav.positionId;
      this.currentView = "simulator";
    } else if (nav.view) {
      this.currentView = nav.view;
      // Session 109 : si le paramètre c__derogationId est présent et qu'on va vers la file
      // d'approbation, le stocker pour le transmettre à arDerogationQueue.
      if (nav.derogationId) {
        this.selectedDerogationId = nav.derogationId;
      }
    } else if (state.c__view) {
      // Session 26 §3 : un `c__view` présent mais inconnu (alias renommé, lien d'email erroné)
      // retombait silencieusement sur le tableau de bord — l'utilisateur atterrissait ailleurs que
      // prévu sans savoir que son lien était faux. Comportement retenu : rediriger quand même vers
      // le tableau de bord (aucune vue sûre à deviner depuis un alias inconnu), mais le dire.
      this.showToast(
        I18N.AR_App_InvalidLinkTitle,
        I18N.AR_App_InvalidLinkMessage,
        "warning"
      );
      this.restoreFromFallback();
    } else {
      this.restoreFromFallback();
    }
    this.stateApplied = true;
    this.updateUrlState();
  }

  /**
   * Session 164 : Précédent/Suivant du navigateur. `pushState` ne remonte pas la page et ne réveille
   * pas le routeur Lightning (mesuré sur la full sandbox le 12/10) ; seul `popstate` est émis, et il
   * est lu ici. La cible est appliquée sans réécrire l'URL (déjà la bonne). Cible identique à l'état
   * courant, ou URL sans état connu : on ne fait rien (ni toast ni fallback).
   */
  handlePopState = () => {
    if (!this.stateApplied) {
      return;
    }
    const nav = readNavState(
      Object.fromEntries(new URLSearchParams(window.location.search))
    );
    if (!nav.view || this.isCurrentNavState(nav)) {
      return;
    }
    this.applyExternalNavigation(nav);
  };

  /**
   * Cible lue hors premier chargement (Précédent/Suivant, ou nouvel état de page arrivé en second —
   * session 184a2) : confirmation si le simulateur a des modifications non enregistrées, sinon
   * application directe sans réécrire l'URL.
   */
  applyExternalNavigation(nav) {
    this.simulatorFocusSection = null;
    if (this.currentView === "simulator" && this.isSimulatorDirty()) {
      // Un popstate ne s'annule pas : l'URL est déjà sur la cible. On demande confirmation, et
      // Annuler remet l'URL de la matrice (cf. handleDirtyCancel).
      this.openDirtyModal({
        view: nav.view,
        matrixId: nav.matrixId,
        positionId: nav.positionId,
        derogationId: nav.derogationId,
        fromHistory: true,
        returnUrl: this.lastKnownUrl
      });
      return;
    }
    this.applyHistoryTarget(nav);
  }

  isCurrentNavState(nav) {
    if (nav.view !== this.currentView) {
      return false;
    }
    if (nav.view === "simulator") {
      return (
        (this.simulatorMatrixId || null) === nav.matrixId &&
        (this.simulatorPositionId || null) === nav.positionId
      );
    }
    if (nav.view === "derogations") {
      return (this.selectedDerogationId || null) === nav.derogationId;
    }
    return true;
  }

  applyHistoryTarget(target) {
    this.performNavigation(
      target.view,
      target.matrixId,
      target.derogationId,
      "none",
      target.positionId
    );
  }

  /**
   * URL de l'état courant : les `c__*` sont tous recalculés depuis l'état du shell (posés ou
   * retirés), les autres paramètres de l'URL sont conservés. Le chemin
   * `/lightning/n/AR_Pricing_App` est conservé tel quel.
   */
  buildUrl() {
    const params = new URLSearchParams(window.location.search);
    params.set(
      "c__view",
      INTERNAL_TO_URL_VIEW[this.currentView] || this.currentView
    );
    // Session 44 §3 : un Id de besoin (arrivée par quick action, aucune matrice encore créée) ne
    // doit jamais être réécrit sous c__matrixId — c'était le défaut voisin de cette session, qui ne
    // tenait que parce que resolveRecordContext({anyId}) accepte les deux sans distinction.
    if (this.currentView === "simulator" && this.simulatorMatrixId) {
      params.set("c__matrixId", this.simulatorMatrixId);
      params.delete("c__positionId");
    } else if (this.currentView === "simulator" && this.simulatorPositionId) {
      params.set("c__positionId", this.simulatorPositionId);
      params.delete("c__matrixId");
    } else {
      params.delete("c__matrixId");
      params.delete("c__positionId");
    }

    // Session 109 : c__derogationId est posé seulement si currentView === 'derogations' et
    // selectedDerogationId est non nul ; sinon le paramètre est retiré (même motif que c__matrixId).
    // Le paramètre ne sera jamais réécrit quand on est dans une autre vue (getPageReference l'a lu
    // mais ne l'a stocké que si on allait vers 'derogations').
    if (this.currentView === "derogations" && this.selectedDerogationId) {
      params.set("c__derogationId", this.selectedDerogationId);
    } else {
      params.delete("c__derogationId");
    }
    return `${window.location.pathname}?${params.toString()}`;
  }

  /**
   * Écrit l'état de navigation dans l'URL sans remonter le composant (pas de NavigationMixin : une
   * re-navigation remonterait toute la FlexiPage). Doublé d'une écriture sessionStorage (fallback
   * silencieux si l'écriture d'historique est bloquée par LWS — non vérifiable sans accès navigateur
   * dans cette session, cf. docs/13-navigation-etat.md).
   *
   * Session 164, `mode` : « replace » (défaut) remplace l'entrée courante (premier chargement, Id
   * reçu au 1er enregistrement, dérogation consultée) ; « push » ajoute une entrée d'historique
   * (navigation voulue par l'utilisateur), sauf si l'URL est identique à la courante (vue déjà
   * affichée → replace, pas d'entrée en double) ; « none » n'écrit rien (l'URL est déjà la bonne :
   * application d'un popstate), seul le fallback sessionStorage est mis à jour.
   */
  updateUrlState(mode = "replace") {
    if (mode === "none") {
      this.lastKnownUrl = `${window.location.pathname}${window.location.search}`;
      this.persistFallbackState();
      return;
    }
    const url = this.buildUrl();
    try {
      const current = `${window.location.pathname}${window.location.search}`;
      if (mode === "push" && url !== current) {
        window.history.pushState(null, "", url);
      } else {
        window.history.replaceState(null, "", url);
      }
    } catch (error) {
      console.error(
        "arPricingApp : écriture de l'historique indisponible (LWS ?) — repli sur sessionStorage uniquement.",
        error
      );
    }
    this.lastKnownUrl = url;
    this.persistFallbackState();
  }

  /**
   * Fusionnante sur `sidebarCollapsed` (session 32b) : `@wire(CurrentPageReference)` s'exécute
   * avant `connectedCallback`, donc `getPageReference` → `updateUrlState` → cette méthode peut
   * s'exécuter avant que `restoreSidebarManualPreference()` (appelée dans `connectedCallback`)
   * n'ait lu la préférence stockée. À cet instant `sidebarManualOverride` vaut encore `null` (sa
   * valeur de champ par défaut) : écrire `null` ici écraserait un `true`/`false` déjà enregistré
   * avant même que la restauration n'ait eu lieu. Quand `sidebarManualOverride` est `null`, on
   * relit l'entrée existante et on conserve son `sidebarCollapsed` plutôt que de le remplacer —
   * aucun ordre d'exécution ne peut alors détruire une préférence enregistrée. `view`/`matrixId`
   * n'ont pas ce problème : ils sont toujours recalculés depuis `currentView`/`simulatorRecordId`,
   * déjà à jour à ce point de l'exécution.
   */
  persistFallbackState() {
    let sidebarCollapsed = this.sidebarManualOverride;
    if (sidebarCollapsed === null) {
      sidebarCollapsed = this.readStoredSidebarCollapsed();
    }
    try {
      window.sessionStorage.setItem(
        SESSION_STORAGE_KEY,
        JSON.stringify({
          view: this.currentView,
          matrixId:
            this.currentView === "simulator"
              ? this.simulatorMatrixId || null
              : null,
          positionId:
            this.currentView === "simulator"
              ? this.simulatorPositionId || null
              : null,
          sidebarCollapsed
        })
      );
    } catch {
      // sessionStorage indisponible (navigation privée stricte, LWS) : dégradation silencieuse — un
      // F5 sans URL exploitable retombera simplement sur le tableau de bord.
    }
  }

  readStoredSidebarCollapsed() {
    try {
      const raw = window.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (!raw) {
        return null;
      }
      const existing = JSON.parse(raw);
      return typeof existing.sidebarCollapsed === "boolean"
        ? existing.sidebarCollapsed
        : null;
    } catch {
      // Même repli best-effort que restoreSidebarManualPreference/restoreFromFallback (session 34,
      // revue des .catch silencieux) : une entrée sessionStorage corrompue ou indisponible retombe
      // sur l'état automatique par largeur de fenêtre, jamais un plantage pour un simple confort d'UI.
      return null;
    }
  }

  restoreFromFallback() {
    try {
      const raw = window.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (!raw) {
        return;
      }
      const saved = JSON.parse(raw);
      if (saved.matrixId) {
        this.simulatorRecordId = saved.matrixId;
        this.simulatorMatrixId = saved.matrixId;
        this.currentView = "simulator";
      } else if (saved.positionId) {
        this.simulatorRecordId = saved.positionId;
        this.simulatorPositionId = saved.positionId;
        this.currentView = "simulator";
      } else if (saved.view) {
        this.currentView = saved.view;
      }
    } catch {
      // Fallback best-effort : une entrée corrompue ne doit pas empêcher l'app de démarrer.
    }
  }

  /**
   * Session 165 : vue active pour le surlignage de la navigation. Une matrice existante
   * (simulatorMatrixId renseigné) doit montrer « Matrices de prix » comme active, pas « Nouvelle
   * matrice AT ». Une nouvelle matrice en cours (currentView === "simulator" sans matrixId) affiche
   * « Nouvelle matrice AT » surligné. Entrée Admin toujours sur son propre état (aucune vue mixte).
   */
  get activeNavView() {
    if (this.currentView === "simulator" && this.simulatorMatrixId) {
      return "matrices";
    }
    return this.currentView;
  }

  // Session 40 : « l'onglet n'existe pas » pour qui n'a pas la permission — filtré hors de la
  // liste, pas seulement caché par CSS.
  get navItems() {
    return NAV_ITEMS.filter(
      (item) => item.view !== "derogations" || this.canApproveDerogations
    ).map((item) => {
      const pendingBadge =
        item.view === "derogations" && this.pendingDerogationCount > 0
          ? this.pendingDerogationCount
          : 0;
      return {
        ...item,
        cssClass: `nav-item${item.view === this.activeNavView ? " nav-item-active" : ""}${item.disabled ? " nav-item-disabled" : ""}`,
        pendingBadge,
        hasPendingBadge: pendingBadge > 0
      };
    });
  }

  get sidebarCssClass() {
    return `sidebar${this.sidebarCollapsed ? " sidebar-collapsed" : ""}`;
  }

  get logoUrl() {
    return this.sidebarCollapsed
      ? `${PRICE_PILOT_LOGOS}/pricepilot-mark.png`
      : `${PRICE_PILOT_LOGOS}/pricepilot-horizontal.png`;
  }

  get sidebarToggleIcon() {
    return this.sidebarCollapsed
      ? "utility:chevronright"
      : "utility:chevronleft";
  }

  get sidebarToggleLabel() {
    return this.sidebarCollapsed
      ? I18N.AR_App_ExpandSidebar
      : I18N.AR_App_CollapseSidebar;
  }

  /** Propose l'autre langue : FR quand l'interface est en anglais, EN sinon. */
  get languageToggle() {
    return this.isEnglish ? LANGUAGE_TOGGLE_TO_FR : LANGUAGE_TOGGLE_TO_EN;
  }

  get isEnglish() {
    return (LANG || "").startsWith("en");
  }

  /** Code de la langue active (affiché en gras dans le sélecteur). */
  get activeLanguageCode() {
    return this.isEnglish ? "EN" : "FR";
  }

  get frLanguageClass() {
    return this.isEnglish
      ? "language-code"
      : "language-code language-code-active";
  }

  get enLanguageClass() {
    return this.isEnglish
      ? "language-code language-code-active"
      : "language-code";
  }

  get adminItem() {
    return {
      ...ADMIN_ITEM,
      cssClass: `nav-item nav-item-admin${this.activeNavView === "admin" ? " nav-item-active" : ""}`
    };
  }

  labels = {
    breadcrumbAriaLabel: LBL_AR_App_BreadcrumbAriaLabel,
    breadcrumbBackAriaLabel: LBL_AR_App_BreadcrumbBackAriaLabel,
    breadcrumbMatrices: LBL_AR_App_BreadcrumbMatrices,
    validatorPermissionMissingTitle: LBL_AR_App_ValidatorPermissionMissingTitle,
    validatorPermissionMissingText: LBL_AR_App_ValidatorPermissionMissingText
  };

  /**
   * Session 166 : fil d'Ariane « ← Matrices de prix › {matrice} » sur la fiche d'une matrice
   * EXISTANTE uniquement (simulatorMatrixId renseigné) — jamais pour une nouvelle matrice non
   * enregistrée. Pendant le chargement du libellé, seul « ← Matrices de prix » est affiché.
   */
  get showBreadcrumb() {
    return this.currentView === "simulator" && !!this.simulatorMatrixId;
  }

  get hasBreadcrumbLabel() {
    return !!this.simulatorMatrixLabel;
  }

  get isDashboard() {
    return this.currentView === "dashboard";
  }

  get isSimulator() {
    return this.currentView === "simulator";
  }

  get isMatrices() {
    return this.currentView === "matrices";
  }

  // Session 40 : une URL directe (?c__view=approbations) ne doit rien rendre pour qui n'a pas la
  // permission — la vue elle-même est gardée, pas seulement l'entrée de menu qui y mène.
  get isDerogations() {
    return this.currentView === "derogations" && this.canApproveDerogations;
  }

  // Lien de notification ouvert par un utilisateur sans la permission : la vue reste vide côté
  // sécurité, ce getter n'affiche que le message. Attend la réponse serveur pour ne pas clignoter
  // chez un valideur.
  get isDerogationsForbidden() {
    return (
      this.currentView === "derogations" &&
      this.derogationApproverStateLoaded &&
      !this.canApproveDerogations
    );
  }

  get isAdmin() {
    return this.currentView === "admin";
  }

  /**
   * Bascule de langue : même garde-fou que la navigation (modifications non enregistrées du
   * simulateur → même confirmation), puis changement de LanguageLocaleKey et rechargement.
   */
  handleLanguageToggle() {
    const { languageKey } = this.languageToggle;
    if (this.currentView === "simulator" && this.isSimulatorDirty()) {
      this.openDirtyModal({ languageKey });
      return;
    }
    this.switchLanguage(languageKey);
  }

  /**
   * Voile immédiat pendant l'appel Apex, qui reste affiché jusqu'au rechargement. Un second clic
   * est ignoré tant que l'opération est en cours.
   */
  async switchLanguage(languageKey) {
    if (this.isSwitchingLanguage) {
      return;
    }
    this.isSwitchingLanguage = true;
    this.languageSwitchMessage =
      languageKey === LANGUAGE_TOGGLE_TO_FR.languageKey
        ? LANGUAGE_TOGGLE_TO_FR.switchingMessage
        : LANGUAGE_TOGGLE_TO_EN.switchingMessage;
    try {
      await setMyLanguage({ languageKey });
    } catch (error) {
      this.isSwitchingLanguage = false;
      console.error("arPricingApp : changement de langue refusé.", error);
      return;
    }
    window.location.reload();
  }

  handleNavClick(event) {
    const { view, disabled } = event.currentTarget.dataset;
    if (disabled === "true") {
      return;
    }
    this.simulatorFocusSection = null;
    this.navigateTo(view);
  }

  /**
   * Point d'entrée public de la navigation : intercepte le cas « on quitte la Matrice AT avec des
   * modifications non sauvegardées » (session 13) avant de déléguer à performNavigation. Le
   * simulateur expose isDirty/saveDraftForNavigation via `lwc:ref` — cf. arPriceMatrixSimulator.js.
   */
  navigateTo(view, recordId, derogationId) {
    if (
      this.currentView === "simulator" &&
      view !== "simulator" &&
      this.isSimulatorDirty()
    ) {
      this.openDirtyModal({
        view,
        recordId: recordId || null,
        derogationId: derogationId || null
      });
      return;
    }
    this.performNavigation(view, recordId, derogationId);
  }

  openDirtyModal(pending) {
    this.pendingNavigation = pending;
    // Session 26 §2 : ne propose « Enregistrer le brouillon » que si le simulateur peut
    // réellement le faire — sinon le bandeau rouge (taux de change manquant) vient de dire le
    // contraire, et le bouton échouerait à coup sûr.
    const simulator = this.refs.simulator;
    this.dirtyModalCanSaveDraft = !!(simulator && simulator.canSaveDraft);
    this.showDirtyModal = true;
  }

  isSimulatorDirty() {
    const simulator = this.refs.simulator;
    return !!(simulator && simulator.isDirty);
  }

  /**
   * Le simulateur ne relit sa cible qu'à son insertion dans le DOM (connectedCallback) : changer
   * simulatorRecordId sur une instance déjà montée ne provoque pas de rechargement. Quand on reste
   * sur la vue « simulator » et qu'on cible un autre enregistrement (ex. « Nouvelle matrice » cliqué
   * depuis une matrice déjà ouverte), on démonte puis remonte via un aller-retour à null.
   * Session 117 : utiliser simulatorMounted pour forcer un vrai démontage plutôt que de compter
   * uniquement sur isSimulator (qui laisse le composant monté, sans re-lire recordId).
   */
  performNavigation(
    view,
    recordId,
    derogationId,
    mode = "push",
    positionId = null
  ) {
    // Session 164 : `mode` = « push » (navigation utilisateur, défaut) ou « none » (cible d'un
    // popstate, URL déjà écrite). `positionId` : cible simulateur qui est un besoin, jamais rangée
    // sous un Id de matrice (session 44).
    const targetMatrixId = recordId || null;
    const targetPositionId = targetMatrixId ? null : positionId || null;
    const targetRecordId = targetMatrixId || targetPositionId;
    if (
      view === "simulator" &&
      this.currentView === "simulator" &&
      this.simulatorRecordId !== targetRecordId
    ) {
      this.simulatorMounted = false;
      // Session 117 : utiliser setTimeout(0) plutôt qu'un microtask (Promise.resolve) pour que le
      // démontage soit observable au prochain rendu, et que connectedCallback s'exécute sur la nouvelle
      // instance. Nécessaire pour que le composant se remonte réellement au lieu de rester une instance figée.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        this.simulatorMatrixLabel = null;
        this.simulatorRecordId = targetRecordId;
        // handleOpenMatrix est le seul appelant à fournir un recordId ici, toujours un Id de matrice
        // confirmé (« Mes matrices », tableau de bord, chaîne de négociation) — cf. docs/44-url-matrice-
        // creee.md §3. L'absence de recordId (« Matrice AT » depuis le menu) efface aussi bien la
        // matrice que le besoin d'origine : formulaire réellement vierge, pas seulement démonté/remonté.
        this.simulatorMatrixId = targetMatrixId;
        this.simulatorPositionId = targetPositionId;
        this.updateUrlState(mode);
        this.simulatorMounted = true;
      }, 0);
      return;
    }
    if (view === "simulator" && this.currentView !== "simulator") {
      // Nouveau montage du simulateur : il annoncera lui-même le libellé de sa cible.
      this.simulatorMatrixLabel = null;
    }
    this.currentView = view;
    if (view === "simulator") {
      this.simulatorRecordId = targetRecordId;
      this.simulatorMatrixId = targetMatrixId;
      this.simulatorPositionId = targetPositionId;
    }
    // Session 109 : à la navigation vers une autre vue, selectedDerogationId est effacé (le paramètre
    // disparaît de l'URL via updateUrlState). Vers « derogations » alors qu'on y est déjà : ne pas
    // toucher (même derogation conservée, URL inchangée). Vers « derogations » depuis une autre vue :
    // selectedDerogationId reste null (l'URL rend la file sans focus sauf si getPageReference l'a
    // posé — navigation en arrière depuis un lien partagé).
    // Session 112 : derogationId permet de cibler une dérogation en arrivant sur la file.
    if (view !== "derogations") {
      this.selectedDerogationId = null;
    } else if (derogationId || mode === "none") {
      // En « none », la cible vient de l'URL : sans c__derogationId, aucune dérogation ciblée.
      this.selectedDerogationId = derogationId || null;
    }
    if (view === "derogations") {
      this.refreshDerogationApproverState();
    }
    this.updateUrlState(mode);
  }

  handleOpenMatrix(event) {
    this.simulatorFocusSection = event.detail.focusSection || null;
    this.navigateTo("simulator", event.detail.matrixId);
  }

  /** Retour à la liste depuis le fil d'Ariane : toujours navigateTo (garde-fou dirty inclus), jamais history.back(). */
  handleBreadcrumbBack() {
    this.simulatorFocusSection = null;
    this.navigateTo("matrices");
  }

  handleMatrixLabelChange(event) {
    this.simulatorMatrixLabel = event.detail.label || null;
  }

  handleMatrixListStateChange(event) {
    this.matrixListState = event.detail;
  }

  handleOpenDecision(event) {
    this.navigateTo("derogations", null, event.detail.derogationId);
  }

  /**
   * Session 44 (cf. docs/44-url-matrice-creee.md §2) : le simulateur annonce l'Id qu'il vient
   * d'obtenir du serveur (brouillon, validation, dérogation, autosauvegarde, reprise de brouillon) —
   * jamais via navigateTo/performNavigation, qui démonterait/remonterait le composant en pleine
   * saisie. On enregistre l'Id confirmé et on réécrit l'URL ; l'instance déjà montée du simulateur
   * n'est jamais touchée (elle ne relit recordId qu'à connectedCallback).
   */
  handleMatrixIdChange(event) {
    const matrixId = event.detail.matrixId;
    this.simulatorRecordId = matrixId;
    this.simulatorMatrixId = matrixId;
    this.simulatorPositionId = null;
    if (this.pendingNavigation && this.pendingNavigation.fromHistory) {
      // Session 164 : un Précédent/Suivant attend la réponse de la modale, l'entrée courante porte
      // déjà l'URL de la cible — ne pas la réécrire. On met seulement à jour l'URL de retour.
      this.pendingNavigation.returnUrl = this.buildUrl();
      this.persistFallbackState();
      return;
    }
    this.updateUrlState();
  }

  /**
   * Session 291c : le simulateur monté n'a pas pu ouvrir la matrice demandée (supprimée ou plus accessible). Il reste
   * monté (message visible, sélection du besoin disponible) ; on retire l'identifiant de l'URL, remplacement sans
   * nouvelle entrée d'historique.
   */
  handleMatrixUnavailable() {
    this.simulatorRecordId = null;
    this.simulatorMatrixId = null;
    this.simulatorPositionId = null;
    this.simulatorMatrixLabel = null;
    this.updateUrlState();
  }

  handleDerogationSelect(event) {
    const derogationId = event.detail.derogationId || null;
    this.selectedDerogationId = derogationId;
    this.updateUrlState();
  }

  handleDirtySaveAndLeave() {
    const simulator = this.refs.simulator;
    if (!simulator) {
      this.completePendingNavigation();
      return;
    }
    simulator
      .saveDraftForNavigation()
      .then(() => {
        this.completePendingNavigation();
      })
      .catch(() => {
        // L'échec est déjà remonté par le simulateur (toast) : on reste sur la vue, rien à ajouter ici.
        this.cancelPendingNavigation();
      });
  }

  handleDirtyDiscard() {
    this.completePendingNavigation();
  }

  handleDirtyCancel() {
    this.cancelPendingNavigation();
  }

  /**
   * Abandon de la navigation en attente. Pour un Précédent/Suivant (session 164), l'URL est déjà
   * sur la cible : on remet celle de la matrice (nouvelle entrée, `popstate` n'étant pas annulable).
   */
  cancelPendingNavigation() {
    const nav = this.pendingNavigation;
    this.showDirtyModal = false;
    this.pendingNavigation = null;
    if (nav && nav.fromHistory && nav.returnUrl) {
      try {
        window.history.pushState(null, "", nav.returnUrl);
      } catch (error) {
        console.error(
          "arPricingApp : impossible de restaurer l'URL après annulation (LWS ?).",
          error
        );
      }
      this.lastKnownUrl = nav.returnUrl;
    }
  }

  completePendingNavigation() {
    this.showDirtyModal = false;
    const nav = this.pendingNavigation;
    this.pendingNavigation = null;
    if (nav && nav.languageKey) {
      this.switchLanguage(nav.languageKey);
    } else if (nav && nav.fromHistory) {
      this.applyHistoryTarget(nav);
    } else if (nav) {
      this.performNavigation(nav.view, nav.recordId, nav.derogationId);
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}