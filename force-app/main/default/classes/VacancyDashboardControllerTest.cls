@isTest
private class VacancyDashboardControllerTest {
    @isTest
    static void testErrorUserTA() {
        cxsrec__cxsPosition__c vac  = new cxsrec__cxsPosition__c();
        vac.Name = 'test';
        vac.cxsrec__Channel_Internet_start_date__c = System.today();
        insert vac;

        Contact user = new Contact();
        user.firstName = 'test';
        user.lastName = 'test';
        insert user;

        VacancyDashoardController.createUserTA(user.Id, vac.Id);
        //Delete the record
        VacancyDashoardController.deleteUserTA(user.Id, vac.Id);

    }

    @isTest
    static void testUserTA() {
        cxsrec__cxsPosition__c vac  = new cxsrec__cxsPosition__c();
        vac.Name = 'test';
        vac.cxsrec__Channel_Internet_start_date__c = System.today();
        insert vac;

        User u = [select Id from User limit 1];

        VacancyDashoardController.createUserTA(u.Id, vac.Id);
        //get records
        VacancyDashoardController.getAllUsersTA(vac.Id,5);
        VacancyDashoardController.getUsersTA(vac.Id,5);
        //Delete the record
        VacancyDashoardController.deleteUserTA(u.Id, vac.Id);

    }

    @isTest(seeAllData=true)
    static void TestgetFilters(){
        Test.startTest();
        String result = VacancyDashoardController.getFilters('Dev',null,null,null,null,null);
        Integer result1 = VacancyDashoardController.countVacancyForUser('Dev',null,null,null,null,null);
        VacancyDashoardController.getVacancyForUser(0,'Dev',null,null,null,null,null,'ASC','priorite');
        Test.stopTest();
    }

    @isTest(seeAllData=true)
    static void testGetData(){
        Test.startTest();
        Integer result2 = VacancyDashoardController.countVacancyForUser(null,null,null,null,null,null);
        VacancyDashoardController.getVacancyForUser(0,null,null,null,null,null,null,'ASC','sourcingPriority');
        Test.stopTest();
    }

    @isTest(seeAllData=true)
    static void TestchangeStatusJobApplication(){
        cxsrec__cxsPosition__c vac  = [select Id from cxsrec__cxsPosition__c limit 1];
        cxsrec__cxsCandidate__c cand = [select Id from cxsrec__cxsCandidate__c limit 1];

        String job = VacancyDashoardController.createJobApplication(cand.Id,vac.Id);
        VacancyDashoardController.changeStatusJobApplication('KO Abylsen',job);
    }

    @isTest
    static void testUpdateNeed() {
        // Create test data
        cxsrec__cxsPosition__c vac  = new cxsrec__cxsPosition__c();
        vac.Name = 'test';
        vac.cxsrec__Channel_Internet_start_date__c = System.today();
        insert vac;

        String testData = '{"Id":"' + vac.Id + '","Name":"New Value"}';

        // Call the method to be tested
        Test.startTest();
        String result = VacancyDashoardController.updateNeed(testData);
        Test.stopTest();
    }

}