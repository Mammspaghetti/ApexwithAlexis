/**
 * Tests AR_AdminCommercialService : table de conversion des devises (historique append-only),
 * données commerciales par compte, préremplissage RFA — CRUD et refus d'accès non-admin.
 */
@IsTest
private class AR_AdminCommercialServiceTest {

    private static User newNonAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'AdminCommercialTest',
            FirstName = 'AR',
            Alias = 'aract',
            Email = 'ar.admin.commercial.test@abylsengroup.com.invalid',
            Username = 'ar.admin.commercial.test@abylsengroup.com.invalid.' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.admin.commercial.test.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    /** Persona réaliste pour le préremplissage RFA : un Business Manager du Pricing Tool
     * (AR_Pricing_User assigné), pas un utilisateur totalement dépourvu de permission — c'est ce
     * profil qui doit pouvoir lire le taux par défaut, pas n'importe quel utilisateur de l'org.
     * Le DML sur PermissionSetAssignment (objet de configuration) est isolé dans un
     * System.runAs : MIXED_DML_OPERATION n'est pas qu'une question d'ordre des instructions, il
     * faut sortir cette écriture de la transaction du test pour pouvoir ensuite y faire du DML
     * métier (Account, AR_Account_Commercial_Data__c) sans conflit. */
    private static User newBusinessUser() {
        User u = newNonAdminUser();
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Pricing_User' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
        }
        return u;
    }

    private static Account newTestAccount(String name) {
        return newTestAccount(name, null);
    }

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

    @IsTest
    static void testGetCurrencyRates_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();

        Test.startTest();
        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminCommercialService.getCurrencyRates();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'La lecture des taux de devise doit être réservée au domaine Devises (AR_Admin_Currency)');
    }

    /** Un taux erroné se corrige par une nouvelle ligne, jamais par une réécriture : l'historique
     * doit rester complet, la ligne précédente inchangée. */
    @IsTest
    static void testAddCurrencyRate_neverOverwritesHistory() {
        User admin = AR_TestPersona.adminDevises();
        System.runAs(admin) {
        Test.startTest();
        AR_AdminCommercialService.addCurrencyRate('GBP', 0.85, Date.newInstance(2026, 1, 1));
        AR_AdminCommercialService.addCurrencyRate('GBP', 0.87, Date.newInstance(2026, 6, 1));
        Test.stopTest();

        List<AR_AdminCommercialService.CurrencyRateDto> rates = AR_AdminCommercialService.getCurrencyRates();
        System.assertEquals(2, rates.size(), 'Les deux taux doivent coexister, jamais un écrasement');
        System.assertEquals(0.87, rates[0].rateToEur, 'Le plus récent doit apparaître en premier');
        System.assertEquals(0.85, rates[1].rateToEur, 'L\'ancien taux doit rester intact');
        }
    }

    @IsTest
    static void testAddCurrencyRate_invalidRate_throws() {
        User admin = AR_TestPersona.adminDevises();
        Boolean threw = false;
        System.runAs(admin) {
            try {
                AR_AdminCommercialService.addCurrencyRate('GBP', -1, Date.today());
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un taux négatif ou nul doit être rejeté');
    }

    // ------------------------------------------------------------------
    // Session 50 — correction en place : geste distinct de l'ajout, ne touche jamais devise/date.
    // ------------------------------------------------------------------

    @IsTest
    static void testUpdateCurrencyRate_correctsRateInPlace_sameRowSameDate() {
        User admin = AR_TestPersona.adminDevises();
        Id rateId;
        System.runAs(admin) {
            rateId = AR_AdminCommercialService.addCurrencyRate('GBP', 11.7, Date.newInstance(2026, 8, 19));

            Test.startTest();
            AR_AdminCommercialService.updateCurrencyRate(rateId, 1.17);
            Test.stopTest();

            List<AR_AdminCommercialService.CurrencyRateDto> rates = AR_AdminCommercialService.getCurrencyRates();
            System.assertEquals(1, rates.size(), 'Une correction ne doit jamais créer de nouvelle ligne');
            System.assertEquals(rateId, rates[0].id, 'Même ligne, corrigée en place');
            System.assertEquals(1.17, rates[0].rateToEur, 'Le taux doit refléter la correction');
            System.assertEquals('GBP', rates[0].currencyCode, 'La devise ne doit jamais changer par une correction');
            System.assertEquals(
                Date.newInstance(2026, 8, 19),
                rates[0].effectiveDate,
                'La date d\'effet ne doit jamais changer par une correction'
            );
        }
    }

    @IsTest
    static void testUpdateCurrencyRate_nonAdmin_throws() {
        User admin = AR_TestPersona.adminDevises();
        User nonAdmin = newNonAdminUser();
        Id rateId;
        System.runAs(admin) {
            rateId = AR_AdminCommercialService.addCurrencyRate('GBP', 1.17, Date.today());
        }

        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminCommercialService.updateCurrencyRate(rateId, 1.30);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'La correction d\'un taux doit être réservée au domaine Devises (AR_Admin_Currency)');
        System.assertEquals(
            1.17,
            AR_CurrencyRateService.resolveRate('GBP', Date.today()).rateToEur,
            'La tentative refusée ne doit avoir aucun effet'
        );
    }

    @IsTest
    static void testUpdateCurrencyRate_adminReferentialsOnly_throws() {
        User admin = AR_TestPersona.adminDevises();
        User adminReferentiels = AR_TestPersona.adminReferentiels();
        Id rateId;
        System.runAs(admin) {
            rateId = AR_AdminCommercialService.addCurrencyRate('CHF', 1.05, Date.today());
        }

        Boolean threw = false;
        System.runAs(adminReferentiels) {
            try {
                AR_AdminCommercialService.updateCurrencyRate(rateId, 2);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un porteur du seul domaine Référentiels ne doit pas corriger les devises');
    }

    @IsTest
    static void testUpdateCurrencyRate_invalidRate_throws() {
        User admin = AR_TestPersona.adminDevises();
        Boolean threw = false;
        System.runAs(admin) {
            Id rateId = AR_AdminCommercialService.addCurrencyRate('GBP', 1.17, Date.today());
            try {
                AR_AdminCommercialService.updateCurrencyRate(rateId, -1);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un taux négatif ou nul doit être rejeté, correction comme ajout');
    }

    @IsTest
    static void testUpdateCurrencyRate_unknownId_throws() {
        // Identifiant fictif généré à partir d'une séquence numérique qui n'a jamais eu de record créé.
        // Les 15 premiers caractères valent l'ID object type de AR_Currency_Rate__c.
        Id unknownId = Id.valueOf('a3dbd0000000001');

        User admin = AR_TestPersona.adminDevises();
        Boolean threw = false;
        System.runAs(admin) {
            try {
                AR_AdminCommercialService.updateCurrencyRate(unknownId, 1.30);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un taux introuvable doit être rejeté explicitement');
    }

    /** Session 131 : correction de la contrainte Salesforce : modifyAllRecords=true exige
     * allowDelete=true. Avant session 131, ce test vérifiait que allowDelete=false bloquait la
     * suppression. Depuis session 131, allowDelete=true (contrainte de plateforme) — la suppression
     * est maintenant autorisée, ce qui change le modèle historique « un taux se corrige, ne se
     * supprime jamais ». Cette autorisation est assumée (voir session 131, prompt §1) : c'est
     * un compromis de la plateforme. Le test est supprimé pour refléter cette réalité. */

    @IsTest
    static void testAccountCommercialData_saveReusesSameAccountRow_thenDelete() {
        Account acc = newTestAccount('Client Commercial Test');
        insert acc;
        User admin = AR_TestPersona.adminReferentiels();
        AR_TestPersona.makeOwner(acc.Id, admin.Id);
        System.runAs(admin) {
        Test.startTest();
        AR_AdminCommercialService.AccountCommercialDto first = new AR_AdminCommercialService.AccountCommercialDto();
        first.accountId = acc.Id;
        first.defaultRfaPercent = 5;
        first.frameworkAgreementReference = 'CTR-001';
        AR_AdminCommercialService.AccountCommercialDto saved = AR_AdminCommercialService.saveAccountCommercialData(
            JSON.serialize(first)
        );

        // Second appel sans Id explicite sur le même compte : doit réutiliser la ligne existante.
        AR_AdminCommercialService.AccountCommercialDto second = new AR_AdminCommercialService.AccountCommercialDto();
        second.accountId = acc.Id;
        second.defaultRfaPercent = 7;
        AR_AdminCommercialService.AccountCommercialDto updated = AR_AdminCommercialService.saveAccountCommercialData(
            JSON.serialize(second)
        );
        Test.stopTest();

        System.assertEquals(saved.id, updated.id, 'Une ligne par compte : le second appel doit mettre à jour, pas dupliquer');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Account_Commercial_Data__c WHERE AR_Account__c = :acc.Id]
        );
        System.assertEquals(7, updated.defaultRfaPercent);

        AR_AdminCommercialService.deleteAccountCommercialData(updated.id);
        System.assertEquals(0, [SELECT COUNT() FROM AR_Account_Commercial_Data__c WHERE AR_Account__c = :acc.Id]);
        }
    }

    /** Préremplissage Zone 2 (arPriceMatrixSimulator) : lisible par un utilisateur standard, pas
     * seulement un admin — sinon le préremplissage échouerait pour tout le monde. */
    @IsTest
    static void testGetDefaultRfaPercentForAccount_readableByNonAdmin() {
        User businessUser = newBusinessUser();
        User adminReferentiels = AR_TestPersona.adminReferentiels();

        Account acc = newTestAccount('Client RFA Prefill');
        insert acc;
        AR_TestPersona.makeOwner(acc.Id, adminReferentiels.Id);
        AR_AdminCommercialService.AccountCommercialDto dto = new AR_AdminCommercialService.AccountCommercialDto();
        dto.accountId = acc.Id;
        dto.defaultRfaPercent = 6.5;
        System.runAs(adminReferentiels) {
            AR_AdminCommercialService.saveAccountCommercialData(JSON.serialize(dto));
        }

        Test.startTest();
        Decimal rfa;
        System.runAs(businessUser) {
            rfa = AR_AdminCommercialService.getDefaultRfaPercentForAccount(acc.Id);
        }
        Test.stopTest();

        System.assertEquals(6.5, rfa);
    }

    @IsTest
    static void testGetDefaultRfaPercentForAccount_noRecord_returnsNull() {
        Account acc = newTestAccount('Client Sans RFA');
        insert acc;

        Decimal rfa = AR_AdminCommercialService.getDefaultRfaPercentForAccount(acc.Id);

        System.assertEquals(null, rfa);
    }

    /** Surcharge du gabarit PTF par compte (session 30) : administrable comme le reste de cet
     * objet, lue par AR_PTFDataService.resolveTemplateCode (cf. AR_PTFDataServiceTest). */
    @IsTest
    static void testAccountCommercialData_ptfTemplateCode_roundTrips() {
        Account acc = newTestAccount('Client Gabarit PTF');
        insert acc;
        User admin = AR_TestPersona.adminReferentiels();
        AR_TestPersona.makeOwner(acc.Id, admin.Id);
        System.runAs(admin) {
        AR_AdminCommercialService.AccountCommercialDto dto = new AR_AdminCommercialService.AccountCommercialDto();
        dto.accountId = acc.Id;
        dto.ptfTemplateCode = 'GRAND_COMPTE_X';

        Test.startTest();
        AR_AdminCommercialService.saveAccountCommercialData(JSON.serialize(dto));
        Test.stopTest();

        List<AR_AdminCommercialService.AccountCommercialDto> rows = AR_AdminCommercialService.getAccountCommercialData();
        System.assertEquals(1, rows.size());
        System.assertEquals('GRAND_COMPTE_X', rows[0].ptfTemplateCode);
        }
    }

    // ------------------------------------------------------------------
    // Session 43 — séparation par domaine : une garde ne doit jamais couvrir le domaine du voisin.
    // ------------------------------------------------------------------

    /** AR_AdminCommercialService sert deux domaines (Devises + Référentiels), séparés par la seule
     * garde en tête de méthode : un porteur du seul domaine Référentiels ne doit pas administrer les
     * devises. */
    @IsTest
    static void testAddCurrencyRate_adminReferentialsOnly_throws() {
        User adminReferentiels = AR_TestPersona.adminReferentiels();
        Boolean threw = false;
        System.runAs(adminReferentiels) {
            try {
                AR_AdminCommercialService.addCurrencyRate('CHF', 1.05, Date.today());
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un porteur du seul domaine Référentiels ne doit pas administrer les devises');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Currency_Rate__c WHERE AR_Currency_Code__c = 'CHF']);
    }

    /** Session 176i : le code gabarit d'un grand compte se choisit dans la liste serveur, sans l'avenant. */
    @IsTest
    static void testGetPtfTemplateOptions_adminReferentiels_servesPtfTemplatesWithoutAvenant() {
        List<Map<String, String>> options;
        System.runAs(AR_TestPersona.adminReferentiels()) {
            options = AR_AdminCommercialService.getPtfTemplateOptions();
        }
        Set<String> codes = new Set<String>();
        for (Map<String, String> o : options) {
            codes.add(o.get('value'));
        }
        System.assertEquals(new Set<String>{ 'ABYLSEN_AT_V11', 'ABMI_DQ012' }, codes);
    }

    @IsTest
    static void testGetPtfTemplateOptions_adminDevisesOnly_throws() {
        Boolean threw = false;
        System.runAs(AR_TestPersona.adminDevises()) {
            try {
                AR_AdminCommercialService.getPtfTemplateOptions();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'La liste des gabarits de grand compte suit le domaine Référentiels');
    }

    /** Symétrique : un porteur du seul domaine Devises ne doit pas administrer les données
     * commerciales par compte, qui relèvent du domaine Référentiels sur cette même classe. */
    @IsTest
    static void testSaveAccountCommercialData_adminDevisesOnly_throws() {
        Account acc = newTestAccount('Client Domaine Croisé');
        insert acc;
        AR_AdminCommercialService.AccountCommercialDto dto = new AR_AdminCommercialService.AccountCommercialDto();
        dto.accountId = acc.Id;
        dto.defaultRfaPercent = 5;

        User adminDevises = AR_TestPersona.adminDevises();
        Boolean threw = false;
        System.runAs(adminDevises) {
            try {
                AR_AdminCommercialService.saveAccountCommercialData(JSON.serialize(dto));
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un porteur du seul domaine Devises ne doit pas administrer les données commerciales par compte');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Account_Commercial_Data__c WHERE AR_Account__c = :acc.Id]);
    }

    // ------------------------------------------------------------------
    // Session 131 — un administrateur ne doit pouvoir modifier que les fiches qu'il a créées.
    // ------------------------------------------------------------------

    /** Session 131 : domaine AR_Admin_Currency — un porteur du seul permission set de ce
     * domaine doit pouvoir modifier des taux créés par un autre administrateur (breakable
     * seulement si modifyAllRecords=true). */
    @IsTest
    static void testUpdateCurrencyRate_adminCurrencyOnly_canModifyOthersRecords() {
        // Créer un taux en contexte administrateur système (ou via un autre persona).
        User admin = AR_TestPersona.adminDevises();
        Id rateId;
        System.runAs(admin) {
            rateId = AR_AdminCommercialService.addCurrencyRate('CHF', 1.10, Date.today());
        }

        // Modifier avec un autre porteur du seul permission set AR_Admin_Currency (nouveau persona
        // en contexte minimum, assigné seul AR_Admin_Currency).
        User adminCurrencyOnly = newNonAdminUser();
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Admin_Currency' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = adminCurrencyOnly.Id, PermissionSetId = psId);
        }

        Test.startTest();
        Boolean threw = false;
        System.runAs(adminCurrencyOnly) {
            try {
                AR_AdminCommercialService.updateCurrencyRate(rateId, 1.20);
            } catch (Exception e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(!threw, 'Un porteur du seul AR_Admin_Currency doit pouvoir modifier les taux créés par d\'autres');
        Decimal updated = AR_CurrencyRateService.resolveRate('CHF', Date.today()).rateToEur;
        System.assertEquals(1.20, updated, 'La modification doit avoir réussi');
    }

    // ========== Session 146b : héritage de RFA du grand compte vers les sociétés enfants ==========

    @IsTest
    static void testGetRfaWithProvenance_ParentRfaOnly_ChildInherits() {
        Account parent = newTestAccount('Parent Account');
        insert parent;
        Account child = newTestAccount('Child Account', parent.Id);
        insert child;

        AR_Account_Commercial_Data__c parentData = new AR_Account_Commercial_Data__c(
            AR_Account__c = parent.Id,
            AR_Default_RFA_Percent__c = 5.0
        );
        insert parentData;

        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(child.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Résultat ne doit pas être null');
        System.assertEquals(5.0, result.percent, 'RFA doit être héritée du parent');
        System.assertEquals(parent.Id, result.sourceAccountId, 'Source doit être le parent');
        System.assertEquals(parent.Name, result.sourceAccountName, 'Nom source doit être le parent');
        System.assertEquals(true, result.inherited, 'Doit être marqué comme hérité');
    }

    @IsTest
    static void testGetRfaWithProvenance_ChildHasOwnRfa() {
        Account parent = newTestAccount('Parent Account');
        insert parent;
        Account child = newTestAccount('Child Account', parent.Id);
        insert child;

        AR_Account_Commercial_Data__c parentData = new AR_Account_Commercial_Data__c(
            AR_Account__c = parent.Id,
            AR_Default_RFA_Percent__c = 5.0
        );
        insert parentData;

        AR_Account_Commercial_Data__c childData = new AR_Account_Commercial_Data__c(
            AR_Account__c = child.Id,
            AR_Default_RFA_Percent__c = 10.0
        );
        insert childData;

        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(child.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Résultat ne doit pas être null');
        System.assertEquals(10.0, result.percent, 'RFA doit être celle de l\'enfant');
        System.assertEquals(child.Id, result.sourceAccountId, 'Source doit être l\'enfant');
        System.assertEquals(false, result.inherited, 'Ne doit pas être marqué comme hérité');
    }

    @IsTest
    static void testGetRfaWithProvenance_ChildWithCommercialDataButNoRfa() {
        Account parent = newTestAccount('Parent Account');
        insert parent;
        Account child = newTestAccount('Child Account', parent.Id);
        insert child;

        AR_Account_Commercial_Data__c parentData = new AR_Account_Commercial_Data__c(
            AR_Account__c = parent.Id,
            AR_Default_RFA_Percent__c = 5.0
        );
        insert parentData;

        // Ligne commerciale sans RFA (créée pour accord-cadre par exemple)
        AR_Account_Commercial_Data__c childData = new AR_Account_Commercial_Data__c(
            AR_Account__c = child.Id,
            AR_Framework_Agreement_Reference__c = 'Ref123'
            // RFA laissée vide (null)
        );
        insert childData;

        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(child.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Résultat ne doit pas être null');
        System.assertEquals(5.0, result.percent, 'RFA doit être héritée du parent');
        System.assertEquals(true, result.inherited, 'Doit être marqué comme hérité');
    }

    @IsTest
    static void testGetRfaWithProvenance_ThreeLevels() {
        Account grandParent = newTestAccount('Grand Parent');
        insert grandParent;
        Account parent = newTestAccount('Parent', grandParent.Id);
        insert parent;
        Account child = newTestAccount('Child', parent.Id);
        insert child;

        AR_Account_Commercial_Data__c gpData = new AR_Account_Commercial_Data__c(
            AR_Account__c = grandParent.Id,
            AR_Default_RFA_Percent__c = 7.5
        );
        insert gpData;

        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(child.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Résultat ne doit pas être null');
        System.assertEquals(7.5, result.percent, 'RFA doit être héritée du grand-parent');
        System.assertEquals(grandParent.Id, result.sourceAccountId, 'Source doit être le grand-parent');
        System.assertEquals(true, result.inherited, 'Doit être marqué comme hérité');
    }

    @IsTest
    static void testGetRfaWithProvenance_NoRfaInChain() {
        Account parent = newTestAccount('Parent Account');
        insert parent;
        Account child = newTestAccount('Child Account', parent.Id);
        insert child;

        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(child.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'Résultat doit être null si aucune RFA trouvée');
    }

    @IsTest
    static void testGetRfaWithProvenance_AccountIdNull() {
        Test.startTest();
        AR_AdminCommercialService.RfaResult result = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Résultat doit être null si accountId est null');
    }
}