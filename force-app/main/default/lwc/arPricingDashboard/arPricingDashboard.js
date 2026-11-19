import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import LANG from "@salesforce/i18n/lang";
import getDashboardAnalytics from "@salesforce/apex/AR_DashboardService.getDashboardAnalytics";
import getDashboardTab from "@salesforce/apex/AR_DashboardService.getDashboardTab";
import getDashboardData from "@salesforce/apex/AR_DashboardService.getDashboardData";
import getPricingSettings from "@salesforce/apex/AR_PricingMatrixService.getPricingSettings";
import {
  formatMoney,
  formatPercent,
  getCorridorSegment
} from "c/arPricingEngine";
import { reduceErrors } from "c/arErrorUtils";
import { formatLabel, pluralLabel } from "c/arI18n";
import { LBL, axisNoun, fill, pct } from "c/arDashboardShared";
import LBL_AR_App_NavDashboard from "@salesforce/label/c.AR_App_NavDashboard";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_DB_AverageMc2 from "@salesforce/label/c.AR_DB_AverageMc2";
import LBL_AR_DB_AverageRateEur from "@salesforce/label/c.AR_DB_AverageRateEur";
import LBL_AR_DB_CorridorThresholdsUnavailable from "@salesforce/label/c.AR_DB_CorridorThresholdsUnavailable";
import LBL_AR_DB_DefaultCorridorColors from "@salesforce/label/c.AR_DB_DefaultCorridorColors";
import LBL_AR_DB_DefaultCorridorColorsWithValues from "@salesforce/label/c.AR_DB_DefaultCorridorColorsWithValues";
import LBL_AR_DB_NoEntity from "@salesforce/label/c.AR_DB_NoEntity";
import LBL_AR_DB_DerogationRate from "@salesforce/label/c.AR_DB_DerogationRate";
import LBL_AR_DB_InsufficientData from "@salesforce/label/c.AR_DB_InsufficientData";
import LBL_AR_DB_LatestMatrices from "@salesforce/label/c.AR_DB_LatestMatrices";
import LBL_AR_DB_NoMatrixYetHelp from "@salesforce/label/c.AR_DB_NoMatrixYetHelp";
import LBL_AR_DB_SavedMatricesMany from "@salesforce/label/c.AR_DB_SavedMatricesMany";
import LBL_AR_DB_SavedMatricesOne from "@salesforce/label/c.AR_DB_SavedMatricesOne";
import LBL_AR_DB_SegmentBreakdown from "@salesforce/label/c.AR_DB_SegmentBreakdown";
import LBL_AR_DB_ValidatedMatrices from "@salesforce/label/c.AR_DB_ValidatedMatrices";
import LBL_AR_DB_FilterPeriod from "@salesforce/label/c.AR_DB_FilterPeriod";
import LBL_AR_DB_PeriodLast12 from "@salesforce/label/c.AR_DB_PeriodLast12";
import LBL_AR_DB_PeriodYear from "@salesforce/label/c.AR_DB_PeriodYear";
import LBL_AR_DB_PeriodAll from "@salesforce/label/c.AR_DB_PeriodAll";
import LBL_AR_DB_PeriodCustom from "@salesforce/label/c.AR_DB_PeriodCustom";
import LBL_AR_DB_FilterFrom from "@salesforce/label/c.AR_DB_FilterFrom";
import LBL_AR_DB_FilterTo from "@salesforce/label/c.AR_DB_FilterTo";
import LBL_AR_DB_FilterEntity from "@salesforce/label/c.AR_DB_FilterEntity";
import LBL_AR_DB_FilterCountry from "@salesforce/label/c.AR_DB_FilterCountry";
import LBL_AR_DB_FilterAllEntities from "@salesforce/label/c.AR_DB_FilterAllEntities";
import LBL_AR_DB_FilterAllCountries from "@salesforce/label/c.AR_DB_FilterAllCountries";
import LBL_AR_DB_FilterReset from "@salesforce/label/c.AR_DB_FilterReset";
import LBL_AR_DB_ValidationTitle from "@salesforce/label/c.AR_DB_ValidationTitle";
import LBL_AR_DB_ValidationDirect from "@salesforce/label/c.AR_DB_ValidationDirect";
import LBL_AR_DB_ValidationDerogation from "@salesforce/label/c.AR_DB_ValidationDerogation";
import LBL_AR_DB_Mc2BandsTitle from "@salesforce/label/c.AR_DB_Mc2BandsTitle";
import LBL_AR_DB_ThresholdsTitle from "@salesforce/label/c.AR_DB_ThresholdsTitle";
import LBL_AR_DB_ThresholdsByEntity from "@salesforce/label/c.AR_DB_ThresholdsByEntity";
import LBL_AR_DB_Others from "@salesforce/label/c.AR_DB_Others";
import LBL_AR_DB_ReasonsTitle from "@salesforce/label/c.AR_DB_ReasonsTitle";
import LBL_AR_DB_ReasonsCount from "@salesforce/label/c.AR_DB_ReasonsCount";
import LBL_AR_DB_TrendTitle from "@salesforce/label/c.AR_DB_TrendTitle";
import LBL_AR_DB_ClientsBest from "@salesforce/label/c.AR_DB_ClientsBest";
import LBL_AR_DB_ClientsWorst from "@salesforce/label/c.AR_DB_ClientsWorst";
import LBL_AR_DB_ClientsSingle from "@salesforce/label/c.AR_DB_ClientsSingle";
import LBL_AR_DB_ClientsNone from "@salesforce/label/c.AR_DB_ClientsNone";
import LBL_AR_DB_ColAccount from "@salesforce/label/c.AR_DB_ColAccount";
import LBL_AR_DB_ColMatrices from "@salesforce/label/c.AR_DB_ColMatrices";
import LBL_AR_DB_ColMc2 from "@salesforce/label/c.AR_DB_ColMc2";
import LBL_AR_DB_ColRate from "@salesforce/label/c.AR_DB_ColRate";
import LBL_AR_DB_NoDataPeriod from "@salesforce/label/c.AR_DB_NoDataPeriod";
import LBL_AR_DB_ChartTotal from "@salesforce/label/c.AR_DB_ChartTotal";
import LBL_AR_DQ_SegmentBelowFloor from "@salesforce/label/c.AR_DQ_SegmentBelowFloor";
import LBL_AR_ML_NoMatrixYet from "@salesforce/label/c.AR_ML_NoMatrixYet";
import LBL_AR_PMS_SegmentLowMargin from "@salesforce/label/c.AR_PMS_SegmentLowMargin";
import LBL_AR_PMS_SegmentRecommended from "@salesforce/label/c.AR_PMS_SegmentRecommended";
import LBL_AR_PMS_SegmentSuperstar from "@salesforce/label/c.AR_PMS_SegmentSuperstar";

