@isTest(SeeAllData=true)
public without sharing class TMBChangeTriggerPublicationsF45DU2Q1Test {
    @isTest
    public static void testTrigger() {
        SObject testRecord = TMB.TriggerTestUtils.createTestRecord('Opportunity');
        System.assert(testRecord != null);
    }
}