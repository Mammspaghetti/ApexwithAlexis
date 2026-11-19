/**
 * Session 179 : chaîne de valideurs d'une matrice (AR_ValidatorChain) et ses deux appelants
 * (AR_PricingMatrixService.getValidatorOptionsForMatrix, garde de requestDerogationInput).
 * Personas réels sous System.runAs : le propriétaire de la matrice (profil Recruiter +
 * AR_Pricing_User) appelle lui-même la méthode, comme Matthieu ou un BM en usage réel.
 */
@IsTest
private class AR_ValidatorChainTest {
    private static Integer counter = 0;

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Chaine',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        insert new cxsrec__cxsPosition__c(
            Name = 'Besoin Chaine', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert AR_GeneralSettingDefaults.newDefaultRecord();
    }

    private static User plainUser(String key, Boolean active) {
        counter++;
        User u = new User(
            LastName = 'Chaine ' + key,
            Email = key + counter + '@example.com.invalid',
            Username = 'ar.chain.' + key + counter + Datetime.now().getTime() + '@example.com.invalid',
            Alias = (key + counter).left(8),
            IsActive = active,
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            ProfileId = AR_TestPersona.standardProfileId(),
            FederationIdentifier = 'ar.chain.' + key + counter + Datetime.now().getTime()
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** Propriétaire de matrice (persona BM) avec la hiérarchie donnée ; renvoie la matrice et l'utilisateur. */
    private static AR_Price_Matrix__c matrixOwnedBy(User owner) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = owner.Id,
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Chaine' LIMIT 1].Id,
            AR_Position_Name__c = 'Besoin Chaine',
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Proposed_TJM__c = 480
        );
        insert m;
        return m;
    }

    private static User ownerWith(Id da, Id dd, Id directeur) {
        User owner = AR_TestPersona.bm();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = owner.Id, TP_DA__c = da, TP_DD__c = dd, TP_Directeur__c = directeur);
        }
        return owner;
    }

    private static User ownerWithAll(Id ra, Id da, Id dd, Id directeur, Id dc, Id dcg) {
        User owner = AR_TestPersona.bm();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = owner.Id, TP_RA__c = ra, TP_DA__c = da, TP_DD__c = dd, TP_Directeur__c = directeur,
                TP_Directeur_commercial__c = dc, TP_Directeur_commercial_groupe__c = dcg
            );
        }
        return owner;
    }

    @IsTest
    static void testSixNiveauxDansLOrdreAvecLeRole() {
        User ra = plainUser('ra', true);
        User da = plainUser('da', true);
        User dd = plainUser('dd', true);
        User directeur = plainUser('dir', true);
        User dc = plainUser('dc', true);
        User dcg = plainUser('dcg', true);
        User owner = ownerWithAll(ra.Id, da.Id, dd.Id, directeur.Id, dc.Id, dcg.Id);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(false, res.blocked);
        System.assertEquals(6, res.options.size());
        System.assertEquals(ra.Id, res.options[0].userId);
        System.assertEquals(da.Id, res.options[1].userId);
        System.assertEquals(dd.Id, res.options[2].userId);
        System.assertEquals(directeur.Id, res.options[3].userId);
        System.assertEquals(dc.Id, res.options[4].userId);
        System.assertEquals(dcg.Id, res.options[5].userId);
        System.assertEquals('RA', res.options[0].role);
        System.assertEquals('DA', res.options[1].role);
        System.assertEquals('DD', res.options[2].role);
        System.assertEquals('Directeur', res.options[3].role);
        System.assertEquals('Directeur commercial', res.options[4].role);
        System.assertEquals('Directeur commercial groupe', res.options[5].role);
    }

    @IsTest
    static void testMemePersonneSurDeuxNiveauxRolesCumules() {
        User ra = plainUser('ra', true);
        User da = plainUser('da', true);
        User dd = plainUser('dd', true);
        User directeur = plainUser('dir', true);
        User dc = plainUser('dc', true);
        // Doublon : le RA est aussi DA. Six niveaux renseignés, cinq lignes.
        User owner = ownerWithAll(ra.Id, ra.Id, dd.Id, directeur.Id, dc.Id, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(4, res.options.size(), 'RA = DA : une seule ligne');
        System.assertEquals(ra.Id, res.options[0].userId);
        System.assertEquals('RA, DA', res.options[0].role, 'Les rôles de la personne sont cumulés dans l\'étiquette');
        System.assertEquals(dd.Id, res.options[1].userId);
    }

    @IsTest
    static void testNiveauInactifDansLaListeExclu() {
        User raOff = plainUser('raOff', false);
        User da = plainUser('da', true);
        User owner = ownerWithAll(raOff.Id, da.Id, null, null, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(new Set<Id>{ da.Id }, ids(res), 'Le RA inactif ne doit pas être proposé');
    }

    private static void setTestValidators(String value) {
        AR_General_Setting__c s = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        s.AR_Test_Validator_Ids__c = value;
        update s;
    }

    private static AR_PricingMatrixService.ValidatorOptionsResult optionsAs(User caller, Id matrixId) {
        AR_PricingMatrixService.ValidatorOptionsResult res;
        System.runAs(caller) {
            res = AR_PricingMatrixService.getValidatorOptionsForMatrix(matrixId);
        }
        return res;
    }

    private static Set<Id> ids(AR_PricingMatrixService.ValidatorOptionsResult res) {
        Set<Id> out = new Set<Id>();
        for (AR_PricingMatrixService.ValidatorOption o : res.options) {
            out.add(o.userId);
        }
        return out;
    }

    @IsTest
    static void testDaSeulEstPropose() {
        User da = plainUser('da', true);
        User owner = ownerWith(da.Id, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(false, res.blocked);
        System.assertEquals(new Set<Id>{ da.Id }, ids(res));
    }

    @IsTest
    static void testDirecteurSeulEstPropose() {
        User directeur = plainUser('dir', true);
        User owner = ownerWith(null, null, directeur.Id);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(false, res.blocked, 'Un Directeur seul suffit, il était ignoré avant la session 179');
        System.assertEquals(new Set<Id>{ directeur.Id }, ids(res));
        System.assertEquals(directeur.LastName, res.options[0].userName);
    }

    @IsTest
    static void testTroisNiveauxDansLOrdreDaDdDirecteur() {
        User da = plainUser('da', true);
        User dd = plainUser('dd', true);
        User directeur = plainUser('dir', true);
        User owner = ownerWith(da.Id, dd.Id, directeur.Id);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(3, res.options.size());
        System.assertEquals(da.Id, res.options[0].userId);
        System.assertEquals(dd.Id, res.options[1].userId);
        System.assertEquals(directeur.Id, res.options[2].userId);
    }

    @IsTest
    static void testMemePersonneSurDeuxNiveauxDedoublonnee() {
        User da = plainUser('da', true);
        User owner = ownerWith(da.Id, da.Id, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(1, res.options.size(), 'DA = DD : une seule ligne (Matthieu voyait Alexis deux fois)');
    }

    @IsTest
    static void testUtilisateurInactifExclu() {
        User inactifDa = plainUser('daOff', false);
        User dd = plainUser('dd', true);
        User owner = ownerWith(inactifDa.Id, dd.Id, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(new Set<Id>{ dd.Id }, ids(res), 'Le DA inactif ne doit pas être proposé');
    }

    @IsTest
    static void testToutVideBloqueEtNommeLesChampsEtLaFiche() {
        User owner = ownerWith(null, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(true, res.blocked);
        System.assert(res.options.isEmpty());
        System.assert(res.blockedReason.contains(owner.LastName), 'Le motif nomme la fiche concernée : ' + res.blockedReason);
        System.assert(res.blockedReason.contains('TP_DA__c') && res.blockedReason.contains('TP_DD__c') && res.blockedReason.contains('TP_Directeur__c'), res.blockedReason);
        System.assert(
            res.blockedReason.contains('TP_RA__c') && res.blockedReason.contains('TP_Directeur_commercial__c') &&
            res.blockedReason.contains('TP_Directeur_commercial_groupe__c'),
            'Les six champs sont nommés : ' + res.blockedReason
        );
        System.assert(res.blockedReason.contains('vide'), res.blockedReason);
    }

    @IsTest
    static void testToutInactifDitQuiEstInactif() {
        User inactifDa = plainUser('daOff', false);
        User owner = ownerWith(inactifDa.Id, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(true, res.blocked);
        System.assert(res.blockedReason.contains(inactifDa.LastName + ' est inactif'), res.blockedReason);
    }

    @IsTest
    static void testValideurDeTestAjouteMemeSansChaine() {
        User testValidator = plainUser('test', true);
        setTestValidators(testValidator.Id);
        User owner = ownerWith(null, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(false, res.blocked, 'Le valideur de test débloque une chaîne vide');
        System.assertEquals(new Set<Id>{ testValidator.Id }, ids(res));
    }

    @IsTest
    static void testValideurDeTestAjouteALaChaine() {
        User da = plainUser('da', true);
        User testValidator = plainUser('test', true);
        setTestValidators(testValidator.Id);
        User owner = ownerWith(da.Id, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(new Set<Id>{ da.Id, testValidator.Id }, ids(res));
        System.assertEquals(da.Id, res.options[0].userId, 'La chaîne d\'abord, le valideur de test ensuite');
    }

    @IsTest
    static void testValideurDeTestDejaDaEstDedoublonne() {
        User da = plainUser('da', true);
        setTestValidators(da.Id + ', ' + da.Id);
        User owner = ownerWith(da.Id, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(1, res.options.size());
    }

    @IsTest
    static void testValideurDeTestInactifOuJetonInvalideIgnoreEtMessageLeDit() {
        User testOff = plainUser('testOff', false);
        setTestValidators('pas-un-id; ' + testOff.Id);
        User owner = ownerWith(null, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(true, res.blocked);
        System.assert(res.blockedReason.contains('Valideurs de test'), res.blockedReason);
    }

    @IsTest
    static void testReglageVideOuAbsentNAjouteRien() {
        delete [SELECT Id FROM AR_General_Setting__c];
        User owner = ownerWith(null, null, null);
        System.assertEquals(0, AR_ValidatorChain.testValidatorIds().size());
        System.assertEquals(true, optionsAs(owner, matrixOwnedBy(owner).Id).blocked);
    }

    @IsTest
    static void testMatriceInconnueOuNulle() {
        System.runAs(AR_TestPersona.francais()) {
            System.assertEquals(true, AR_PricingMatrixService.getValidatorOptionsForMatrix(null).blocked);
            AR_Price_Matrix__c m = matrixOwnedBy(ownerWith(null, null, null));
            Id gone = m.Id;
            delete m;
            AR_PricingMatrixService.ValidatorOptionsResult res = AR_PricingMatrixService.getValidatorOptionsForMatrix(gone);
            System.assertEquals(true, res.blocked);
            System.assertEquals('Matrice non trouvée.', res.blockedReason);
        }
    }

    @IsTest
    static void testGardeServeurRefuseChaineVideAvecLeMemeMotif() {
        User owner = ownerWith(null, null, null);
        AR_Price_Matrix__c m = matrixOwnedBy(owner);
        String message;
        System.runAs(owner) {
            try {
                AR_PricingMatrixService.verifyCreatorHasValidatorChain(m.Id);
            } catch (Exception e) {
                message = e.getMessage();
            }
        }
        System.assert(message != null && message.contains('Aucun valideur trouvé'), 'Garde serveur : ' + message);
        System.assert(message.contains('TP_Directeur__c'), message);
    }

    @IsTest
    static void testGardeServeurLaisseePasserAvecUnValideurDeTest() {
        User testValidator = plainUser('test', true);
        setTestValidators(testValidator.Id);
        User owner = ownerWith(null, null, null);
        AR_Price_Matrix__c m = matrixOwnedBy(owner);
        System.runAs(owner) {
            AR_PricingMatrixService.verifyCreatorHasValidatorChain(m.Id);
        }
        System.assert(true, 'Aucune exception : le valideur de test satisfait la garde serveur');
    }

    /** Résolution exécutée dans le contexte du propriétaire : le message et le label sont dans la même langue. */
    private static AR_ValidatorChain.Resolution resolveAs(User owner, Set<Id> excluded) {
        AR_ValidatorChain.Resolution res;
        System.runAs(owner) {
            res = AR_ValidatorChain.resolveForOwner(owner.Id, excluded);
        }
        return res;
    }

    @IsTest
    static void testSeulLeDemandeurEcarteDonneLeMessageDedie() {
        User da = plainUser('da', true);
        User owner = ownerWith(da.Id, null, null);
        AR_ValidatorChain.Resolution res = resolveAs(owner, new Set<Id>{ da.Id });
        String expected;
        System.runAs(owner) {
            expected = Label.AR_Msg_VAL_OnlyExcludedValidators;
        }
        System.assertEquals(0, res.validators.size());
        System.assertEquals(
            expected,
            res.blockedReason,
            'Seul valideur de la chaîne écarté (demandeur)'
        );
    }

    @IsTest
    static void testChaineVideGardeLeMessageExistant() {
        User owner = ownerWith(null, null, null);
        AR_ValidatorChain.Resolution res = resolveAs(owner, new Set<Id>{ owner.Id });
        System.assertEquals(0, res.validators.size());
        System.assertNotEquals(Label.AR_Msg_VAL_OnlyExcludedValidators, res.blockedReason, 'Chaîne vide : rien n\'a été écarté');
        System.assert(res.blockedReason.contains('Aucun valideur trouvé'), res.blockedReason);
    }

    @IsTest
    static void testLevelsEstLOrdreDeLEscalade() {
        User da = plainUser('da', true);
        User dd = plainUser('dd', true);
        User directeur = plainUser('dir', true);
        User owner = ownerWith(da.Id, dd.Id, directeur.Id);
        Map<Id, User> loaded = AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ owner.Id });
        List<User> levels = AR_ValidatorChain.levels(loaded.get(owner.Id));
        System.assertEquals(da.Id, levels[0].Id);
        System.assertEquals(dd.Id, levels[1].Id);
        System.assertEquals(directeur.Id, levels[2].Id);
        System.assertEquals(dd.Id, AR_DerogationReminderBatch.escalationTarget(loaded.get(owner.Id), da.Id).Id);
    }

    // ---------- Valideurs d'entité PTF ----------

    private static void addEntityValidator(User u) {
        Id entityId = AR_TestPersona.entityRefId('Abylsen GAMMA');
        insert new AR_PTF_Entity_Validator__c(
            AR_Entity_Ref__c = entityId, AR_User__c = u.Id,
            AR_Unique_Key__c = String.valueOf(entityId) + ':' + String.valueOf(u.Id)
        );
    }

    @IsTest
    static void testValideurEntite_actifPropose_inactifJamais_roleCumule() {
        User da = plainUser('da', true);
        User active = plainUser('evact', true);
        User inactive = plainUser('evinact', true);
        addEntityValidator(active);
        addEntityValidator(inactive);
        addEntityValidator(da);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = inactive.Id, IsActive = false);
        }
        User owner = ownerWith(da.Id, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);

        System.assertEquals(false, res.blocked);
        System.assertEquals(2, res.options.size(), 'DA (rôles cumulés) + valideur d\'entité actif');
        System.assertEquals(da.Id, res.options[0].userId);
        // Le libellé de rôle suit la langue de l'utilisateur appelant (persona « fr »), pas celle de l'exécutant du test.
        String entityRole;
        System.runAs(owner) {
            entityRole = Label.AR_Msg_VAL_LevelEntityValidator;
        }
        System.assertEquals('DA, ' + entityRole, res.options[0].role);
        System.assertEquals(active.Id, res.options[1].userId);
        System.assertEquals(entityRole, res.options[1].role);
        System.assert(!ids(res).contains(inactive.Id), 'Un valideur d\'entité inactif n\'est jamais proposé.');
    }

    @IsTest
    static void testValideurEntite_proprietaireJamaisPropose_etChaineVideDebloquee() {
        User owner = ownerWith(null, null, null);
        addEntityValidator(owner);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(true, res.blocked, 'Le propriétaire valideur d\'entité n\'est pas proposé : plus personne.');
        System.assertEquals(0, res.options.size());
    }

    @IsTest
    static void testEntiteSansValideur_messageChaineVideInchange() {
        User owner = ownerWith(null, null, null);
        AR_PricingMatrixService.ValidatorOptionsResult res = optionsAs(owner, matrixOwnedBy(owner).Id);
        System.assertEquals(true, res.blocked);
        System.assert(res.blockedReason.contains('Aucun valideur trouvé'), res.blockedReason);
    }

    @IsTest
    static void testGardeServeur_accepteValideurEntite_refuseHorsChaineEtHorsEntite() {
        User ev = plainUser('evguard', true);
        User outsider = plainUser('outsider', true);
        addEntityValidator(ev);
        User owner = ownerWith(null, null, null);
        AR_Price_Matrix__c m = matrixOwnedBy(owner);
        System.runAs(owner) {
            AR_PricingMatrixService.requireSelectableValidator(m.Id, ev.Id);
            String message;
            try {
                AR_PricingMatrixService.requireSelectableValidator(m.Id, outsider.Id);
            } catch (Exception e) {
                message = e.getMessage();
            }
            System.assertEquals(Label.AR_Msg_DRG_ValidatorNotProposed, message);
        }
    }
}