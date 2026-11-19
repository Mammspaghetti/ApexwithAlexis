public with sharing class VacancyDashoardController {
    @AuraEnabled
    public static Boolean createUserTA(String userId, String vacancyId){
        try{
            cxsPosition_With_TA__c userTA = new cxsPosition_With_TA__c();
            userTA.User__c = userId;
            userTA.Job__c = vacancyId;
            insert userTA;
            return true;
        }catch(Exception e){
            return false;
        }
    }

    @AuraEnabled
    public static Boolean deleteUserTA(String userId, String vacancyId){
        try{
            cxsPosition_With_TA__c userTA = [SELECT Id FROM cxsPosition_With_TA__c WHERE User__c = :userId AND Job__c = :vacancyId];
            delete userTA;
            return true;
        }catch(Exception e){
            return false;
        }
    }

    @AuraEnabled
    public static List<cxsPosition_With_TA__c> getAllUsersTA(string vacancyId,integer limitItems){
        List<cxsPosition_With_TA__c> result = [SELECT Id, User__r.Id, User__r.Name FROM cxsPosition_With_TA__c WHERE Job__c = :vacancyId limit :limitItems];
        return result;
    }

    @AuraEnabled
    public static String changeStatusJobApplication(String status,String jobAppID){
       list<cxsrec__cxsWorkflow_status__c> workflow = database.query('SELECT Id FROM cxsrec__cxsWorkflow_status__c WHERE Name  like  \'%' + status + '\'');
       System.debug('workflow: ' + workflow);
       set<Id> workflowIds = new set<Id>();
        for(cxsrec__cxsWorkflow_status__c w : workflow){
            workflowIds.add(w.Id);
        }

        system.debug('workflowIds: ' + workflowIds);

        cxsrec__cxsJob_application__c jobApp = [SELECT Id,cxsrec__Candidate__c, cxsrec__Workflow_status__c FROM cxsrec__cxsJob_application__c WHERE Id = :jobAppID];

        list<cxsrec__cxsWorkflow_status_transition__c> workflowTrans = [select Id,cxsrec__Workflow_event_type__c,cxsrec__New_workflow_status__r.Id from cxsrec__cxsWorkflow_status_transition__c where cxsrec__Old_workflow_status__c = :jobApp.cxsrec__Workflow_status__c and cxsrec__New_workflow_status__r.Id IN :workflowIds];

        System.debug('workflowTrans: ' + workflowTrans);
        cxsrec__cxsWorkflow_status_transition__c workflowItem = new cxsrec__cxsWorkflow_status_transition__c();
        //check if workflow transition is possible
        boolean isPossible = false;
        for(cxsrec__cxsWorkflow_status_transition__c w : workflowTrans){
            if(workflowIds.contains(w.cxsrec__New_workflow_status__r.Id)){
                workflowItem = w;
                isPossible = true;
                break;
            }
        }

        String json = '';
        if(isPossible){
            cxsrec__cxsStep__c step = new cxsrec__cxsStep__c();
            step.cxsrec__Job_application__c = jobAppID;
            step.cxsrec__Candidate__c = jobApp.cxsrec__Candidate__c;
            step.cxsrec__New_workflow_status__c = workflowItem.cxsrec__New_workflow_status__r.Id;
            step.cxsrec__Workflow_event__c = workflowItem.cxsrec__Workflow_event_type__c;
            insert step;
            jobApp.cxsrec__Workflow_status__c = workflowItem.cxsrec__New_workflow_status__r.Id;
            update jobApp;
            json = '{"status":200,"message":""}';
        }else{
            json = '{"status":500,"message":"Workflow Step is not possible"}';
            
        }
       
        return json;
    }


    @AuraEnabled
    public static String createJobApplication(string candidateId, string vacancyId){
        //check if job application already exists
        list<cxsrec__cxsJob_application__c> jobApp = [SELECT Id FROM cxsrec__cxsJob_application__c WHERE cxsrec__Candidate__c = :candidateId AND cxsrec__Position__c = :vacancyId];
        if(jobApp.size()  > 0){return 'exist';}
        //string to json object
        cxsrec__cxsCandidate__c cand = [SELECT Id,OwnerId, Name FROM cxsrec__cxsCandidate__c WHERE Id = :candidateId];
        cxsrec__cxsPosition__c vac = [SELECT Id, Name FROM cxsrec__cxsPosition__c WHERE Id = :vacancyId];
        String jobName = cand.Name + ' - ' + vac.Name;
        //max 80 characters
        if(jobName.length() > 80){ jobName = jobName.substring(0,80);}

        cxsrec__cxsJob_application__c jobApplication = new cxsrec__cxsJob_application__c();
        jobApplication.cxsrec__Candidate__c = candidateId;
        jobApplication.Name = jobName;
        jobApplication.cxsrec__Position__c = vacancyId;
        jobApplication.cxsrec__Workflow_status__c = 'a180900000022xwAAA';
        jobApplication.recordTypeId = '01209000001Z20rAAC';

        insert jobApplication;

        ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
        ConnectApi.MentionSegmentInput mentionSegmentInput = new ConnectApi.MentionSegmentInput();
        ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
        ConnectApi.TextSegmentInput textSegmentInput = new ConnectApi.TextSegmentInput();

        messageBodyInput.messageSegments = new List<ConnectApi.MessageSegmentInput>();

        mentionSegmentInput.id = cand.OwnerId;
        messageBodyInput.messageSegments.add(mentionSegmentInput);

        textSegmentInput.text = ' Your candidate ' + cand.Name + ' has been linked to a need by ' +   UserInfo.getFirstName() + ' ' + UserInfo.getLastName() + ':' +  vac.Name;
        messageBodyInput.messageSegments.add(textSegmentInput);

        feedItemInput.body = messageBodyInput;
        feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
        feedItemInput.subjectId = cand.Id;
        ConnectApi.FeedElement feedElement = ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), feedItemInput);

        return jobApplication.Id;
    }



    @AuraEnabled(cacheable=false)
    public static String getFilters(String search, string filterBM, string filterTA, string filterSourcing, string filterPriority,String filterAccount){
        User currentUser = [SELECT Id, TP_Perimetre__c FROM User WHERE Id = :UserInfo.getUserId()];
        //BM
        Id recordType = [Select Id from RecordType where name = 'Offre'].Id;
        String searchBM = 'Select TP_Manager__r.Id, TP_Manager__r.Name, TP_P_rim_tre__c, Count(Id)  FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true AND RecordType.Id != \'' + recordType + '\'';

        String searchAccount = 'Select AB_Need_details__r.AB_Account__r.Name,AB_Need_details__r.AB_Account__r.Id, Count(Id)  FROM cxsrec__cxsPosition__c WHERE  cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true AND RecordType.Id != \'' + recordType + '\'';

        String searchTA = 'select User__r.Id, User__r.Name, Count(Id)  from cxsPosition_With_TA__c WHERE  Job__r.cxsrec__Status__c = \'Open\' AND Job__r.AB_Display_in_need_dashboard__c = true AND Job__r.RecordType.Id != \'' + recordType + '\'';

        String searchSourcing = 'Select Priorit_sourcing__c, Count(Id)  FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true  AND RecordType.Id != \'' + recordType + '\'';

        String searchNeedPriority = 'Select Priorit__c, Count(Id)  FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true AND RecordType.Id != \'' + recordType + '\'';

        if(search != null && search != ''){
            searchBM += ' AND (Name LIKE ' + ' \'%' + search + '%\' OR AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\')';
            searchTA += ' AND (job__r.Name LIKE ' + ' \'%' + search + '%\' OR job__r.AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\')';
            searchSourcing += ' AND (Name LIKE ' + ' \'%' + search + '%\' OR AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\')';
            searchNeedPriority += ' AND (Name LIKE ' + ' \'%' + search + '%\' OR AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\')';
        }

        if(filterAccount != null && filterAccount != ''){
            searchBM += ' AND AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';
            searchTA += ' AND job__r.AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';
            searchSourcing += ' AND AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';
            searchNeedPriority += ' AND AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';
        }
    
        if(filterBM != null && filterBM != ''){
            // searchBM += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')';
            // searchTA += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')';
            searchSourcing += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')';
            searchNeedPriority += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')';
        }

        if(filterTA != null && filterTA != ''){
            // searchBM += ' AND cxsrec__Recruiter__r.Id IN (\'' + filterTA + '\')';
            // searchTA += ' AND cxsrec__Recruiter__r.Id IN (\'' + filterTA + '\')';
            searchSourcing += ' AND cxsrec__Recruiter__r.Id IN (\'' + filterTA + '\')';
            searchNeedPriority += ' AND cxsrec__Recruiter__r.Id IN (\'' + filterTA + '\')';
        }

        if(filterSourcing != null && filterSourcing != ''){
            searchBM += ' AND Priorit_sourcing__c IN (\'' + filterSourcing + '\')';
            searchTA += ' AND job__r.Priorit_sourcing__c IN (\'' + filterSourcing + '\')';
            searchSourcing += ' AND Priorit_sourcing__c IN (\'' + filterSourcing + '\')';
            searchNeedPriority += ' AND Priorit_sourcing__c IN (\'' + filterSourcing + '\')';
        }

        if(filterPriority != null && filterPriority != ''){
            searchBM += ' AND Priorit__c IN (\'' + filterPriority + '\')';
            searchTA += ' AND job__r.Priorit__c IN (\'' + filterPriority + '\')';
            searchSourcing += ' AND Priorit__c IN (\'' + filterPriority + '\')';
            searchNeedPriority += ' AND Priorit__c IN (\'' + filterPriority + '\')';
        }

        searchBM += ' GROUP BY TP_Manager__r.Id,TP_Manager__r.Name,TP_P_rim_tre__c';
        searchTA += ' GROUP BY User__r.Id, User__r.Name';
        searchSourcing += ' GROUP BY Priorit_sourcing__c';
        searchNeedPriority += ' GROUP BY Priorit__c';
        searchAccount += ' GROUP BY AB_Need_details__r.AB_Account__r.Name,AB_Need_details__r.AB_Account__r.Id';


        AggregateResult[] resultsTP = Database.query(searchBM);
        AggregateResult[] resultsTA = Database.query(searchTA);
        AggregateResult[] resultsSourcingPriority = Database.query(searchSourcing);
        AggregateResult[] resultsNeedPriority = Database.query(searchNeedPriority);
        AggregateResult[] resultsAccount = Database.query(searchAccount);

        filters filters = new filters();
        
        filters.filter = new List<filter>();

            filter f = new filter();
            f.Name = 'BM';
            f.Code = 'BM';
            f.items = new List<items>();
            for(AggregateResult result : resultsTP){
                if((String) result.get('name')  == null){continue;}
                items item = new items();
                item.Name = (String) result.get('name') + ' (' + (Integer) result.get('expr0') + ')';
                item.Value = (String) result.get('Id');
                f.items.add(item);
            }
            filters.filter.add(f);

            filter f2 = new filter();
            f2.Name = 'TA';
            f2.Code = 'TA';
            f2.items = new List<items>();
            for(AggregateResult result : resultsTA){
                if((String) result.get('name')  == null){ continue;}
                items item = new items();
                item.Name = (String) result.get('name') + ' (' + (Integer) result.get('expr0') + ')';
                item.Value = (String) result.get('Id');
                f2.items.add(item);
            }
            filters.filter.add(f2);


            filter f3 = new filter();
            f3.Name = 'Sourcing priority';
            f3.Code = 'sourcingPriority';
            f3.items = new List<items>();
            for(AggregateResult result : resultsSourcingPriority){
                if((String) result.get('Priorit_sourcing__c')  == null){ continue; }
                items item = new items();
                item.Name = (String) result.get('Priorit_sourcing__c') + ' (' + (Integer) result.get('expr0') + ')';
                item.Value = (String) result.get('Priorit_sourcing__c');
                f3.items.add(item);
            }
            filters.filter.add(f3);

            filter f4 = new filter();
            f4.Name = 'Need priority';
            f4.Code = 'needPriority';
            f4.items = new List<items>();
            for(AggregateResult result : resultsNeedPriority){
                if((String) result.get('Priorit__c')  == null){ continue;}
                items item = new items();
                item.Name = (String) result.get('Priorit__c') + ' (' + (Integer) result.get('expr0') + ')';
                item.Value = (String) result.get('Priorit__c');
                f4.items.add(item);
            }
            filters.filter.add(f4);

            filter f5 = new filter();
            f5.Name = 'Account';
            f5.Code = 'account';
            f5.items = new List<items>();
            for(AggregateResult result : resultsAccount){
                if((String) result.get('Name')  == null){ continue;}
                items item = new items();
                item.Name = (String) result.get('Name') + ' (' + (Integer) result.get('expr0') + ')';
                item.Value = (String) result.get('Id');
                f5.items.add(item);
            }

            filters.filter.add(f5);

        System.debug('filters: ' + JSON.serialize(filters));
        return JSON.serialize(filters);
      

    }


    @AuraEnabled(cacheable=true)
    public static Integer countVacancyForUser(string search, string filterBM, string filterTA, string filterSourcing, string filterPriority,String filterAccount){
        Integer counter = 0;
        User currentUser = [SELECT Id, TP_Perimetre__c FROM User WHERE Id = :UserInfo.getUserId()];
        Id recordType = [Select Id from RecordType where name = 'Offre'].Id;
        if(search != null && search != ''){
            search = 'SELECT Id FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true  AND (Name LIKE ' + ' \'%' + search + '%\' OR AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\') AND RecordType.Id != \'' + recordType + '\'';
        }else{
            search = 'SELECT Id FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true  AND RecordType.Id != \'' + recordType + '\'';
        }

        if(filterBM != null && filterBM != ''){ search += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')'; }

        if(filterSourcing != null && filterSourcing != ''){ search += ' AND Priorit_sourcing__c IN (\'' + filterSourcing + '\')';}

        if(filterPriority != null && filterPriority != ''){ search += ' AND Priorit__c IN (\'' + filterPriority + '\')';}

        if(filterAccount != null && filterAccount != ''){ search += ' AND AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';}

        list<cxsrec__cxsPosition__c> result = Database.query(search);
        counter = result.size();
        Set<Id> vacancyIds = new Set<Id>();
        if(filterTA != null && filterTA != ''){
            for(cxsrec__cxsPosition__c vac : result){ vacancyIds.add(vac.Id);}
            search = 'SELECT Id FROM cxsPosition_With_TA__c WHERE Job__c IN :vacancyIds and User__c IN (\'' + filterTA + '\')';
            list<cxsPosition_With_TA__c> resultSearch = Database.query(search);
            counter = resultSearch.size();
        }

        return counter;
      
    }

    
    @AuraEnabled
    public static String updateNeed(String data){
        // {"status":200,"message":""};
        cxsrec__cxsPosition__c vac = (cxsrec__cxsPosition__c) JSON.deserialize(data, cxsrec__cxsPosition__c.class);
        try{
            update vac;
            return '{"status":200,"message":""}';
        }catch(Exception e){
            return '{"status":500,"message":"' + e.getMessage() + '"}';
        }
    }

    @AuraEnabled(cacheable=false)
    public static  List<vacancy> getVacancyForUser(integer offset, String search, string filterBM, string filterTA, string filterSourcing, string filterPriority,String filterAccount, String sortOrder, String sortField ){
        Id recordType = [Select Id from RecordType where name = 'Offre'].Id;
        list<Vacancy_Dashboard_Colors__mdt> colors = [select API_Name__c,Hex_Color__c from Vacancy_Dashboard_Colors__mdt];

        //Make a map
        Map<String,String> colorMap = new Map<String,String>();
        for(Vacancy_Dashboard_Colors__mdt color : colors){
            colorMap.put(color.API_Name__c,color.Hex_Color__c);
        }

        offset = offset * 20 -20;
        if(offset < 0){ offset = 0; }
        User currentUser = [SELECT Id, TP_Perimetre__c FROM User WHERE Id = :UserInfo.getUserId()];
        List<cxsrec__cxsPosition__c> result;
        set <Id> vacancyIds = new set<Id>();
        String vacancyIdsString = '';
        if(filterTA != null && filterTA != ''){
            String searchTA = 'SELECT job__r.Id FROM cxsPosition_With_TA__c WHERE User__r.Id IN (\'' + filterTA + '\')';
            list<cxsPosition_With_TA__c> resultSearch = Database.query(searchTA);
            for(cxsPosition_With_TA__c vac : resultSearch){
                vacancyIds.add(vac.Job__r.Id);
            }    
            //vacancyIds to string seperated by comma
            
            for(Id vacId : vacancyIds){
                vacancyIdsString += '\''+  vacId + '\',';
            }
            vacancyIdsString = vacancyIdsString.removeEnd(',');
        }
        
        System.debug(vacancyIdsString);

        if(search != null && search != ''){
            search = 'SELECT Id, Name,AB_Need_details__r.AB_Account__r.Id,AB_Need_details__r.AB_Account__r.Name, cxsrec__Status__c,HL_date_de_qualification__c,TP_Date_de_d_marrage_attendue__c,Account__r.Name,cxsrec__Location__c, TP_TJM__c,Infos_Solution__c,TP_P_rim_tre__c,Priorit__c,TP_Manager__r.Name,cxsrec__Recruiter__r.Name,Priorit_sourcing__c,Date_de_d_marrage_souhait_e__c,createdDate,Avancement__c,TP_Experience__c FROM cxsrec__cxsPosition__c WHERE cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true AND (Name LIKE ' + ' \'%' + search + '%\' OR AB_Need_details__r.AB_Account__r.Name LIKE ' + ' \'%' + search + '%\')  AND RecordType.Id != \'' + recordType + '\'';
            System.debug('search: ' + search);
        }else{
            search = 'SELECT Id, Name,AB_Need_details__r.AB_Account__r.Id,AB_Need_details__r.AB_Account__r.Name, cxsrec__Status__c,HL_date_de_qualification__c,TP_Date_de_d_marrage_attendue__c,Account__r.Name,cxsrec__Location__c, TP_TJM__c,Infos_Solution__c,TP_P_rim_tre__c,Priorit__c,TP_Manager__r.Name,cxsrec__Recruiter__r.Name,Priorit_sourcing__c,Date_de_d_marrage_souhait_e__c,createdDate,Avancement__c,TP_Experience__c FROM cxsrec__cxsPosition__c WHERE  cxsrec__Status__c = \'Open\' AND AB_Display_in_need_dashboard__c = true AND RecordType.Id != \'' + recordType + '\'';
            System.debug('search: ' + search);
        }

        if(filterBM != null && filterBM != ''){search += ' AND TP_Manager__r.Id IN (\'' + filterBM + '\')';}

        if(filterTA != null && filterTA != ''){search += ' AND Id IN (' + vacancyIdsString + ')';}

        if(filterSourcing != null && filterSourcing != ''){search += ' AND Priorit_sourcing__c IN (\'' + filterSourcing + '\')';}

        if(filterPriority != null && filterPriority != ''){search += ' AND Priorit__c IN (\'' + filterPriority + '\')';}

        if(filterAccount != null && filterAccount != ''){search += ' AND AB_Need_details__r.AB_Account__r.Id IN (\'' + filterAccount + '\')';}
        //Switch
        String FieldSort = 'TP_Manager__r.Name';
        switch on sortField {
            when 'createdDate'{ FieldSort ='CreatedDate';}
            when 'accountName'{ FieldSort = 'AB_Need_details__r.AB_Account__r.Name';}
            when 'BM' { FieldSort = 'TP_Manager__r.Name';}
            when 'TA' { FieldSort = 'cxsrec__Recruiter__r.Name';}
            when 'priorite' { FieldSort = 'Priorit__c';}
            when 'sourcingPriority' { FieldSort = 'Priorit_sourcing__c';}
        }

        search += ' ORDER BY ' + FieldSort + ' ' + sortOrder + ' NULLS LAST LIMIT 20 OFFSET ' + offset;  
        System.debug(search);
        result = Database.query(search);

        List<vacancy> vacancies = new List<vacancy>();
        for(cxsrec__cxsPosition__c vac : result){
            vacancy v = new vacancy();
            v.Id = vac.Id;
            v.name = vac.Name;
            v.status = vac.cxsrec__Status__c;
            v.account = (vac.AB_Need_details__r.AB_Account__r == null) ? '-' : vac.AB_Need_details__r.AB_Account__r.Name;
            v.accountId = (vac.AB_Need_details__r.AB_Account__r == null) ? '-' : vac.AB_Need_details__r.AB_Account__r.Id;
            v.location = (vac.cxsrec__Location__c == null) ? '-' : vac.cxsrec__Location__c;
            v.TJM = vac.TP_TJM__c;

            if(vac.Infos_Solution__c != null){
                if(vac.Infos_Solution__c.length() > 100){ v.infosSolution = vac.Infos_Solution__c.substring(0,100) + '...'; }else{ v.infosSolution = vac.Infos_Solution__c; }
                v.infosSolutionVisible = true;
            }else{
                v.infosSolutionVisible = false;
            }
            v.infoSolutions = vac.Infos_Solution__c;

            v.perimetre = vac.TP_P_rim_tre__c;
            v.priorite = vac.Priorit__c;

            colorMap.get(vac.Priorit__c);
            v.prioriteColor = 'background-color:' + colorMap.get(vac.Priorit__c);
            v.prioriteOnlyColor = 'color:' + colorMap.get(vac.Priorit__c) + ';font-weight:bold';
 
            v.prioriteColor += ';width: 22px;height: 22px;float: left;margin-right: 0.5%; margin-top: 0.0%;border-radius: 50px;border: 1px solid rgb(116, 116, 116);';

            Date dateDeQualification = vac.HL_date_de_qualification__c;
            if(vac.HL_date_de_qualification__c == null){
                v.dateDeQualification = '-';
            }else{
                String dateQual =  String.valueOf(vac.HL_date_de_qualification__c);
                //format date
                dateQual = dateQual.substring(8,10) + '/' + dateQual.substring(5,7) + '/' + dateQual.substring(0,4);
                v.dateDeQualification = dateQual;
            } 
            v.BM = (vac.TP_Manager__r == null) ? '-' : vac.TP_Manager__r.Name;

            v.prioriteSourcing =  (vac.Priorit_sourcing__c == null) ? '-' : vac.Priorit_sourcing__c;
            v.priorite = (vac.Priorit__c == null) ? '-' : vac.Priorit__c;
            
            v.perimetreColor = 'background-color:' + colorMap.get(vac.Priorit_sourcing__c);
            v.perimetreOnlyColor = 'color:' + colorMap.get(vac.Priorit_sourcing__c) + ';font-weight:bold';
            v.perimetreColor+= ';width: 22px;height: 22px;float: left;margin-right: 0.5%; margin-top: 0.0%;border-radius: 50px;border: 1px solid rgb(116, 116, 116);';

             DateTime dateDeDemarrage = vac.TP_Date_de_d_marrage_attendue__c ;
            v.dateDeDemarrage = (vac.TP_Date_de_d_marrage_attendue__c  == null) ? '-' : dateDeDemarrage.format('dd/MM/yyyy');
            v.createdDate = vac.createdDate.format('dd/MM/yyyy HH:mm');

            if(vac.Avancement__c != null){
                v.avancement = vac.Avancement__c;
                if(vac.Avancement__c.length() > 100){v.avancement = vac.Avancement__c.substring(0,100) + '...'; }
                v.avancementVisible = true;
            }else{
                v.avancementVisible = false;
            }
            v.avancements = vac.Avancement__c;

            if(vac.TP_Experience__c != null){
                v.experience = new List<experiences>();
                for(String exp : vac.TP_Experience__c.split(';')){
                    experiences e = new experiences();
                    e.name = exp;
                    v.experience.add(e);
                }
            }else{
                v.experience = new List<experiences>();
            }
            v.matches = getMatchesByVacanyID(vac.Id,5);
            v.usersTA = getUsersTA(vac.Id,3);
            v.usersVisibleTA = v.usersTA.size() > 0;
            v.matchesVisible = v.matches.size() > 0;
            vacancies.add(v);
        }

        return vacancies;
    }


    @AuraEnabled(cacheable=false)
    public static List<cxsPosition_With_TA__c> getUsersTA(Id vacancyId,integer limitItems){
        List<cxsPosition_With_TA__c> result = [SELECT Id, Name, User__r.Name FROM cxsPosition_With_TA__c WHERE Job__c = :vacancyId limit :limitItems];
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<cxsrec__cxsJob_application__c> getMatchesByVacanyID(Id vacancyId, Integer limitItems){
        list<cxsrec__cxsWorkflow_status__c> statuses = [SELECT Id FROM cxsrec__cxsWorkflow_status__c WHERE Name  like '%KO%'];
        set<Id> statusIds = new set<Id>();
        for(cxsrec__cxsWorkflow_status__c s : statuses){
            statusIds.add(s.Id);
        }
        List<cxsrec__cxsJob_application__c> result = [SELECT Id, 
                                                        Name, 
                                                        TP_Statut_Parcours_Besoin__c,
                                                        cxsrec__Status__c,cxsrec__Candidate__r.Statut_de_recrutement__c,
                                                        cxsrec__Candidate__r.id,
                                                        cxsrec__Candidate__r.cxsrec__Last_name__c,
                                                        cxsrec__Candidate__r.cxsrec__First_name__c,
                                                        cxsrec__Candidate__r.Name,
                                                        cxsrec__Candidate__r.cxsrec__Current_position__c,
                                                        cxsrec__Candidate__r.RecordType.name
        from cxsrec__cxsJob_application__c WHERE cxsrec__Position__c = :vacancyId and cxsrec__Workflow_status__c not IN :statusIds ORDER BY cxsrec__Status__c Desc limit :limitItems];
        //get vacancyIds
        return result;
    }

    public class experiences{
        @AuraEnabled
        public String name;
    }

    public class filters{
        @AuraEnabled
        public filter[] filter;
       
    }

    public class filter{
        @AuraEnabled
        public String Name;
        @AuraEnabled
        public String Code;
        @AuraEnabled
        public items[] items;
    }

    public class items{
        @AuraEnabled
        public String Name;
        @AuraEnabled
        public String Value;
    }

    public class vacancy{
        @AuraEnabled
        public Id Id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String account;
        @AuraEnabled
        public String accountId;
        @AuraEnabled
        public String location;
        @AuraEnabled
        public Decimal TJM;
        @AuraEnabled
        public String infosSolution;
        @AuraEnabled
        public String perimetre;
        @AuraEnabled
        public String priorite;
        @AuraEnabled
        public String prioriteSourcing;
        @AuraEnabled
        public String dateDeDemarrage;
        @AuraEnabled
        public String BM;
        @AuraEnabled
        public List<cxsPosition_With_TA__c> usersTA;
        @AuraEnabled
        public Boolean usersVisibleTA;
        @AuraEnabled
        public String dateDeQualification;
        @AuraEnabled
        public String createdDate;
        @AuraEnabled
        public String avancement;
        @AuraEnabled
        public List<experiences> experience;
        @AuraEnabled
        public List<cxsrec__cxsJob_application__c> matches;
        @AuraEnabled
        public Boolean matchesVisible;
        @AuraEnabled
        public Boolean infosSolutionVisible;
        @AuraEnabled
        public Boolean avancementVisible;
        @AuraEnabled
        public String infoSolutions;
        @AuraEnabled
        public String avancements;
        @AuraEnabled
        public String prioriteColor;
        @AuraEnabled
        public String prioriteOnlyColor;
        @AuraEnabled
        public String perimetreColor;
        @auraEnabled
        public String perimetreOnlyColor;

    }
}