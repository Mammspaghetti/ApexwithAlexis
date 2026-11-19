/**
 * Passage d'un besoin à « Gagné » : horodate les matrices validées du besoin et, si aucune version
 * n'est encore confirmée gagnante, prévient le propriétaire de la dernière validée et son DA
 * (notification in-app). Appelé par AR_PositionStatusTrigger, à côté (jamais à la place) de
 * AR_ValidatedMatrixSyncService.
 *
 * without sharing : les matrices sont Private et le trigger s'exécute pour n'importe quel utilisateur
 * qui modifie le besoin. Erreur technique : journalisée, jamais propagée vers Connexys.
 */
public without sharing class AR_WonDealDetector {
    public static final String WON_STATUS = 'Gagné';

    public static void handlePositions(
        List<cxsrec__cxsPosition__c> records,
        Map<Id, cxsrec__cxsPosition__c> oldMap
    ) {
        try {
            Set<Id> positionIds = new Set<Id>();
            if (records == null || oldMap == null) {
                return;
            }
            for (cxsrec__cxsPosition__c record : records) {
                cxsrec__cxsPosition__c oldRecord = oldMap.get(record.Id);
                if (oldRecord != null && record.cxsrec__Status__c == WON_STATUS && oldRecord.cxsrec__Status__c != WON_STATUS) {
                    positionIds.add(record.Id);
                }
            }
            if (positionIds.isEmpty()) {
                return;
            }
            if (Limits.getLimitQueries() - Limits.getQueries() < 5 || Limits.getLimitDmlStatements() - Limits.getDmlStatements() < 3) {
                System.debug(LoggingLevel.ERROR, 'AR_WonDealDetector : marge de limites insuffisante, ' + positionIds.size() + ' besoin(s) non traité(s).');
                return;
            }
            process(positionIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AR_WonDealDetector : ' + e.getTypeName() + ' — ' + e.getMessage() + ' — ' + e.getStackTraceString());
        }
    }

    private static void process(Set<Id> positionIds) {
        Set<String> validated = AR_ValidatedMatrixSyncService.VALIDATED_STATUSES;
        List<AR_Price_Matrix__c> matrices = [
            SELECT Id, OwnerId, AR_Position__c, AR_Account_Name__c, AR_Won__c
            FROM AR_Price_Matrix__c
            WHERE AR_Position__c IN :positionIds AND AR_Status__c IN :validated
            ORDER BY AR_Validated_At__c DESC NULLS LAST, CreatedDate DESC
        ];
        if (matrices.isEmpty()) {
            return;
        }
        Datetime now = System.now();
        Map<Id, AR_Price_Matrix__c> latestByPosition = new Map<Id, AR_Price_Matrix__c>();
        Set<Id> alreadyWon = new Set<Id>();
        List<AR_Price_Matrix__c> updates = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : matrices) {
            updates.add(new AR_Price_Matrix__c(Id = m.Id, AR_Position_Won_At__c = now));
            if (!latestByPosition.containsKey(m.AR_Position__c)) {
                latestByPosition.put(m.AR_Position__c, m);
            }
            if (m.AR_Won__c == true) {
                alreadyWon.add(m.AR_Position__c);
            }
        }
        AR_TriggerBypass.serviceContext = true;
        try {
            update updates;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Set<Id> ownerIds = new Set<Id>();
        for (Id positionId : latestByPosition.keySet()) {
            if (!alreadyWon.contains(positionId)) {
                ownerIds.add(latestByPosition.get(positionId).OwnerId);
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        Map<Id, User> owners = new Map<Id, User>([SELECT Id, IsActive, TP_DA__c, TP_DA__r.IsActive FROM User WHERE Id IN :ownerIds]);
        for (Id positionId : latestByPosition.keySet()) {
            if (alreadyWon.contains(positionId)) {
                continue;
            }
            AR_Price_Matrix__c latest = latestByPosition.get(positionId);
            Set<Id> recipients = new Set<Id>();
            User owner = owners.get(latest.OwnerId);
            if (owner != null && owner.IsActive) {
                recipients.add(owner.Id);
            }
            if (owner != null && owner.TP_DA__c != null && owner.TP_DA__r.IsActive == true) {
                recipients.add(owner.TP_DA__c);
            }
            AR_NotificationService.sendWonDealInApp(latest.AR_Account_Name__c, recipients);
        }
    }
}