const I18N = {
  AR_App_NavDashboard: LBL_AR_App_NavDashboard,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_DB_AverageMc2: LBL_AR_DB_AverageMc2,
  AR_DB_AverageRateEur: LBL_AR_DB_AverageRateEur,
  AR_DB_CorridorThresholdsUnavailable: LBL_AR_DB_CorridorThresholdsUnavailable,
  AR_DB_DefaultCorridorColors: LBL_AR_DB_DefaultCorridorColors,
  AR_DB_DefaultCorridorColorsWithValues:
    LBL_AR_DB_DefaultCorridorColorsWithValues,
  AR_DB_DerogationRate: LBL_AR_DB_DerogationRate,
  AR_DB_NoEntity: LBL_AR_DB_NoEntity,
  AR_DB_InsufficientData: LBL_AR_DB_InsufficientData,
  AR_DB_LatestMatrices: LBL_AR_DB_LatestMatrices,
  AR_DB_NoMatrixYetHelp: LBL_AR_DB_NoMatrixYetHelp,
  AR_DB_SavedMatricesMany: LBL_AR_DB_SavedMatricesMany,
  AR_DB_SavedMatricesOne: LBL_AR_DB_SavedMatricesOne,
  AR_DB_SegmentBreakdown: LBL_AR_DB_SegmentBreakdown,
  AR_DB_ValidatedMatrices: LBL_AR_DB_ValidatedMatrices,
  AR_DB_FilterPeriod: LBL_AR_DB_FilterPeriod,
  AR_DB_PeriodLast12: LBL_AR_DB_PeriodLast12,
  AR_DB_PeriodYear: LBL_AR_DB_PeriodYear,
  AR_DB_PeriodAll: LBL_AR_DB_PeriodAll,
  AR_DB_PeriodCustom: LBL_AR_DB_PeriodCustom,
  AR_DB_FilterFrom: LBL_AR_DB_FilterFrom,
  AR_DB_FilterTo: LBL_AR_DB_FilterTo,
  AR_DB_FilterEntity: LBL_AR_DB_FilterEntity,
  AR_DB_FilterCountry: LBL_AR_DB_FilterCountry,
  AR_DB_FilterAllEntities: LBL_AR_DB_FilterAllEntities,
  AR_DB_FilterAllCountries: LBL_AR_DB_FilterAllCountries,
  AR_DB_FilterReset: LBL_AR_DB_FilterReset,
  AR_DB_ValidationTitle: LBL_AR_DB_ValidationTitle,
  AR_DB_ValidationDirect: LBL_AR_DB_ValidationDirect,
  AR_DB_ValidationDerogation: LBL_AR_DB_ValidationDerogation,
  AR_DB_Mc2BandsTitle: LBL_AR_DB_Mc2BandsTitle,
  AR_DB_ThresholdsTitle: LBL_AR_DB_ThresholdsTitle,
  AR_DB_ThresholdsByEntity: LBL_AR_DB_ThresholdsByEntity,
  AR_DB_Others: LBL_AR_DB_Others,
  AR_DB_ReasonsTitle: LBL_AR_DB_ReasonsTitle,
  AR_DB_ReasonsCount: LBL_AR_DB_ReasonsCount,
  AR_DB_TrendTitle: LBL_AR_DB_TrendTitle,
  AR_DB_ClientsBest: LBL_AR_DB_ClientsBest,
  AR_DB_ClientsWorst: LBL_AR_DB_ClientsWorst,
  AR_DB_ClientsSingle: LBL_AR_DB_ClientsSingle,
  AR_DB_ClientsNone: LBL_AR_DB_ClientsNone,
  AR_DB_ColAccount: LBL_AR_DB_ColAccount,
  AR_DB_ColMatrices: LBL_AR_DB_ColMatrices,
  AR_DB_ColMc2: LBL_AR_DB_ColMc2,
  AR_DB_ColRate: LBL_AR_DB_ColRate,
  AR_DB_NoDataPeriod: LBL_AR_DB_NoDataPeriod,
  AR_DB_ChartTotal: LBL_AR_DB_ChartTotal,
  AR_DQ_SegmentBelowFloor: LBL_AR_DQ_SegmentBelowFloor,
  AR_ML_NoMatrixYet: LBL_AR_ML_NoMatrixYet,
  AR_PMS_SegmentLowMargin: LBL_AR_PMS_SegmentLowMargin,
  AR_PMS_SegmentRecommended: LBL_AR_PMS_SegmentRecommended,
  AR_PMS_SegmentSuperstar: LBL_AR_PMS_SegmentSuperstar
};
// Sous ce seuil, un taux ou une moyenne n'a pas de sens statistique (ex. 1 dérogation sur 1
// matrice = « 100 % » de dérogation) : le dashboard affiche « — » plutôt qu'un chiffre trompeur.
const MIN_SAMPLE_SIZE = 3;

