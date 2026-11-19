trigger AR_Currency_RateTrigger on AR_Currency_Rate__c (before delete) {
    if (Trigger.isBefore && Trigger.isDelete) {
        AR_Currency_RateTriggerHandler.beforeDelete(Trigger.old);
    }
}