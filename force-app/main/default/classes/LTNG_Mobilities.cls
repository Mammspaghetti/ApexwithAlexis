public class LTNG_Mobilities {

	@AuraEnabled
	public static MobilitiesConfig getMobilitiesConfig(Id recordId, String fieldValueToBeStored) {
		return new MobilitiesConfig(recordId, fieldValueToBeStored);
	}
	
	@AuraEnabled
	public static void saveMobilities(Id recordId, List<String> mobilities, String fieldValueToBeStored){
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        SObject sObj = Schema.getGlobalDescribe().get(sObjName).newSObject();
        sObj.put('Id', recordId);
        sObj.put('Mobilites__c', getTagsString(getStoredFieldValues(mobilities, fieldValueToBeStored)));
        update sObj;
	}

	public static Map<String, String> getStoredFieldValueByCode(List<String> tagCodes, String fieldValueToBeStored) {
        List<SObject> mobilites = Database.query('SELECT Id, Code__c, ' + fieldValueToBeStored +
                                                ' FROM Mobilite__c WHERE Code__c IN ('+ getInClauseListString(tagCodes) +') ');
		Map<String, String> storedFieldByCode = new Map<String, String>();
		for(SObject m : mobilites) {
			storedFieldByCode.put((String)m.get('Code__c'), (String)m.get(fieldValueToBeStored));
		}
		return storedFieldByCode;
    }
    
    public static String getInClauseListString(List<String> fieldValues) {
        List<String> inClauseListString = new List<String>();
        for (String s : fieldValues) {
            inClauseListString.add('\'' + s + '\'');
        }
        return String.join(inClauseListString, ',');
    }

	public static Map<String, String> getCodeByStoredFieldValue(List<String> storedFieldValues, String fieldValueToBeStored) {
        List<SObject> mobilites = Database.query('SELECT Id, Code__c, ' + fieldValueToBeStored +
                                        ' FROM Mobilite__c WHERE ' + fieldValueToBeStored + ' IN ('+ getInClauseListString(storedFieldValues) +') ');
		Map<String, String> codeByStoredField = new Map<String, String>();
		for(SObject m : mobilites) {
			codeByStoredField.put((String)m.get(fieldValueToBeStored), (String)m.get('Code__c'));
		}
		return codeByStoredField;
    }

    public static List<String> getStoredFieldValues(List<String> tagCodes, String fieldValueToBeStored) {
        System.debug('tagCodes==' +tagCodes);
        if (fieldValueToBeStored.toUpperCase() == 'CODE__C') return tagCodes;
        List<String> storedFieldValues = new List<String>();
		if (tagCodes.isEmpty()) return storedFieldValues;
		Map<String, String> storedFieldValueByCode = getStoredFieldValueByCode(tagCodes, fieldValueToBeStored);
		for (String code : tagCodes) {
			storedFieldValues.add(storedFieldValueByCode.get(code));
		}
        System.debug('storedFieldValues==' +storedFieldValues);
        return storedFieldValues;
    }

	public static String getTagsString(List<String> storedFieldValues){
        String tagsString = (';' + String.join(storedFieldValues, ';') + ';').replaceAll(';+', ';');
        return (tagsString == ';' ? null : tagsString);
	}
	
	public class MobilitiesConfig{
		
		@AuraEnabled public List<HierarchyNode> availableMobilities;
		@AuraEnabled public List<String> selectedMobilities;
		
		public MobilitiesConfig(Id recordId, String fieldValueToBeStored){
			this.availableMobilities = getAvailableMobilities();
			String sObjName = recordId.getSObjectType().getDescribe().getName();
			SObject sobj = (Database.query('SELECT Id, Mobilites__c FROM '+ sObjName + ' WHERE Id = \'' + recordId + '\''))[0];
			System.debug('sobj' + sobj);
            String mobilities = (String)sobj.get('Mobilites__c');
            List<String> tagCodes = (String.isBlank(mobilities) ? '' : mobilities.removeStart(';').removeEnd(';')).split(';');
			this.selectedMobilities = fieldValueToBeStored.toUpperCase() == 'CODE__C' ? tagCodes : getSelectedMobilitiesCodes(tagCodes, fieldValueToBeStored);
		}	
	}
	
		
	public static List<String> getSelectedMobilitiesCodes(List<String> storedFieldValues, String fieldValueToBeStored) {
        List<String> tagCodes = new List<String>();
        System.debug('storedFieldValues'+ storedFieldValues);
		if (storedFieldValues == null || storedFieldValues.isEmpty()) return tagCodes;
		Map<String, String> codeByStoredField = getCodeByStoredFieldValue(storedFieldValues, fieldValueToBeStored);
		System.debug('codeByStoredField'+ codeByStoredField);
		for (String fieldValue : storedFieldValues) {
			tagCodes.add(codeByStoredField.get(fieldValue));
		}
		return tagCodes;
	}
	
	public static List<HierarchyNode> getAvailableMobilities() {
		
		List<HierarchyNode> mobilities = new List<HierarchyNode>();
		
		Map<Id, List<Mobilite__c>> mobilitiesByParentId = new Map<Id, List<Mobilite__c>>();
		List<Mobilite__c> tempParams;
		for(Mobilite__c mobilite : [SELECT Id, Name, Code__c, Parent__c FROM Mobilite__c ORDER BY Name]){
			tempParams = mobilitiesByParentId.get(mobilite.Parent__c);
			if(tempParams == null) {
				tempParams = new List<Mobilite__c>();
				mobilitiesByParentId.put(mobilite.Parent__c, tempParams);
			}
			tempParams.add(mobilite);
		}
		
		if(mobilitiesByParentId.containsKey(null)){
			for(Mobilite__c mobilite : mobilitiesByParentId.get(null)){
				mobilities.add(new HierarchyNode(mobilite, mobilitiesByParentId));
			}
		}
		
		return mobilities;
	}
	
	

	public class HierarchyNode{
		@AuraEnabled public String value;
		@AuraEnabled public String label;
		@AuraEnabled public Boolean checked;
		@AuraEnabled public Integer hasCheckedChildren;
		@AuraEnabled public List<HierarchyNode> children;
		
		public HierarchyNode(Mobilite__c mobilite, Map<Id, List<Mobilite__c>> allMobilitiesByParentId){
			this.value = mobilite.Code__c;
			this.label = mobilite.Name;
			this.checked = false;
			this.children = new List<HierarchyNode>();
			
			List<Mobilite__c> childrenParams = allMobilitiesByParentId.get(mobilite.Id);
			if(childrenParams != null){
				for(Mobilite__c m : childrenParams){
					this.children.add(new HierarchyNode(m, allMobilitiesByParentId));
				}
			}
		}
	}
}