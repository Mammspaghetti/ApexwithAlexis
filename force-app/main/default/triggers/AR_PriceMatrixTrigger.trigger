trigger AR_PriceMatrixTrigger on AR_Price_Matrix__c (before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        AR_PriceMatrixTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    // Partage de la chaîne (création et changement de propriétaire).
    if (Trigger.isAfter && !Trigger.isDelete) {
        AR_MatrixSharingService.handleMatrixSaved(Trigger.new, Trigger.oldMap);
    }
    // Session 174 : liste « Matrice validée ». after delete lit Trigger.old (Trigger.new est nul).
    if (Trigger.isAfter) {
        AR_ValidatedMatrixSyncService.handle(
            Trigger.isDelete ? Trigger.old : Trigger.new,
            Trigger.oldMap,
            Trigger.isDelete
        );
    }
}