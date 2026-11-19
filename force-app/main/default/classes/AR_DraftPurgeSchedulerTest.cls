/** Test AR_DraftPurgeScheduler : lance bien AR_DraftPurgeBatch (no-op avec les réglages réels par
 * défaut, AR_Draft_Purge_Enabled__c = false — la couverture du comportement activé est dans
 * AR_DraftPurgeBatchTest). */
@IsTest
private class AR_DraftPurgeSchedulerTest {

    @IsTest
    static void testExecute_enqueuesBatchJob() {
        Test.startTest();
        String jobId = System.schedule(
            'AR_DraftPurgeSchedulerTest job',
            '0 0 2 * * ?',
            new AR_DraftPurgeScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job planifié doit être créé');
        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AR_DraftPurgeBatch'
        ];
        System.assert(!jobs.isEmpty(), 'AR_DraftPurgeScheduler doit avoir lancé AR_DraftPurgeBatch');
    }
}