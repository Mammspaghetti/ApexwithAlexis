import { LightningElement, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import getChain from "@salesforce/apex/AR_MatrixChainService.getChain";
import {
  formatMoney,
  formatPercent,
  formatTjmPeriodsDetail
} from "c/arPricingEngine";
import LBL_AR_TJM_Weighted_Label from "@salesforce/label/c.AR_TJM_Weighted_Label";
import { formatLabel, matrixStatusLabel } from "c/arI18n";
import LBL_AR_MCP_CurrentVersion from "@salesforce/label/c.AR_MCP_CurrentVersion";
import LBL_AR_MCP_LoadError from "@salesforce/label/c.AR_MCP_LoadError";
import LBL_AR_MCP_OpenVersion from "@salesforce/label/c.AR_MCP_OpenVersion";
import LBL_AR_MCP_OpenVersionAvenant from "@salesforce/label/c.AR_MCP_OpenVersionAvenant";
import LBL_AR_MCP_PartiallyVisible from "@salesforce/label/c.AR_MCP_PartiallyVisible";
import LBL_AR_MCP_Title from "@salesforce/label/c.AR_MCP_Title";
import LBL_AR_MCP_VersionAvenant from "@salesforce/label/c.AR_MCP_VersionAvenant";

const I18N = {
  AR_MCP_CurrentVersion: LBL_AR_MCP_CurrentVersion,
  AR_MCP_LoadError: LBL_AR_MCP_LoadError,
  AR_MCP_OpenVersion: LBL_AR_MCP_OpenVersion,
  AR_MCP_OpenVersionAvenant: LBL_AR_MCP_OpenVersionAvenant,
  AR_MCP_PartiallyVisible: LBL_AR_MCP_PartiallyVisible,
  AR_MCP_Title: LBL_AR_MCP_Title,
  AR_MCP_VersionAvenant: LBL_AR_MCP_VersionAvenant
};
/**
 * Panneau en lecture seule de la chaîne de négociation (session 22). Affiché uniquement quand la
 * matrice courante appartient à une chaîne d'au moins 2 versions — cf. arPriceMatrixSimulator.
 * `partiallyVisible` : ne jamais présenter une chaîne tronquée comme complète (même famille de
 * défaut que le PDF vide silencieux de la session 20) — un bandeau explicite prend le pas sur
 * l'affichage normal des maillons.
 */
export default class ArMatrixChainPanel extends LightningElement {
  i18n = I18N;

  @api recordId;

  nodes = [];
  partiallyVisible = false;
  hasLoaded = false;
  // Session 34 (revue des .catch silencieux) : sans cet état, un échec de chargement produisait
  // nodes=[] — indiscernable de "cette matrice n'appartient à aucune chaîne", exactement la classe de
  // défaut que ce composant dénonce lui-même dans son commentaire de tête au sujet des chaînes
  // tronquées.
  loadError;

  get loadErrorMessage() {
    return formatLabel(I18N.AR_MCP_LoadError, this.loadError);
  }

  connectedCallback() {
    this.load();
  }

  @api
  refresh() {
    this.load();
  }

  load() {
    if (!this.recordId) {
      return;
    }
    getChain({ anyMatrixIdInChain: this.recordId })
      .then((result) => {
        this.nodes = (result.nodes || []).map((node) => ({
          ...node,
          isCurrent: node.matrixId === this.recordId,
          reasonsLabel: (node.reasons || []).join(", "),
          // La devise reste constante sur toute une chaîne (copiée à la duplication, cf.
          // AR_MatrixChainService.duplicateMatrix) — formatée par nœud plutôt qu'en dur en € (session 24).
          formattedTjm: formatMoney(node.proposedTjm, node.currencyCode),
          tjmPeriodsDetail: formatTjmPeriodsDetail(
            node.tjmPeriods,
            node.currencyCode,
            LBL_AR_TJM_Weighted_Label
          ),
          // Session 163b : MC2 vide si absent, avec euros en parenthèses si présents.
          mc2Label: this.formatMc2(
            node.mc2PercentHuman,
            node.mc2PerDay,
            node.currencyCode
          ),
          // Session 180a : « V3 · Avenant » pour une version avenant ; versionType null = négociation (« V3 »).
          statusLabel: matrixStatusLabel(node.status),
          versionLabel:
            node.versionType === "Avenant"
              ? formatLabel(I18N.AR_MCP_VersionAvenant, node.negotiationVersion)
              : `V${node.negotiationVersion}`,
          openTitle: formatLabel(
            node.versionType === "Avenant"
              ? I18N.AR_MCP_OpenVersionAvenant
              : I18N.AR_MCP_OpenVersion,
            node.negotiationVersion
          )
        }));
        this.partiallyVisible = result.partiallyVisible;
        this.loadError = undefined;
        this.hasLoaded = true;
      })
      .catch((error) => {
        this.nodes = [];
        this.loadError = this.reduceError(error);
        this.hasLoaded = true;
        console.error(
          "arMatrixChainPanel : échec du chargement de la chaîne de négociation.",
          error
        );
      });
  }

  formatMc2(mc2Percent, mc2PerDay, currencyCode) {
    if (mc2Percent === null || mc2Percent === undefined || mc2Percent === "") {
      return "";
    }
    let result = formatPercent(mc2Percent);
    if (mc2PerDay !== null && mc2PerDay !== undefined) {
      const formattedAmount = formatMoney(mc2PerDay, currencyCode);
      result += ` (${formattedAmount} / j)`;
    }
    return result;
  }

  /**
   * Session 163 : ouvre la version cliquée. Même contrat que arMatrixList / duplication : l'événement
   * `openmatrix` traverse le simulateur (bubbles + composed) jusqu'à arPricingApp.handleOpenMatrix.
   */
  handleOpenVersion(event) {
    const matrixId = event.currentTarget.dataset.matrixId;
    if (!matrixId || matrixId === this.recordId) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: { matrixId },
        bubbles: true,
        composed: true
      })
    );
  }

  get hasMultipleVersions() {
    return this.nodes.length > 1;
  }

  get hasLoadError() {
    return !!this.loadError;
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}