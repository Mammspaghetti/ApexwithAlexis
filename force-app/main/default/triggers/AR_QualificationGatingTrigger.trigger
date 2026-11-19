trigger AR_QualificationGatingTrigger on cxsrec__cxsJob_application__c (before insert, before update) {
    AR_QualificationGatingHandler.beforeSave(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
}