/**
 * Verrouillage serveur des dérogations : toute modification ou suppression doit passer par
 * AR_DerogationService.decide() (positionne AR_TriggerBypass.serviceContext). Sans ce verrou, un
 * valideur peut éditer AR_Decision__c depuis le layout standard en contournant le service — ni
 * commentaire obligatoire, ni snapshot, ni changement de statut de la matrice, ni email.
 */
public class AR_DerogationTriggerHandler {

    public static void beforeUpdate(List<AR_Derogation__c> newRecords) {
        if (AR_TriggerBypass.serviceContext) {
            return;
        }
        for (AR_Derogation__c newRecord : newRecords) {
            newRecord.addError(Label.AR_Msg_DRG_OnlyViaValidator);
        }
    }

    public static void beforeDelete(List<AR_Derogation__c> oldRecords) {
        if (AR_TriggerBypass.serviceContext) {
            return;
        }
        for (AR_Derogation__c oldRecord : oldRecords) {
            oldRecord.addError(Label.AR_Msg_DRG_CannotDelete);
        }
    }
}