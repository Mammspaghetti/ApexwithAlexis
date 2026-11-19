trigger AR_PTFEntityValidatorTrigger on AR_PTF_Entity_Validator__c (after insert, after delete) {
    // Valideur d'entité ajouté ou retiré → recalcul asynchrone du partage des matrices de l'entité.
    AR_MatrixSharingService.onEntityValidatorsChanged(Trigger.isDelete ? Trigger.old : Trigger.new);
}