/**
 * Session 175 — Expiration des entrées « Matrice validée » (AR_Validated_Matrix__c) dont la date de validation est
 * plus vieille que AR_General_Setting__c.AR_Validated_Matrix_Lifetime_Days__c jours (365 par défaut).
 *
 * Ne touche QUE les entrées (données dérivées) : la vraie matrice, ses snapshots et le champ « Matrice de prix
 * (référence) » des Steps (AR_Price_Matrix__c, posé en session 174) ne sont jamais modifiés ; seul le champ de la
 * popup (AR_Validated_Matrix__c du Step) est vidé par la plateforme (SetNull).
 *
 * Même critère que la synchro (AR_ValidatedMatrixSyncService.validatedOn / cutoffFor) : AR_Validated_At__c de la
 * matrice, à défaut sa date de création ; exactement N jours = conservée. La synchro applique la même règle, donc
 * une entrée expirée n'est pas recréée par un événement ultérieur sur la matrice ou le besoin.
 *
 * Sans effet si la synchro est coupée (AR_Validated_Matrix_Sync_Enabled__c = false) : l'interrupteur gèle tout le
 * module « Matrice validée » (entrées conservées), expiration comprise.
 *
 * without sharing : les matrices sont Private, l'entrée doit être trouvée quel que soit son propriétaire.
 * Ordonnancement : AR_ValidatedMatrixExpiryScheduler (quotidien). Modèle : AR_DraftPurgeBatch.
 */
public without sharing class AR_ValidatedMatrixExpiryBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        AR_General_Setting__c settings = AR_ValidatedMatrixSyncService.loadSettings();
        if (!AR_ValidatedMatrixSyncService.isSyncEnabled(settings)) {
            return Database.getQueryLocator([SELECT Id FROM AR_Validated_Matrix__c WHERE Id = null]);
        }
        Datetime cutoff = AR_ValidatedMatrixSyncService.cutoffFor(settings);
        return Database.getQueryLocator([
            SELECT Id
            FROM AR_Validated_Matrix__c
            WHERE (AR_Price_Matrix__r.AR_Validated_At__c != null AND AR_Price_Matrix__r.AR_Validated_At__c < :cutoff)
               OR (AR_Price_Matrix__r.AR_Validated_At__c = null AND AR_Price_Matrix__r.CreatedDate < :cutoff)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<AR_Validated_Matrix__c> scope) {
        if (scope.isEmpty()) {
            return;
        }
        // allOrNone = false : une entrée déjà supprimée entre-temps (synchro concurrente) ne doit pas faire échouer le lot.
        // Étiquette « journaliser » (CLAUDE.md, session 34) : l'échec est tracé, la purge reprend au passage suivant.
        for (Database.DeleteResult result : Database.delete(scope, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'AR_ValidatedMatrixExpiryBatch : suppression refusée ' + result.getId()
                    + ' — ' + result.getErrors()[0].getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}