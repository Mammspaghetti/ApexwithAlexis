/**
 * Journalise en console un e-mail ou une notification qui n'est pas partie. Rien ne s'affiche à
 * l'écran : l'action métier est enregistrée, et l'information sert aux développeurs et aux
 * administrateurs.
 * @param {"request"|"decision"|"validation"} kind
 * @param {string} detail canal | destinataires | code | message, renvoyé par le serveur
 */
export function logNotificationFailure(kind, detail) {
  if (!detail) {
    return;
  }
  // eslint-disable-next-line no-console
  console.warn(`[Price Pilot] Notification not delivered (${kind}): ${detail}`);
}