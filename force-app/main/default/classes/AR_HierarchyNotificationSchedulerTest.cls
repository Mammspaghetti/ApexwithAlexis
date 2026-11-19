/** Test AR_HierarchyNotificationScheduler : lance bien AR_HierarchyNotificationBatch (no-op avec
 * les réglages réels par défaut, AR_Hierarchy_Notification_Frequency__c = 'Désactivé' — la
 * couverture du comportement activé est dans AR_HierarchyNotificationBatchTest). */
@IsTest
private class AR_HierarchyNotificationSchedulerTest {

    @IsTest
    static void testExecute_enqueuesBatchJob() {
        Test.startTest();
        String jobId = System.schedule(
            'AR_HierarchyNotificationSchedulerTest job',
            '0 0 4 * * ?',
            new AR_HierarchyNotificationScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job planifié doit être créé');
        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AR_HierarchyNotificationBatch'
        ];
        System.assert(!jobs.isEmpty(), 'AR_HierarchyNotificationScheduler doit avoir lancé AR_HierarchyNotificationBatch');
    }
}