/**
 * Lance AR_HierarchyNotificationBatch. Non activé par ce déploiement. Rythme : quotidien (un seul
 * job couvre Quotidien et Hebdomadaire — le batch lui-même n'envoie rien un jour hors lundi si la
 * fréquence est Hebdomadaire, cf. AR_HierarchyNotificationBatch.isWeeklyDispatchDay).
 *
 * Activation :
 * 1. Choisir la fréquence sur AR_General_Setting__c.AR_Hierarchy_Notification_Frequency__c
 *    (Quotidien ou Hebdomadaire — Immédiat n'a pas besoin de ce job, cf. AR_NotificationService).
 * 2. System.schedule('AR Hierarchy Notification', '0 0 7 * * ?', new AR_HierarchyNotificationScheduler());
 *    (7 h, hors heures ouvrées : un digest n'a pas la même exigence de fraîcheur qu'une relance de
 *    dérogation).
 * Désactivation d'urgence : repositionner AR_Hierarchy_Notification_Frequency__c à Désactivé plutôt
 * que d'annuler le job planifié — même convention que les deux autres batchs de ce module.
 */
public class AR_HierarchyNotificationScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AR_HierarchyNotificationBatch(), 200);
    }
}