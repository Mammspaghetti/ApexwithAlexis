trigger AR_UserTrigger on User (after insert, after update) {
    // Changement des six champs de la chaîne → recalcul asynchrone du partage des matrices du propriétaire.
    if (Trigger.isUpdate) {
        AR_MatrixSharingService.onUsersUpdated(Trigger.new, Trigger.oldMap);
    }
    // Session 282 : agence ou activation → groupe d'agence (asynchrone), puis partage en lecture des matrices.
    AR_AgencySharingService.onUsersChanged(Trigger.new, Trigger.oldMap);
}