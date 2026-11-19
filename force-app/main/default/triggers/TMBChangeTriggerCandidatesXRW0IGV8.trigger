trigger TMBChangeTriggerCandidatesXRW0IGV8 on cxsrec__cxsCandidate__c (after insert, after update, after delete, after undelete) {
    TMB.TriggerDispatcher.Run(new TMB.QueueableCallbackHandler('candidates'));
}