const SEGMENT_META = {
  below_floor: {
    label: I18N.AR_DQ_SegmentBelowFloor,
    cssClass: "bar-fill segment-below-floor"
  },
  low_margin: {
    label: I18N.AR_PMS_SegmentLowMargin,
    cssClass: "bar-fill segment-low-margin"
  },
  recommended: {
    label: I18N.AR_PMS_SegmentRecommended,
    cssClass: "bar-fill segment-recommended"
  },
  superstar: {
    label: I18N.AR_PMS_SegmentSuperstar,
    cssClass: "bar-fill segment-superstar"
  }
};

// Cards de seuils maquette (session 10) — mêmes teintes que les pills de segment, réutilisées
// pour colorer la valeur MC2 moyenne "selon le sens" (below_floor/low_margin en rouge/ambre,
// recommended/superstar en vert — un seul token vert fourni par la maquette pour ces deux-là).
const KPI_MC2_CLASS = {
  below_floor: "kpi-card kpi-tint-red",
  low_margin: "kpi-card kpi-tint-amber",
  recommended: "kpi-card kpi-tint-green",
  superstar: "kpi-card kpi-tint-green"
};

const SEGMENT_COLORS = {
  below_floor: "#dc2626",
  low_margin: "#f59e0b",
  recommended: "#4ade80",
  superstar: "#16a34a"
};
const SEGMENT_ORDER = ["below_floor", "low_margin", "recommended", "superstar"];
// Du vert (haute marge) au rouge (basse) pour les tranches de MC2.
const BAND_COLORS = ["#16a34a", "#4ade80", "#f59e0b", "#dc2626"];
const VALIDATION_COLORS = { direct: "#16a34a", derogation: "#D31876" };
const MAX_ENTITIES = 8;
const MC2_CLASS = {
  below_floor: "mc2-red",
  low_margin: "mc2-amber",
  recommended: "mc2-green",
  superstar: "mc2-green"
};

const AXIS_BM = "bm";
const AXIS_ENTITY = "entity";
const AXIS_PERIMETER = "perimeter";
const AXIS_GROUP = "group";
const TAB_OVERVIEW = "overview";
const TAB_DEROGATIONS = "derogations";
const TAB_PROFITABILITY = "profitability";
const TAB_WON = "won";
// Valeur de `c__tab` (lien de la notification « affaire gagnée ») → onglet.
const DEEP_LINK_TABS = {
  won: TAB_WON,
  derogations: TAB_DEROGATIONS,
  profitability: TAB_PROFITABILITY,
  overview: TAB_OVERVIEW
};
const FUNNEL_COLORS = ["#3b82f6", "#16a34a", "#0f766e"];

const PERIOD_LAST12 = "last12";
const PERIOD_YEAR = "year";
const PERIOD_ALL = "all";
const PERIOD_CUSTOM = "custom";

