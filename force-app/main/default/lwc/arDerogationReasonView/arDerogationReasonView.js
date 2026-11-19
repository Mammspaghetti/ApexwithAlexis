import { formatLabel } from "c/arI18n";
import LBL_AR_DQ_ReasonWithComment from "@salesforce/label/c.AR_DQ_ReasonWithComment";

const I18N = {
  AR_DQ_ReasonWithComment: LBL_AR_DQ_ReasonWithComment
};

/**
 * Bloc « Motif de dérogation » lu par la file d'approbation et le panneau de décision : motifs
 * cochés par le demandeur (libellés, dans l'ordre du référentiel) et commentaire libre.
 *
 * Cas rendus :
 * - un motif seul : « Motif A » ; avec commentaire : « Motif A : commentaire » (une seule ligne) ;
 * - plusieurs motifs : liste à puces, puis le commentaire en dessous s'il existe ;
 * - aucun motif (anciennes dérogations) : le commentaire seul ;
 * - rien : pas de bloc.
 */
export function buildReasonView(reasonLabels, comment) {
  const labels = reasonLabels || [];
  const text = (comment || "").trim();
  const isSingle = labels.length === 1;
  return {
    hasReasonBlock: labels.length > 0 || text !== "",
    reasonInlineText: isSingle
      ? text
        ? formatLabel(I18N.AR_DQ_ReasonWithComment, labels[0], text)
        : labels[0]
      : null,
    hasReasonItems: labels.length > 1,
    reasonItems: labels.map((label, index) => ({ key: `${index}`, label })),
    plainText: !isSingle && text !== "" ? text : null
  };
}