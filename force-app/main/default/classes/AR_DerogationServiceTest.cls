/**
 * Tests AR_DerogationService.decide()/getContext(). Session 40 : l'habilitation vient de la Custom
 * Permission AR_Approve_Derogation (assignation de AR_Pricing_Validator/_Manager, l'un ou l'autre),
 * plus de TP_Job_Title__c. makeCurrentUserValidator() assigne AR_Pricing_Validator à l'utilisateur
 * EXÉCUTANT le test (rollback automatique en fin de test) — additif, donc sûr quelle que soit
 * l'habilitation déjà portée par cet utilisateur dans la sandbox.
 *
 * Session 43 : le pendant « non-habilité » (retirer les permission sets de l'utilisateur exécutant
 * les tests) a été retiré — il couplait le résultat du test à ce que porte cet utilisateur réel dans
 * l'org, et a cassé silencieusement à la création d'AR_Pricing_Manager (session 42). Un non-habilité
 * se crée désormais (AR_TestPersona.sansHabilitation()), il ne se simule plus par déshabillage.
 */
@IsTest
private class AR_DerogationServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Dérogation',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Dérogation', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        User requester = AR_TestPersona.bm();

        // Insérée directement au statut En dérogation (le trigger ne s'applique qu'aux update, pas aux insert).
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Position_Name__c = position.Name,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 205,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_TJM_Target__c = 267,
            AR_TJM_Ideal__c = 286,
            AR_MC2_Per_Day__c = 5,
            AR_MC2_Percent__c = 2.44,
            AR_Corridor_Segment__c = 'below_floor',
            AR_Status__c = 'En dérogation',
            AR_Derogation_Reason__c = 'Contexte concurrentiel tendu',
            AR_Selected_Validator__c = UserInfo.getUserId(),
            OwnerId = requester.Id
        );
        insert matrix;

        // Le demandeur n'est pas l'utilisateur exécutant, qui reste libre de jouer le valideur.
        AR_Derogation__c pending = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = UserInfo.getUserId(),
            AR_Requester_Reason__c = 'Contexte concurrentiel tendu',
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        System.runAs(requester) {
            Database.insert(pending, AccessLevel.SYSTEM_MODE);
        }
    }

    private static AR_Price_Matrix__c getMatrix() {
        return [SELECT Id, AR_Position__c, AR_Number_Of_Days__c FROM AR_Price_Matrix__c LIMIT 1];
    }

    private static AR_Derogation__c getPendingDerogation() {
        return [SELECT Id FROM AR_Derogation__c WHERE AR_Decision__c = 'En attente' LIMIT 1];
    }

    private static void makeCurrentUserValidator() {
        assignPermissionSetIfMissing(UserInfo.getUserId(), 'AR_Pricing_Validator');
    }

    // MIXED_DML_OPERATION : isoler la DML sur PermissionSetAssignment (objet de configuration) dans
    // un System.runAs, sinon toute DML sur un objet métier plus loin dans la même méthode de test
    // (AR_Derogation__c/AR_Price_Matrix__c) échoue — même motif que newStandardUser ci-dessus et
    // AR_DerogationReminderBatchTest.newUser (session 40).
    private static void assignPermissionSetIfMissing(Id userId, String permissionSetName) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1].Id;
            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
            ];
            if (existing.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
            }
        }
    }

    /** Réassigne au valideur choisi (persona ou utilisateur exécutant les tests) la dérogation en
     * attente créée au @TestSetup — hors partage du trigger, sur le modèle déjà utilisé par
     * testRunAs_validatorPermissionSetHolder_canDecideAndSeesQueue. */
    private static void reassignSelectedValidator(Id derogationId, Id newValidatorId) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = derogationId, AR_Selected_Validator__c = newValidatorId);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    /** Session 143 : pose les trois entrées de la MC2/jour sur la matrice du @TestSetup (verrouillée
     * en dérogation : passage par le bypass de service, comme reassignSelectedValidator). */
    private static void setMatrixMc2(Decimal perDay, Decimal tjm, Decimal percent) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id,
                AR_MC2_Per_Day__c = perDay,
                AR_Proposed_TJM__c = tjm,
                AR_MC2_Percent__c = percent
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    @IsTest
    static void testListDerogations_mc2PerDay_storedValueIsReturned() {
        // Valeur stockée volontairement différente de TJM × MC2 % (490 × 8,9 % = 43,61) : prouve
        // que la valeur de la matrice prime sur le repli.
        setMatrixMc2(77.5, 490, 8.9);

        AR_DerogationService.DerogationListItem item = AR_DerogationService.listDerogations()[0];
        System.assertEquals(77.5, item.mc2PerDay, 'la MC2/jour stockée sur la matrice est remontée telle quelle');

        AR_DerogationService.DerogationContext ctx = AR_DerogationService.getContext([SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id);
        System.assertEquals(77.5, ctx.mc2PerDay, 'même valeur dans getContext');
    }

    @IsTest
    static void testListDerogations_mc2PerDay_fallbackWhenStoredIsNull() {
        setMatrixMc2(null, 490, 8.9);

        AR_DerogationService.DerogationListItem item = AR_DerogationService.listDerogations()[0];
        System.assertEquals(43.61, item.mc2PerDay, 'repli : TJM × MC2 % / 100 arrondi à 2 décimales');

        AR_DerogationService.DerogationContext ctx = AR_DerogationService.getContext([SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id);
        System.assertEquals(43.61, ctx.mc2PerDay, 'même repli dans getContext');
    }

    @IsTest
    static void testListDerogations_mc2PerDay_nullWhenFallbackInputsMissing() {
        setMatrixMc2(null, 490, null);
        System.assertEquals(null, AR_DerogationService.listDerogations()[0].mc2PerDay, 'MC2 % absente => null, jamais 0');

        System.assertEquals(null, AR_DerogationService.resolveMc2PerDay(null, null, 8.9), 'TJM absent => null');
        System.assertEquals(null, AR_DerogationService.resolveMc2PerDay(null, 490, null), 'MC2 % absente => null');
        System.assertEquals(0, AR_DerogationService.resolveMc2PerDay(0, 490, 8.9), 'un 0 stocké est une valeur, pas un trou');
    }

    @IsTest
    static void testListDerogations_returnsQueueRowWithGapVsFloor() {
        List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();

        System.assertEquals(1, items.size());
        AR_DerogationService.DerogationListItem item = items[0];
        System.assertEquals('En attente', item.decision);
        System.assertEquals(205, item.proposedTjm);
        System.assertEquals(250, item.tjmFloor);
        System.assertEquals(-45, item.gapVsFloor);
        System.assertEquals(
            [SELECT Name FROM User WHERE Id IN (SELECT OwnerId FROM AR_Price_Matrix__c)].Name,
            item.requesterName
        );
        System.assertNotEquals(null, item.requestedAt);
        System.assertEquals('Besoin Dérogation', item.positionName);
        System.assertEquals('France', item.accountCountry);
        System.assertEquals(267, item.tjmTarget);
        System.assertEquals(286, item.tjmIdeal);
        System.assertEquals(2.44, item.mc2PercentHuman);
        System.assertEquals('below_floor', item.corridorSegment);
        System.assertEquals('Contexte concurrentiel tendu', item.requesterReason);
        System.assertEquals(UserInfo.getName(), item.selectedValidatorName);
        System.assertEquals(null, item.effectiveValidatorName, 'Pas encore traitée');
    }

    @IsTest
    static void testListDerogations_rfa_matrixAndAccountRfaExposed() {
        makeCurrentUserValidator();
        Id ownerId = [SELECT OwnerId FROM AR_Price_Matrix__c LIMIT 1].OwnerId;
        Account account = insertAccount('Compte RFA différente', null);
        insert new AR_Account_Commercial_Data__c(AR_Account__c = account.Id, AR_Default_RFA_Percent__c = 2);
        AR_Price_Matrix__c matrix = insertMatrixOnAccount(account, 3, ownerId);
        insertDerogations(new List<AR_Derogation__c>{ newDerogation(matrix.Id) }, ownerId);

        AR_DerogationService.DerogationListItem item = findItem(matrix.Id);

        System.assertEquals(3, item.matrixRfaPercent);
        System.assertEquals(2, item.accountRfaPercent);
    }

    @IsTest
    static void testListDerogations_rfa_accountRfaInheritedFromParent() {
        makeCurrentUserValidator();
        Id ownerId = [SELECT OwnerId FROM AR_Price_Matrix__c LIMIT 1].OwnerId;
        Account parent = insertAccount('Grand compte RFA', null);
        insert new AR_Account_Commercial_Data__c(AR_Account__c = parent.Id, AR_Default_RFA_Percent__c = 4);
        Account child = insertAccount('Filiale sans RFA', parent.Id);
        AR_Price_Matrix__c matrix = insertMatrixOnAccount(child, 4, ownerId);
        insertDerogations(new List<AR_Derogation__c>{ newDerogation(matrix.Id) }, ownerId);

        AR_DerogationService.DerogationListItem item = findItem(matrix.Id);

        System.assertEquals(4, item.accountRfaPercent, 'RFA du grand compte, héritée par la filiale');
    }

    @IsTest
    static void testListDerogations_rfa_accountRfaNullWhenNoneRecorded() {
        makeCurrentUserValidator();
        AR_DerogationService.DerogationListItem item = AR_DerogationService.listDerogations()[0];

        System.assertEquals(0, item.matrixRfaPercent);
        System.assertEquals(null, item.accountRfaPercent, 'Compte sans RFA enregistrée');
    }

    /** Volume : 50 demandes réparties sur trois comptes. Les requêtes doivent suivre le nombre de comptes, pas de lignes. */
    @IsTest
    static void testListDerogations_rfa_fiftyRowsStayWithinFewQueries() {
        makeCurrentUserValidator();
        Id ownerId = [SELECT OwnerId FROM AR_Price_Matrix__c LIMIT 1].OwnerId;
        Account parent = insertAccount('Grand compte volume', null);
        insert new AR_Account_Commercial_Data__c(AR_Account__c = parent.Id, AR_Default_RFA_Percent__c = 4);
        Account child = insertAccount('Filiale volume', parent.Id);
        Account alone = insertAccount('Compte volume sans RFA', null);
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>{
            insertMatrixOnAccount(parent, 4, ownerId),
            insertMatrixOnAccount(child, 4, ownerId),
            insertMatrixOnAccount(alone, 0, ownerId)
        };
        List<AR_Derogation__c> derogations = new List<AR_Derogation__c>();
        for (Integer i = 0; i < 50; i++) {
            derogations.add(newDerogation(matrices[Math.mod(i, matrices.size())].Id));
        }
        insertDerogations(derogations, ownerId);

        Integer before = Limits.getQueries();
        List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
        Integer used = Limits.getQueries() - before;

        System.assertEquals(51, items.size());
        System.assert(used < 30, 'Requêtes SOQL de la file pour 51 demandes sur 3 comptes : ' + used);
    }

    private static Account insertAccount(String name, Id parentId) {
        Account acc = new Account(
            Name = name,
            ParentId = parentId,
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        return acc;
    }

    private static AR_Price_Matrix__c insertMatrixOnAccount(Account account, Decimal rfaPercent, Id ownerId) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin ' + account.Name, cxsrec__Account__c = account.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Position_Name__c = position.Name,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = rfaPercent,
            AR_Proposed_TJM__c = 205,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_TJM_Target__c = 267,
            AR_TJM_Ideal__c = 286,
            AR_MC2_Per_Day__c = 5,
            AR_MC2_Percent__c = 2.44,
            AR_Corridor_Segment__c = 'below_floor',
            AR_Status__c = 'En dérogation',
            AR_Derogation_Reason__c = 'Contexte concurrentiel tendu',
            AR_Selected_Validator__c = UserInfo.getUserId(),
            OwnerId = ownerId
        );
        insert matrix;
        return matrix;
    }

    private static AR_Derogation__c newDerogation(Id matrixId) {
        return new AR_Derogation__c(
            AR_Price_Matrix__c = matrixId,
            AR_Selected_Validator__c = UserInfo.getUserId(),
            AR_Requester_Reason__c = 'Contexte concurrentiel tendu',
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
    }

    private static void insertDerogations(List<AR_Derogation__c> derogations, Id ownerId) {
        System.runAs(new User(Id = ownerId)) {
            Database.insert(derogations, AccessLevel.SYSTEM_MODE);
        }
    }

    private static AR_DerogationService.DerogationListItem findItem(Id matrixId) {
        for (AR_DerogationService.DerogationListItem item : AR_DerogationService.listDerogations()) {
            if (item.matrixId == matrixId) {
                return item;
            }
        }
        System.assert(false, 'Demande absente de la file pour la matrice ' + matrixId);
        return null;
    }

    /**
     * Session 28 §5 : filtre "agence/BU" de la file d'approbation, porte le Nom de la fiche d'entité
     * AR_Entity_Ref__c (Zone 1 « Entité ») — nouveau record dédié plutôt que de modifier la matrice du @TestSetup
     * partagée par les autres tests de ce fichier.
     */
    @IsTest
    static void testListDerogations_includesEntityForBuFilter() {
        cxsrec__cxsPosition__c position = [SELECT Id, Name FROM cxsrec__cxsPosition__c LIMIT 1];
        AR_Price_Matrix__c matrixWithEntity = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Position_Name__c = position.Name,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 205,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_Status__c = 'En dérogation',
            AR_Derogation_Reason__c = 'Contexte',
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
        insert matrixWithEntity;
        insert new AR_Derogation__c(
            AR_Price_Matrix__c = matrixWithEntity.Id,
            AR_Selected_Validator__c = UserInfo.getUserId(),
            AR_Requester_Reason__c = 'Contexte',
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );

        List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();

        AR_DerogationService.DerogationListItem match;
        for (AR_DerogationService.DerogationListItem item : items) {
            if (item.matrixId == matrixWithEntity.Id) {
                match = item;
            }
        }
        System.assertNotEquals(null, match, 'La nouvelle dérogation doit apparaître dans la file');
        System.assertEquals('Abylsen GAMMA', match.entity);
    }

    @IsTest
    static void testListDerogations_isAddressedToCurrentUser_trueWhenSelectedValidatorAndHabilite() {
        makeCurrentUserValidator();

        List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();

        System.assertEquals(true, items[0].isAddressedToCurrentUser);
    }

    /**
     * Session 40 : listDerogations() ne renvoie RIEN à un non-habilité (garde en tête de méthode),
     * même sélectionné comme valideur sur la dérogation — remplace l'ancien test (session 33), dont
     * la prémisse (une liste populée avec isAddressedToCurrentUser=false) ne correspond plus au
     * nouveau modèle : « pas la permission » veut dire liste vide, pas une liste filtrée.
     */
    @IsTest
    static void testListDerogations_nonValidator_returnsNothingEvenWhenSelectedAsValidator() {
        AR_Derogation__c derogation = getPendingDerogation();
        User withoutPermission = AR_TestPersona.sansHabilitation();
        reassignSelectedValidator(derogation.Id, withoutPermission.Id);

        System.runAs(withoutPermission) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(
                0,
                items.size(),
                'Même sélectionné comme valideur sur la dérogation, un non-habilité ne doit rien recevoir'
            );
        }
    }

    /** Motif du référentiel, actif et applicable aux dérogations. */
    private static Id createReason(String label, Decimal sortOrder) {
        AR_Reason__c reason = new AR_Reason__c(
            Name = label,
            AR_Active__c = true,
            AR_Applies_To_Derogation__c = true,
            AR_Sort_Order__c = sortOrder
        );
        insert reason;
        return reason.Id;
    }

    /** Chemin de production : les motifs de dérogation passent par AR_ReasonService.insertSelections. */
    private static void selectReasons(Id derogationId, List<Id> reasonIds) {
        AR_ReasonService.insertSelections(null, derogationId, reasonIds);
    }

    /** Remplace le commentaire du demandeur sur la dérogation du @TestSetup (verrouillage levé par le bypass). */
    private static void setRequesterReason(Id derogationId, String reason) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = derogationId, AR_Requester_Reason__c = reason);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    /** Session 216 : aucun motif coché, commentaire seul — la liste reste vide, jamais null. */
    @IsTest
    static void testListDerogations_reasonLabels_emptyWhenNoReasonSelected() {
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(1, items.size());
            System.assertNotEquals(null, items[0].reasonLabels, 'Jamais null, même sans motif');
            System.assertEquals(0, items[0].reasonLabels.size());
            System.assertEquals('Contexte concurrentiel tendu', items[0].requesterReason, 'Le commentaire reste lu tel quel');
        }
    }

    /** Session 216 : un motif, avec commentaire. */
    @IsTest
    static void testListDerogations_reasonLabels_singleReasonWithComment() {
        AR_Derogation__c derogation = getPendingDerogation();
        selectReasons(derogation.Id, new List<Id>{ createReason('Concurrence', 1) });
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(1, items[0].reasonLabels.size());
            System.assertEquals('Concurrence', items[0].reasonLabels[0]);
            System.assertEquals('Contexte concurrentiel tendu', items[0].requesterReason);
        }
    }

    /** Session 216 : un motif, sans commentaire. */
    @IsTest
    static void testListDerogations_reasonLabels_singleReasonWithoutComment() {
        AR_Derogation__c derogation = getPendingDerogation();
        setRequesterReason(derogation.Id, null);
        selectReasons(derogation.Id, new List<Id>{ createReason('Concurrence', 1) });
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(1, items[0].reasonLabels.size());
            System.assertEquals('Concurrence', items[0].reasonLabels[0]);
            System.assertEquals(null, items[0].requesterReason);
        }
    }

    /**
     * Session 216 : deux motifs, saisis dans le désordre — la liste suit l'ordre du référentiel
     * (tri sur AR_Sort_Order__c), comme la modale de demande, avec le commentaire inchangé.
     */
    @IsTest
    static void testListDerogations_reasonLabels_twoReasonsInReferentialOrder() {
        AR_Derogation__c derogation = getPendingDerogation();
        Id budget = createReason('Budget client', 2);
        Id concurrence = createReason('Concurrence', 1);
        selectReasons(derogation.Id, new List<Id>{ budget, concurrence });
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(2, items[0].reasonLabels.size());
            System.assertEquals('Concurrence', items[0].reasonLabels[0]);
            System.assertEquals('Budget client', items[0].reasonLabels[1]);
            System.assertEquals('Contexte concurrentiel tendu', items[0].requesterReason);
        }
    }

    /** Session 216 : deux motifs sans commentaire. */
    @IsTest
    static void testListDerogations_reasonLabels_twoReasonsWithoutComment() {
        AR_Derogation__c derogation = getPendingDerogation();
        setRequesterReason(derogation.Id, null);
        selectReasons(derogation.Id, new List<Id>{ createReason('Concurrence', 1), createReason('Budget client', 2) });
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(2, items[0].reasonLabels.size());
            System.assertEquals(null, items[0].requesterReason);
        }
    }

    /** Session 216 : le contexte du panneau de décision porte les mêmes libellés, dans le même ordre. */
    @IsTest
    static void testGetContext_reasonLabels_orderedAndReadByValidator() {
        AR_Derogation__c derogation = getPendingDerogation();
        Id matrixId = getMatrix().Id;
        selectReasons(derogation.Id, new List<Id>{ createReason('Budget client', 2), createReason('Concurrence', 1) });
        User holder = AR_TestPersona.manager();

        System.runAs(holder) {
            AR_DerogationService.DerogationContext ctx = AR_DerogationService.getContext(matrixId);
            System.assertEquals(2, ctx.reasonLabels.size());
            System.assertEquals('Concurrence', ctx.reasonLabels[0]);
            System.assertEquals('Budget client', ctx.reasonLabels[1]);
            System.assertEquals('Contexte concurrentiel tendu', ctx.requesterReason);
        }
    }

    @IsTest
    static void testCountPendingDerogations_countsOnlyEnAttente() {
        System.assertEquals(1, AR_DerogationService.countPendingDerogations());

        makeCurrentUserValidator();
        AR_DerogationService.decide(getPendingDerogation().Id, 'Acceptée', 'OK.');

        System.assertEquals(0, AR_DerogationService.countPendingDerogations());
    }

    /**
     * Session 43 : converti en deux personas distincts (plus de manipulation de l'utilisateur
     * exécutant les tests) — chaque System.runAs sur un utilisateur différent est de toute façon un
     * contexte frais pour FeatureManagement.checkPermission(), sans artefact de cache à contourner.
     */
    @IsTest
    static void testIsCurrentUserValidator_reflectsPermissionSetAssignment() {
        User withoutPermission = AR_TestPersona.sansHabilitation();
        System.runAs(withoutPermission) {
            System.assertEquals(false, AR_DerogationService.isCurrentUserValidator());
        }

        User holder = AR_TestPersona.valideur();
        System.runAs(holder) {
            System.assertEquals(true, AR_DerogationService.isCurrentUserValidator());
        }
    }

    @IsTest
    static void testGetCurrentUserIdentity_returnsNameAndJobTitle() {
        // Purement informatif (en-tête "Connecté : Nom (poste)") : sans rapport avec l'habilitation
        // depuis la session 40, donc positionné directement ici plutôt que via makeCurrentUserValidator().
        update new User(Id = UserInfo.getUserId(), TP_Job_Title__c = 'Directeur d\'Activité');

        AR_DerogationService.CurrentUserIdentity identity = AR_DerogationService.getCurrentUserIdentity();

        System.assertEquals(UserInfo.getName(), identity.name);
        System.assertEquals('Directeur d\'Activité', identity.jobTitle);
    }

    @IsTest
    static void testGetContext_returnsMatrixAndDerogationDetails() {
        AR_Price_Matrix__c matrix = getMatrix();

        AR_DerogationService.DerogationContext ctx = AR_DerogationService.getContext(matrix.Id);

        System.assertNotEquals(null, ctx.derogationId);
        System.assertEquals('En attente', ctx.decision);
        System.assertEquals('below_floor', ctx.corridorSegment);
        System.assertEquals('Contexte concurrentiel tendu', ctx.requesterReason);
        System.assertEquals(-45, ctx.gapVsFloor); // 205 - 250
        System.assertEquals(-62, ctx.gapVsTarget); // 205 - 267
    }

    @IsTest
    static void testDecide_accept_freezesPerimeter_unchangedWhenPositionChanges() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();
        AR_Price_Matrix__c m = [SELECT AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
        update new cxsrec__cxsPosition__c(Id = m.AR_Position__c, TP_P_rim_tre__c = 'NEO');

        Test.startTest();
        AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Accord donné.');
        Test.stopTest();

        update new cxsrec__cxsPosition__c(Id = m.AR_Position__c, TP_P_rim_tre__c = 'NEO/NORD');
        System.assertEquals('NEO', [SELECT AR_Perimeter__c FROM AR_Price_Matrix__c LIMIT 1].AR_Perimeter__c);
    }

    @IsTest
    static void testDecide_refuse_doesNotFreezePerimeter() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();
        AR_Price_Matrix__c m = [SELECT AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
        update new cxsrec__cxsPosition__c(Id = m.AR_Position__c, TP_P_rim_tre__c = 'NEO');

        Test.startTest();
        AR_DerogationService.decide(derogation.Id, 'Refusée', 'Marge insuffisante.');
        Test.stopTest();

        System.assertEquals(null, [SELECT AR_Perimeter__c FROM AR_Price_Matrix__c LIMIT 1].AR_Perimeter__c);
    }

    @IsTest
    static void testDecide_accept_setsStatusAndSnapshotAndEffectiveValidator() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();

        // Test.startTest() réinitialise les limites de gouverneur : la baseline email doit être
        // mesurée à l'intérieur du bloc startTest/stopTest, jamais avant.
        Test.startTest();
        AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Contexte client exceptionnel, accord donné.');
        System.assert(Limits.getEmailInvocations() > 0, 'Le résultat de la dérogation doit déclencher un envoi email');
        Test.stopTest();

        AR_Derogation__c reloaded = [SELECT AR_Decision__c, AR_Effective_Validator__c, AR_Selected_Validator__c, AR_Validator_Comment__c, AR_Decided_At__c FROM AR_Derogation__c WHERE Id = :derogation.Id];
        System.assertEquals('Acceptée', reloaded.AR_Decision__c);
        System.assertEquals(UserInfo.getUserId(), reloaded.AR_Effective_Validator__c);
        System.assertNotEquals(null, reloaded.AR_Decided_At__c);

        AR_Price_Matrix__c matrix = [SELECT AR_Status__c, AR_Version_Number__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals('Validée par dérogation', matrix.AR_Status__c);
        System.assertEquals(1, matrix.AR_Version_Number__c);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Matrix_Version__c]);
    }

    @IsTest
    static void testDecide_reject_setsStatusRefusee() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();

        AR_DerogationService.decide(derogation.Id, 'Refusée', 'Marge trop faible, pas d\'accord possible.');

        AR_Price_Matrix__c matrix = [SELECT AR_Status__c FROM AR_Price_Matrix__c LIMIT 1];
        System.assertEquals('Refusée', matrix.AR_Status__c);
        System.assertEquals('Refusée', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testDecide_nonValidator_throws() {
        AR_Derogation__c derogation = getPendingDerogation();
        User withoutPermission = AR_TestPersona.sansHabilitation();

        Boolean threw = false;
        System.runAs(withoutPermission) {
            try {
                AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Commentaire.');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un utilisateur sans AR_Approve_Derogation ne doit pas pouvoir décider');
        System.assertEquals('En attente', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testDecide_missingComment_throws() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();

        Boolean threw = false;
        try {
            AR_DerogationService.decide(derogation.Id, 'Acceptée', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Le commentaire est obligatoire');
    }

    @IsTest
    static void testDecide_alreadyDecided_throws() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();
        AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Premier traitement.');

        Boolean threw = false;
        try {
            AR_DerogationService.decide(derogation.Id, 'Refusée', 'Second traitement, ne doit pas passer.');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Une dérogation ne se traite qu\'une seule fois');
        System.assertEquals('Acceptée', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testDecide_effectiveValidatorMayDifferFromSelected() {
        // Le valideur sélectionné (setup) est l'utilisateur courant ; on vérifie que les deux champs
        // sont bien distincts en base (sélectionné = valeur d'origine, effectif = décideur réel),
        // même quand il s'agit du même utilisateur — les deux champs sont conservés indépendamment.
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();

        AR_DerogationService.decide(derogation.Id, 'Acceptée', 'OK.');

        AR_Derogation__c reloaded = [SELECT AR_Selected_Validator__c, AR_Effective_Validator__c FROM AR_Derogation__c WHERE Id = :derogation.Id];
        System.assertEquals(UserInfo.getUserId(), reloaded.AR_Selected_Validator__c);
        System.assertEquals(UserInfo.getUserId(), reloaded.AR_Effective_Validator__c);
    }

    @IsTest
    static void testMatrixLock_directEditAfterDecision_isBlocked() {
        System.runAs(AR_TestPersona.francais()) {
            makeCurrentUserValidator();
            AR_Derogation__c derogation = getPendingDerogation();
            AR_DerogationService.decide(derogation.Id, 'Acceptée', 'OK.');

            AR_Price_Matrix__c matrix = getMatrix();
            Boolean threw = false;
            try {
                update new AR_Price_Matrix__c(Id = matrix.Id, AR_Proposed_TJM__c = 999);
            } catch (DmlException e) {
                threw = true;
                System.assert(e.getMessage().contains('ne peut plus être modifiée'));
            }
            System.assert(threw, 'Une matrice Validée par dérogation ne doit plus être modifiable directement');
        }
    }

    @IsTest
    static void testDerogationLock_directEdit_isBlocked() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Derogation__c derogation = getPendingDerogation();

            Boolean threw = false;
            try {
                update new AR_Derogation__c(Id = derogation.Id, AR_Decision__c = 'Acceptée', AR_Validator_Comment__c = 'Contournement du service.');
            } catch (DmlException e) {
                threw = true;
                System.assert(e.getMessage().contains('traitement du valideur'));
            }
            System.assert(threw, 'AR_DerogationTrigger doit bloquer toute édition directe hors AR_DerogationService.decide()');
            System.assertEquals('En attente', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
        }
    }

    @IsTest
    static void testDerogationLock_delete_isBlocked() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Derogation__c derogation = getPendingDerogation();

            Boolean threw = false;
            try {
                delete derogation;
            } catch (DmlException e) {
                threw = true;
                System.assert(e.getMessage().contains('ne peut pas être supprimée'));
            }
            System.assert(threw, 'AR_DerogationTrigger doit bloquer la suppression directe d\'une dérogation');
            System.assertEquals(1, [SELECT COUNT() FROM AR_Derogation__c WHERE Id = :derogation.Id]);
        }
    }

    /**
     * Session 40 — trois tests Apex sous System.runAs (exigence de vérification du prompt de
     * session) : un porteur de AR_Pricing_Validator, un porteur du second permission set habilité à
     * décider, un utilisateur sans aucun des deux. Contrairement à l'accès aux classes Apex (session
     * 37), FeatureManagement EST évalué sous runAs — ces tests sont donc réels et valent preuve, pas
     * seulement une simulation. Remplace testThreeProfiles_endToEnd_addressedVisibilityAndSharingGap
     * (session 33), dont l'essentiel (hasSharingGap, le diagnostic de partage) a disparu avec le
     * mécanisme bancal qu'il rattrapait — le partage (viewAllRecords sur
     * AR_Price_Matrix__c/AR_Derogation__c) reste néanmoins vérifié ici, via le même appariement que
     * scripts/check-validator-permission-pairing.js (AR_Pricing_Validator/_Manager accordent déjà les
     * deux ensemble depuis la session 42). Personas construites via AR_TestPersona (session 41) —
     * remplace la fabrique locale newStandardUser/assignPermissionSet, désormais partagée avec
     * AR_UserJourneyTest plutôt que recopiée. Session 43 : le second porteur est AR_Pricing_Manager,
     * successeur non-administratif de l'ancien permission set d'administration unique, supprimé cette
     * session — cf. docs/43-purge-pricing-admin-et-tests-independants.md.
     */
    @IsTest
    static void testRunAs_validatorPermissionSetHolder_canDecideAndSeesQueue() {
        // Un valideur ne voit la dérogation que s'il est dans la chaîne du propriétaire.
        User holder = AR_TestPersona.valideur();
        AR_Derogation__c derogation = derogationOwnedBy(AR_TestPersona.bm(), null, holder);
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = derogation.Id, AR_Selected_Validator__c = holder.Id);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Test.startTest();
        System.runAs(holder) {
            System.assertEquals(true, AR_DerogationService.isCurrentUserValidator(), 'AR_Pricing_Validator accorde AR_Approve_Derogation');
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(1, items.size(), 'AR_Pricing_Validator dans la chaîne du propriétaire voit la file');
            System.assertEquals(true, items[0].isAddressedToCurrentUser, 'Valideur sélectionné = destinataire');

            AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Décidé par un porteur de AR_Pricing_Validator.');
        }
        Test.stopTest();

        System.assertEquals('Acceptée', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testRunAs_managerPermissionSetHolder_canDecideAndSeesQueue() {
        AR_Derogation__c derogation = getPendingDerogation();
        User holder = AR_TestPersona.manager();

        Test.startTest();
        System.runAs(holder) {
            System.assertEquals(true, AR_DerogationService.isCurrentUserValidator(), 'AR_Pricing_Manager accorde aussi AR_Approve_Derogation');
            List<AR_DerogationService.DerogationListItem> items = AR_DerogationService.listDerogations();
            System.assertEquals(1, items.size(), 'AR_Pricing_Manager donne accès (viewAllRecords) à la file');
            System.assertEquals(false, items[0].isAddressedToCurrentUser, 'Pas le valideur sélectionné (setup par défaut) : visible, pas adressée');

            AR_DerogationService.decide(derogation.Id, 'Refusée', 'Décidé par un porteur de AR_Pricing_Manager.');
        }
        Test.stopTest();

        System.assertEquals('Refusée', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testRunAs_userWithoutPermission_cannotDecideAndSeesNothing() {
        AR_Derogation__c derogation = getPendingDerogation();
        // Intentionnellement AR_Pricing_User seul : aucune assignation AR_Pricing_Validator/_Manager.
        User withoutPermission = AR_TestPersona.bm();

        Test.startTest();
        System.runAs(withoutPermission) {
            System.assertEquals(false, AR_DerogationService.isCurrentUserValidator(), 'AR_Pricing_User seul n\'accorde pas AR_Approve_Derogation');
            System.assertEquals(
                0,
                AR_DerogationService.listDerogations().size(),
                'listDerogations() ne renvoie rien à un non-habilité, même si l\'objet est lisible (session 40 §1)'
            );

            Boolean threw = false;
            try {
                AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Ne doit jamais passer.');
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw, 'decide() doit refuser un utilisateur sans AR_Approve_Derogation');
        }
        Test.stopTest();

        System.assertEquals(
            'En attente',
            [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c,
            'Le refus de decide() ne doit laisser aucune trace en base'
        );
    }

    /** Session 33 §2 : le bandeau de verrouillage post-décision a besoin de ces trois informations,
     * déjà en base mais jusqu'ici non exposées par getContext(). */
    @IsTest
    static void testGetContext_afterDecision_exposesEffectiveValidatorDecidedAtAndComment() {
        makeCurrentUserValidator();
        AR_Derogation__c derogation = getPendingDerogation();
        AR_DerogationService.decide(derogation.Id, 'Refusée', 'Marge trop faible pour ce contexte.');

        AR_DerogationService.DerogationContext ctx = AR_DerogationService.getContext(getMatrix().Id);

        System.assertEquals('Refusée', ctx.decision);
        System.assertEquals(UserInfo.getName(), ctx.effectiveValidatorName);
        System.assertNotEquals(null, ctx.decidedAt);
        System.assertEquals('Marge trop faible pour ce contexte.', ctx.validatorComment);
    }

    // === Session 136, décision d'Alexis du 02/10/2026 : valider exige la permission AR_Approve_Derogation ===
    // La chaîne DA/DD/Directeur sert à proposer et à escalader, jamais à autoriser : les tests de la
    // session 79 qui affirmaient le contraire (« le DA du créateur peut voir/décider sans permission »)
    // sont remplacés par les tests ci-dessous, qui affirment la règle inverse.

    /** Matrice + dérogation en attente appartenant à `owner`, avec `da` / `directeur` posés sur son profil. */
    private static AR_Price_Matrix__c matrixOwnedBy(User owner, User da, User directeur) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = owner.Id, TP_DA__c = da == null ? null : da.Id, TP_Directeur__c = directeur == null ? null : directeur.Id);
        }
        AR_Price_Matrix__c baseMatrix = getMatrix();
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            OwnerId = owner.Id,
            AR_Position__c = baseMatrix.AR_Position__c,
            AR_Status__c = 'En dérogation',
            AR_Proposed_TJM__c = 400,
            AR_Currency__c = 'EUR',
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA')
        );
        insert matrix;
        return matrix;
    }

    private static AR_Derogation__c derogationOwnedBy(User owner, User da, User directeur) {
        AR_Price_Matrix__c matrix = matrixOwnedBy(owner, da, directeur);
        AR_Derogation__c derogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = owner.Id,
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        insert derogation;
        return derogation;
    }

    private static void assertDecisionRefused(User who, Id derogationId) {
        String message;
        System.runAs(who) {
            try {
                AR_DerogationService.decide(derogationId, 'Acceptée', 'Tentative sans permission');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        System.assertNotEquals(null, message, 'Sans AR_Approve_Derogation, decide() doit refuser (décision 1, 02/10/2026)');
        System.assert(message.contains('Approuver les dérogations'), 'Message lisible attendu, reçu : ' + message);
        System.assertEquals('En attente', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogationId].AR_Decision__c, 'La dérogation ne doit pas avoir été traitée');
    }

    @IsTest
    static void testListDerogations_daWithoutPermission_seesNothing() {
        User da = AR_TestPersona.bm();
        User owner = AR_TestPersona.bm();
        derogationOwnedBy(owner, da, null);

        Test.startTest();
        System.runAs(da) {
            System.assertEquals(false, AR_DerogationService.isCurrentUserValidator(), 'Être DA ne donne pas la permission');
            System.assertEquals(0, AR_DerogationService.listDerogations().size(), 'Un DA sans permission ne voit pas la file');
            System.assertEquals(0, AR_DerogationService.countPendingDerogations(), 'Ni le badge');
        }
        Test.stopTest();
    }

    @IsTest
    static void testDecide_daWithoutPermission_isRefused() {
        User da = AR_TestPersona.bm();
        User owner = AR_TestPersona.bm();
        AR_Derogation__c derogation = derogationOwnedBy(owner, da, null);
        assertDecisionRefused(da, derogation.Id);
    }

    @IsTest
    static void testDecide_directeurWithoutPermission_isRefused() {
        User directeur = AR_TestPersona.bm();
        User owner = AR_TestPersona.bm();
        AR_Derogation__c derogation = derogationOwnedBy(owner, null, directeur);
        assertDecisionRefused(directeur, derogation.Id);
    }

    @IsTest
    static void testDecide_directeurWithPermission_isAccepted() {
        User directeur = AR_TestPersona.valideur();
        User owner = AR_TestPersona.bm();
        AR_Derogation__c derogation = derogationOwnedBy(owner, null, directeur);

        Test.startTest();
        System.runAs(directeur) {
            AR_DerogationService.decide(derogation.Id, 'Acceptée', 'Directeur porteur de la permission.');
        }
        Test.stopTest();

        AR_Derogation__c updated = [SELECT AR_Decision__c, AR_Effective_Validator__c FROM AR_Derogation__c WHERE Id = :derogation.Id];
        System.assertEquals('Acceptée', updated.AR_Decision__c);
        System.assertEquals(directeur.Id, updated.AR_Effective_Validator__c);
    }

    @IsTest
    static void testIsCurrentUserAuthorizedFor_followsPermissionOnly() {
        User daWithout = AR_TestPersona.bm();
        User holder = AR_TestPersona.valideur();
        User outsider = AR_TestPersona.valideur();
        User owner = AR_TestPersona.bm();
        // Le porteur de la permission doit aussi être dans la chaîne (TP_Directeur__c du propriétaire).
        AR_Derogation__c derogation = derogationOwnedBy(owner, daWithout, holder);

        Boolean daAuthorized;
        Boolean holderAuthorized;
        Boolean outsiderAuthorized;
        System.runAs(daWithout) {
            daAuthorized = AR_DerogationService.isCurrentUserAuthorizedFor(derogation.Id);
        }
        System.runAs(holder) {
            holderAuthorized = AR_DerogationService.isCurrentUserAuthorizedFor(derogation.Id);
        }
        System.runAs(outsider) {
            outsiderAuthorized = AR_DerogationService.isCurrentUserAuthorizedFor(derogation.Id);
        }
        System.assertEquals(false, daAuthorized, 'DA sans permission : non autorisé');
        System.assertEquals(true, holderAuthorized, 'Porteur de la permission dans la chaîne : autorisé');
        System.assertEquals(false, outsiderAuthorized, 'Porteur de la permission hors chaîne : non autorisé ');
    }

    @IsTest
    static void testListDerogations_unrelatedUser_doesNotSeeDerogation() {
        // Crée un utilisateur sans relation avec la matrice
        User unrelated = createUserWithoutValidatorPermission('unrelated-session79');

        // Crée une matrice/dérogation sans rapport (utilise position du setup)
        AR_Price_Matrix__c baseMatrix = getMatrix();
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = baseMatrix.AR_Position__c,
            AR_Status__c = 'En dérogation',
            AR_Proposed_TJM__c = 400,
            AR_Currency__c = 'EUR',
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA')
        );
        insert matrix;

        AR_Derogation__c derogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()][0].Id,
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        insert derogation;

        // En tant qu'utilisateur sans rapport, ne doit pas voir
        Test.startTest();
        List<AR_DerogationService.DerogationListItem> derogations = new List<AR_DerogationService.DerogationListItem>();
        System.runAs(unrelated) {
            derogations = AR_DerogationService.listDerogations();
        }
        Test.stopTest();

        System.assertEquals(0, derogations.size(), 'Utilisateur sans rapport ne doit pas voir la dérogation');
    }

    private static User createUserWithoutValidatorPermission(String suffix) {
        User u = new User(
            LastName = 'NoPermission' + suffix,
            Email = 'noperm.' + suffix + '@example.com.invalid',
            Username = 'ar.noperm.' + suffix + '.' + Datetime.now().getTime() + '@example.com.invalid',
            Alias = suffix.substring(0, 4),
            IsActive = true,
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            ProfileId = AR_TestPersona.standardProfileId(),
            FederationIdentifier = 'ar.noperm.' + suffix + '.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    private static User createTestUserByFedId(String fedId) {
        List<User> users = [SELECT Id FROM User WHERE FederationIdentifier = :fedId LIMIT 1];
        if (!users.isEmpty()) {
            return users[0];
        }
        User u = new User(
            LastName = fedId,
            Email = fedId + '@example.com.invalid',
            Username = fedId + '@example.com.invalid',
            Alias = fedId.substring(0, Math.min(8, fedId.length())),
            IsActive = true,
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            ProfileId = AR_TestPersona.standardProfileId(),
            FederationIdentifier = fedId
        );
        insert u;
        return u;
    }

    // ====================================================================
    // Tests getPendingDerogationForCurrentUser (Session 112)
    // ====================================================================

    @IsTest
    static void testGetPendingDerogationForCurrentUser_withPermissionAndPendingDerogation() {
        makeCurrentUserValidator();
        AR_Price_Matrix__c matrix = getMatrix();

        AR_DerogationService.PendingDerogationDTO result = AR_DerogationService.getPendingDerogationForCurrentUser(matrix.Id);

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.derogationId);
        System.assertNotEquals(null, result.requesterName);
        System.assertNotEquals(null, result.requestedAt);
        System.assertEquals(UserInfo.getName(), result.selectedValidatorName);
        System.assertEquals(true, result.isAddressedToCurrentUser);
    }

    @IsTest
    static void testGetPendingDerogationForCurrentUser_daWithoutPermissionGetsNull() {
        // Session 136, décision 1 : l'ancien test (session 112) affirmait que le DA sans permission lit
        // la dérogation en attente ; la règle est inversée, pas de permission = pas d'encart.
        User da = AR_TestPersona.bm();
        User owner = AR_TestPersona.bm();
        AR_Derogation__c derogation = derogationOwnedBy(owner, da, null);
        Id matrixId = [SELECT AR_Price_Matrix__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Price_Matrix__c;

        System.runAs(da) {
            System.assertEquals(null, AR_DerogationService.getPendingDerogationForCurrentUser(matrixId));
        }
    }

    @IsTest
    static void testGetPendingDerogationForCurrentUser_nonAuthorizedUserReturnsNull() {
        User unauthorized = createUserWithoutValidatorPermission('Unauthorized');

        AR_Price_Matrix__c matrix = getMatrix();

        System.runAs(unauthorized) {
            AR_DerogationService.PendingDerogationDTO result = AR_DerogationService.getPendingDerogationForCurrentUser(matrix.Id);
            System.assertEquals(null, result);
        }
    }

    @IsTest
    static void testGetPendingDerogationForCurrentUser_acceptedDerogationReturnsNull() {
        makeCurrentUserValidator();
        AR_Price_Matrix__c matrix = getMatrix();
        AR_Derogation__c derogation = getPendingDerogation();

        // Accepter la dérogation
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(
                Id = derogation.Id,
                AR_Decision__c = 'Acceptée',
                AR_Effective_Validator__c = UserInfo.getUserId(),
                AR_Decided_At__c = System.now()
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        AR_DerogationService.PendingDerogationDTO result = AR_DerogationService.getPendingDerogationForCurrentUser(matrix.Id);

        System.assertEquals(null, result);
    }

    @IsTest
    static void testGetPendingDerogationForCurrentUser_twoDerogationsReturnsLatestPending() {
        makeCurrentUserValidator();
        AR_Price_Matrix__c matrix = getMatrix();
        AR_Derogation__c firstDerogation = getPendingDerogation();

        // Refuser la première
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(
                Id = firstDerogation.Id,
                AR_Decision__c = 'Refusée',
                AR_Effective_Validator__c = UserInfo.getUserId(),
                AR_Decided_At__c = System.now()
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        // Créer une deuxième dérogation en attente
        AR_Derogation__c secondDerogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = UserInfo.getUserId(),
            AR_Requester_Reason__c = 'Raison 2',
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now().addSeconds(1)
        );
        System.runAs(new User(Id = [SELECT OwnerId FROM AR_Price_Matrix__c WHERE Id = :matrix.Id].OwnerId)) {
            Database.insert(secondDerogation, AccessLevel.SYSTEM_MODE);
        }

        AR_DerogationService.PendingDerogationDTO result = AR_DerogationService.getPendingDerogationForCurrentUser(matrix.Id);

        System.assertNotEquals(null, result);
        System.assertEquals(secondDerogation.Id, result.derogationId);
    }

    @IsTest
    static void testGetPendingDerogationForCurrentUser_notAddressedToCurrentUserButAuthorized() {
        User validator1 = createTestUserByFedId('Validator1_112');
        User validator2 = createTestUserByFedId('Validator2_112');

        makeCurrentUserValidator();
        AR_Price_Matrix__c matrix = getMatrix();
        AR_Derogation__c derogation = getPendingDerogation();

        // Assigner à validator2, mais validator1 a la permission et peut aussi traiter
        reassignSelectedValidator(derogation.Id, validator2.Id);

        AR_DerogationService.PendingDerogationDTO result = AR_DerogationService.getPendingDerogationForCurrentUser(matrix.Id);

        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isAddressedToCurrentUser);
    }

    // === Ni le demandeur ni le propriétaire de la matrice ne statuent sur la dérogation ===

    /** Dérogation demandée PAR `requester` (CreatedById) sur une matrice appartenant à `owner`. */
    private static AR_Derogation__c derogationRequestedBy(User requester, User owner) {
        AR_Price_Matrix__c matrix = matrixOwnedBy(owner, null, requester);
        AR_Derogation__c derogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = requester.Id,
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        System.runAs(requester) {
            Database.insert(derogation, AccessLevel.SYSTEM_MODE);
        }
        return derogation;
    }

    /** Label résolu dans la langue de l'utilisateur qui reçoit le message (pas celle du lanceur de tests). */
    private static String ownRequestMessageAs(User who) {
        String expected;
        System.runAs(who) {
            expected = Label.AR_Msg_DRG_OwnRequest;
        }
        return expected;
    }

    private static String decideAndCatch(User who, Id derogationId) {
        String message;
        System.runAs(who) {
            try {
                AR_DerogationService.decide(derogationId, 'Acceptée', 'Tentative sur sa propre demande.');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    @IsTest
    static void testRunAs_requesterWithPermission_cannotDecideOwnRequest() {
        User holder = AR_TestPersona.valideur();
        AR_Derogation__c derogation = derogationRequestedBy(holder, AR_TestPersona.bm());

        String message = decideAndCatch(holder, derogation.Id);

        System.assertNotEquals(null, message, 'Le demandeur porteur de la permission doit être refusé');
        System.assertEquals(ownRequestMessageAs(holder), message);
        System.assertEquals('En attente', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);

        System.runAs(holder) {
            AR_DerogationService.DerogationListItem item = AR_DerogationService.listDerogations()[0];
            System.assertEquals(true, item.isOwnRequest);
            System.assertEquals(false, item.isAddressedToCurrentUser, 'Sa propre demande n\'est jamais « à traiter »');
            System.assertEquals(0, AR_DerogationService.countPendingDerogations(), 'Pas comptée dans le badge');
            System.assertEquals(null, AR_DerogationService.getPendingDerogationForCurrentUser(derogation.AR_Price_Matrix__c));
            System.assertEquals(true, AR_DerogationService.getContext(derogation.AR_Price_Matrix__c).isOwnRequest);
        }
    }

    @IsTest
    static void testRunAs_ownerWithPermission_cannotDecideOwnMatrix() {
        User holder = AR_TestPersona.valideur();
        AR_Derogation__c derogation = derogationOwnedBy(holder, null, null);

        System.assertEquals(ownRequestMessageAs(holder), decideAndCatch(holder, derogation.Id));
        System.assertEquals('En attente', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testRunAs_sameHolder_canDecideAnotherUsersRequest() {
        User holder = AR_TestPersona.valideur();
        AR_Derogation__c derogation = derogationOwnedBy(AR_TestPersona.bm(), null, holder);

        System.assertEquals(null, decideAndCatch(holder, derogation.Id), 'Sur la demande d\'un autre, la décision passe');
        System.assertEquals('Acceptée', [SELECT AR_Decision__c FROM AR_Derogation__c WHERE Id = :derogation.Id].AR_Decision__c);
    }

    @IsTest
    static void testSelectableValidator_requesterAndOwnerRefused() {
        User owner = AR_TestPersona.bm();
        AR_Derogation__c derogation = derogationOwnedBy(owner, null, null);
        Id matrixId = derogation.AR_Price_Matrix__c;
        User other = AR_TestPersona.valideur();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = owner.Id, TP_DA__c = other.Id);
        }

        AR_PricingMatrixService.requireSelectableValidator(matrixId, other.Id);

        for (Id forbidden : new List<Id>{ owner.Id, UserInfo.getUserId() }) {
            try {
                AR_PricingMatrixService.requireSelectableValidator(matrixId, forbidden);
                System.assert(false, 'Le propriétaire et le demandeur ne sont pas sélectionnables');
            } catch (AuraHandledException e) {
                System.assertEquals(Label.AR_Msg_DRG_OwnRequest, e.getMessage());
            }
        }
    }

    @IsTest
    static void testValidatorChain_excludesRequesterAndOwner_evenIfInChain() {
        User da = AR_TestPersona.bm();
        User directeur = AR_TestPersona.bm();
        User owner = AR_TestPersona.bm();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = owner.Id, TP_DA__c = da.Id, TP_Directeur__c = directeur.Id);
        }

        AR_ValidatorChain.Resolution all = AR_ValidatorChain.resolveForOwner(owner.Id);
        AR_ValidatorChain.Resolution withoutDa = AR_ValidatorChain.resolveForOwner(owner.Id, new Set<Id>{ da.Id });
        AR_ValidatorChain.Resolution none = AR_ValidatorChain.resolveForOwner(owner.Id, new Set<Id>{ da.Id, directeur.Id });

        System.assertEquals(2, all.validators.size());
        System.assertEquals(1, withoutDa.validators.size());
        System.assertEquals(directeur.Id, withoutDa.validators[0].Id);
        System.assertEquals(0, none.validators.size());
        System.assertNotEquals(null, none.blockedReason, 'Plus personne : message « aucun valideur » existant');
    }
}