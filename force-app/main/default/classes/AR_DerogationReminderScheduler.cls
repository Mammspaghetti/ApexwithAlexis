/**
 * Lance AR_DerogationReminderBatch. Non activé par ce déploiement (cf. AR_DerogationReminderBatch et
 * docs/29-relances-et-notifications.md pour la procédure d'activation/désactivation).
 *
 * Rythme retenu : horaire, pas quotidien (contrairement à AR_DraftPurgeScheduler). Un délai de
 * relance à 12 h mesuré par un batch quotidien produirait une erreur de plusieurs heures selon le
 * moment de la journée où la demande est faite — inacceptable pour une exigence exprimée en heures.
 * Une exécution horaire borne l'erreur à ±1 h pour un coût mesuré : un balayage complet de
 * AR_Derogation__c coûte une requête + éventuellement quelques DML par heure, plafonné par
 * AR_Derogation_Reminder_Max_Per_Run__c — négligeable au volume constaté (27 matrices de
 * démonstration). Documenté et justifié en détail dans docs/29-relances-et-notifications.md §3.
 *
 * Activation (aucun déploiement requis pour changer les délais, seuls désactivés par défaut) :
 * 1. AR_General_Setting__c.AR_Derogation_Reminder_Enabled__c = true (page d'administration).
 * 2. System.schedule('AR Derogation Reminder', '0 0 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,
 *    19,20,21,22,23 * * ?', new AR_DerogationReminderScheduler());
 *    (24 heures explicitement listées plutôt qu'un pas '/1' : plus sûr, la syntaxe CRON de
 *    System.schedule n'est pas garantie identique à celle d'un crontab Unix standard.)
 * Désactivation d'urgence : positionner AR_Derogation_Reminder_Enabled__c à false plutôt que
 * d'annuler le job planifié (System.abortJob) — le batch devient alors un no-op immédiat sans
 * toucher à la planification, même convention que AR_DraftPurgeScheduler.
 */
public class AR_DerogationReminderScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AR_DerogationReminderBatch(), 200);
    }
}