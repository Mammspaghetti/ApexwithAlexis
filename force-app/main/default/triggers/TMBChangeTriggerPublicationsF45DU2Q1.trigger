trigger TMBChangeTriggerPublicationsF45DU2Q1 on Opportunity (after insert, after update, after delete, after undelete) {
    TMB.TriggerDispatcher.Run(new TMB.QueueableCallbackHandler('publications'));
}