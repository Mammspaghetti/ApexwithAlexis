@isTest(SeeAllData=true)
public without sharing class TMBChangeTriggerCandidatesME8VJMBPTest {
    @isTest
    public static void testTrigger() {
        SObject testRecord = TMB.TriggerTestUtils.createTestRecord('cxsrec__cxsCandidate__c');
        System.assert(testRecord != null);
    }
}