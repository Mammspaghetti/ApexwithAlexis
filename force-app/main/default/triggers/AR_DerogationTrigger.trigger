trigger AR_DerogationTrigger on AR_Derogation__c (before update, before delete) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        AR_DerogationTriggerHandler.beforeUpdate(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        AR_DerogationTriggerHandler.beforeDelete(Trigger.old);
    }
}