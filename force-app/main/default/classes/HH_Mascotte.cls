public with sharing class HH_Mascotte {
    public HH_Mascotte() {

    }

   @AuraEnabled(cacheable=true)
   public static List<HH_cadeaux__c> listerCadeaux() {
       return [
           SELECT Id, Name, Offert__c
           FROM HH_cadeaux__c
           ORDER BY CreatedDate DESC
       ];
   }

   @AuraEnabled
   public static String offrirCadeau(Id cadeauId) {
       if (cadeauId == null) {
           throw new AuraHandledException('L\'identifiant du cadeau est obligatoire.');
       }
       try {
           HH_cadeaux__c cadeau = new HH_cadeaux__c(Id = cadeauId, Offert__c = true);
           update cadeau;
           return cadeau.Id;
       } catch (DmlException e) {
           throw new AuraHandledException(e.getDmlMessage(0));
       }
   }

}