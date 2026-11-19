@isTest
public class MockHttpResponseGenerator implements HttpCalloutMock {
    private Integer statusCode; // Een integer om de statuscode dynamisch in te stellen

    // Constructor om de statuscode in te stellen
    public MockHttpResponseGenerator(Integer statusCode) {
        this.statusCode = statusCode;
    }
    public HttpResponse respond(HttpRequest req) {
        // Maak een nieuwe HTTP-response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode); // Stel de statuscode in op succes

        // Simuleer een JSON-response van de externe service
        String jsonResponse = '{"autologinUrl": "https://example.com"}';

        // Stel de response-body in op de JSON-response
        res.setBody(jsonResponse);

        return res;
    }
    
}