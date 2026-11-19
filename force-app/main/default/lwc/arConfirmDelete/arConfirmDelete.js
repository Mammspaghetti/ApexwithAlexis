import LightningConfirm from "lightning/confirm";
import LBL_AR_Admin_ConfirmDeleteTitle from "@salesforce/label/c.AR_Admin_ConfirmDeleteTitle";
import LBL_AR_Admin_ConfirmDelete from "@salesforce/label/c.AR_Admin_ConfirmDelete";
import { formatLabel } from "c/arI18n";

/**
 * Confirmation commune à toute suppression dans l'administration.
 * Résout `true` si l'utilisateur confirme, `false` s'il annule : le serveur n'est appelé
 * qu'après une confirmation.
 */
export function confirmAdminDelete(rowName) {
  return LightningConfirm.open({
    message: formatLabel(LBL_AR_Admin_ConfirmDelete, rowName),
    variant: "header",
    label: LBL_AR_Admin_ConfirmDeleteTitle,
    theme: "warning"
  });
}