/** Test AR_DerogationReminderScheduler : lance bien AR_DerogationReminderBatch (no-op avec les
 * réglages réels par défaut, AR_Derogation_Reminder_Enabled__c = false — la couverture du
 * comportement activé est dans AR_DerogationReminderBatchTest). */
@IsTest
private class AR_DerogationReminderSchedulerTest {

    @IsTest
    static void testExecute_enqueuesBatchJob() {
        Test.startTest();
        String jobId = System.schedule(
            'AR_DerogationReminderSchedulerTest job',
            '0 0 3 * * ?',
            new AR_DerogationReminderScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job planifié doit être créé');
        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AR_DerogationReminderBatch'
        ];
        System.assert(!jobs.isEmpty(), 'AR_DerogationReminderScheduler doit avoir lancé AR_DerogationReminderBatch');
    }
}