/**
 * Recette automatisée « Matthieu » (session 106) : parcours joués sous System.runAs avec le VRAI
 * utilisateur de Matthieu (son profil, ses permission sets) — seul ce qui est propre à la personne
 * est lu dans l'org.
 *
 * Session 180b §0 : plus aucune dépendance aux données de la sandbox (plus de SeeAllData). La version
 * d'origine lisait « la première matrice de Matthieu » sans filtre de statut : depuis le nettoyage
 * 176f c'était une matrice décidée, dont la duplication exige un motif — le test dépendait de l'état
 * de la sandbox. Désormais @TestSetup crée tout ce qu'il faut (besoins, motif, entité, paramètres) et
 * chaque parcours crée SA matrice Brouillon, propriété de Matthieu : le test reste vert si l'on
 * supprime toutes ses matrices. Seul l'utilisateur est requis ; absent, le test échoue avec un message
 * nommé (jamais de repli sur un autre utilisateur).
 * Cette classe n'est PAS dans la liste de déploiement production (docs/deploiement-production.md) :
 * elle joue un utilisateur nommé de la sandbox.
 */
@IsTest
private class AR_RecetteMatthieuTest {
    private static final String MATTHIEU_USERNAME_PREFIX = 'matthieu.szczesny@abylsen.com';
    // Valideur de test : créé par @TestSetup, jamais lu dans l'org.
    private static final String VALIDATOR_USERNAME = 'ar.recette.valideur@example.com';
    // Utilisateur qui exécute le test, capturé au chargement de la classe (avant tout runAs) :
    // les données de départ se créent sous son identité, jamais sous celle de Matthieu (qui n'a pas
    // le droit de créer un besoin Connexys), puis lui sont transférées.
    private static final Id RUNNER_ID = UserInfo.getUserId();

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Recette Matthieu',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        insert new AR_Reason__c(
            Name = 'Motif Recette Matthieu', AR_Applies_To_Version__c = true,
            AR_Applies_To_Derogation__c = true, AR_Active__c = true
        );
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Working_Days_Per_Year__c = 218,
            AR_Markup_Percent__c = 18,
            AR_Markup_Max__c = 60,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Draft_Purge_Enabled__c = false,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Warning_Days__c = 5,
            AR_Draft_Purge_Max_Per_Run__c = 200
        );
        // Chaîne de valideurs propre au test : les champs TP_* réels de Matthieu ne sont pas lus. Un valideur
        // de test (permission AR_Pricing_Validator) devient la DA de Matthieu le temps du test ; ces DML sur User
        // sont annulés en fin de test. Sous l'identité du runner : pas de mixed DML avec les objets ci-dessus.
        System.runAs(new User(Id = RUNNER_ID)) {
            // Profil de Matthieu : un valideur métier lit les champs de la matrice par son profil, pas par ses permission sets
            // (AR_Position__c est requis, donc non accordable en FLS dans un permission set).
            User matthieu = findMatthieu();
            if (matthieu == null) {
                return;
            }
            User valideur = newValidator(matthieu.ProfileId);
            insert valideur;
            insert new PermissionSetAssignment(
                AssigneeId = valideur.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Pricing_Validator' LIMIT 1].Id
            );
            matthieu.TP_DA__c = valideur.Id;
            update matthieu;
        }
    }

    @IsTest
    static void testParcours1_SaveDraftOwnMatrixWithManager() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            // P1 : saveDraftInput sur une vraie matrice de Matthieu avec TP_Manager
            cxsrec__cxsPosition__c position = findPositionWithManager(matthieu.Id);
            if (position == null) {
                System.assert(false, 'Aucune position avec TP_Manager trouvée pour Matthieu');
                return;
            }

            AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
            input.positionId = position.Id;
            input.contractType = 'CDI';
            input.currencyCode = 'EUR';
            input.annualSalary = 35000;
            input.feeIk = 0;
            input.feeMeals = 0;
            input.feeLodging = 0;
            input.feeOmOther = 0;
            input.gratuityDays = 0;
            input.proposedTjm = 350;
            input.seniorityLevel = 'Senior Consultant';
            input.clientSite = 'Paris';
            input.clientGrid = true;

            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
                System.assertNotEquals(null, result, 'P1: Résultat saveDraft attendu');
            } catch (Exception e) {
                System.assert(false, 'P1: ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours2_RequestDerogationBelowFloor() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            // P2 : dupliquer une vraie matrice, fixer TJM sous plancher, requestDerogation
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            if (baseMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            // Dupliquer pour obtenir un brouillon neuf
            AR_MatrixChainService.DuplicateResult dup = AR_MatrixChainService.duplicateMatrix(
                baseMatrix.Id, baseMatrix.AR_Position__c, new List<Id>(), 'Duplication pour P2'
            );
            if (dup == null || dup.matrixId == null) {
                System.assert(false, 'Duplication échouée pour P2');
                return;
            }

            // Modifier le TJM pour être sous plancher (fixé à 250, sachant que plancher est 20%)
            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(dup.matrixId);
            ensureMissionDates(input); // session 108 : les dates de la matrice sont désormais exigées
            ensureMatrixPrerequisites(input); // session 119b : séniorité et site client exigés
            input.proposedTjm = 250;

            List<AR_Reason__c> reasons = [
                SELECT Id FROM AR_Reason__c WHERE AR_Active__c = true LIMIT 1
            ];
            if (reasons.isEmpty()) {
                System.assert(false, 'Aucun motif actif trouvé');
                return;
            }

            AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
            req.matrixInput = input;
            req.reason = 'Test session 106';
            req.selectedValidatorId = findValideur().Id;
            req.derogationReasonIds = new List<Id>{ reasons[0].Id };

            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.requestDerogationInput(req);
                System.assertNotEquals(null, result, 'P2: Résultat requestDerogation attendu');
            } catch (Exception e) {
                System.assert(false, 'P2: ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours3_DuplicateMatrix() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            // P3 : dupliquer une vraie matrice de Matthieu
            AR_Price_Matrix__c ownMatrix = findMatrixOwned(matthieu.Id);
            if (ownMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            try {
                AR_MatrixChainService.DuplicateResult result = AR_MatrixChainService.duplicateMatrix(
                    ownMatrix.Id, ownMatrix.AR_Position__c, new List<Id>(), 'Duplication test P3'
                );
                System.assertNotEquals(null, result, 'P3: Duplication attendue');
                System.assertNotEquals(null, result.matrixId, 'P3: ID de matrice dupliquée attendu');
            } catch (Exception e) {
                System.assert(false, 'P3: ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours4_SaveDraftOtherOwnerMatrix() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            // P4 : trouver une vraie matrice Brouillon d'un autre propriétaire, essayer de la modifier
            AR_Price_Matrix__c otherMatrix = findMatrixBrouillonNotOwned(matthieu.Id);
            if (otherMatrix == null) {
                System.assert(false, 'Aucune matrice Brouillon d\'un autre propriétaire trouvée');
                return;
            }

            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(otherMatrix.Id);
            input.proposedTjm = 400;

            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
                System.assertNotEquals(null, result, 'P4: Résultat attendu (succès ou erreur métier explicite)');
            } catch (AuraHandledException e) {
                // Erreur métier attendue : message explicite requis
                System.assert(
                    e.getMessage() != null && e.getMessage().length() > 0,
                    'P4: Message métier explicite attendu, reçu : ' + e.getMessage()
                );
            } catch (DmlException e) {
                // DmlException acceptable (partage, accès insuffisant, etc.) — message explicite requis
                System.assert(
                    e.getMessage() != null && e.getMessage().length() > 0,
                    'P4: Message technique explicite attendu (DmlException), reçu : ' + e.getMessage()
                );
            } catch (Exception e) {
                System.assert(false, 'P4: Exception inattendue (hors AuraHandledException/DmlException): ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours5_ValidateAboveFloor() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            // P5 : dupliquer, fixer TJM au-dessus plancher, validateInput
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            if (baseMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            AR_MatrixChainService.DuplicateResult dup = AR_MatrixChainService.duplicateMatrix(
                baseMatrix.Id, baseMatrix.AR_Position__c, new List<Id>(), 'Duplication pour P5'
            );
            if (dup == null || dup.matrixId == null) {
                System.assert(false, 'Duplication échouée pour P5');
                return;
            }

            // TJM au-dessus du plancher (fixé à 500)
            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(dup.matrixId);
            ensureMissionDates(input); // session 108 : les dates de la matrice sont désormais exigées
            ensureMatrixPrerequisites(input); // session 119b : séniorité et site client exigés
            input.proposedTjm = 500;

            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
                System.assertNotEquals(null, result, 'P5: Résultat validate attendu');
            } catch (Exception e) {
                System.assert(false, 'P5: ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours6_ApproveDerogation() {
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        Id derogationId;
        System.runAs(matthieu) {
            // P6 : créer une dérogation (brouillon sous plancher), puis la décider
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            if (baseMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            // Dupliquer et fixer sous plancher
            AR_MatrixChainService.DuplicateResult dup = AR_MatrixChainService.duplicateMatrix(
                baseMatrix.Id, baseMatrix.AR_Position__c, new List<Id>(), 'Duplication pour P6'
            );
            if (dup == null || dup.matrixId == null) {
                System.assert(false, 'Duplication échouée pour P6');
                return;
            }

            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(dup.matrixId);
            ensureMissionDates(input); // session 108 : les dates de la matrice sont désormais exigées
            ensureMatrixPrerequisites(input); // session 119b : séniorité et site client exigés
            input.proposedTjm = 250; // Sous plancher

            List<AR_Reason__c> reasons = [
                SELECT Id FROM AR_Reason__c WHERE AR_Active__c = true LIMIT 1
            ];
            if (reasons.isEmpty()) {
                System.assert(false, 'Aucun motif actif trouvé');
                return;
            }

            // Créer la dérogation
            AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
            req.matrixInput = input;
            req.reason = 'Dérogation pour P6';
            req.selectedValidatorId = findValideur().Id;
            req.derogationReasonIds = new List<Id>{ reasons[0].Id };

            AR_PricingMatrixService.MatrixSaveResult saveResult = AR_PricingMatrixService.requestDerogationInput(req);
            if (saveResult == null) {
                System.assert(false, 'Création dérogation échouée pour P6');
                return;
            }

            // Récupérer la dérogation créée
            AR_Derogation__c derogation = findDerogationForValidator(findValideur().Id);
            if (derogation == null) {
                System.assert(false, 'Dérogation non trouvée après création pour P6');
                return;
            }
            derogationId = derogation.Id;
        }

        // Décision par le valideur de la chaîne, sous sa propre identité (permission AR_Pricing_Validator)
        System.runAs(findValideur()) {
            try {
                AR_DerogationService.decide(derogationId, 'Acceptée', 'Test session 106');
                System.assert(true, 'P6: Décision enregistrée');
            } catch (Exception e) {
                System.assert(false, 'P6: ' + exceptionMessage(e));
            }
        }
    }

    @IsTest
    static void testParcours7_ValidateRefusedWithoutDates() {
        // Session 107 : validation refusée si dates de mission manquentes
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            if (baseMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            AR_MatrixChainService.DuplicateResult dup = AR_MatrixChainService.duplicateMatrix(
                baseMatrix.Id, baseMatrix.AR_Position__c, new List<Id>(), 'Duplication pour P7'
            );
            if (dup == null || dup.matrixId == null) {
                System.assert(false, 'Duplication échouée pour P7');
                return;
            }

            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(dup.matrixId);
            ensureMissionDates(input); // session 108 : les dates de la matrice sont désormais exigées
            ensureMatrixPrerequisites(input); // session 119b : séniorité et site client exigés
            input.proposedTjm = 500;
            // Dates volontairement nulles
            input.startDate = null;
            input.endDate = null;

            try {
                AR_PricingMatrixService.validateInput(input);
                System.assert(false, 'P7: Validation aurait dû être refusée sans dates');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains('date') || e.getMessage().contains('complétez'),
                    'P7: Message attendu de blocage dates, reçu : ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void testParcours8_ValidateAcceptedWithoutValidator() {
        // Session 107 : validation acceptée SANS valideur (valideur = champ du formulaire PTF, pas de la matrice)
        User matthieu = findMatthieu();
        if (matthieu == null) {
            System.assert(false, 'Recette Matthieu : utilisateur introuvable dans cette org');
            return;
        }

        System.runAs(matthieu) {
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            if (baseMatrix == null) {
                System.assert(false, 'Aucune matrice possédée par Matthieu trouvée');
                return;
            }

            AR_MatrixChainService.DuplicateResult dup = AR_MatrixChainService.duplicateMatrix(
                baseMatrix.Id, baseMatrix.AR_Position__c, new List<Id>(), 'Duplication pour P8'
            );
            if (dup == null || dup.matrixId == null) {
                System.assert(false, 'Duplication échouée pour P8');
                return;
            }

            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(dup.matrixId);
            ensureMissionDates(input); // session 108 : les dates de la matrice sont désormais exigées
            ensureMatrixPrerequisites(input); // session 119b : séniorité et site client exigés
            input.proposedTjm = 500;

            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
                System.assertNotEquals(null, result, 'P8: Validation acceptée même sans valideur sélectionné sur la matrice');
                System.assertEquals('Validée', result.status, 'P8: Statut attendu « Validée »');
            } catch (Exception e) {
                System.assert(false, 'P8: ' + exceptionMessage(e));
            }
        }
    }

    /**
     * Session 108 : chemin RÉEL de l'écran. JSON sérialisé depuis MatrixInput sans les nulls —
     * exactement ce que produit buildMatrixInput côté LWC (clés startDate, positionId…), sur un
     * besoin sans date de démarrage ni interlocuteur client, comme celui du constat navigateur
     * (MAT-00146). La 107 lisait des clés AR_*__c : ce test était rouge sur son code.
     */
    @IsTest
    static void testParcours9_PrerequisitesFromScreenJson() {
        User matthieu = findMatthieu();
        System.assertNotEquals(null, matthieu, 'Recette Matthieu : utilisateur introuvable dans cette org');
        cxsrec__cxsPosition__c pos = findPositionWithoutStartDateNorContact();
        System.assertNotEquals(null, pos, 'P9 : aucun besoin sans date de démarrage ni interlocuteur dans cette org');

        System.runAs(matthieu) {
            AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
            input.positionId = pos.Id;
            input.currencyCode = 'EUR';
            input.contractType = 'CDI';
            input.proposedTjm = 800;
            input.seniorityLevel = 'Senior Consultant';
            input.clientSite = 'Paris';
            input.clientGrid = true;
            String screenJson = JSON.serialize(input, true);
            System.assert(!screenJson.contains('AR_Start_Date__c'), 'P9 : le JSON écran ne porte pas de clé AR_*__c');

            List<String> labels = new List<String>();
            for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.getValidationPrerequisites(screenJson)) {
                labels.add(p.label);
            }
            System.assert(labels.contains('Date de démarrage'), 'P9 : date de démarrage non signalée, reçu ' + labels);
            System.assert(!labels.contains('Interlocuteur client absent du besoin'), 'P9 : l\'interlocuteur ne doit plus être signalé, reçu ' + labels);
            for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.getValidationPrerequisites(screenJson)) {
                if (p.label == 'Date de démarrage') {
                    System.assertEquals(true, p.blocking, 'P9 : la date de la matrice doit bloquer');
                }
            }
        }
    }

    /** Session 108 : la façade @AuraEnabled validate() — pas validateInput — refuse le même cas. */
    @IsTest
    static void testParcours10_ValidateFacadeRefusesIncompleteNewMatrix() {
        User matthieu = findMatthieu();
        System.assertNotEquals(null, matthieu, 'Recette Matthieu : utilisateur introuvable dans cette org');
        cxsrec__cxsPosition__c pos = findPositionWithoutStartDateNorContact();
        System.assertNotEquals(null, pos, 'P10 : aucun besoin sans date de démarrage ni interlocuteur dans cette org');

        System.runAs(matthieu) {
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            System.assertNotEquals(null, baseMatrix, 'P10 : aucune matrice possédée par Matthieu');
            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(baseMatrix.Id);
            input.matrixId = null; // matrice NEUVE, comme dans le constat
            input.positionId = pos.Id;
            input.startDate = null;
            input.proposedTjm = 2000; // au-dessus du plancher : seul le prérequis peut bloquer
            try {
                AR_PricingMatrixService.validate(JSON.serialize(input, true));
                System.assert(false, 'P10 : validate() a accepté une matrice sans date de démarrage ni interlocuteur');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains('Date de démarrage'),
                    'P10 : refus attendu sur la date de démarrage, reçu : ' + e.getMessage()
                );
            }
        }
    }

    /**
     * Session 108 (décision d'Alexis) : un besoin sans interlocuteur client NE BLOQUE PAS la
     * validation — seules les données de la matrice bloquent. Dates saisies sur la matrice.
     */
    @IsTest
    static void testParcours11_BesoinSansInterlocuteurNeBloquePas() {
        User matthieu = findMatthieu();
        System.assertNotEquals(null, matthieu, 'Recette Matthieu : utilisateur introuvable dans cette org');
        cxsrec__cxsPosition__c pos = findPositionWithoutStartDateNorContact();
        System.assertNotEquals(null, pos, 'P11 : aucun besoin sans interlocuteur dans cette org');

        System.runAs(matthieu) {
            AR_Price_Matrix__c baseMatrix = findMatrixOwned(matthieu.Id);
            System.assertNotEquals(null, baseMatrix, 'P11 : aucune matrice possédée par Matthieu');
            AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(baseMatrix.Id);
            input.matrixId = null;
            input.positionId = pos.Id;
            input.startDate = Date.today();
            input.endDate = Date.today().addMonths(3);
            input.proposedTjm = 2000;
            ensureMatrixPrerequisites(input);
            try {
                AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validate(JSON.serialize(input, true));
                System.assertEquals('Validée', result.status, 'P11 : statut attendu « Validée »');
            } catch (Exception e) {
                System.assert(false, 'P11 : ' + exceptionMessage(e));
            }
        }
    }

    private static void ensureMissionDates(AR_PricingMatrixService.MatrixInput input) {
        if (input.startDate == null) {
            input.startDate = Date.today();
        }
        if (input.endDate == null || input.endDate < input.startDate) {
            input.endDate = input.startDate.addMonths(3);
        }
    }

    private static void ensureMatrixPrerequisites(AR_PricingMatrixService.MatrixInput input) {
        if (String.isBlank(input.seniorityLevel)) {
            input.seniorityLevel = 'Senior Consultant';
        }
        if (String.isBlank(input.clientSite)) {
            input.clientSite = 'Paris';
            input.clientGrid = true;
        }
    }

    /** Besoin neuf, propriété de Matthieu, sans date de démarrage ni interlocuteur (cas du constat MAT-00146). */
    private static cxsrec__cxsPosition__c findPositionWithoutStartDateNorContact() {
        return newPositionOwnedBy(findMatthieu().Id, null);
    }

    // ===== Helpers =====

    private static User findMatthieu() {
        List<User> users = [
            SELECT Id, ProfileId FROM User WHERE Username LIKE :(MATTHIEU_USERNAME_PREFIX + '%') AND IsActive = true LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private static User findValideur() {
        List<User> users = [SELECT Id FROM User WHERE Username = :VALIDATOR_USERNAME LIMIT 1];
        return users.isEmpty() ? null : users[0];
    }

    private static User newValidator(Id profileId) {
        return new User(
            Username = VALIDATOR_USERNAME,
            Email = VALIDATOR_USERNAME,
            FederationIdentifier = VALIDATOR_USERNAME,
            Alias = 'rcvalid',
            LastName = 'Valideur Recette',
            ProfileId = profileId,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'fr',
            LocaleSidKey = 'fr_FR',
            TimeZoneSidKey = 'Europe/Paris',
            IsActive = true
        );
    }

    private static cxsrec__cxsPosition__c newPositionOwnedBy(Id ownerId, Id managerId) {
        cxsrec__cxsPosition__c position;
        System.runAs(new User(Id = RUNNER_ID)) {
            position = insertPositionOwnedBy(ownerId, managerId);
        }
        return position;
    }

    private static cxsrec__cxsPosition__c insertPositionOwnedBy(Id ownerId, Id managerId) {
        Account acc = [SELECT Id, OwnerId FROM Account WHERE Name = 'Client Recette Matthieu' LIMIT 1];
        if (acc.OwnerId != ownerId) {
            acc.OwnerId = ownerId; // un propriétaire voit toujours ses enregistrements, sans dépendre du partage
            update acc;
        }
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin recette ' + Datetime.now().getTime(), cxsrec__Account__c = acc.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI',
            OwnerId = ownerId
        );
        if (managerId != null) {
            // TP_Manager__c référence un Contact (pas un User).
            // Filtre du lookup TP_Manager__c : contact recruteur (cxsrec__Recruiter__c) relié à un utilisateur actif.
            Contact manager = new Contact(
                AccountId = acc.Id, LastName = 'Manager Recette ' + Datetime.now().getTime(),
                cxsrec__Recruiter__c = true, cxsrec__User__c = ownerId
            );
            insert manager;
            position.TP_Manager__c = manager.Id;
        }
        insert position;
        return position;
    }

    private static cxsrec__cxsPosition__c findPositionWithManager(Id ownerId) {
        return newPositionOwnedBy(ownerId, ownerId);
    }

    /** Matrice Brouillon neuve, propriété de `ownerId` (jamais une matrice décidée : pas de motif exigé). */
    private static AR_Price_Matrix__c findMatrixOwned(Id ownerId) {
        return newMatrix(ownerId, newPositionOwnedBy(ownerId, null).Id);
    }

    private static AR_Price_Matrix__c newMatrix(Id ownerId, Id positionId) {
        AR_Price_Matrix__c created;
        System.runAs(new User(Id = RUNNER_ID)) {
            created = insertMatrix(ownerId, positionId);
        }
        return created;
    }

    private static AR_Price_Matrix__c insertMatrix(Id ownerId, Id positionId) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = ownerId,
            AR_Position__c = positionId,
            AR_Contract_Type__c = 'CDI',
            AR_Currency__c = 'EUR',
            AR_Status__c = 'Brouillon',
            AR_Annual_Salary__c = 35000, // coût ≈ 324 €/j : TJM 500 → MC2 ≈ 35 %, TJM 250 → sous le plancher
            AR_Proposed_TJM__c = 400,
            AR_RFA_Percent__c = 0,
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA')
        );
        insert m;
        return [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c WHERE Id = :m.Id];
    }

    /** Brouillon d'un autre propriétaire que `notOwnerId` (l'utilisateur qui exécute le test). */
    private static AR_Price_Matrix__c findMatrixBrouillonNotOwned(Id notOwnerId) {
        return newMatrix(RUNNER_ID, newPositionOwnedBy(RUNNER_ID, null).Id);
    }

    private static AR_Derogation__c findDerogationForValidator(Id validatorId) {
        List<AR_Derogation__c> derogations = [
            SELECT Id
            FROM AR_Derogation__c
            WHERE AR_Selected_Validator__c = :validatorId AND AR_Decision__c = 'En attente'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return derogations.isEmpty() ? null : derogations[0];
    }

    private static String exceptionMessage(Exception e) {
        return 'Type: ' + e.getTypeName() + ' | Message: ' + e.getMessage() + ' | Stack: ' +
            e.getStackTraceString();
    }
}