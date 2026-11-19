global with sharing class OauhFlowController {

    @testVisible static private Map<String, sObject> metadataCoverageRecordMap = new Map<String, sObject>();

    public static sObject getMetadataCoverageRecord(String query) {
        if (!metadataCoverageRecordMap.containsKey(query)) {
            metadataCoverageRecordMap.put(query, Database.query(query));
        } 
        return metadataCoverageRecordMap.get(query);
    }

    @InvocableMethod
    public static List <Results> OauthToken(){
        Results response = new Results();

        HrlHOHR__Vacancy_Assistent_Setting__mdt setting = (HrlHOHR__Vacancy_Assistent_Setting__mdt) getMetadataCoverageRecord('SELECT Id,HrlHOHR__audience__c,HrlHOHR__client_id__c,HrlHOHR__client_secret__c,HrlHOHR__grant_type__c,HrlHOHR__parentID_Field__r.QualifiedApiName,HrlHOHR__Translation_Object__r.QualifiedApiName,HrlHOHR__Translation_on_same_object__c,HrlHOHR__Translation_Language_Field__r.QualifiedApiName,HrlHOHR__recordTypeId__c,HrlHOHR__Translation_Language_Config_Name__c FROM HrlHOHR__Vacancy_Assistent_Setting__mdt where DeveloperName = \'Main\' limit 1');

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:hohrOauth');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setTimeout(120000);
        request.setBody('grant_type=' + setting.HrlHOHR__grant_type__c +'&audience=' + setting.HrlHOHR__audience__c + '&client_id=' + setting.HrlHOHR__client_id__c + '&client_secret=' + setting.HrlHOHR__client_secret__c);

        // Send the request using the Named Credential
        HttpResponse resp = new Http().send(request);  
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        String token;
         List<String> lString = new List<String>();
        if(resp.getStatusCode() == 200){
            response.token = (String)result.get('access_token');
           
        }else{
            response.token = null;
        }
        List<Results> responseWrapper= new List<Results>();
        responseWrapper.add(response);
        return responseWrapper;

    } 
    public class Results {
        @InvocableVariable(label='Records for Output' description='yourDescription' required=true)
        public String token;
    }
}