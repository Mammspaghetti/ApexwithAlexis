//with sharing permet de récupérer la données que peux voir l'utilisateur vs without sharing view all*
// Pas de ""
//Proche du Java avec le typeage d'où le List 
//Règle de 75% du code
public with sharing class GP_Mascotte {
    @AuraEnabled(cacheable=true)

    public static List<GPGift__c> listerCadeaux() {
        return [
            SELECT Id, Name, offert__c, CreatedDate
            FROM GPGift__c
            ORDER BY CreatedDate DESC
        ];
    }

    // Pas de cacheable=true ici : la méthode modifie des données (DML)
    @AuraEnabled
    public static void supprimerCadeau(Id cadeauId) {
        delete [SELECT Id FROM GPGift__c WHERE Id = :cadeauId];
    }

    // Coche / décoche "Donné" : met à jour offert__c sur le cadeau
    @AuraEnabled
    public static void donnerCadeau(Id cadeauId, Boolean offert) {
        update new GPGift__c(Id = cadeauId, offert__c = offert);
    }

}