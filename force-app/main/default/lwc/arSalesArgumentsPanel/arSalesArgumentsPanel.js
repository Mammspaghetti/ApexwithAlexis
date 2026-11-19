import { LightningElement, api } from "lwc";

import LBL_AR_SAP_NotEnoughData from "@salesforce/label/c.AR_SAP_NotEnoughData";
import LBL_AR_SAP_Title from "@salesforce/label/c.AR_SAP_Title";

const I18N = {
  AR_SAP_NotEnoughData: LBL_AR_SAP_NotEnoughData,
  AR_SAP_Title: LBL_AR_SAP_Title
};
/**
 * Panneau « Arguments de vente » (spec §5.1, exigence non-LLM du lot 1, cf. CLAUDE.md) — repliable,
 * replié par défaut, purement présentation : reçoit une liste d'arguments déjà produits
 * (arSalesArgumentsEngine.buildSalesArguments, aujourd'hui algorithmique) et les affiche tels quels.
 * Ce composant ne sait pas comment un argument a été produit — c'est la frontière posée pour la
 * phase 4 (LLM), qui pourra remplacer le producteur sans toucher à ce fichier.
 */
export default class ArSalesArgumentsPanel extends LightningElement {
  i18n = I18N;

  @api arguments = [];
  @api unavailableNotes = [];

  isOpen = false;

  handleToggle() {
    this.isOpen = !this.isOpen;
  }

  get toggleIcon() {
    return this.isOpen ? "utility:chevronup" : "utility:chevrondown";
  }

  get hasArguments() {
    return !!(this.arguments && this.arguments.length > 0);
  }

  get argumentCount() {
    return this.arguments ? this.arguments.length : 0;
  }

  get argumentCountLabel() {
    return `(${this.argumentCount})`;
  }

  get hasNotes() {
    return !!(this.unavailableNotes && this.unavailableNotes.length > 0);
  }

  get notesForDisplay() {
    return (this.unavailableNotes || []).map((text, index) => ({
      key: `note-${index}`,
      text
    }));
  }

  get showEmptyState() {
    return !this.hasArguments && !this.hasNotes;
  }
}