/**
 * Crée les snapshots immuables AR_Matrix_Version__c à chaque validation/décision de matrice.
 * `without sharing` : la création du snapshot doit toujours réussir, même si l'utilisateur courant
 * n'a pas de droit d'édition explicite sur AR_Matrix_Version__c (cf. docs/02-modele-de-donnees.md §6 :
 * aucune permission Create/Edit/Delete utilisateur n'est accordée sur cet objet — Apex insère en
 * contexte système). La donnée du snapshot fait foi, jamais le PDF généré à partir d'elle.
 */
public without sharing class AR_MatrixVersionService {

    @AuraEnabled
    public static Id createSnapshot(Id matrixId, String snapshotTrigger) {
        try {
            AR_Price_Matrix__c m = [
                SELECT Id, AR_Position__c, AR_Status__c, AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c, AR_MC2_Per_Day__c, AR_MC2_Percent__c, AR_Corridor_Segment__c,
                       AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_TJM_Top10__c, AR_Total_Daily_Cost__c,
                       AR_Selected_Validator__c, AR_Effective_Validator__c, AR_Version_Number__c,
                       AR_Account_Name__c, AR_Account_Country__c, AR_Manager_Contact__c, AR_Position_Name__c,
                       AR_Currency__c, AR_Contract_Type__c, AR_RFA_Percent__c,
                       AR_Entity_Ref__c, AR_Entity_Ref__r.Name, AR_Consultant_Name__c, AR_Consultant__c, AR_Consultant__r.Name, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c,
                       AR_VIE_Country__c, AR_Nearshore_Country__c,
                       AR_Previous_Version__c, AR_Root_Matrix__c, AR_Negotiation_Version__c, AR_Version_Change_Comment__c,
                       AR_Currency_Rate_Applied__c, AR_Currency_Rate_Effective_Date__c,
                       AR_TJM_EUR_Equivalent__c, AR_Total_Daily_Cost_EUR_Equivalent__c, AR_MC2_Per_Day_EUR_Equivalent__c,
                       AR_Contract_Coefficient_Applied__c, AR_Seniority__c, AR_Fee_Periods__c, AR_TJM_Periods__c, AR_Salary_Periods__c, AR_TJM_Weighted__c,
                       AR_RPLSR_Enabled__c, AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Plan__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c
                FROM AR_Price_Matrix__c
                WHERE Id = :matrixId
                LIMIT 1
            ];

            AR_ComparablesService.MarketReference marketRef = AR_ComparablesService.getMarketReference(
                m.AR_Position__c,
                m.AR_Contract_Type__c,
                m.AR_Currency__c,
                m.AR_Currency_Rate_Applied__c,
                m.AR_Seniority__c
            );

            List<String> versionReasons = new List<String>();
            for (AR_Reason_Selection__c sel : [
                SELECT AR_Reason__r.Name
                FROM AR_Reason_Selection__c
                WHERE AR_Price_Matrix__c = :m.Id
            ]) {
                versionReasons.add(sel.AR_Reason__r.Name);
            }

            Map<String, Object> snapshotPayload = new Map<String, Object>{
                'snapshotTrigger' => snapshotTrigger,
                'matrix' => m,
                'marketReference' => marketRef,
                'previousVersionId' => m.AR_Previous_Version__c,
                'rootMatrixId' => m.AR_Root_Matrix__c,
                'negotiationVersion' => m.AR_Negotiation_Version__c,
                'versionChangeReasons' => versionReasons
            };

            AR_Matrix_Version__c version = new AR_Matrix_Version__c();
            version.AR_Price_Matrix__c = m.Id;
            version.AR_Snapshot__c = JSON.serialize(snapshotPayload);
            version.AR_TJM__c = AR_PricingMatrixService.effectiveTjm(m);
            version.AR_MC2_Percent__c = m.AR_MC2_Percent__c;
            version.AR_Corridor_Segment__c = m.AR_Corridor_Segment__c;
            version.AR_Status__c = m.AR_Status__c;
            version.AR_TJM_Floor__c = m.AR_TJM_Floor__c;
            version.AR_TJM_Target__c = m.AR_TJM_Target__c;
            version.AR_TJM_Ideal__c = m.AR_TJM_Ideal__c;
            version.AR_TJM_Top10__c = m.AR_TJM_Top10__c;
            version.AR_Selected_Validator__c = m.AR_Selected_Validator__c;
            version.AR_Effective_Validator__c = m.AR_Effective_Validator__c;
            version.AR_Snapshot_At__c = System.now();
            Database.insert(version, AccessLevel.SYSTEM_MODE);

            Decimal newVersionNumber = (m.AR_Version_Number__c != null ? m.AR_Version_Number__c : 0) + 1;
            AR_TriggerBypass.serviceContext = true;
            try {
                Database.update(
                    new AR_Price_Matrix__c(Id = m.Id, AR_Version_Number__c = newVersionNumber),
                    AccessLevel.SYSTEM_MODE
                );
            } finally {
                AR_TriggerBypass.serviceContext = false;
            }

            return version.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_VER_SnapshotAction);
        }
    }
}