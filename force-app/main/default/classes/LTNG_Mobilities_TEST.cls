@isTest
private class LTNG_Mobilities_TEST {
    private static cxsrec__cxsCandidate__c candidate;

    @isTest    
    private static void testMobilities_Code() {
		
		initMobilites();
		initCandidate(';IDF-;BE-;');
		
		Test.startTest();
		
            LTNG_Mobilities.MobilitiesConfig config = LTNG_Mobilities.getMobilitiesConfig(candidate.Id, 'Code__c');
			
			System.assertEquals(2, config.selectedMobilities.size());
			
			config.selectedMobilities.add('FR-');
			LTNG_Mobilities.saveMobilities(candidate.Id, config.selectedMobilities, 'Code__c');
			
			candidate = [SELECT Id, Mobilites__c FROM cxsrec__cxsCandidate__c WHERE Id = :candidate.Id][0];
			
			System.assert(candidate.Mobilites__c.contains(';IDF-;'));
			System.assert(candidate.Mobilites__c.contains(';FR-;'));
			System.assert(candidate.Mobilites__c.contains(';BE-;'));
			
			
		Test.stopTest();
    }
    
    @isTest   
    private static void testMobilities_Name() {
		
		initMobilites();
		initCandidate(';Ile de france;Belgique;');
		
		Test.startTest();
		
            LTNG_Mobilities.MobilitiesConfig config = LTNG_Mobilities.getMobilitiesConfig(candidate.Id, 'Name');
			
			System.assertEquals(2, config.selectedMobilities.size());
			
			config.selectedMobilities.add('FR-');
			LTNG_Mobilities.saveMobilities(candidate.Id, config.selectedMobilities, 'Name');
			
			candidate = [SELECT Id, Mobilites__c FROM cxsrec__cxsCandidate__c WHERE Id = :candidate.Id][0];
			
			System.assert(candidate.Mobilites__c.contains(';Ile de france;'));
			System.assert(candidate.Mobilites__c.contains(';France;'));
			System.assert(candidate.Mobilites__c.contains(';Belgique;'));
			
			
		Test.stopTest();
    }

    private static void initCandidate(String mobilities){
        candidate = new cxsrec__cxsCandidate__c(
            RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c.getRecordTypeInfosByDeveloperName().get('External_candidate').getRecordTypeId(),
            Mobilites__c = mobilities,
            cxsrec__First_name__c = 'TEST FIRST NAME',
            cxsrec__Last_name__c = 'TEST LAST NAME'
        );
        insert candidate;
    }
    
    private static void initMobilites(){
		insert new Mobilite__c(Name = 'International', Code__c = 'INT-');
		insert new List<Mobilite__c>{
			new Mobilite__c(Name = 'France', Code__c = 'FR-', Parent__r = new Mobilite__c(Code__c = 'INT-')),
			new Mobilite__c(Name = 'Belgique', Code__c = 'BE-', Parent__r = new Mobilite__c(Code__c = 'INT-'))
		};
		insert new Mobilite__c(Name = 'Ile de france', Code__c = 'IDF-', Parent__r = new Mobilite__c(Code__c = 'FR-'));	
	}
}