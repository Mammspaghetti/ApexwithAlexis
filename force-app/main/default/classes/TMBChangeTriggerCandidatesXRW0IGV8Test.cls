@isTest(SeeAllData=true)
public without sharing class TMBChangeTriggerCandidatesXRW0IGV8Test {
    @isTest
    public static void testTrigger() {
        SObject testRecord = TMB.TriggerTestUtils.createTestRecord('cxsrec__cxsCandidate__c');
        System.assert(testRecord != null);
    }
}