trigger AR_StepMatrixLinkTrigger on cxsrec__cxsStep__c (before insert, before update) {
    AR_StepMatrixLinkHandler.handleStepMatrixLink(Trigger.new, Trigger.oldMap);
}