@isTest
private class VacancyAssistentFlowControllerTest {

    @isTest
    static void testCalloutAzure() {
        // Mock the HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200));
        // Create a test request
        VacancyAssistentFlowController.Request testRequest = new VacancyAssistentFlowController.Request();
        testRequest.token = 'TestToken';
        testRequest.jobTitle = 'TestJobTitle';
        // Add other required fields

        // Create a list of requests
        List<VacancyAssistentFlowController.Request> requestList = new List<VacancyAssistentFlowController.Request>();
        requestList.add(testRequest);

        // Call the calloutAzure method
        Test.startTest();
        List<VacancyAssistentFlowController.ResponseList> resultList = VacancyAssistentFlowController.calloutAzure(requestList);
        Test.stopTest();

    }

    // Add more test methods for other public methods in VacancyAssistentFlowController
}