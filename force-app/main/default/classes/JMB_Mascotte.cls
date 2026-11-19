//il faut déployer la classe avant de l'intégrer dans le reste (c'est mieux).
// 'with sharing' ==> run with user data access  // 'without sharing' ==> run as view all data
public with sharing class JMB_Mascotte {
 
    // permet de signifier que la prochaine methode peut être appeler depuis un LWC ==> lien direct avec la déclaration suivante
    @AuraEnabled(cacheable=true)

    //Methode // 'public static' obligatoire pour utilisation depuis un lwc
    public static List<JMB_KDO__c> listerCadeaux() {
        return [
            SELECT Id, Name, AB_Offert__c
            FROM JMB_KDO__c
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static void offrirCadeau(Id cadeauId){
        update new JMB_KDO__c(Id=cadeauId, AB_Offert__c = true);
    }

}