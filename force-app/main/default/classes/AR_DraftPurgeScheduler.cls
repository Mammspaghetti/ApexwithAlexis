/**
 * Lance AR_DraftPurgeBatch. Prévu pour un System.schedule quotidien, non activé par ce
 * déploiement (cf. AR_DraftPurgeBatch et docs/22-versioning-negociation.md pour la procédure
 * d'activation/désactivation). Désactivation : positionner AR_General_Setting__c.AR_Draft_Purge_Enabled__c
 * à false plutôt que de désinscrire le job planifié — le batch devient alors un no-op immédiat.
 */
public class AR_DraftPurgeScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AR_DraftPurgeBatch(), 200);
    }
}