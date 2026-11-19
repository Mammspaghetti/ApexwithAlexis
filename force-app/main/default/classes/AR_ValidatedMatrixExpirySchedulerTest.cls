/** Test AR_ValidatedMatrixExpiryScheduler (session 175) : l'inscription crée bien un CronTrigger quotidien et le
 * déclenchement lance AR_ValidatedMatrixExpiryBatch. Le comportement du batch est dans AR_ValidatedMatrixExpiryBatchTest. */
@IsTest
private class AR_ValidatedMatrixExpirySchedulerTest {
    private static final String JOB_NAME = 'AR_ValidatedMatrixExpirySchedulerTest job';

    @IsTest
    static void testScheduleCreatesDailyCronTriggerAndRunLaunchesTheBatch() {
        Test.startTest();
        Id jobId = System.schedule(JOB_NAME, '0 30 3 * * ?', new AR_ValidatedMatrixExpiryScheduler());
        Test.stopTest();

        CronTrigger cron = [SELECT CronExpression, CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(JOB_NAME, cron.CronJobDetail.Name);
        System.assertEquals('0 30 3 * * ?', cron.CronExpression, 'Quotidien, 03:30');
    }

    @IsTest
    static void testExecuteEnqueuesTheExpiryBatch() {
        Test.startTest();
        new AR_ValidatedMatrixExpiryScheduler().execute(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = 'AR_ValidatedMatrixExpiryBatch'];
        System.assert(!jobs.isEmpty(), 'AR_ValidatedMatrixExpiryScheduler doit avoir lancé AR_ValidatedMatrixExpiryBatch');
    }
}