function isoDate(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function defaultFilters() {
  return {
    period: PERIOD_LAST12,
    from: "",
    to: "",
    entityId: "",
    country: "",
    axis: AXIS_ENTITY,
    motifAxisValue: ""
  };
}

export default class ArPricingDashboard extends LightningElement {
  i18n = I18N;
  lbl = LBL;

  activeTab = TAB_OVERVIEW;
  // Données par onglet chargé à la demande : { data, key, loading, error } (objet remplacé à chaque changement).
  tabStates = {};
  analyticsKey;
  showWonDialog = false;
  wonPositionId;
  _tabSeq = {};
  _deepLinkApplied = false;

  isLoading = true;
  isRefreshing = false;
  errorMessage;
  settingsErrorMessage;
  data;
  analytics;
  corridorSettings;
  filters = defaultFilters();
  _requestSeq = 0;

  connectedCallback() {
    this.loadCorridorSettings();
    this.loadAnalytics();
  }

  // Dernières matrices et nombre total (état vide) : indépendants des filtres.
  @wire(getDashboardData)
  wiredData({ data, error }) {
    if (data) {
      this.data = data;
    } else if (error) {
      this.errorMessage = this.reduceError(error);
    }
  }

  loadCorridorSettings() {
    getPricingSettings()
      .then((result) => {
        this.corridorSettings = result;
        this.settingsErrorMessage = undefined;
      })
      .catch((error) => {
        this.corridorSettings = undefined;
        this.settingsErrorMessage = formatLabel(
          I18N.AR_DB_CorridorThresholdsUnavailable,
          this.reduceError(error)
        );
      });
  }

  // Filtres sérialisés pour Apex (dates ISO yyyy-MM-dd, champs vides omis).
  buildFiltersJson() {
    const f = this.filters;
    const payload = {};
    const today = new Date();
    if (f.period === PERIOD_LAST12) {
      payload.validatedFrom = isoDate(
        new Date(today.getFullYear(), today.getMonth() - 12, today.getDate())
      );
    } else if (f.period === PERIOD_YEAR) {
      payload.validatedFrom = isoDate(new Date(today.getFullYear(), 0, 1));
    } else if (f.period === PERIOD_CUSTOM) {
      if (f.from) {
        payload.validatedFrom = f.from;
      }
      if (f.to) {
        payload.validatedTo = f.to;
      }
    }
    // En vue Groupe, Entité et Pays sont ignorés (le serveur aussi) : on ne les envoie pas.
    if (f.axis !== AXIS_GROUP) {
      if (f.entityId) {
        payload.entityId = f.entityId;
      }
      if (f.country) {
        payload.entityCountry = f.country;
      }
    }
    // « entity » est l'axe par défaut du serveur : omis, comme avant l'ajout de l'axe.
    if (f.axis && f.axis !== AXIS_ENTITY) {
      payload.axis = f.axis;
    }
    return JSON.stringify(payload);
  }

  // Filtres de l'onglet Dérogations : + valeur d'axe retenue pour la pastille des motifs.
  buildTabFiltersJson(tab) {
    const payload = JSON.parse(this.buildFiltersJson());
    if (tab === TAB_DEROGATIONS && this.filters.motifAxisValue) {
      payload.motifAxisValue = this.filters.motifAxisValue;
    }
    return JSON.stringify(payload);
  }

  loadAnalytics() {
    const seq = ++this._requestSeq;
    this.isRefreshing = !!this.analytics;
    const key = this.buildFiltersJson();
    getDashboardAnalytics({ filtersJson: key })
      .then((result) => {
        if (seq !== this._requestSeq) {
          return;
        }
        this.analytics =
          typeof result === "string" ? JSON.parse(result) : result;
        this.analyticsKey = key;
        this.errorMessage = undefined;
      })
      .catch((error) => {
        if (seq !== this._requestSeq) {
          return;
        }
        this.errorMessage = this.reduceError(error);
      })
      .finally(() => {
        if (seq === this._requestSeq) {
          this.isLoading = false;
          this.isRefreshing = false;
        }
      });
  }

  // ---------- Filtres ----------

  get periodOptions() {
    return [
      { label: I18N.AR_DB_PeriodLast12, value: PERIOD_LAST12 },
      { label: I18N.AR_DB_PeriodYear, value: PERIOD_YEAR },
      { label: I18N.AR_DB_PeriodAll, value: PERIOD_ALL },
      { label: I18N.AR_DB_PeriodCustom, value: PERIOD_CUSTOM }
    ];
  }

  get isCustomPeriod() {
    return this.filters.period === PERIOD_CUSTOM;
  }

  get filterOptions() {
    return (this.analytics && this.analytics.filterOptions) || {};
  }

  get countryOptions() {
    const countries = this.filterOptions.countries || [];
    return [
      { label: I18N.AR_DB_FilterAllCountries, value: "" },
      ...countries.map((c) => ({ label: c, value: c }))
    ];
  }

  // Choisir un pays restreint la liste des entités à ce pays.
  get entityOptions() {
    const entities = (this.filterOptions.entities || []).filter(
      (e) => !this.filters.country || e.country === this.filters.country
    );
    return [
      { label: I18N.AR_DB_FilterAllEntities, value: "" },
      ...entities.map((e) => ({ label: e.name, value: e.id }))
    ];
  }

  updateFilters(patch) {
    this.filters = { ...this.filters, ...patch };
    this.reloadActive();
  }

  // Un changement de filtre recharge l'onglet affiché ; les autres se rechargeront à leur prochaine
  // ouverture (leur clé de filtres ne correspondra plus).
  reloadActive() {
    if (this.activeTab === TAB_OVERVIEW) {
      this.loadAnalytics();
    } else {
      this.loadTab(this.activeTab);
    }
  }

  handlePeriodChange(event) {
    this.updateFilters({ period: event.detail.value });
  }

  handleFromChange(event) {
    this.updateFilters({ from: event.detail.value || "" });
  }

  handleToChange(event) {
    this.updateFilters({ to: event.detail.value || "" });
  }

  handleCountryChange(event) {
    const country = event.detail.value;
    const entity = (this.filterOptions.entities || []).find(
      (e) => e.id === this.filters.entityId
    );
    const keepEntity = !country || (entity && entity.country === country);
    this.updateFilters({
      country,
      entityId: keepEntity ? this.filters.entityId : ""
    });
  }

  handleEntityChange(event) {
    this.updateFilters({ entityId: event.detail.value });
  }

  handleReset() {
    this.filters = defaultFilters();
    this.reloadActive();
  }

  // ---------- Axe d'analyse ----------

  get axisButtons() {
    return [
      [AXIS_BM, LBL.AxisBm],
      [AXIS_ENTITY, LBL.AxisEntity],
      [AXIS_PERIMETER, LBL.AxisPerimeter],
      [AXIS_GROUP, LBL.AxisGroup]
    ].map(([value, label]) => {
      const active = this.filters.axis === value;
      return {
        value,
        label,
        pressed: String(active),
        className: active ? "axis-btn is-active" : "axis-btn"
      };
    });
  }

  get isGroupAxis() {
    return this.filters.axis === AXIS_GROUP;
  }

  handleAxisClick(event) {
    const axis = event.currentTarget.dataset.axis;
    if (axis === this.filters.axis) {
      return;
    }
    // La pastille de motif est propre à un axe : elle repart de « Tous ».
    this.updateFilters({ axis, motifAxisValue: "" });
  }

  get axisNounText() {
    return axisNoun(this.filters.axis);
  }

  // ---------- Onglets ----------

  get tabs() {
    return [
      [TAB_OVERVIEW, LBL.TabOverview],
      [TAB_DEROGATIONS, LBL.TabDerogations],
      [TAB_PROFITABILITY, LBL.TabProfitability],
      [TAB_WON, LBL.TabWon]
    ].map(([value, label]) => {
      const active = this.activeTab === value;
      return {
        value,
        label,
        selected: String(active),
        tabIndex: active ? "0" : "-1",
        className: active ? "tab-btn is-active" : "tab-btn"
      };
    });
  }

  get isOverview() {
    return this.activeTab === TAB_OVERVIEW;
  }

  get isDerogationsTab() {
    return this.activeTab === TAB_DEROGATIONS;
  }

  get isProfitabilityTab() {
    return this.activeTab === TAB_PROFITABILITY;
  }

  get isWonTab() {
    return this.activeTab === TAB_WON;
  }

  get activeTabState() {
    return this.tabStates[this.activeTab] || {};
  }

  get activeTabData() {
    return this.activeTabState.data;
  }

  get showTabSkeleton() {
    return !this.isOverview && !this.activeTabData && !this.activeTabError;
  }

  get activeTabError() {
    return this.activeTabState.error;
  }

  get showTabContent() {
    return !this.isOverview && !!this.activeTabData;
  }

  get tabBodyClass() {
    return this.activeTabState.loading
      ? "tab-content is-refreshing"
      : "tab-content";
  }

  handleTabClick(event) {
    this.selectTab(event.currentTarget.dataset.tab);
  }

  handleTabKeydown(event) {
    const order = [TAB_OVERVIEW, TAB_DEROGATIONS, TAB_PROFITABILITY, TAB_WON];
    const index = order.indexOf(this.activeTab);
    let next = null;
    if (event.key === "ArrowRight") {
      next = order[(index + 1) % order.length];
    } else if (event.key === "ArrowLeft") {
      next = order[(index - 1 + order.length) % order.length];
    }
    if (next) {
      event.preventDefault();
      this.selectTab(next);
      const button = this.template.querySelector(`[data-tab="${next}"]`);
      if (button) {
        button.focus();
      }
    }
  }

  selectTab(tab) {
    this.activeTab = tab;
    if (tab === TAB_OVERVIEW) {
      // Les filtres ont pu changer depuis un autre onglet : la Vue d'ensemble se recharge alors.
      if (this.analyticsKey !== this.buildFiltersJson()) {
        this.loadAnalytics();
      }
      return;
    }
    const state = this.tabStates[tab];
    // Première ouverture, ou filtres changés depuis le dernier chargement ; sinon, rien à rappeler.
    if (
      !state ||
      (!state.loading && state.key !== this.buildTabFiltersJson(tab))
    ) {
      this.loadTab(tab);
    }
  }

  setTabState(tab, patch) {
    this.tabStates = {
      ...this.tabStates,
      [tab]: { ...(this.tabStates[tab] || {}), ...patch }
    };
  }

  loadTab(tab) {
    const seq = (this._tabSeq[tab] || 0) + 1;
    this._tabSeq[tab] = seq;
    const key = this.buildTabFiltersJson(tab);
    this.setTabState(tab, { loading: true, error: undefined });
    getDashboardTab({ tab, filtersJson: key })
      .then((result) => {
        if (seq !== this._tabSeq[tab]) {
          return;
        }
        this.setTabState(tab, {
          data: typeof result === "string" ? JSON.parse(result) : result,
          key,
          error: undefined
        });
      })
      .catch((error) => {
        if (seq !== this._tabSeq[tab]) {
          return;
        }
        // Erreur affichée dans l'onglet, distincte d'un état « aucune donnée ».
        this.setTabState(tab, { error: this.reduceError(error) });
      })
      .finally(() => {
        if (seq === this._tabSeq[tab]) {
          this.setTabState(tab, { loading: false });
        }
      });
  }

  // Lien profond : ?c__tab=won (cible de la notification « affaire gagnée »).
  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const tab =
      pageRef && pageRef.state && DEEP_LINK_TABS[pageRef.state.c__tab];
    if (tab && !this._deepLinkApplied) {
      this._deepLinkApplied = true;
      this.selectTab(tab);
    }
  }

  handleMotifFilter(event) {
    this.filters = {
      ...this.filters,
      motifAxisValue: event.detail.value || ""
    };
    this.loadTab(TAB_DEROGATIONS);
  }

  // ---------- Affaires gagnées à confirmer ----------

  handleConfirmDeal(event) {
    this.wonPositionId = event.detail.positionId;
    this.showWonDialog = true;
  }

  handleWonClose() {
    this.showWonDialog = false;
  }

  handleWonConfirmed() {
    this.showWonDialog = false;
    // L'onglet et les KPI de la Vue d'ensemble se rechargent (l'affaire n'est plus « à confirmer »).
    this.loadTab(TAB_WON);
    this.loadAnalytics();
  }

  get groupNote() {
    return this.isGroupAxis ? LBL.GroupNote : "";
  }

  // ---------- Vue d'ensemble : ajouts ----------

  get formattedSimulations() {
    return String(this.kpis.simulationsCount || 0);
  }

  get formattedWon() {
    return String(this.kpis.wonCount || 0);
  }

  get byAxisTitle() {
    return fill(LBL.ByAxis, this.axisNounText);
  }

  get funnelRows() {
    const funnel = (this.analytics && this.analytics.funnel) || {};
    const steps = [
      [LBL.FunnelSimulations, funnel.simulations || 0],
      [LBL.FunnelValidated, funnel.validated || 0],
      [LBL.FunnelWon, funnel.won || 0]
    ];
    const max = Math.max(1, ...steps.map(([, count]) => count));
    return steps.map(([label, count], i) => {
      const previous = i === 0 ? null : steps[i - 1][1];
      return {
        key: label,
        label,
        count,
        barStyle: `width:${(count / max) * 100}%;background:${FUNNEL_COLORS[i]};`,
        ratio:
          previous === null
            ? ""
            : fill(
                LBL.FunnelOfPrevious,
                previous >= MIN_SAMPLE_SIZE
                  ? pct(Math.round((count / previous) * 1000) / 10)
                  : "—"
              )
      };
    });
  }

  get funnelAria() {
    const funnel = (this.analytics && this.analytics.funnel) || {};
    return fill(
      LBL.FunnelAria,
      funnel.simulations || 0,
      funnel.validated || 0,
      funnel.won || 0
    );
  }

  // ---------- En-tête et états ----------

  get isEmpty() {
    return !!this.data && this.data.totalCount === 0;
  }

  get hasAnalytics() {
    return !!this.analytics;
  }

  get showDashboard() {
    return !this.isEmpty && this.hasAnalytics;
  }

  get matrixCountLabel() {
    const n = this.data ? this.data.totalCount : 0;
    return pluralLabel(
      n,
      I18N.AR_DB_SavedMatricesOne,
      I18N.AR_DB_SavedMatricesMany
    );
  }

  get dashboardClass() {
    return this.isRefreshing ? "dashboard is-refreshing" : "dashboard";
  }

  // ---------- KPI ----------

  get kpis() {
    return (this.analytics && this.analytics.kpis) || {};
  }

  get validatedCount() {
    return this.kpis.validatedCount || 0;
  }

  get hasEnoughData() {
    return this.validatedCount >= MIN_SAMPLE_SIZE;
  }

  get hasInsufficientData() {
    return this.validatedCount > 0 && !this.hasEnoughData;
  }

  get hasNoValidated() {
    return this.hasAnalytics && this.validatedCount === 0;
  }

  get formattedValidatedCount() {
    return this.hasEnoughData ? String(this.validatedCount) : "—";
  }

  get formattedDerogationRate() {
    return this.hasEnoughData
      ? formatPercent(this.kpis.derogationValidatedPercent)
      : "—";
  }

  get formattedAverageTjm() {
    return this.hasEnoughData
      ? formatMoney(this.kpis.averageTjmEur, this.kpis.pivotCurrencyCode)
      : "—";
  }

  get formattedAverageMc2() {
    return this.hasEnoughData
      ? formatPercent(this.kpis.averageMc2Percent)
      : "—";
  }

  segmentOfMc2(percent) {
    if (!this.corridorSettings || percent === null || percent === undefined) {
      return null;
    }
    return getCorridorSegment(percent / 100, {
      floorPercent: this.corridorSettings.floorPercentDefault,
      targetPercent: this.corridorSettings.targetPercentDefault,
      idealPercent: this.corridorSettings.idealPercentDefault
    });
  }

  get mc2KpiClass() {
    if (!this.hasEnoughData) {
      return "kpi-card";
    }
    const segment = this.segmentOfMc2(this.kpis.averageMc2Percent);
    return segment ? KPI_MC2_CLASS[segment] : "kpi-card";
  }

  get corridorSettingsTooltip() {
    if (!this.corridorSettings) {
      return I18N.AR_DB_DefaultCorridorColors;
    }
    return formatLabel(
      I18N.AR_DB_DefaultCorridorColorsWithValues,
      Math.round(this.corridorSettings.floorPercentDefault),
      Math.round(this.corridorSettings.targetPercentDefault),
      Math.round(this.corridorSettings.idealPercentDefault)
    );
  }

  // ---------- Validation (donut) ----------

  get validationSegments() {
    const split = (this.analytics && this.analytics.validationSplit) || [];
    const labels = {
      direct: I18N.AR_DB_ValidationDirect,
      derogation: I18N.AR_DB_ValidationDerogation
    };
    return split.map((s) => ({
      label: labels[s.key],
      value: s.count,
      color: VALIDATION_COLORS[s.key],
      percent: s.percent
    }));
  }

  get validationLegend() {
    return this.validationSegments.map((s) => ({
      ...s,
      style: `background:${s.color}`,
      detail: `${s.value} (${formatPercent(s.percent)})`
    }));
  }

  // ---------- Tranches de MC2 ----------

  get mc2Buckets() {
    const buckets =
      (this.analytics &&
        this.analytics.mc2Bands &&
        this.analytics.mc2Bands.buckets) ||
      [];
    const last = buckets.length - 1;
    return buckets.map((b, i) => {
      const color =
        BAND_COLORS[
          last <= 0 ? 0 : Math.round((i * (BAND_COLORS.length - 1)) / last)
        ];
      return {
        key: b.key,
        label: b.label,
        detail: `${b.count} (${formatPercent(b.percent)})`,
        barStyle: `width:${b.percent || 0}%;background:${color};`
      };
    });
  }

  // ---------- Seuils de rentabilité ----------

  segmentLabel(segment) {
    return SEGMENT_META[segment].label;
  }

  get thresholdSegments() {
    const shares = (this.analytics && this.analytics.segments) || [];
    return SEGMENT_ORDER.map((segment) => {
      const share = shares.find((s) => s.segment === segment) || {};
      return {
        segment,
        label: this.segmentLabel(segment),
        value: share.count || 0,
        color: SEGMENT_COLORS[segment],
        percent: share.percent || 0
      };
    });
  }

  get thresholdLegend() {
    return this.thresholdSegments.map((s) => ({
      ...s,
      style: `background:${s.color}`,
      detail: `${s.value} (${formatPercent(s.percent)})`
    }));
  }

  // 8 entités au plus (le service les trie par volume), le reste regroupé dans « Autres ».
  get entityBars() {
    const entities = (this.analytics && this.analytics.segmentsByAxis) || [];
    const toBar = (name, total, counts) => ({
      key: name,
      name,
      total,
      segments: SEGMENT_ORDER.map((segment) => ({
        label: this.segmentLabel(segment),
        value: counts[segment] || 0,
        color: SEGMENT_COLORS[segment]
      }))
    });
    const countsOf = (entity) => {
      const counts = {};
      entity.segments.forEach((s) => {
        counts[s.segment] = s.count;
      });
      return counts;
    };
    const bars = entities
      .slice(0, MAX_ENTITIES)
      .map((e) =>
        toBar(
          e.noEntity ? e.entityName || I18N.AR_DB_NoEntity : e.entityName,
          e.total,
          countsOf(e)
        )
      );
    const rest = entities.slice(MAX_ENTITIES);
    if (rest.length) {
      const merged = {};
      let total = 0;
      rest.forEach((e) => {
        total += e.total;
        Object.entries(countsOf(e)).forEach(([segment, count]) => {
          merged[segment] = (merged[segment] || 0) + count;
        });
      });
      bars.push(toBar(I18N.AR_DB_Others, total, merged));
    }
    return bars;
  }

  // ---------- Motifs ----------

  get reasons() {
    return (this.analytics && this.analytics.reasons) || {};
  }

  get derogationCount() {
    return this.reasons.derogationCount || 0;
  }

  get hasReasons() {
    return this.derogationCount >= MIN_SAMPLE_SIZE;
  }

  get reasonsInsufficient() {
    return this.derogationCount > 0 && !this.hasReasons;
  }

  get reasonsEmpty() {
    return this.hasAnalytics && this.derogationCount === 0;
  }

  get reasonRows() {
    const rows = (this.reasons.top || []).map((r) => ({
      key: r.reasonName,
      label: r.reasonName,
      detail: `${r.count} (${formatPercent(r.percent)})`,
      barStyle: `width:${r.percent || 0}%;background:#D31876;`
    }));
    if (this.reasons.othersCount > 0) {
      rows.push({
        key: "__others",
        label: I18N.AR_DB_Others,
        detail: `${this.reasons.othersCount} (${formatPercent(this.reasons.othersPercent)})`,
        barStyle: `width:${this.reasons.othersPercent || 0}%;background:#94a3b8;`
      });
    }
    return rows;
  }

  get reasonsCountLabel() {
    return formatLabel(I18N.AR_DB_ReasonsCount, this.derogationCount);
  }

  // ---------- Tendance ----------

  get monthColumns() {
    const months = (this.analytics && this.analytics.monthly) || [];
    const totals = months.map((m) =>
      SEGMENT_ORDER.reduce((sum, s) => sum + (m[s] || 0), 0)
    );
    const max = Math.max(1, ...totals);
    return months.map((m, i) => {
      const [year, month] = m.month.split("-").map(Number);
      const label = new Date(year, month - 1, 1).toLocaleDateString(LANG, {
        month: "short"
      });
      return {
        key: m.month,
        label,
        total: totals[i],
        columnStyle: `height:${(totals[i] / max) * 100}%;`,
        parts: SEGMENT_ORDER.filter((s) => m[s] > 0).map((s) => ({
          key: s,
          style: `flex:${m[s]};background:${SEGMENT_COLORS[s]};`,
          title: `${this.segmentLabel(s)} : ${m[s]}`
        })),
        title: `${label} : ${totals[i]}`
      };
    });
  }

  get trendHasData() {
    return this.monthColumns.some((c) => c.total > 0);
  }

  get trendLegend() {
    return this.thresholdSegments.map((s) => ({
      key: s.segment,
      label: s.label,
      style: `background:${s.color}`
    }));
  }

  // ---------- Lecture client ----------

  get clients() {
    return (this.analytics && this.analytics.clients) || {};
  }

  rankRows(rows) {
    return (rows || []).map((r, i) => {
      const segment = this.segmentOfMc2(r.averageMc2Percent);
      return {
        key: `${i}-${r.accountName}`,
        rank: i + 1,
        accountName: r.accountName,
        matrixCount: r.matrixCount,
        mc2: formatPercent(r.averageMc2Percent),
        mc2Class: segment ? `mc2-cell ${MC2_CLASS[segment]}` : "mc2-cell",
        tjm: formatMoney(r.averageTjmEur, this.kpis.pivotCurrencyCode)
      };
    });
  }

  get hasEligibleClients() {
    return (
      !!this.clients.best &&
      (this.clients.best.length > 0 || (this.clients.worst || []).length > 0)
    );
  }

  get noEligibleClients() {
    return this.hasAnalytics && !this.hasEligibleClients;
  }

  get isSingleRanking() {
    return !!this.clients.singleRanking;
  }

  get bestRows() {
    return this.rankRows(this.clients.best);
  }

  get worstRows() {
    return this.rankRows(this.clients.worst);
  }

  // ---------- Dernières matrices ----------

  get recentMatrices() {
    if (!this.data) {
      return [];
    }
    return this.data.recentMatrices.map((m) => ({
      ...m,
      recentDetail: m.positionName
        ? `${m.positionName} — ${m.accountName}`
        : m.accountName,
      formattedDate: m.createdDate
        ? new Date(m.createdDate).toLocaleDateString("fr-FR", {
            day: "2-digit",
            month: "2-digit",
            year: "numeric"
          })
        : ""
    }));
  }

  handleRowClick(event) {
    const matrixId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("openmatrix", { detail: { matrixId } }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}