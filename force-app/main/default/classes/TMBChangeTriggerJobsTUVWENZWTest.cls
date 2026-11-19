@isTest(SeeAllData=true)
public without sharing class TMBChangeTriggerJobsTUVWENZWTest {
    @isTest
    public static void testTrigger() {
        SObject testRecord = TMB.TriggerTestUtils.createTestRecord('cxsrec__cxsPosition__c');
        System.assert(testRecord != null);
    }
}