/**
 * Tests AR_AdminReferentialService : corridors grands comptes, référentiels VIE/Nearshore, recherche
 * de compte — CRUD, validations et refus d'accès non-admin (System.runAs).
 */
@IsTest
private class AR_AdminReferentialServiceTest {

    private static User newNonAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'AdminReferentialTest',
            FirstName = 'AR',
            Alias = 'arart',
            Email = 'ar.admin.referential.test@abylsengroup.com.invalid',
            Username = 'ar.admin.referential.test@abylsengroup.com.invalid.' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.admin.referential.test.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    private static Account newTestAccount(String name) {
        return new Account(
            Name = name,
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
    }

    @IsTest
    static void testGetCorridors_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();

        Test.startTest();
        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminReferentialService.getCorridors();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'La lecture des corridors doit être réservée au domaine Référentiels (AR_Admin_Referentials)');
    }

    @IsTest
    static void testSaveCorridor_invalidOrdering_throws() {
        Account acc = newTestAccount('Client Corridor Invalide');
        insert acc;
        User admin = AR_TestPersona.adminReferentiels();

        Boolean threw = false;
        System.runAs(admin) {
            try {
                AR_AdminReferentialService.saveCorridor(null, acc.Id, 30, 25, 20);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'plancher ≤ cible ≤ idéal doit être appliqué');
    }

    @IsTest
    static void testSaveCorridor_thenSearchAccount_andDelete() {
        Account acc = newTestAccount('Client Corridor Recherche');
        insert acc;
        User admin = AR_TestPersona.adminReferentiels();
        AR_TestPersona.makeOwner(acc.Id, admin.Id);

        System.runAs(admin) {
        Test.startTest();
        List<AR_AdminReferentialService.AccountOption> found = AR_AdminReferentialService.searchAccounts('Corridor Recherche');
        System.assertEquals(1, found.size());

        Id corridorId = AR_AdminReferentialService.saveCorridor(null, acc.Id, 20, 25, 30);
        List<AR_AdminReferentialService.CorridorDto> corridors = AR_AdminReferentialService.getCorridors();
        System.assertEquals(1, corridors.size());
        System.assertEquals(acc.Id, corridors[0].accountId);

        AR_AdminReferentialService.deleteCorridor(corridorId);
        Test.stopTest();

        System.assertEquals(0, AR_AdminReferentialService.getCorridors().size());
        }
    }

    /** Session 279 : ville de facturation, à défaut de livraison, aucune → null. */
    @IsTest
    static void testSearchAccounts_returnsCity_billingThenShippingThenNone() {
        Account billing = newTestAccount('Homonyme Ville Facturation');
        billing.BillingCity = 'Lyon';
        Account shipping = newTestAccount('Homonyme Ville Livraison');
        // Un compte sans aucune adresse ne peut pas être inséré (règle de validation Compte de
        // l'org) : le cas « aucune ville » est vérifié directement sur la règle de dérivation.
        insert new List<Account>{ billing, shipping };
        User admin = AR_TestPersona.adminReferentiels();
        for (Account a : new List<Account>{ billing, shipping }) {
            AR_TestPersona.makeOwner(a.Id, admin.Id);
        }
        System.assertEquals(null, AR_AdminReferentialService.accountCity(new Account(Name = 'Sans ville')),
            'aucune ville : null, pas de texte de remplacement');

        System.runAs(admin) {
            Map<Id, String> cityById = new Map<Id, String>();
            for (AR_AdminReferentialService.AccountOption o : AR_AdminReferentialService.searchAccounts('Homonyme Ville')) {
                cityById.put(o.accountId, o.city);
            }
            System.assertEquals(2, cityById.size());
            System.assertEquals('Lyon', cityById.get(billing.Id), 'ville de facturation prioritaire');
            System.assertEquals('Paris', cityById.get(shipping.Id), 'repli sur la ville de livraison');
        }
    }

    /** Non-régression (le point le plus important de la session) : une matrice déjà validée sous
     * un corridor donné ne doit jamais changer de valeur si ce corridor est modifié après coup. */
    @IsTest
    static void testChangingCorridor_afterValidation_neverAffectsDecidedMatrix() {
        Account acc = newTestAccount('Client Corridor Non Regression');
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Corridor Non Regression', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        User admin = AR_TestPersona.adminReferentiels();
        AR_TestPersona.makeOwner(acc.Id, admin.Id);

        Id corridorId;
        System.runAs(admin) {
            corridorId = AR_AdminReferentialService.saveCorridor(null, acc.Id, 5, 8, 12);
        }

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'EUR';
        input.contractType = 'CDI';
        input.entity = String.valueOf(AR_TestPersona.entityRefId('Abylsen GAMMA'));
        input.annualSalary = 43600;
        input.feeIk = 8;
        input.feeMeals = 12;
        input.feeLodging = 15;
        input.feeOmOther = 5;
        input.gratuityDays = 1;
        input.feeComputer = 0;
        input.feeTraining = 200;
        input.feeEpi = 50;
        input.seniorityLevel = 'Senior';
        input.clientSite = 'Site A';
        input.clientGrid = true;
        input.startDate = Date.newInstance(2026, 9, 1);
        input.endDate = Date.newInstance(2026, 9, 30);
        input.rfaPercent = 0;
        input.proposedTjm = 500;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
        AR_Price_Matrix__c beforeChange = [
            SELECT AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_Corridor_Segment__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];

        Test.startTest();
        System.runAs(admin) {
            AR_AdminReferentialService.saveCorridor(corridorId, acc.Id, 40, 45, 49);
        }
        Test.stopTest();

        AR_Price_Matrix__c afterChange = [
            SELECT AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_Corridor_Segment__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(beforeChange.AR_TJM_Floor__c, afterChange.AR_TJM_Floor__c);
        System.assertEquals(beforeChange.AR_TJM_Target__c, afterChange.AR_TJM_Target__c);
        System.assertEquals(beforeChange.AR_TJM_Ideal__c, afterChange.AR_TJM_Ideal__c);
        System.assertEquals(beforeChange.AR_Corridor_Segment__c, afterChange.AR_Corridor_Segment__c);
    }

    @IsTest
    static void testVieReferential_saveAndDelete() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Test.startTest();
        Id recordId = AR_AdminReferentialService.saveVieReferential(null, 'Allemagne', 190, 'EUR');
        List<AR_AdminReferentialService.VieReferentialDto> rows = AR_AdminReferentialService.getVieReferentials();
        System.assertEquals(1, rows.size());
        System.assertEquals(190, rows[0].dailyAllowance);
        System.assertEquals('EUR', rows[0].currencyCode);

        AR_AdminReferentialService.deleteVieReferential(recordId);
        Test.stopTest();

        System.assertEquals(0, AR_AdminReferentialService.getVieReferentials().size());
        }
    }

    @IsTest
    static void testNearshoreReferential_saveAndDelete() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Test.startTest();
        Id recordId = AR_AdminReferentialService.saveNearshoreReferential(null, 'Tunisie', 'DEFAULT', 210, 'EUR');
        List<AR_AdminReferentialService.NearshoreReferentialDto> rows = AR_AdminReferentialService.getNearshoreReferentials();
        System.assertEquals(1, rows.size());
        System.assertEquals(210, rows[0].dailyRate);
        System.assertEquals('EUR', rows[0].currencyCode);

        AR_AdminReferentialService.deleteNearshoreReferential(recordId);
        Test.stopTest();

        System.assertEquals(0, AR_AdminReferentialService.getNearshoreReferentials().size());
        }
    }

    @IsTest
    static void testNearshoreReferential_duplicateCountrySeniorityPair_refusedNamingThePair() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
            AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'Technicien', 150, 'EUR');
            Boolean threw = false;
            try {
                AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'Technicien', 160, 'EUR');
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('Maroc') && e.getMessage().contains('Technicien'), e.getMessage());
            }
            System.assertEquals(true, threw);
            // Un même pays peut porter d'autres séniorités, et la ligne existante reste modifiable.
            AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'DEFAULT', 100, 'EUR');
            Id existing = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'Technicien' LIMIT 1].Id;
            AR_AdminReferentialService.saveNearshoreReferential(existing, 'Maroc', 'Technicien', 155, 'EUR');
            System.assertEquals(155, [SELECT AR_Daily_Rate__c FROM AR_Nearshore_Referential__c WHERE Id = :existing].AR_Daily_Rate__c);
        }
    }

    @IsTest
    static void testNearshoreReferential_blankSeniority_refused() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
            Boolean threw = false;
            try {
                AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', null, 150, 'EUR');
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assertEquals(true, threw);
            System.assertEquals(0, [SELECT COUNT() FROM AR_Nearshore_Referential__c]);
        }
    }

    @IsTest
    static void testNearshoreReferential_listedByCountryThenDefaultFirst() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
            AR_AdminReferentialService.saveNearshoreReferential(null, 'Tunisie', 'DEFAULT', 210, 'EUR');
            AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'Technicien', 150, 'EUR');
            AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'DEFAULT', 100, 'EUR');
            List<AR_AdminReferentialService.NearshoreReferentialDto> rows = AR_AdminReferentialService.getNearshoreReferentials();
            System.assertEquals(3, rows.size());
            System.assertEquals('Maroc', rows[0].country);
            System.assertEquals('DEFAULT', rows[0].seniority);
            System.assertEquals('Technicien', rows[1].seniority);
            System.assertEquals('Tunisie', rows[2].country);
        }
    }

    // Socle multi-devises (session 24) : un référentiel peut désormais porter une devise non-EUR.
    @IsTest
    static void testVieReferential_savedWithNonEurCurrency_persistsAndReturnsCurrency() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Id recordId = AR_AdminReferentialService.saveVieReferential(null, 'Royaume-Uni', 150, 'GBP');

        AR_VIE_Referential__c reloaded = [SELECT AR_Currency__c FROM AR_VIE_Referential__c WHERE Id = :recordId];
        System.assertEquals('GBP', reloaded.AR_Currency__c);
        }
    }

    @IsTest
    static void testVieReferential_blankCurrency_defaultsToEur() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Id recordId = AR_AdminReferentialService.saveVieReferential(null, 'Espagne', 160, null);

        AR_VIE_Referential__c reloaded = [SELECT AR_Currency__c FROM AR_VIE_Referential__c WHERE Id = :recordId];
        System.assertEquals('EUR', reloaded.AR_Currency__c, 'Devise non renseignée : défaut EUR, jamais null (cohérence avec la picklist)');
        }
    }

    @IsTest
    static void testNearshoreReferential_savedWithNonEurCurrency_persistsAndReturnsCurrency() {
        System.runAs(AR_TestPersona.adminReferentiels()) {
        Id recordId = AR_AdminReferentialService.saveNearshoreReferential(null, 'Maroc', 'DEFAULT', 200, 'MAD');

        AR_Nearshore_Referential__c reloaded = [SELECT AR_Currency__c FROM AR_Nearshore_Referential__c WHERE Id = :recordId];
        System.assertEquals('MAD', reloaded.AR_Currency__c);
        }
    }

    // ------------------------------------------------------------------
    // Entités PTF (session 46) : remplace l'administration via Setup > Custom Metadata Types de
    // AR_PTF_Entity__mdt.
    // ------------------------------------------------------------------

    @IsTest
    static void testGetPtfTemplateOptions_adminPtfEntities_servesPtfTemplatesWithoutAvenant() {
        List<Map<String, String>> options;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            options = AR_AdminReferentialService.getPtfTemplateOptions();
        }
        Set<String> codes = new Set<String>();
        for (Map<String, String> o : options) {
            codes.add(o.get('value'));
        }
        System.assertEquals(new Set<String>{ 'ABYLSEN_AT_V11', 'ABMI_DQ012' }, codes);
    }

    @IsTest
    static void testGetPtfTemplateOptions_adminReferentielsOnly_throws() {
        Boolean threw = false;
        System.runAs(AR_TestPersona.adminReferentiels()) {
            try {
                AR_AdminReferentialService.getPtfTemplateOptions();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'La liste des gabarits d\'entité suit le domaine Entités PTF');
    }

    @IsTest
    static void testGetPtfEntities_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();

        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminReferentialService.getPtfEntities();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'La lecture des entités PTF doit être réservée au domaine Entités PTF (AR_Admin_PTF_Entities)');
    }

    /** Symétrique (cf. AR_AdminCommercialServiceTest.testSaveAccountCommercialData_adminDevisesOnly_throws) :
     * un porteur du domaine Référentiels ne doit pas administrer les entités PTF, domaine séparé
     * depuis la session 46 à la demande du client. */
    @IsTest
    static void testGetPtfEntities_adminReferentielsOnly_throws() {
        Boolean threw = false;
        System.runAs(AR_TestPersona.adminReferentiels()) {
            try {
                AR_AdminReferentialService.getPtfEntities();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'AR_Admin_Referentials ne doit pas donner accès au domaine Entités PTF, séparé depuis la session 46');
    }

    @IsTest
    static void testSavePtfEntity_blankName_throws() {
        Boolean threw = false;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            try {
                AR_AdminReferentialService.savePtfEntity(
                    null, '', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Le nom d\'entité est obligatoire');
    }

    @IsTest
    static void testSavePtfEntity_blankCountry_isStoredAsNull() {
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            Id recordId = AR_AdminReferentialService.savePtfEntity(
                null, 'Abylsen PAYS', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, '   ', null, null, null, null
                );
            System.assertEquals(
                null,
                [SELECT AR_Country__c FROM AR_PTF_Entity_Referential__c WHERE Id = :recordId].AR_Country__c,
                'Un pays vide ne doit pas être stocké comme chaîne d\'espaces'
            );
        }
    }

    @IsTest
    static void testSavePtfEntity_nameAbsentFromOldPicklist_isAccepted() {
        // Session 132 : la liste d'administration est l'unique référence d'entité — plus aucun
        // contrôle de correspondance avec l'ancien picklist Entité. Une fiche comme « ABYLSEN EST –
        // Metz » (jamais présente dans l'ancien picklist) doit se sauvegarder.
        Id recordId;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            recordId = AR_AdminReferentialService.savePtfEntity(
                null, 'ABYLSEN EST – Metz', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );
        }
        AR_PTF_Entity_Referential__c saved = [
            SELECT Name, AR_Active__c FROM AR_PTF_Entity_Referential__c WHERE Id = :recordId
        ];
        System.assertEquals('ABYLSEN EST – Metz', saved.Name);
        System.assertEquals(true, saved.AR_Active__c);
    }

    @IsTest
    static void testSavePtfEntity_duplicateNames_areAllKept() {
        // Décision 3 (session 132) : les doublons de la liste sont conservés, aucune fusion.
        Id first;
        Id second;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            first = AR_AdminReferentialService.savePtfEntity(
                null, 'Abylsen EST', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );
            second = AR_AdminReferentialService.savePtfEntity(
                null, 'ABYLSEN EST – Strasbourg', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );
        }
        System.assertNotEquals(first, second);
        System.assertEquals(2, [SELECT COUNT() FROM AR_PTF_Entity_Referential__c WHERE Id IN :new Set<Id>{ first, second } AND AR_Active__c = true]);
    }

    @IsTest
    static void testSavePtfEntity_thenGet_andDelete() {
        System.runAs(AR_TestPersona.adminPtfEntities()) {
        Test.startTest();
        Id recordId = AR_AdminReferentialService.savePtfEntity(
            null,
            'Abylsen STRA',
            true,
            '1 rue de Strasbourg',
            '67000',
            'Strasbourg',
            '12345678900012',
            '+33100000000',
            null,
            null,
            null,
            'Banque Test',
            'FR7600000000000000000000000',
            null,
            'TESTFRPP',
            null,
            'GENERIQUE',
            1.95,
            210,
            ' France ', null, null, null, null
                );

        List<AR_AdminReferentialService.PtfEntityDto> rows = AR_AdminReferentialService.getPtfEntities();
        AR_AdminReferentialService.PtfEntityDto saved;
        for (AR_AdminReferentialService.PtfEntityDto row : rows) {
            if (row.id == recordId) {
                saved = row;
            }
        }
        System.assertNotEquals(null, saved, 'L\'entité enregistrée doit apparaître dans la liste');
        System.assertEquals('Abylsen STRA', saved.name);
        System.assertEquals(true, saved.active);
        System.assertEquals('Strasbourg', saved.city);
        System.assertEquals('France', saved.country, 'Le pays est enregistré, espaces de tête/queue retirés');
        System.assertEquals('Banque Test', saved.bankName);
        // Session 48 : coefficient/jours travaillés saisis sur l'entité — la cascade doit les
        // retenir tels quels comme valeur effective, source "entité".
        System.assertEquals(1.95, saved.coefficient);
        System.assertEquals(210, saved.workingDays);
        System.assertEquals(1.95, saved.coefficientEffective);
        System.assertEquals('entité', saved.coefficientSource);
        System.assertEquals(210, saved.workingDaysEffective);
        System.assertEquals('entité', saved.workingDaysSource);

        AR_AdminReferentialService.deletePtfEntity(recordId);
        Test.stopTest();

        Boolean stillPresent = false;
        for (AR_AdminReferentialService.PtfEntityDto row : AR_AdminReferentialService.getPtfEntities()) {
            if (row.id == recordId) {
                stillPresent = true;
            }
        }
        System.assert(!stillPresent, 'L\'entité doit avoir disparu après suppression');
        }
    }

    /** Session 48 : sans coefficient/jours travaillés saisis sur l'entité NI singleton
     * AR_General_Setting__c en base (cette classe n'en insère aucun) — la cascade doit retomber
     * directement sur les constantes moteur, jamais sur une case vide qui laisserait croire que
     * rien ne s'applique (CLAUDE.md, leçon session 35). */
    @IsTest
    static void testGetPtfEntities_noOverride_effectiveValuesFallBackToEngineDefaults() {
        System.runAs(AR_TestPersona.adminPtfEntities()) {
        Id recordId = AR_AdminReferentialService.savePtfEntity(
            null, 'Abylsen SUD', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );

        AR_AdminReferentialService.PtfEntityDto saved;
        for (AR_AdminReferentialService.PtfEntityDto row : AR_AdminReferentialService.getPtfEntities()) {
            if (row.id == recordId) {
                saved = row;
            }
        }
        System.assertNotEquals(null, saved);
        System.assertEquals(null, saved.coefficient);
        System.assertEquals(null, saved.workingDays);
        System.assertEquals(
            AR_PricingCalculator.CONTRACT_COEFFICIENT_DEFAULT,
            saved.coefficientEffective,
            'Sans coefficient d\'entité ni paramètre général fonctionnel, la constante moteur doit s\'afficher'
        );
        System.assertEquals('valeur par défaut moteur', saved.coefficientSource);
        System.assertEquals(
            AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT,
            saved.workingDaysEffective,
            'Sans jours travaillés d\'entité ni singleton AR_General_Setting__c en base, la constante moteur doit s\'afficher'
        );
        System.assertEquals('valeur par défaut moteur', saved.workingDaysSource);
        }
    }

    @IsTest
    static void testGetPtfEntities_readinessIssues_listsMissingFieldsPerKnownTemplate() {
        // Session 47 : écran de préparation (§4 du prompt) — le détail technique par gabarit a sa
        // place ici (registre admin), contrairement au sélecteur d'entité ou à arPtfPanel.
        System.runAs(AR_TestPersona.adminPtfEntities()) {
        Id recordId = AR_AdminReferentialService.savePtfEntity(
            null, 'Abylsen STRA', true, null, null, null, null, null, null, null, null, null, null, null, null, null, 'GENERIQUE', null, null, null, null, null, null, null
                );

        List<AR_AdminReferentialService.PtfEntityDto> rows = AR_AdminReferentialService.getPtfEntities();
        AR_AdminReferentialService.PtfEntityDto saved;
        for (AR_AdminReferentialService.PtfEntityDto row : rows) {
            if (row.id == recordId) {
                saved = row;
            }
        }
        System.assertNotEquals(null, saved);

        Map<String, String> missingByCode = new Map<String, String>();
        for (AR_AdminReferentialService.TemplateReadinessDto issue : saved.readinessIssues) {
            missingByCode.put(issue.templateCode, issue.missingFields);
        }
        System.assert(
            missingByCode.containsKey('ABYLSEN_AT_V11') && missingByCode.get('ABYLSEN_AT_V11').contains('RIB'),
            'Coordonnées bancaires absentes : doit apparaître pour ce gabarit, avec le détail des champs : ' + missingByCode
        );
        System.assert(
            missingByCode.containsKey('ABMI_DQ012') && missingByCode.get('ABMI_DQ012').contains('Téléphone') && !missingByCode.get('ABMI_DQ012').contains('Fax'),
            'Coordonnées d\'établissement absentes : doit apparaître pour ce gabarit : ' + missingByCode
        );
        System.assert(
            !missingByCode.containsKey('GENERIQUE'),
            'Le gabarit générique n\'exige rien de l\'entité : ne doit jamais être listé comme manquant'
        );
        }
    }

    @IsTest
    static void testSavePtfEntity_editExisting_updatesFieldsInPlace() {
        System.runAs(AR_TestPersona.adminPtfEntities()) {
        Id recordId = AR_AdminReferentialService.savePtfEntity(
            null, 'Abylsen EST', true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );

        AR_AdminReferentialService.savePtfEntity(
            recordId, 'Abylsen EST', false, 'Nouvelle adresse', null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null
                );

        AR_PTF_Entity_Referential__c reloaded = [
            SELECT AR_Active__c, AR_Address__c
            FROM AR_PTF_Entity_Referential__c
            WHERE Id = :recordId
        ];
        System.assertEquals(false, reloaded.AR_Active__c, 'La désactivation doit être persistée, pas seulement acceptée');
        System.assertEquals('Nouvelle adresse', reloaded.AR_Address__c);
        }
    }

    // ------------------------------------------------------------------
    // Session 131 — un administrateur ne doit pouvoir modifier que les fiches qu'il a créées.
    // ------------------------------------------------------------------

    // Remarque session 131 : les tests pour AR_Admin_Referentials et AR_Admin_PTF_Entities
    // ne sont pas inclus ici car ils sont complexes à cause des référentiels métier :
    // - AR_Account_Corridor__c a une lookup Account qui nécessite un partage CRUD, hors du scope
    //   de modifyAllRecords sur le corridor lui-même.
    // - AR_PTF_Entity_Referential__c a une validation métier de nom dans une picklist, qui
    //   complique le test sans rapport avec modifyAllRecords.
    // Les deux cas (modifyAllRecords) sont couverts par les tests pour
    // AR_Admin_General_Settings et AR_Admin_Currency, qui démontrent le principe.

    // Session 252 : seuils propres à l'entité, tous les trois ou aucun, même garde d'ordre que le grand compte.
    private static String ptfEntityThresholdError(String name, Decimal floor, Decimal target, Decimal ideal) {
        String message;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            try {
                AR_AdminReferentialService.savePtfEntity(
                    null, name, true,
                    null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
                    floor, target, ideal, null
                );
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    @IsTest
    static void testSavePtfEntity_partialThresholds_refused() {
        String expected;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            expected = Label.AR_Msg_ADM_EntityThresholdsPartial;
        }
        System.assertEquals(expected, ptfEntityThresholdError('Entite seuils partiels', 18, null, null));
        System.assertEquals(expected, ptfEntityThresholdError('Entite seuils partiels', 18, 23, null));
    }

    @IsTest
    static void testSavePtfEntity_incoherentThresholds_refused() {
        String expected;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            expected = Label.AR_Msg_ADM_ThresholdsOrder;
        }
        System.assertEquals(expected, ptfEntityThresholdError('Entite seuils incoherents', 25, 20, 30));
    }

    @IsTest
    static void testSavePtfEntity_completeThresholds_stored() {
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            AR_AdminReferentialService.savePtfEntity(
                null, 'Entite seuils complets', true,
                null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
                18, 23, 28, null
                );
        }
        AR_PTF_Entity_Referential__c stored = [
            SELECT AR_Floor_Percent__c, AR_Target_Percent__c, AR_Ideal_Percent__c
            FROM AR_PTF_Entity_Referential__c WHERE Name = 'Entite seuils complets' LIMIT 1
        ];
        System.assertEquals(18, stored.AR_Floor_Percent__c);
        System.assertEquals(23, stored.AR_Target_Percent__c);
        System.assertEquals(28, stored.AR_Ideal_Percent__c);
    }

    // ------------------------------------------------------------------
    // Valideurs d'entité PTF
    // ------------------------------------------------------------------

    private static Integer userSeq = 0;

    private static User newValidatorCandidate(String lastName, Boolean active) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        userSeq++;
        String suffix = String.valueOf(Datetime.now().getTime()) + '.' + userSeq;
        User u = new User(
            ProfileId = p.Id,
            LastName = lastName,
            FirstName = 'Zz',
            Title = 'Directeur ' + lastName,
            Alias = 'zv' + userSeq,
            Email = 'zv' + suffix + '@abylsengroup.com.invalid',
            Username = 'zv' + suffix + '@abylsengroup.com.invalid',
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            IsActive = active,
            FederationIdentifier = 'zv.' + suffix
        );
        insert u;
        return u;
    }

    private static Id saveEntityWithValidators(Id recordId, String name, List<Id> userIds) {
        return AR_AdminReferentialService.savePtfEntity(
            recordId, name, true, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, userIds
        );
    }

    private static AR_AdminReferentialService.PtfEntityDto dtoFor(Id entityId) {
        for (AR_AdminReferentialService.PtfEntityDto dto : AR_AdminReferentialService.getPtfEntities()) {
            if (dto.id == entityId) {
                return dto;
            }
        }
        return null;
    }

    @IsTest
    static void testEntityValidators_addTwo_removeOne() {
        User v1 = newValidatorCandidate('ValidatorAlpha', true);
        User v2 = newValidatorCandidate('ValidatorBeta', true);
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            Id entityId = saveEntityWithValidators(null, 'Entite valideurs', new List<Id>{ v1.Id, v2.Id });
            AR_AdminReferentialService.PtfEntityDto dto = dtoFor(entityId);
            System.assertEquals(2, dto.validators.size());
            System.assertEquals(0, dto.inactiveValidatorCount);
            System.assertEquals('ValidatorAlpha', dto.validators[0].name.substringAfter(' '));
            System.assertEquals('Directeur ValidatorAlpha', dto.validators[0].title);
            System.assertEquals(true, dto.validators[0].active);
            System.assertEquals(v1.Id, dto.validators[0].userId);
            System.assertNotEquals(null, dto.validators[0].rowId);

            saveEntityWithValidators(entityId, 'Entite valideurs', new List<Id>{ v2.Id });
            dto = dtoFor(entityId);
            System.assertEquals(1, dto.validators.size());
            System.assertEquals(v2.Id, dto.validators[0].userId);
            System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Entity_Validator__c WHERE AR_Entity_Ref__c = :entityId]);
        }
    }

    @IsTest
    static void testEntityValidators_nullList_leavesValidatorsUntouched() {
        User v1 = newValidatorCandidate('ValidatorGamma', true);
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            Id entityId = saveEntityWithValidators(null, 'Entite intacte', new List<Id>{ v1.Id });
            saveEntityWithValidators(entityId, 'Entite intacte renommee', null);
            System.assertEquals(1, dtoFor(entityId).validators.size());
        }
    }

    @IsTest
    static void testEntityValidators_duplicateInList_refusedWithMessage() {
        User v1 = newValidatorCandidate('ValidatorDelta', true);
        String message;
        Id entityId;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            try {
                saveEntityWithValidators(null, 'Entite doublon', new List<Id>{ v1.Id, v1.Id });
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertEquals(Label.AR_Msg_ADM_EntityValidatorDuplicate, message);
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_PTF_Entity_Referential__c WHERE Name = 'Entite doublon'],
            'Le refus annule la transaction : l\'entité n\'est pas créée sans ses valideurs'
        );
    }

    @IsTest
    static void testEntityValidators_duplicateKeyInDatabase_refusedWithMessage() {
        // Garde-fou de l'unicité en base (course entre deux enregistrements) : la clé « entité:utilisateur ».
        User v1 = newValidatorCandidate('ValidatorEpsilon', true);
        AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Name = 'Entite cle', AR_Active__c = true);
        insert entity;
        insert new AR_PTF_Entity_Validator__c(
            AR_Entity_Ref__c = entity.Id, AR_User__c = v1.Id, AR_Unique_Key__c = String.valueOf(entity.Id) + ':' + String.valueOf(v1.Id)
        );
        Boolean duplicate = false;
        try {
            insert new AR_PTF_Entity_Validator__c(
                AR_Entity_Ref__c = entity.Id, AR_User__c = v1.Id, AR_Unique_Key__c = String.valueOf(entity.Id) + ':' + String.valueOf(v1.Id)
            );
        } catch (DmlException e) {
            duplicate = e.getDmlType(0) == StatusCode.DUPLICATE_VALUE;
        }
        System.assert(duplicate, 'La clé unique doit refuser un deuxième enregistrement identique');
    }

    @IsTest
    static void testEntityValidators_inactiveUserCannotBeAdded() {
        User inactive = newValidatorCandidate('ValidatorZeta', false);
        String message;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            try {
                saveEntityWithValidators(null, 'Entite inactif ajoute', new List<Id>{ inactive.Id });
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertEquals(Label.AR_Msg_ADM_EntityValidatorInactive, message);
        }
    }

    @IsTest
    static void testSearchActiveUsers_onlyActive_minTwoChars_max20() {
        User active = newValidatorCandidate('Searchable Qwerty', true);
        newValidatorCandidate('Searchable Qwerty Inactif', false);
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            System.assertEquals(0, AR_AdminReferentialService.searchActiveUsers('Q').size(), '2 caractères minimum');
            System.assertEquals(0, AR_AdminReferentialService.searchActiveUsers(null).size());
            List<AR_AdminReferentialService.UserSearchResultDto> found = AR_AdminReferentialService.searchActiveUsers('searchable qwerty');
            System.assertEquals(1, found.size(), 'Les utilisateurs inactifs ne sont jamais proposés');
            System.assertEquals(active.Id, found[0].userId);
            System.assertEquals('Directeur Searchable Qwerty', found[0].title);
            System.assertEquals(0, AR_AdminReferentialService.searchActiveUsers('%%').size(), 'Le joker % est traité littéralement');
        }
    }

    @IsTest
    static void testSearchActiveUsers_cappedAt20() {
        List<User> many = new List<User>();
        for (Integer i = 0; i < 21; i++) {
            many.add(newValidatorCandidate('Cappedname' + i, true));
        }
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            System.assertEquals(20, AR_AdminReferentialService.searchActiveUsers('Cappedname').size());
        }
    }

    @IsTest
    static void testEntityValidators_withoutPermission_refused() {
        User v1 = newValidatorCandidate('ValidatorEta', true);
        Integer refused = 0;
        System.runAs(AR_TestPersona.sansHabilitation()) {
            try {
                saveEntityWithValidators(null, 'Entite interdite', new List<Id>{ v1.Id });
            } catch (AuraHandledException e) {
                refused++;
            }
            try {
                AR_AdminReferentialService.searchActiveUsers('Validator');
            } catch (AuraHandledException e) {
                refused++;
            }
        }
        System.assertEquals(2, refused, 'Enregistrement et recherche exigent AR_Admin_PTF_Entities');
    }

    @IsTest
    static void testEntityValidators_deleteEntity_deletesValidators() {
        User v1 = newValidatorCandidate('ValidatorTheta', true);
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            Id entityId = saveEntityWithValidators(null, 'Entite supprimee', new List<Id>{ v1.Id });
            System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Entity_Validator__c WHERE AR_Entity_Ref__c = :entityId]);
            AR_AdminReferentialService.deletePtfEntity(entityId);
            System.assertEquals(0, [SELECT COUNT() FROM AR_PTF_Entity_Validator__c WHERE AR_Entity_Ref__c = :entityId]);
        }
    }

    @IsTest
    static void testEntityValidators_deactivatedUser_flaggedInactiveAndCounted() {
        User v1 = newValidatorCandidate('ValidatorIota', true);
        User v2 = newValidatorCandidate('ValidatorKappa', true);
        Id entityId;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            entityId = saveEntityWithValidators(null, 'Entite desactivation', new List<Id>{ v1.Id, v2.Id });
        }
        v1.IsActive = false;
        update v1;
        System.runAs(AR_TestPersona.adminPtfEntities()) {
            AR_AdminReferentialService.PtfEntityDto dto = dtoFor(entityId);
            System.assertEquals(2, dto.validators.size(), 'Un valideur devenu inactif reste affiché');
            System.assertEquals(1, dto.inactiveValidatorCount);
            for (AR_AdminReferentialService.EntityValidatorDto v : dto.validators) {
                System.assertEquals(v.userId != v1.Id, v.active);
            }
            // Réenregistrer en gardant l'inactif ne le retire pas et n'échoue pas ; l'en retirer le supprime.
            saveEntityWithValidators(entityId, 'Entite desactivation', new List<Id>{ v1.Id, v2.Id });
            System.assertEquals(2, dtoFor(entityId).validators.size());
            saveEntityWithValidators(entityId, 'Entite desactivation', new List<Id>{ v2.Id });
            dto = dtoFor(entityId);
            System.assertEquals(1, dto.validators.size());
            System.assertEquals(0, dto.inactiveValidatorCount);
        }
    }
}