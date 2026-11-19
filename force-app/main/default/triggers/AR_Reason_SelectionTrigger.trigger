trigger AR_Reason_SelectionTrigger on AR_Reason_Selection__c (before insert, before update, before delete, after insert) {
    // Un motif ajouté suit le partage de sa matrice (lookup en cascade, sans héritage).
    if (Trigger.isAfter && Trigger.isInsert) {
        AR_MatrixSharingService.handleReasonsInserted(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        AR_ReasonSelectionTriggerHandler.beforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        AR_ReasonSelectionTriggerHandler.beforeUpdate(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        AR_ReasonSelectionTriggerHandler.beforeDelete(Trigger.old);
    }
}