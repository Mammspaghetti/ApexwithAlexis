import { LightningElement } from "lwc";
import getAdminAccess from "@salesforce/apex/AR_AdminAccessGuard.getAdminAccess";

import LBL_AR_ADM_AccessDenied from "@salesforce/label/c.AR_ADM_AccessDenied";
import LBL_AR_ADM_TabClientData from "@salesforce/label/c.AR_ADM_TabClientData";
import LBL_AR_ADM_TabCurrencies from "@salesforce/label/c.AR_ADM_TabCurrencies";
import LBL_AR_ADM_TabGeneralSettings from "@salesforce/label/c.AR_ADM_TabGeneralSettings";
import LBL_AR_ADM_TabKeyAccounts from "@salesforce/label/c.AR_ADM_TabKeyAccounts";
import LBL_AR_ADM_TabNearshore from "@salesforce/label/c.AR_ADM_TabNearshore";
import LBL_AR_ADM_TabPtfEntities from "@salesforce/label/c.AR_ADM_TabPtfEntities";
import LBL_AR_ADM_TabVie from "@salesforce/label/c.AR_ADM_TabVie";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Reasons from "@salesforce/label/c.AR_Common_Reasons";

const I18N = {
  AR_ADM_AccessDenied: LBL_AR_ADM_AccessDenied,
  AR_ADM_TabClientData: LBL_AR_ADM_TabClientData,
  AR_ADM_TabCurrencies: LBL_AR_ADM_TabCurrencies,
  AR_ADM_TabGeneralSettings: LBL_AR_ADM_TabGeneralSettings,
  AR_ADM_TabKeyAccounts: LBL_AR_ADM_TabKeyAccounts,
  AR_ADM_TabNearshore: LBL_AR_ADM_TabNearshore,
  AR_ADM_TabPtfEntities: LBL_AR_ADM_TabPtfEntities,
  AR_ADM_TabVie: LBL_AR_ADM_TabVie,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Reasons: LBL_AR_Common_Reasons
};
const TABS = [
  {
    key: "general",
    label: I18N.AR_ADM_TabGeneralSettings,
    domain: "generalSettings"
  },
  {
    key: "corridors",
    label: I18N.AR_ADM_TabKeyAccounts,
    domain: "referentials"
  },
  {
    key: "ptfEntities",
    label: I18N.AR_ADM_TabPtfEntities,
    domain: "ptfEntities"
  },
  {
    key: "currency",
    label: I18N.AR_ADM_TabCurrencies,
    domain: "currencyAccess"
  },
  {
    key: "commercial",
    label: I18N.AR_ADM_TabClientData,
    domain: "referentials"
  },
  { key: "vie", label: I18N.AR_ADM_TabVie, domain: "referentials" },
  { key: "nearshore", label: I18N.AR_ADM_TabNearshore, domain: "referentials" },
  { key: "reasons", label: I18N.AR_Common_Reasons, domain: "referentials" }
];

const NO_ACCESS = {
  generalSettings: false,
  currencyAccess: false,
  referentials: false,
  ptfEntities: false
};

/**
 * Page d'administration (session 23), redécoupée en habilitations indépendantes par domaine
 * (session 42, quatrième domaine « Entités PTF » ajouté en session 46 à la demande du client —
 * habilitable indépendamment des autres référentiels) : un onglet n'existe que pour qui détient la
 * permission de son domaine. Contrôle d'accès en double : arPricingApp masque déjà l'entrée
 * « Administration » pour qui ne détient aucun domaine, mais ce composant revérifie indépendamment
 * (getAdminAccess) pour ne rien afficher à quelqu'un qui atteindrait cette vue directement par
 * l'URL (?c__view=admin) — masquer l'entrée de menu n'est qu'un confort, pas une sécurité ; chaque
 * méthode @AuraEnabled des services d'admin revérifie de toute façon côté serveur, par domaine
 * (AR_AdminAccessGuard.requireGeneralSettings/requireCurrency/requireReferentials/requirePtfEntities).
 */
export default class ArAdminPage extends LightningElement {
  i18n = I18N;

  isLoading = true;
  access = NO_ACCESS;
  activeTab;

  connectedCallback() {
    getAdminAccess()
      .then((result) => {
        this.access = result;
        const firstVisible = this.tabs[0];
        this.activeTab = firstVisible ? firstVisible.key : undefined;
      })
      .catch((error) => {
        // Repli fail-closed délibéré (session 34, revue des .catch silencieux) : masquer tous les
        // onglets à un administrateur dont l'appel a échoué est sans risque de sécurité (chaque
        // méthode d'admin revérifie de toute façon côté serveur, par domaine, cf. commentaire de
        // tête) — jamais l'inverse. Journalisé pour rester diagnosticable si l'appel échoue
        // systématiquement.
        console.error(
          "arAdminPage : getAdminAccess a échoué, aucun onglet d'administration affiché par défaut.",
          error
        );
        this.access = NO_ACCESS;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Onglets réellement autorisés par le triplet du serveur, jamais la liste complète — un onglet
  // masqué dans le DOM ne doit jamais rester atteignable par un data-tab correspondant.
  get tabs() {
    return TABS.filter((t) => this.access && this.access[t.domain]);
  }

  get hasAnyAccess() {
    return this.tabs.length > 0;
  }

  get tabItems() {
    return this.tabs.map((t) => ({
      ...t,
      cssClass: `admin-tab${t.key === this.activeTab ? " admin-tab-active" : ""}`
    }));
  }

  handleTabClick(event) {
    const requested = event.currentTarget.dataset.tab;
    // Session 42 §3 : un élément masqué dans le DOM reste atteignable — revérifie que la clé
    // demandée fait partie des onglets réellement autorisés avant de l'activer. L'interface cache,
    // le serveur interdit, et l'aiguillage entre les deux ne doit pas faire confiance à `dataset`.
    if (this.tabs.some((t) => t.key === requested)) {
      this.activeTab = requested;
    }
  }

  get isGeneral() {
    return this.activeTab === "general";
  }
  get isCorridors() {
    return this.activeTab === "corridors";
  }
  get isPtfEntities() {
    return this.activeTab === "ptfEntities";
  }
  get isCurrency() {
    return this.activeTab === "currency";
  }
  get isCommercial() {
    return this.activeTab === "commercial";
  }
  get isVie() {
    return this.activeTab === "vie";
  }
  get isNearshore() {
    return this.activeTab === "nearshore";
  }
  get isReasons() {
    return this.activeTab === "reasons";
  }
}