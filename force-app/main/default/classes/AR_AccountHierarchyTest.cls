/**
 * Tests AR_AccountHierarchy : remontée de hiérarchie de compte, réutilisée par corridors et RFA.
 * Session 146b.
 */
@IsTest
private class AR_AccountHierarchyTest {

    private static Account newTestAccount(String name, Id parentId) {
        return new Account(
            Name = name,
            ParentId = parentId,
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
    }

    private static Account newTestAccount(String name) {
        return newTestAccount(name, null);
    }

    @IsTest
    static void testChainFrom_Null() {
        List<Id> chain = AR_AccountHierarchy.chainFrom(null);
        System.assertEquals(null, chain, 'Doit retourner null si accountId est null');
    }

    @IsTest
    static void testChainFrom_SingleAccount() {
        Account acc = newTestAccount('Standalone');
        insert acc;

        List<Id> chain = AR_AccountHierarchy.chainFrom(acc.Id);

        System.assertEquals(1, chain.size(), 'Doit contenir le compte lui-même');
        System.assertEquals(acc.Id, chain.get(0), 'Premier élément doit être le compte');
    }

    @IsTest
    static void testChainFrom_TwoLevels() {
        Account parent = newTestAccount('Parent');
        insert parent;
        Account child = newTestAccount('Child', parent.Id);
        insert child;

        List<Id> chain = AR_AccountHierarchy.chainFrom(child.Id);

        System.assertEquals(2, chain.size(), 'Doit contenir 2 niveaux');
        System.assertEquals(child.Id, chain.get(0), 'Premier élément doit être l\'enfant');
        System.assertEquals(parent.Id, chain.get(1), 'Deuxième élément doit être le parent');
    }

    @IsTest
    static void testChainFrom_ThreeLevels() {
        Account grandParent = newTestAccount('Grand Parent');
        insert grandParent;
        Account parent = newTestAccount('Parent', grandParent.Id);
        insert parent;
        Account child = newTestAccount('Child', parent.Id);
        insert child;

        List<Id> chain = AR_AccountHierarchy.chainFrom(child.Id);

        System.assertEquals(3, chain.size(), 'Doit contenir 3 niveaux');
        System.assertEquals(child.Id, chain.get(0), 'Chaîne : enfant → parent → grand-parent');
        System.assertEquals(parent.Id, chain.get(1));
        System.assertEquals(grandParent.Id, chain.get(2));
    }

    @IsTest
    static void testChainFrom_TooDeep_ThrowsException() {
        System.runAs(AR_TestPersona.francais()) {
            // Créer une chaîne profonde (21 niveaux, max est 20)
            String uniquePrefix = 'HierarchyTest' + Datetime.now().getTime();
            // Les noms voisins (…_Level1, …_Level10) déclenchent DUPLICATES_DETECTED (règle de doublons floue
            // de l'org, piège déjà rencontré en session 54) : on autorise l'enregistrement malgré la règle,
            // sans toucher à celle-ci.
            Database.DMLOptions allowDuplicates = new Database.DMLOptions();
            allowDuplicates.duplicateRuleHeader.allowSave = true;
            Account current = newTestAccount(uniquePrefix + '_Level0');
            Database.insert(current, allowDuplicates);

            for (Integer i = 1; i <= 21; i++) {
                Account next = newTestAccount(uniquePrefix + '_Level' + i, current.Id);
                Database.insert(next, allowDuplicates);
                current = next;
            }

            Test.startTest();
            try {
                AR_AccountHierarchy.chainFrom(current.Id);
                System.assert(false, 'Doit lever une exception pour hiérarchie trop profonde');
            } catch (AuraHandledException e) {
                String msg = e.getMessage();
                System.assert(msg.contains('anormalement profonde'), 'Message doit mentionner la profondeur');
                System.assert(msg.contains('20'), 'Message doit mentionner le seuil 20');
            }
            Test.stopTest();
        }
    }

    // Session 184f : compte d'un besoin — jonction AB_Need_details__c d'abord, repli sur le champ historique.
    @IsTest
    static void testAccountOfPosition_junctionFirst_legacyFallback_null() {
        Account viaJunction = newTestAccount('S184f Via jonction');
        Account legacy = newTestAccount('S184f Historique');
        insert new List<Account>{ viaJunction, legacy };
        Contact contact = new Contact(LastName = 'S184f', AccountId = viaJunction.Id);
        insert contact;
        AB_Need_details__c need = new AB_Need_details__c(AB_Account__c = viaJunction.Id, AB_Contact__c = contact.Id);
        insert need;

        cxsrec__cxsPosition__c both = new cxsrec__cxsPosition__c(
            Name = 'S184f les deux', AB_Need_details__c = need.Id, cxsrec__Account__c = legacy.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c legacyOnly = new cxsrec__cxsPosition__c(
            Name = 'S184f historique seul', cxsrec__Account__c = legacy.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c neither = new cxsrec__cxsPosition__c(
            Name = 'S184f aucun', cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert new List<cxsrec__cxsPosition__c>{ both, legacyOnly, neither };

        System.assertEquals(viaJunction.Id, AR_AccountHierarchy.accountOfPosition(both.Id), 'La jonction prime');
        System.assertEquals(legacy.Id, AR_AccountHierarchy.accountOfPosition(legacyOnly.Id));
        System.assertEquals(null, AR_AccountHierarchy.accountOfPosition(neither.Id));
        System.assertEquals(null, AR_AccountHierarchy.accountOfPosition(null));
    }
}