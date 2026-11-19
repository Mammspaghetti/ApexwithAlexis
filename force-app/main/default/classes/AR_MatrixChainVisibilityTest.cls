/**
 * AR_MatrixChainVisibility (session 27 §2) : déjà 100 % de couverture de ligne via
 * AR_MatrixChainServiceTest, mais jamais testée pour elle-même — ce fichier verrouille directement
 * le contrat des deux agrégats (MAX/COUNT hors partage) plutôt que de dépendre d'un appelant.
 * Le volet « hors partage » n'est pas testé négativement ici, pour la même raison déjà documentée
 * dans AR_ComparablesServiceTest : un seul profil partagé (Recruiter) existe dans cette sandbox,
 * aucun utilisateur restreint connu pour construire un test négatif sans faux positif.
 */
@IsTest
private class AR_MatrixChainVisibilityTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Chain Visibility',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Chain Visibility', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_Price_Matrix__c root = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Negotiation_Version__c = 1
        );
        insert root;

        List<AR_Price_Matrix__c> children = new List<AR_Price_Matrix__c>();
        for (Integer version = 2; version <= 4; version++) {
            children.add(new AR_Price_Matrix__c(
                AR_Position__c = position.Id,
                AR_Contract_Type__c = 'CDI',
                AR_Status__c = 'Brouillon',
                AR_Root_Matrix__c = root.Id,
                AR_Negotiation_Version__c = version
            ));
        }
        insert children;

        // Matrice sans rapport, sur un autre besoin : ne doit compter dans AUCUNE des deux agrégations.
        cxsrec__cxsPosition__c otherPosition = new cxsrec__cxsPosition__c(
            Name = 'Besoin Sans Rapport', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert otherPosition;
        insert new AR_Price_Matrix__c(
            AR_Position__c = otherPosition.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Negotiation_Version__c = 99
        );
    }

    private static Id rootId() {
        return [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Root_Matrix__c = null AND AR_Negotiation_Version__c = 1 LIMIT 1].Id;
    }

    @IsTest
    static void testMaxNegotiationVersion_returnsHighestAcrossChain() {
        Integer maxVersion = AR_MatrixChainVisibility.maxNegotiationVersion(rootId());
        System.assertEquals(4, maxVersion, 'le maximum doit porter sur la racine ET ses 3 enfants (1 à 4), jamais sur la matrice sans rapport (99)');
    }

    @IsTest
    static void testCountChainMembers_countsRootAndChildrenOnly() {
        Integer count = AR_MatrixChainVisibility.countChainMembers(rootId());
        System.assertEquals(4, count, 'la racine + ses 3 enfants, jamais la matrice sur un autre besoin');
    }

    @IsTest
    static void testMaxNegotiationVersion_singleMatrixNoChildren_returnsItsOwnVersion() {
        // Racine isolée (aucun enfant) : le MAX ne doit pas planter sur un seul enregistrement, ni
        // retomber sur le défaut 1 s'il porte une version différente de 1.
        AR_Price_Matrix__c isolated = new AR_Price_Matrix__c(
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Chain Visibility' LIMIT 1].Id,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Negotiation_Version__c = 7
        );
        insert isolated;

        System.assertEquals(7, AR_MatrixChainVisibility.maxNegotiationVersion(isolated.Id));
        System.assertEquals(1, AR_MatrixChainVisibility.countChainMembers(isolated.Id));
    }

    @IsTest
    static void testMaxNegotiationVersion_noRowFound_defaultsToOne() {
        // Id syntaxiquement valide mais d'un enregistrement inexistant (jamais inséré) : AggregateResult
        // renvoie une ligne avec MAX=null, pas zéro ligne — le repli sur 1 doit s'appliquer, pas planter.
        Id fakeId = AR_Price_Matrix__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
        System.assertEquals(1, AR_MatrixChainVisibility.maxNegotiationVersion(fakeId));
        System.assertEquals(0, AR_MatrixChainVisibility.countChainMembers(fakeId));
    }
}