import { reduceErrors } from "c/arErrorUtils";
import generateAvenantIfNeeded from "@salesforce/apex/AR_PTFGenerationService.generateAvenantIfNeeded";
import renderAndStorePTF from "@salesforce/apex/AR_PTFGenerationService.renderAndStorePTF";
import markRenderFailed from "@salesforce/apex/AR_PTFGenerationService.markRenderFailed";
import { formatLabel } from "c/arI18n";
import LBL_AR_AVN_BelowFloorDerogationNeeded from "@salesforce/label/c.AR_AVN_BelowFloorDerogationNeeded";
import LBL_AR_AVN_CreatedTitle from "@salesforce/label/c.AR_AVN_CreatedTitle";
import LBL_AR_AVN_DocumentNotGenerated from "@salesforce/label/c.AR_AVN_DocumentNotGenerated";
import LBL_AR_AVN_GeneratedTitle from "@salesforce/label/c.AR_AVN_GeneratedTitle";
import LBL_AR_AVN_OpenMatrixToGenerate from "@salesforce/label/c.AR_AVN_OpenMatrixToGenerate";
import LBL_AR_AVN_PdfNoDetail from "@salesforce/label/c.AR_AVN_PdfNoDetail";
import LBL_AR_AVN_Validated from "@salesforce/label/c.AR_AVN_Validated";
import LBL_AR_AVN_ValidatedNotGeneratedTitle from "@salesforce/label/c.AR_AVN_ValidatedNotGeneratedTitle";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_PTF_DocumentGenerated from "@salesforce/label/c.AR_PTF_DocumentGenerated";

const I18N = {
  AR_AVN_BelowFloorDerogationNeeded: LBL_AR_AVN_BelowFloorDerogationNeeded,
  AR_AVN_CreatedTitle: LBL_AR_AVN_CreatedTitle,
  AR_AVN_DocumentNotGenerated: LBL_AR_AVN_DocumentNotGenerated,
  AR_AVN_GeneratedTitle: LBL_AR_AVN_GeneratedTitle,
  AR_AVN_OpenMatrixToGenerate: LBL_AR_AVN_OpenMatrixToGenerate,
  AR_AVN_PdfNoDetail: LBL_AR_AVN_PdfNoDetail,
  AR_AVN_Validated: LBL_AR_AVN_Validated,
  AR_AVN_ValidatedNotGeneratedTitle: LBL_AR_AVN_ValidatedNotGeneratedTitle,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_PTF_DocumentGenerated: LBL_AR_PTF_DocumentGenerated
};
/**
 * Génération du document d'un avenant piloté par la matrice (session 180d, docs/180 §6, Q10 B).
 *
 * Partagé par les trois écrans qui l'enchaînent à une décision : la modale de l'avenant (validation
 * directe), la file d'approbation et le panneau de dérogation (dérogation acceptée). Deux appels Apex
 * DISTINCTS, jamais fusionnés : `getContentAsPDF()` ne voit pas le DML non committé de sa propre
 * transaction (CLAUDE.md, protocole PTF) — le premier appel committe le snapshot, le second le rend.
 *
 * Ne lève jamais : renvoie un résultat que l'appelant affiche. Classement session 34 — AFFICHER :
 * tout échec est rendu à l'appelant avec son motif, jamais un état par défaut.
 *   { outcome: "skipped" }                    rien à générer (pas un avenant, ou document déjà présent)
 *   { outcome: "generated", reference, ptfDocumentId, contentDocumentId, warning }
 *   { outcome: "failed", step: "snapshot" | "render", message, ptfDocumentId? }
 */
export async function generateAvenantDocument(matrixId) {
  let started;
  try {
    started = await generateAvenantIfNeeded({ matrixId });
  } catch (error) {
    return {
      outcome: "failed",
      step: "snapshot",
      message: reduceErrors(error)
    };
  }
  if (!started || !started.ptfDocumentId) {
    return { outcome: "skipped" };
  }
  const ptfDocumentId = started.ptfDocumentId;

  let finished;
  try {
    finished = await renderAndStorePTF({ ptfDocumentId });
  } catch (error) {
    // Ce que le serveur n'a pas pu écrire lui-même (limite plateforme, réseau, session expirée) :
    // le document passerait sinon « En cours » sans trace (session 153b). Si cette écriture échoue
    // aussi, journalisé — l'échec d'origine est déjà rendu à l'appelant ci-dessous.
    const message = reduceErrors(error);
    try {
      await markRenderFailed({ ptfDocumentId, reason: message });
    } catch (markError) {
      console.error(
        "arAvenantGeneration : statut Échec non enregistré.",
        markError
      );
    }
    return { outcome: "failed", step: "render", message, ptfDocumentId };
  }
  if (!finished || finished.status === "Échec") {
    return {
      outcome: "failed",
      step: "render",
      message: (finished && finished.errorMessage) || I18N.AR_AVN_PdfNoDetail,
      ptfDocumentId
    };
  }
  return {
    outcome: "generated",
    reference: finished.reference,
    ptfDocumentId,
    contentDocumentId: finished.contentDocumentId,
    warning: finished.warning || null
  };
}

/**
 * Message de toast correspondant à un résultat de generateAvenantDocument, pour les écrans qui ne
 * font qu'annoncer l'issue. `null` pour « skipped » (rien à dire). `sticky` : un échec reste affiché
 * jusqu'à fermeture — il demande une action (« Générer l'avenant » dans le panneau PTF).
 */
export function avenantGenerationToast(result, { prefix = "" } = {}) {
  if (!result || result.outcome === "skipped") {
    return null;
  }
  if (result.outcome === "failed") {
    return {
      title: I18N.AR_AVN_ValidatedNotGeneratedTitle,
      message:
        prefix +
        formatLabel(I18N.AR_AVN_DocumentNotGenerated, result.message) +
        " " +
        I18N.AR_AVN_OpenMatrixToGenerate,
      variant: "error",
      mode: "sticky"
    };
  }
  if (result.warning) {
    return {
      title: I18N.AR_AVN_GeneratedTitle,
      message: `${prefix}${formatLabel(I18N.AR_PTF_DocumentGenerated, result.reference)} ${result.warning}`,
      variant: "warning",
      mode: "sticky"
    };
  }
  return {
    title: I18N.AR_AVN_GeneratedTitle,
    message:
      prefix + formatLabel(I18N.AR_PTF_DocumentGenerated, result.reference),
    variant: "success",
    mode: "dismissible"
  };
}

/**
 * Toast de fin de la modale de l'avenant (événement `created`), partagé par le simulateur et le
 * panneau PTF : sous le plancher → dérogation à demander ; validé → issue de la génération du document.
 */
export function avenantCreatedToast(detail) {
  if (detail.derogationRequired) {
    return {
      title: I18N.AR_AVN_CreatedTitle,
      message: I18N.AR_AVN_BelowFloorDerogationNeeded,
      variant: "warning",
      mode: "dismissible"
    };
  }
  const generated = avenantGenerationToast(detail.document, {
    prefix: I18N.AR_AVN_Validated + " "
  });
  return (
    generated || {
      title: I18N.AR_Common_SuccessTitle,
      message: I18N.AR_AVN_Validated,
      variant: "success",
      mode: "dismissible"
    }
  );
}