public with sharing class VacancyAssistentFlowController {
    @InvocableMethod(label='Vacabuilder')
    public static List<ResponseList> calloutAzure(List<Request> token){
        Request req = token[0];
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:vacaBuilder' + '/vacancies/write');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + req.token);
        request.setTimeout(120000);
        Map<String, Object> bodyMap = new Map<String, Object>(); 
        Map<String, Object> keyValueMap = new Map<String, Object>(); 
        keyValueMap.put('job_title', req.jobTitle);
        keyValueMap.put('job_info', req.info);
        keyValueMap.put('company_name', req.companyName);
        keyValueMap.put('company_info', req.companyInfo); 
        keyValueMap.put('sector',req.sector);
        keyValueMap.put('subsector',req.subsector);
        bodyMap.put('input',keyValueMap);
        Map<String, Object> keyValueMap1 = new Map<String, Object>(); 
        keyValueMap1.put('target_language', req.language);
        keyValueMap1.put('target_seniority', req.seniority);
        keyValueMap1.put('writing_style', req.writingStyle);
        bodyMap.put('options',keyValueMap1);
        System.debug(bodyMap);
        request.setBody(JSON.serialize(bodyMap));
        // Send the request using the Named Credential
        HttpResponse response = new Http().send(request);
        ResponseList res = new ResponseList();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        if(response.getStatusCode() == 200){
            res.requirements = (String)results.get('job_requirements');
            res.description = (String)results.get('job_description');
        }else{
            res.requirements = 'error';
            res.description = 'error';
        }
        List<ResponseList> responseItems = new List<ResponseList>();
        responseItems.add(res);

        return responseItems;
    }
    public class Request{
        @InvocableVariable
        public String token;

        @InvocableVariable
        public String jobTitle;

        @InvocableVariable
        public String companyName;

        @InvocableVariable
        public String companyInfo;

        @InvocableVariable
        public String language;

        @InvocableVariable
        public String sector;

        @InvocableVariable
        public String subsector;

        @InvocableVariable
        public String seniority;

        @InvocableVariable
        public String writingStyle;

        @InvocableVariable
        public String info;
    }

    public class ResponseList{
        @InvocableVariable
        public String requirements;

        @InvocableVariable
        public String description;
    }
}