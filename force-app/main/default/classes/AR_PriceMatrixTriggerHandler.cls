/**
 * Verrouillage serveur des matrices décidées : une fois sortie de Brouillon/En dérogation, une
 * matrice ne peut plus être modifiée que par les services Apex eux-mêmes (transitions de statut,
 * incrément de version). L'UI read-only de la session 4 est une aide au clic, pas une garantie —
 * le serveur fait foi.
 */
public class AR_PriceMatrixTriggerHandler {

    private static final Set<String> EDITABLE_STATUSES = new Set<String>{ 'Brouillon', 'En dérogation' };

    public static void beforeUpdate(List<AR_Price_Matrix__c> newRecords, Map<Id, AR_Price_Matrix__c> oldMap) {
        if (AR_TriggerBypass.serviceContext) {
            return;
        }
        for (AR_Price_Matrix__c newRecord : newRecords) {
            AR_Price_Matrix__c oldRecord = oldMap.get(newRecord.Id);
            if (!EDITABLE_STATUSES.contains(oldRecord.AR_Status__c)) {
                newRecord.addError(AR_I18n.format(Label.AR_Msg_MTX_Locked, new List<Object>{ oldRecord.AR_Status__c }));
                continue;
            }
            // Toute reprise réelle d'un brouillon (par son propriétaire, hors bypass service)
            // réinitialise l'avertissement de purge — sans quoi un brouillon repris serait quand
            // même supprimé plus tard par AR_DraftPurgeBatch. Le batch lui-même positionne
            // l'avertissement via AR_TriggerBypass.serviceContext, donc ne repasse jamais ici.
            if (oldRecord.AR_Status__c == 'Brouillon' && oldRecord.AR_Purge_Warning_Sent__c == true) {
                newRecord.AR_Purge_Warning_Sent__c = false;
                newRecord.AR_Purge_Warning_Sent_Date__c = null;
            }
        }
    }
}