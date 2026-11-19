import { LightningElement, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getContext from "@salesforce/apex/AR_DerogationService.getContext";
import decideApex from "@salesforce/apex/AR_DerogationService.decide";
import { logNotificationFailure } from "c/arNotificationLog";
import {
  generateAvenantDocument,
  avenantGenerationToast
} from "c/arAvenantGeneration";
import { formatMoney, formatTjmPeriodsDetail } from "c/arPricingEngine";
import LBL_AR_TJM_Weighted_Label from "@salesforce/label/c.AR_TJM_Weighted_Label";
import { formatLabel } from "c/arI18n";
import { buildReasonView } from "c/arDerogationReasonView";
import { buildRfaLine } from "c/arDerogationRfaView";
import LBL_AR_AVN_Mc2Percent from "@salesforce/label/c.AR_AVN_Mc2Percent";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_ProcessedByPrefix from "@salesforce/label/c.AR_Common_ProcessedByPrefix";
import LBL_AR_Common_ProposedRate from "@salesforce/label/c.AR_Common_ProposedRate";
import LBL_AR_Common_Reject from "@salesforce/label/c.AR_Common_Reject";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_DRG_Accept from "@salesforce/label/c.AR_DRG_Accept";
import LBL_AR_DRG_ApprovedLocked from "@salesforce/label/c.AR_DRG_ApprovedLocked";
import LBL_AR_DRG_CommentMandatory from "@salesforce/label/c.AR_DRG_CommentMandatory";
import LBL_AR_DRG_CommentRequired from "@salesforce/label/c.AR_DRG_CommentRequired";
import LBL_AR_DRG_DecisionSaved from "@salesforce/label/c.AR_DRG_DecisionSaved";
import LBL_AR_DRG_GapVsFloor from "@salesforce/label/c.AR_DRG_GapVsFloor";
import LBL_AR_DRG_GapVsTarget from "@salesforce/label/c.AR_DRG_GapVsTarget";
import LBL_AR_DRG_NoPendingDerogation from "@salesforce/label/c.AR_DRG_NoPendingDerogation";
import LBL_AR_DRG_NotAuthorized from "@salesforce/label/c.AR_DRG_NotAuthorized";
import LBL_AR_Msg_DRG_OwnRequest from "@salesforce/label/c.AR_Msg_DRG_OwnRequest";
import LBL_AR_DRG_PanelTitle from "@salesforce/label/c.AR_DRG_PanelTitle";
import LBL_AR_DRG_ReasonValue from "@salesforce/label/c.AR_DRG_ReasonValue";
import LBL_AR_DRG_RejectedLocked from "@salesforce/label/c.AR_DRG_RejectedLocked";
import LBL_AR_DRG_RequesterReason from "@salesforce/label/c.AR_DRG_RequesterReason";

const I18N = {
  AR_AVN_Mc2Percent: LBL_AR_AVN_Mc2Percent,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_ProcessedByPrefix: LBL_AR_Common_ProcessedByPrefix,
  AR_Common_ProposedRate: LBL_AR_Common_ProposedRate,
  AR_Common_Reject: LBL_AR_Common_Reject,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_DRG_Accept: LBL_AR_DRG_Accept,
  AR_DRG_ApprovedLocked: LBL_AR_DRG_ApprovedLocked,
  AR_DRG_CommentMandatory: LBL_AR_DRG_CommentMandatory,
  AR_DRG_CommentRequired: LBL_AR_DRG_CommentRequired,
  AR_DRG_DecisionSaved: LBL_AR_DRG_DecisionSaved,
  AR_DRG_GapVsFloor: LBL_AR_DRG_GapVsFloor,
  AR_DRG_GapVsTarget: LBL_AR_DRG_GapVsTarget,
  AR_DRG_NoPendingDerogation: LBL_AR_DRG_NoPendingDerogation,
  AR_DRG_NotAuthorized: LBL_AR_DRG_NotAuthorized,
  AR_Msg_DRG_OwnRequest: LBL_AR_Msg_DRG_OwnRequest,
  AR_DRG_PanelTitle: LBL_AR_DRG_PanelTitle,
  AR_DRG_ReasonValue: LBL_AR_DRG_ReasonValue,
  AR_DRG_RejectedLocked: LBL_AR_DRG_RejectedLocked,
  AR_DRG_RequesterReason: LBL_AR_DRG_RequesterReason
};
/**
 * Panneau de traitement de dérogation — visible sur la record page de la matrice quand le statut
 * est « En dérogation » (règle de visibilité portée par le FlexiPage). Lecture seule pour un
 * utilisateur non habilité ; le serveur (AR_DerogationService.decide) revalide systématiquement
 * l'habilitation et l'unicité du traitement — cette UI est un confort, pas la garantie.
 */
export default class ArDerogationPanel extends LightningElement {
  i18n = I18N;

  @api recordId;

  isLoading = true;
  isSaving = false;
  errorMessage;
  // Session 156 : _commentDraft stocke la saisie sans déclencher de re-rendu — ne se lit qu'au clic.
  _commentDraft = "";
  context = {};

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    this._commentDraft = "";
    try {
      this.context = await getContext({ matrixId: this.recordId });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleCommentChange(event) {
    this._commentDraft = event.target.value;
  }

  async handleAccept() {
    await this.submitDecision("Acceptée");
  }

  async handleReject() {
    await this.submitDecision("Refusée");
  }

  async submitDecision(decisionValue) {
    if (!this._commentDraft.trim()) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        I18N.AR_DRG_CommentMandatory,
        "error"
      );
      return;
    }
    this.isSaving = true;
    try {
      const warning = await decideApex({
        derogationId: this.context.derogationId,
        decision: decisionValue,
        comment: this._commentDraft
      });
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_DRG_DecisionSaved,
        "success"
      );
      logNotificationFailure("decision", warning && warning.detail);
      this._commentDraft = "";
      if (decisionValue === "Acceptée") {
        // Session 180d (Q10 B) : sur une matrice avenant, l'acceptation génère le document ;
        // sans effet sur une matrice ordinaire. Un échec est affiché sans défaire la décision.
        const toast = avenantGenerationToast(
          await generateAvenantDocument(this.context.matrixId)
        );
        if (toast) {
          this.dispatchEvent(new ShowToastEvent(toast));
        }
      }
      await this.load();
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }

  get hasPendingDerogation() {
    return (
      !!this.context.derogationId && this.context.decision === "En attente"
    );
  }

  // Session 33 §2 : le panneau reste affiché après décision (FlexiPage élargie), pour montrer un
  // état visuellement inerte plutôt que de disparaître — l'ancien comportement masquait le fait
  // que les champs sont bien verrouillés côté serveur depuis la session 28b.
  get isDecided() {
    return (
      !!this.context.derogationId && this.context.decision !== "En attente"
    );
  }

  get isApproved() {
    return this.context.decision === "Acceptée";
  }

  get lockedBannerClass() {
    return this.isApproved
      ? "locked-banner locked-approved"
      : "locked-banner locked-rejected";
  }

  get lockedBannerTitle() {
    return this.isApproved
      ? I18N.AR_DRG_ApprovedLocked
      : I18N.AR_DRG_RejectedLocked;
  }

  get formattedDecidedAt() {
    return this.context.decidedAt
      ? new Date(this.context.decidedAt).toLocaleString("fr-FR")
      : "";
  }

  // Formatage par devise (session 24) : ce panneau affichait auparavant les montants bruts
  // concaténés avec "€" en dur dans le HTML, sans arrondi ni séparateur de milliers cohérents —
  // corrigé au passage, même défaut que celui traité en session 8 pour le reste de l'app.
  get formattedProposedTjm() {
    return formatMoney(this.context.proposedTjm, this.context.currencyCode);
  }

  // Détail par période quand la mission évolue (docs/254 §11.2) : vide sans évolution.
  get tjmPeriodsDetail() {
    return formatTjmPeriodsDetail(
      this.context.tjmPeriods,
      this.context.currencyCode,
      LBL_AR_TJM_Weighted_Label
    );
  }

  get formattedGapVsFloor() {
    return formatMoney(this.context.gapVsFloor, this.context.currencyCode);
  }

  get reasonView() {
    return buildReasonView(
      this.context.reasonLabels,
      this.context.requesterReason
    );
  }

  get rfaLine() {
    return buildRfaLine(
      this.context.matrixRfaPercent,
      this.context.accountRfaPercent
    );
  }

  get formattedGapVsTarget() {
    return formatMoney(this.context.gapVsTarget, this.context.currencyCode);
  }

  get canDecide() {
    return (
      this.context.currentUserIsValidator &&
      !this.context.isOwnRequest &&
      this.hasPendingDerogation
    );
  }

  get validatorCommentLabel() {
    return formatLabel(I18N.AR_DRG_ReasonValue, this.context.validatorComment);
  }

  get readOnlyMessage() {
    if (!this.hasPendingDerogation) {
      return "";
    }
    if (this.context.isOwnRequest) {
      return I18N.AR_Msg_DRG_OwnRequest;
    }
    return this.context.currentUserIsValidator ? "" : I18N.AR_DRG_NotAuthorized;
  }

  get comment() {
    return this._commentDraft;
  }
}