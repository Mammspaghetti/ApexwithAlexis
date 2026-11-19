import { formatLabel } from "c/arI18n";
import LBL_AR_DRG_RfaMatrixLine from "@salesforce/label/c.AR_DRG_RfaMatrixLine";
import LBL_AR_DRG_RfaNoAccountRfa from "@salesforce/label/c.AR_DRG_RfaNoAccountRfa";

const I18N = {
  AR_DRG_RfaMatrixLine: LBL_AR_DRG_RfaMatrixLine,
  AR_DRG_RfaNoAccountRfa: LBL_AR_DRG_RfaNoAccountRfa
};

/**
 * Ligne « RFA de la matrice » comparée à la RFA enregistrée pour le compte (héritage parent → enfant
 * inclus), lue par le panneau de décision et la file d'approbation. Information seule.
 *
 * Cas rendus :
 * - RFA du compte différente de celle de la matrice : les deux valeurs ;
 * - aucune RFA enregistrée pour le compte, matrice avec RFA : la RFA de la matrice seule ;
 * - égalité, ou aucune RFA de part et d'autre : rien (null).
 */
export function buildRfaLine(matrixRfaPercent, accountRfaPercent) {
  const matrixRfa = matrixRfaPercent ?? 0;
  if (accountRfaPercent === null || accountRfaPercent === undefined) {
    return matrixRfa === 0
      ? null
      : formatLabel(I18N.AR_DRG_RfaNoAccountRfa, `${matrixRfa} %`);
  }
  if (accountRfaPercent === matrixRfa) {
    return null;
  }
  return formatLabel(
    I18N.AR_DRG_RfaMatrixLine,
    `${matrixRfa} %`,
    `${accountRfaPercent} %`
  );
}