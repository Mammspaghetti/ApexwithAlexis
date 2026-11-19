@IsTest
private class AR_PerimeterSnapshotTest {
    @IsTest
    static void testPerimeterOfMatrix_readsPosition_andHandlesMissing() {
        Account acc = new Account(Name = 'Client Périmètre', AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT', ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001');
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Périmètre', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI', TP_P_rim_tre__c = 'NEO'
        );
        insert position;
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(AR_Position__c = position.Id, AR_Contract_Type__c = 'CDI', AR_Status__c = 'Brouillon', AR_Proposed_TJM__c = 480);
        insert m;
        System.assertEquals('NEO', AR_PerimeterSnapshot.perimeterOfMatrix(m.Id));
        System.assertEquals(null, AR_PerimeterSnapshot.perimeterOfMatrix(null));
    }
}