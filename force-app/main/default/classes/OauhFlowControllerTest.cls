@isTest
private class OauhFlowControllerTest {

    @isTest
    static void testOauthToken() {

        // Mock the HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200));

        // Call the OauthToken method
        Test.startTest();
        List<OauhFlowController.Results> resultsList = OauhFlowController.OauthToken();
        Test.stopTest();
    }
}