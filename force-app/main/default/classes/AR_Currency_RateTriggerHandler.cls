/**
 * Blocage serveur de la suppression des taux de change : garantie de non-rétroactivité
 * (session 50, confirmée session 131b). Un taux ne peut jamais être supprimé, y compris
 * par un administrateur système. L'application n'expose pas de suppression, mais un admin
 * devises peut la tenter depuis l'interface Salesforce standard ou l'API.
 */
public class AR_Currency_RateTriggerHandler {

    public static void beforeDelete(List<AR_Currency_Rate__c> oldRecords) {
        for (AR_Currency_Rate__c rate : oldRecords) {
            rate.addError(
                Label.AR_Msg_CUR_CannotDelete
            );
        }
    }
}