/**
 * Verrouillage serveur de AR_Reason_Selection__c, même famille que AR_PriceMatrixTriggerHandler /
 * AR_DerogationTriggerHandler.
 * - beforeInsert : contrôle XOR structurel des deux lookups parent (AR_Price_Matrix__c /
 *   AR_Derogation__c) — ne pas compter sur la seule discipline du service appelant.
 * - beforeUpdate/beforeDelete : une sélection de motif devient immuable dès que son parent est
 *   décidé (même statut/décision qui verrouille déjà le parent lui-même), au même titre que le
 *   snapshot AR_Matrix_Version__c.
 */
public class AR_ReasonSelectionTriggerHandler {

    private static final Set<String> EDITABLE_MATRIX_STATUSES = new Set<String>{ 'Brouillon', 'En dérogation' };

    public static void beforeInsert(List<AR_Reason_Selection__c> newRecords) {
        for (AR_Reason_Selection__c newRecord : newRecords) {
            Boolean hasMatrix = newRecord.AR_Price_Matrix__c != null;
            Boolean hasDerogation = newRecord.AR_Derogation__c != null;
            if (hasMatrix == hasDerogation) {
                newRecord.addError(Label.AR_Msg_RSN_ExactlyOneParent);
            }
        }
    }

    public static void beforeUpdate(List<AR_Reason_Selection__c> newRecords) {
        if (AR_TriggerBypass.serviceContext) {
            return;
        }
        lockIfParentDecided(newRecords);
    }

    public static void beforeDelete(List<AR_Reason_Selection__c> oldRecords) {
        if (AR_TriggerBypass.serviceContext) {
            return;
        }
        lockIfParentDecided(oldRecords);
    }

    private static void lockIfParentDecided(List<AR_Reason_Selection__c> records) {
        Set<Id> matrixIds = new Set<Id>();
        Set<Id> derogationIds = new Set<Id>();
        for (AR_Reason_Selection__c r : records) {
            if (r.AR_Price_Matrix__c != null) {
                matrixIds.add(r.AR_Price_Matrix__c);
            }
            if (r.AR_Derogation__c != null) {
                derogationIds.add(r.AR_Derogation__c);
            }
        }

        Map<Id, String> matrixStatuses = new Map<Id, String>();
        for (AR_Price_Matrix__c m : [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c WHERE Id IN :matrixIds]) {
            matrixStatuses.put(m.Id, m.AR_Status__c);
        }
        Map<Id, String> derogationDecisions = new Map<Id, String>();
        for (AR_Derogation__c d : [SELECT Id, AR_Decision__c FROM AR_Derogation__c WHERE Id IN :derogationIds]) {
            derogationDecisions.put(d.Id, d.AR_Decision__c);
        }

        for (AR_Reason_Selection__c r : records) {
            if (r.AR_Price_Matrix__c != null) {
                String status = matrixStatuses.get(r.AR_Price_Matrix__c);
                if (!EDITABLE_MATRIX_STATUSES.contains(status)) {
                    r.addError(Label.AR_Msg_RSN_MatrixDecided);
                }
            } else if (r.AR_Derogation__c != null) {
                String decision = derogationDecisions.get(r.AR_Derogation__c);
                if (decision != 'En attente') {
                    r.addError(Label.AR_Msg_RSN_DerogationProcessed);
                }
            }
        }
    }
}