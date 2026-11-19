import LBL_STATUS_DRAFT from "@salesforce/label/c.AR_Common_StatusDraft";
import LBL_STATUS_VALIDATED from "@salesforce/label/c.AR_Common_StatusValidated";
import LBL_STATUS_IN_DEROGATION from "@salesforce/label/c.AR_Common_StatusInDerogation";
import LBL_STATUS_VALIDATED_BY_DEROGATION from "@salesforce/label/c.AR_Common_StatusValidatedByDerogation";
import LBL_STATUS_REJECTED from "@salesforce/label/c.AR_Common_StatusRejected";

/**
 * Petits utilitaires i18n partagés par les composants du Pricing Tool.
 *
 * Les Custom Labels n'offrent pas de formatage côté LWC : `formatLabel` remplace les
 * marqueurs {0}, {1}… par les arguments, dans l'ordre (même convention que String.format en Apex).
 */
export function formatLabel(template, ...args) {
  if (template === undefined || template === null) {
    return "";
  }
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[Number(index)];
    return value === undefined || value === null ? "" : String(value);
  });
}

/** Choisit la forme singulier / pluriel d'un label selon `count` (1 → singulier). */
export function pluralLabel(count, singular, plural) {
  return formatLabel(Number(count) === 1 ? singular : plural, count);
}

const MATRIX_STATUS_LABELS = {
  Brouillon: LBL_STATUS_DRAFT,
  Validée: LBL_STATUS_VALIDATED,
  "En dérogation": LBL_STATUS_IN_DEROGATION,
  "Validée par dérogation": LBL_STATUS_VALIDATED_BY_DEROGATION,
  Refusée: LBL_STATUS_REJECTED
};

/**
 * Libellé affiché d'un statut de matrice. Les valeurs stockées restent en français (elles servent de
 * clés de comparaison partout) : seule leur forme affichée passe par les Custom Labels.
 */
export function matrixStatusLabel(status) {
  return MATRIX_STATUS_LABELS[status] || status;
}