@isTest(SeeAllData=true)
public without sharing class TMBChangeTriggerJobsI2R5L6IQTest {
    @isTest
    public static void testTrigger() {
        SObject testRecord = TMB.TriggerTestUtils.createTestRecord('cxsrec__cxsPosition__c');
        System.assert(testRecord != null);
    }
}