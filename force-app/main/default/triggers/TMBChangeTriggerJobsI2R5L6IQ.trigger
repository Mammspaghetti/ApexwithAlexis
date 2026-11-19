trigger TMBChangeTriggerJobsI2R5L6IQ on cxsrec__cxsPosition__c (after insert, after update, after delete, after undelete) {
    TMB.TriggerDispatcher.Run(new TMB.QueueableCallbackHandler('jobs'));
}