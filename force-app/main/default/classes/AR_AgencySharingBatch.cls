/**
 * Session 282 — rattrapage du partage d'agence, étape 2 : lignes `AR_Agence_Matrice__c` sur toutes les matrices
 * et leurs motifs, par lots (lancé par scripts/apex/282-partage-agence.apex après l'étape « groupes et membres »,
 * dans d'autres transactions : DML mixte interdit). Idempotent, relançable.
 */
public without sharing class AR_AgencySharingBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([SELECT Id FROM AR_Price_Matrix__c]);
    }

    public void execute(Database.BatchableContext context, List<AR_Price_Matrix__c> scope) {
        AR_AgencySharingService.recalculateMatrices(new Map<Id, AR_Price_Matrix__c>(scope).keySet(), false);
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'Partage d’agence : rattrapage des matrices terminé.');
    }
}