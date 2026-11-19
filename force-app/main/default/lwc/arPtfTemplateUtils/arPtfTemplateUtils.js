import { formatLabel } from "c/arI18n";
import LBL_AR_PTF_TemplateAutoResolution from "@salesforce/label/c.AR_PTF_TemplateAutoResolution";
import LBL_AR_PTF_TemplateUnknownInList from "@salesforce/label/c.AR_PTF_TemplateUnknownInList";

const I18N = {
  AR_PTF_TemplateAutoResolution: LBL_AR_PTF_TemplateAutoResolution,
  AR_PTF_TemplateUnknownInList: LBL_AR_PTF_TemplateUnknownInList
};
/**
 * Liste déroulante « code gabarit PTF » de l'administration (session 176i) : entités et grands
 * comptes partagent ce module, jamais une liste en dur — les options viennent du serveur
 * (AR_PTFDataService.getPtfTemplateOptions, même carte que la résolution des gabarits).
 */

/** Valeur interne de l'option « Résolution automatique » : lightning-combobox traite mal une
 * option dont la valeur est une chaîne vide, le code stocké reste lui "" (pas de gabarit imposé). */
export const AUTO_VALUE = "__AUTO__";
export const AUTO_LABEL = I18N.AR_PTF_TemplateAutoResolution;

/** Code stocké (null/undefined/"" = automatique) → valeur affichée par le combobox. */
export function toComboValue(code) {
  return code ? code : AUTO_VALUE;
}

/** Valeur du combobox → code à stocker ("" pour la résolution automatique). */
export function fromComboValue(value) {
  return !value || value === AUTO_VALUE ? "" : value;
}

/** Un code renseigné qui n'est pas dans la liste servie (donnée antérieure, faute de frappe). */
export function isUnknownCode(code, serverOptions) {
  return (
    !!code && !(serverOptions || []).some((option) => option.value === code)
  );
}

/**
 * Options du combobox : « Résolution automatique », puis les gabarits servis. Un code existant
 * inconnu de la liste reste sélectionné, marqué dans son libellé — il n'est jamais effacé en
 * silence (c'est à l'utilisateur de le remplacer, et le serveur arbitre à l'enregistrement).
 */
export function buildComboOptions(serverOptions, currentCode) {
  const options = [
    { value: AUTO_VALUE, label: AUTO_LABEL },
    ...(serverOptions || []).map((option) => ({
      value: option.value,
      label: option.label
    }))
  ];
  if (isUnknownCode(currentCode, serverOptions)) {
    options.push({
      value: currentCode,
      label: formatLabel(I18N.AR_PTF_TemplateUnknownInList, currentCode)
    });
  }
  return options;
}