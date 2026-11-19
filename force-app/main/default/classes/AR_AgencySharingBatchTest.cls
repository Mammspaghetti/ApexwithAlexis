/**
 * Tests AR_AgencySharingBatch (session 282) : le lot de rattrapage repose les lignes d'agence manquantes et
 * relancé, n'en crée pas de doublon.
 */
@IsTest
private class AR_AgencySharingBatchTest {

    @TestSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_Validated_Matrix_Lifetime_Days__c = 36500,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Max_Per_Run__c = 100,
            AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Working_Days_Per_Year__c = 218
        );
        insert new Account(
            Name = 'Client Lot 282', AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001'
        );
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
    }

    private static Integer agencyShares(Id matrixId) {
        return [
            SELECT COUNT() FROM AR_Price_Matrix__Share
            WHERE ParentId = :matrixId AND RowCause = :AR_AgencySharingService.ROW_CAUSE
        ];
    }

    @IsTest
    static void testBatchRestoresMissingAgencyShares_withoutDuplicates() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new List<User>{
                new User(Id = owner.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Nantes'), new User(Id = colleague.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Nantes')
            };
            AR_AgencySharingService.syncMemberships(new Set<Id>{ owner.Id, colleague.Id });
        }
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Lot 282' LIMIT 1];
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Lot 282', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        AR_TestPersona.makePositionOwner(position.Id, owner.Id);
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = owner.Id, AR_Position__c = position.Id, AR_Status__c = 'Brouillon', AR_Contract_Type__c = 'CDI',
            AR_Currency__c = 'EUR', AR_Annual_Salary__c = 35000, AR_Proposed_TJM__c = 500, AR_RFA_Percent__c = 0,
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA')
        );
        System.runAs(owner) {
            insert m;
        }
        System.assertEquals(1, agencyShares(m.Id), 'Ligne posée à la création.');
        delete [SELECT Id FROM AR_Price_Matrix__Share WHERE ParentId = :m.Id AND RowCause = :AR_AgencySharingService.ROW_CAUSE];

        Test.startTest();
        Database.executeBatch(new AR_AgencySharingBatch(), 200);
        Test.stopTest();

        System.assertEquals(1, agencyShares(m.Id), 'Le lot repose la ligne manquante.');
        new AR_AgencySharingBatch().execute(null, new List<AR_Price_Matrix__c>{ m });
        System.assertEquals(1, agencyShares(m.Id), 'Relancé : aucun doublon.');
        System.runAs(colleague) {
            System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :m.Id], 'Le collègue voit la matrice.');
        }
    }
}