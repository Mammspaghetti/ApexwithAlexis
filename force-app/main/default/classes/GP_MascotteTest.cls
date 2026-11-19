// Classe de test pour GP_Mascotte
// @isTest : ce code ne compte pas dans la limite de code de l'org et ne s'exécute qu'en test.
// Les données créées ici sont annulées à la fin de chaque test (rien n'est gardé en base).
@isTest
private class GP_MascotteTest {

    // Exécuté avant CHAQUE méthode de test : on prépare 2 cadeaux
    @testSetup
    static void preparerDonnees() {
        GPGift__c ancien = new GPGift__c(Name = 'Peluche', offert__c = false);
        GPGift__c recent = new GPGift__c(Name = 'Croquettes', offert__c = true);
        insert new List<GPGift__c>{ ancien, recent };

        // Dans un test, tous les enregistrements ont la même CreatedDate :
        // on la force pour pouvoir vérifier le tri (du plus récent au plus ancien)
        Test.setCreatedDate(ancien.Id, Datetime.now().addDays(-2));
        Test.setCreatedDate(recent.Id, Datetime.now().addDays(-1));
    }

    // Petite méthode utilitaire : récupère un cadeau par son nom
    private static GPGift__c getCadeau(String nom) {
        return [SELECT Id, Name, offert__c FROM GPGift__c WHERE Name = :nom LIMIT 1];
    }

    @isTest
    static void listerCadeaux_renvoieTousLesCadeauxTriesDuPlusRecent() {
        Test.startTest();
        List<GPGift__c> cadeaux = GP_Mascotte.listerCadeaux();
        Test.stopTest();

        Assert.areEqual(2, cadeaux.size(), 'Les 2 cadeaux doivent être renvoyés');
        Assert.areEqual('Croquettes', cadeaux[0].Name, 'Le plus récent doit être en premier');
        Assert.areEqual('Peluche', cadeaux[1].Name, 'Le plus ancien doit être en dernier');
        // Les champs utilisés par le LWC doivent être présents
        Assert.isTrue(cadeaux[0].offert__c, 'Croquettes est offert');
        Assert.isNotNull(cadeaux[0].CreatedDate, 'CreatedDate doit être sélectionné');
    }

    @isTest
    static void listerCadeaux_listeVideSiAucunCadeau() {
        delete [SELECT Id FROM GPGift__c];

        Test.startTest();
        List<GPGift__c> cadeaux = GP_Mascotte.listerCadeaux();
        Test.stopTest();

        Assert.isTrue(cadeaux.isEmpty(), 'Aucun cadeau : la liste doit être vide');
    }

    @isTest
    static void supprimerCadeau_supprimeLeBonCadeau() {
        GPGift__c peluche = getCadeau('Peluche');

        Test.startTest();
        GP_Mascotte.supprimerCadeau(peluche.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM GPGift__c WHERE Id = :peluche.Id], 'La peluche doit être supprimée');
        Assert.areEqual(1, [SELECT COUNT() FROM GPGift__c], 'L\'autre cadeau doit rester');
    }

    @isTest
    static void donnerCadeau_passeOffertATrue() {
        GPGift__c peluche = getCadeau('Peluche');

        Test.startTest();
        GP_Mascotte.donnerCadeau(peluche.Id, true);
        Test.stopTest();

        Assert.isTrue(getCadeau('Peluche').offert__c, 'Bouton Donner : offert__c doit passer à true');
    }

    @isTest
    static void donnerCadeau_reprendreRepasseOffertAFalse() {
        GPGift__c croquettes = getCadeau('Croquettes');

        Test.startTest();
        GP_Mascotte.donnerCadeau(croquettes.Id, false);
        Test.stopTest();

        Assert.isFalse(getCadeau('Croquettes').offert__c, 'Bouton Reprendre : offert__c doit repasser à false');
    }
}
