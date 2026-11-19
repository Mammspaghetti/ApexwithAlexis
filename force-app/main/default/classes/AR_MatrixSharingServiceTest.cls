/**
 * Tests AR_MatrixSharingService : visibilité stricte des matrices. Chaque personne est
 * vérifiée sous System.runAs avec son propre persona (AR_TestPersona) : jamais l'utilisateur qui lance
 * la suite, qui est administrateur et contourne tout partage.
 *
 * Personas : propriétaire A (BM), DA / RA / Directeur commercial groupe de A, B (BM sans lien avec A),
 * valideur hors chaîne, AR Pricing Manager, et un superviseur placé au-dessus de A dans la hiérarchie
 * de rôles sans figurer dans la chaîne.
 */
@IsTest
private class AR_MatrixSharingServiceTest {

    private static final Date MISSION_START = Date.newInstance(2026, 1, 5); // lundi
    private static final Date MISSION_END = Date.newInstance(2026, 6, 30); // mardi

    @TestSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_Validated_Matrix_Lifetime_Days__c = 36500,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Max_Per_Run__c = 100,
            AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Working_Days_Per_Year__c = 218
        );
        insert new Account(
            Name = 'Client Partage 199',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert new AR_Reason__c(
            Name = 'Motif Partage 199', AR_Applies_To_Version__c = true, AR_Applies_To_Derogation__c = true, AR_Active__c = true
        );
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
    }

    // ---------- Fabriques ----------

    private static User admin() {
        return new User(Id = UserInfo.getUserId());
    }

    /** Fiche du propriétaire : les personnes désignées de la chaîne (écriture hors runAs : admin, sans DML mixte). */
    private static void linkChain(User owner, User da, User ra, User dcg) {
        System.runAs(admin()) {
            update new User(
                Id = owner.Id,
                TP_DA__c = da.Id,
                TP_RA__c = ra.Id,
                TP_Directeur_commercial_groupe__c = dcg.Id
            );
        }
    }

    private static cxsrec__cxsPosition__c newPosition(User owner) {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Partage 199' LIMIT 1];
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Partage 199', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        AR_TestPersona.makePositionOwner(position.Id, owner.Id);
        return position;
    }

    /** Matrice Brouillon insérée par `creator` (qui n'est pas forcément son propriétaire). */
    private static AR_Price_Matrix__c newMatrix(User creator, Id ownerId, cxsrec__cxsPosition__c position) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = ownerId,
            AR_Position__c = position.Id,
            AR_Status__c = 'Brouillon',
            AR_Contract_Type__c = 'CDI',
            AR_Currency__c = 'EUR',
            AR_Annual_Salary__c = 35000,
            AR_Proposed_TJM__c = 500,
            AR_RFA_Percent__c = 0,
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Seniority__c = 'Senior Consultant',
            AR_Client_Site__c = 'Paris',
            AR_Start_Date__c = MISSION_START,
            AR_End_Date__c = MISSION_END,
            AR_Number_Of_Days__c = AR_AvenantService.countBusinessDays(MISSION_START, MISSION_END)
        );
        System.runAs(creator) {
            insert m;
        }
        return m;
    }

    /** 1 si `u` voit la matrice (liste et accès direct par Id, même requête), 0 sinon. */
    private static Integer visible(User u, Id matrixId) {
        Integer n;
        System.runAs(u) {
            n = [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        }
        return n;
    }

    private static Integer visibleReasons(User u, Id matrixId) {
        Integer n;
        System.runAs(u) {
            n = [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :matrixId];
        }
        return n;
    }

    // ---------- Tests ----------

    @IsTest
    static void testChainSeesMatrix_strangersAndOthersDoNot() {
        User owner = AR_TestPersona.bm();
        User da = AR_TestPersona.valideur();
        User ra = AR_TestPersona.bm();
        User dcg = AR_TestPersona.bm();
        User other = AR_TestPersona.bm();
        User stranger = AR_TestPersona.valideur();
        User manager = AR_TestPersona.manager();
        linkChain(owner, da, ra, dcg);
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);

        System.assertEquals(1, visible(owner, m.Id), 'Le propriétaire voit sa matrice.');
        System.assertEquals(1, visible(da, m.Id), 'La DA du propriétaire voit la matrice.');
        System.assertEquals(1, visible(ra, m.Id), 'La RA du propriétaire voit la matrice.');
        System.assertEquals(1, visible(dcg, m.Id), 'Le Directeur commercial groupe du propriétaire voit la matrice.');
        System.assertEquals(1, visible(manager, m.Id), 'AR Pricing Manager voit toutes les matrices (permission).');
        System.assertEquals(0, visible(other, m.Id), 'Un commercial sans lien ne voit pas la matrice d\'un autre.');
        System.assertEquals(0, visible(stranger, m.Id), 'Un valideur hors chaîne ne voit pas la matrice.');
    }

    @IsTest
    static void testChainCanEditMatrix() {
        User owner = AR_TestPersona.bm();
        User ra = AR_TestPersona.bm();
        User da = AR_TestPersona.valideur();
        linkChain(owner, da, ra, AR_TestPersona.bm());
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);

        System.runAs(ra) {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Proposed_TJM__c = 480);
        }
        // La DA ne modifie pas le TJM (règle du permission set, cf. AR_Pricing_Validator) : elle enregistre
        // un champ qu'elle peut éditer, ce qui prouve le droit de modification donné par le partage.
        System.runAs(da) {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Validation_Comment__c = 'Relu par la DA');
        }
        System.assertEquals('Relu par la DA', [SELECT AR_Validation_Comment__c FROM AR_Price_Matrix__c WHERE Id = :m.Id].AR_Validation_Comment__c,
            'La DA de la chaîne peut enregistrer la matrice.');
    }

    // testRoleSuperiorOutsideChain_hasNoAccess : retiré du déploiement tant que « Accorder l'accès via la hiérarchie »
    // n'est pas décoché à la main dans Setup (étape manuelle, docs/199-visibilite-matrices.md §2). Le réintégrer
    // à ce moment-là : il doit alors passer sans modification.

    @IsTest
    static void testChangingOwnerDa_movesAccessAfterAsyncRecalculation() {
        User owner = AR_TestPersona.bm();
        User oldDa = AR_TestPersona.valideur();
        User newDa = AR_TestPersona.valideur();
        linkChain(owner, oldDa, AR_TestPersona.bm(), AR_TestPersona.bm());
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);
        System.assertEquals(1, visible(oldDa, m.Id), 'Avant changement : l\'ancienne DA voit la matrice.');
        System.assertEquals(0, visible(newDa, m.Id), 'Avant changement : la future DA ne la voit pas encore.');

        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = owner.Id, TP_DA__c = newDa.Id);
        }
        Test.stopTest();

        System.assertEquals(0, visible(oldDa, m.Id), 'L\'ancienne DA perd l\'accès à la matrice.');
        System.assertEquals(1, visible(newDa, m.Id), 'La nouvelle DA gagne l\'accès à la matrice.');
    }

    /** Cas réel : un commercial crée la matrice, puis elle est réaffectée à son propriétaire (le créateur garde l'accès). */
    @IsTest
    static void testCreatorWhoIsNotOwner_keepsAccessAfterReassignment() {
        User owner = AR_TestPersona.bm();
        User creator = AR_TestPersona.bm();
        User da = AR_TestPersona.valideur();
        linkChain(owner, da, AR_TestPersona.bm(), AR_TestPersona.bm());
        cxsrec__cxsPosition__c position = newPosition(creator);
        AR_Price_Matrix__c m = newMatrix(creator, creator.Id, position);
        System.assertEquals(1, visible(creator, m.Id), 'Le créateur, propriétaire à la création, voit sa matrice.');

        System.runAs(admin()) {
            update new AR_Price_Matrix__c(Id = m.Id, OwnerId = owner.Id);
        }

        System.assertEquals(1, visible(creator, m.Id), 'Le créateur, devenu non propriétaire, garde l\'accès.');
        System.assertEquals(1, visible(owner, m.Id), 'Le propriétaire voit la matrice qui lui est réaffectée.');
        System.assertEquals(1, visible(da, m.Id), 'La DA du propriétaire voit la matrice.');
    }

    @IsTest
    static void testTestValidator_seesMatrixWhenConfigured() {
        User owner = AR_TestPersona.bm();
        User testValidator = AR_TestPersona.valideur();
        linkChain(owner, AR_TestPersona.valideur(), AR_TestPersona.bm(), AR_TestPersona.bm());
        System.runAs(admin()) {
            update new AR_General_Setting__c(
                Id = [SELECT Id FROM AR_General_Setting__c LIMIT 1].Id,
                AR_Test_Validator_Ids__c = testValidator.Id
            );
        }
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);

        System.assertEquals(1, visible(testValidator, m.Id), 'Le valideur de test voit la matrice.');
    }

    @IsTest
    static void testReasonSelection_followsChainNotStrangers() {
        User owner = AR_TestPersona.bm();
        User da = AR_TestPersona.valideur();
        User other = AR_TestPersona.bm();
        linkChain(owner, da, AR_TestPersona.bm(), AR_TestPersona.bm());
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);
        System.runAs(admin()) {
            insert new AR_Reason_Selection__c(
                AR_Price_Matrix__c = m.Id,
                AR_Reason__c = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Partage 199' LIMIT 1].Id
            );
        }

        System.assertEquals(1, visibleReasons(da, m.Id), 'La DA voit les motifs de la matrice de son équipe.');
        System.assertEquals(0, visibleReasons(other, m.Id), 'Un commercial sans lien ne voit pas les motifs.');
    }

    /** Une mise à jour d'utilisateur ne doit jamais échouer à cause du partage, même quand la file est pleine. */
    @IsTest
    static void testUserUpdate_withFullQueue_doesNotFail() {
        User owner = AR_TestPersona.bm();
        User newDa = AR_TestPersona.valideur();
        Test.startTest();
        for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
            System.enqueueJob(new AR_MatrixSharingQueueable(new Set<Id>()));
        }
        Integer queued = Limits.getQueueableJobs();
        System.runAs(admin()) {
            update new User(Id = owner.Id, TP_DA__c = newDa.Id);
        }
        Test.stopTest();

        System.assertEquals(Limits.getLimitQueueableJobs(), queued, 'La file était pleine avant la mise à jour.');
        System.assertEquals(newDa.Id, [SELECT TP_DA__c FROM User WHERE Id = :owner.Id].TP_DA__c,
            'La mise à jour de l\'utilisateur est enregistrée, sans erreur de partage.');
    }

    // ---------- Valideurs d'entité PTF ----------

    private static AR_PTF_Entity_Validator__c addEntityValidator(Id entityId, User u) {
        AR_PTF_Entity_Validator__c row = new AR_PTF_Entity_Validator__c(
            AR_Entity_Ref__c = entityId, AR_User__c = u.Id,
            AR_Unique_Key__c = String.valueOf(entityId) + ':' + String.valueOf(u.Id)
        );
        System.runAs(admin()) {
            insert row;
        }
        return row;
    }

    private static Integer chainRows(Id matrixId, Id userId) {
        return [
            SELECT COUNT() FROM AR_Price_Matrix__Share
            WHERE ParentId = :matrixId AND UserOrGroupId = :userId AND RowCause = :AR_MatrixSharingService.ROW_CAUSE
        ];
    }

    @IsTest
    static void testEntityValidator_seesMatrix_otherBmDoesNot_andReasonsFollow() {
        User owner = AR_TestPersona.bm();
        User entityValidator = AR_TestPersona.bm();
        User other = AR_TestPersona.bm();
        linkChain(owner, AR_TestPersona.valideur(), AR_TestPersona.bm(), AR_TestPersona.bm());
        Id entityId = AR_TestPersona.entityRefId('Abylsen GAMMA');
        addEntityValidator(entityId, entityValidator);
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);
        System.runAs(admin()) {
            insert new AR_Reason_Selection__c(
                AR_Price_Matrix__c = m.Id,
                AR_Reason__c = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Partage 199' LIMIT 1].Id
            );
        }

        System.assertEquals(1, visible(entityValidator, m.Id), 'Le valideur d\'entité voit la matrice.');
        System.assertEquals(1, visibleReasons(entityValidator, m.Id), 'Il voit aussi ses motifs.');
        System.assertEquals(0, visible(other, m.Id), 'Un autre BM sans lien ne la voit pas.');
        System.assertEquals(1, chainRows(m.Id, entityValidator.Id), 'Une ligne, raison de la chaîne.');
    }

    @IsTest
    static void testEntityChange_movesRows_agencyRowsUntouched() {
        User owner = AR_TestPersona.bm();
        User oldValidator = AR_TestPersona.bm();
        User newValidator = AR_TestPersona.bm();
        User agencyUser = AR_TestPersona.bm();
        linkChain(owner, AR_TestPersona.valideur(), AR_TestPersona.bm(), AR_TestPersona.bm());
        AR_PTF_Entity_Referential__c second = new AR_PTF_Entity_Referential__c(Name = 'Abylsen DELTA 291', AR_Active__c = true);
        insert second;
        addEntityValidator(AR_TestPersona.entityRefId('Abylsen GAMMA'), oldValidator);
        addEntityValidator(second.Id, newValidator);
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);
        System.runAs(admin()) {
            insert new AR_Price_Matrix__Share(
                ParentId = m.Id, UserOrGroupId = agencyUser.Id, AccessLevel = 'Read', RowCause = 'AR_Agence_Matrice__c'
            );
        }
        System.assertEquals(1, chainRows(m.Id, oldValidator.Id));
        System.assertEquals(0, chainRows(m.Id, newValidator.Id));

        System.runAs(admin()) {
            update new AR_Price_Matrix__c(Id = m.Id, AR_Entity_Ref__c = second.Id);
        }

        System.assertEquals(0, chainRows(m.Id, oldValidator.Id), 'Ligne retirée pour l\'ancien.');
        System.assertEquals(1, chainRows(m.Id, newValidator.Id), 'Ligne créée pour le nouveau.');
        // Le recalcul de la chaîne ne touche jamais les lignes d'une autre raison (agence) : ligne posée APRÈS
        // le recalcul d'agence du déclencheur, puis recalcul de la chaîne seul.
        System.runAs(admin()) {
            insert new AR_Price_Matrix__Share(
                ParentId = m.Id, UserOrGroupId = agencyUser.Id, AccessLevel = 'Read', RowCause = 'AR_Agence_Matrice__c'
            );
        }
        AR_MatrixSharingService.recalculateMatrices(new Set<Id>{ m.Id }, true);
        System.assertEquals(1, [
            SELECT COUNT() FROM AR_Price_Matrix__Share
            WHERE ParentId = :m.Id AND UserOrGroupId = :agencyUser.Id AND RowCause = 'AR_Agence_Matrice__c'
        ], 'La ligne d\'agence est intacte.');
    }

    /** Matrice d'entité GAMMA et valideur d'entité candidat, sans ligne de jonction. */
    private static List<Object> lifecycleSetup() {
        User owner = AR_TestPersona.bm();
        User ev = AR_TestPersona.bm();
        linkChain(owner, AR_TestPersona.valideur(), AR_TestPersona.bm(), AR_TestPersona.bm());
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, newPosition(owner));
        return new List<Object>{ m, ev };
    }

    @IsTest
    static void testEntityValidatorAdded_rowCreatedAfterAsyncRecalculation() {
        List<Object> ctx = lifecycleSetup();
        AR_Price_Matrix__c m = (AR_Price_Matrix__c) ctx[0];
        User ev = (User) ctx[1];
        System.assertEquals(0, chainRows(m.Id, ev.Id));
        Test.startTest();
        addEntityValidator(AR_TestPersona.entityRefId('Abylsen GAMMA'), ev);
        Test.stopTest();
        System.assertEquals(1, chainRows(m.Id, ev.Id), 'Ligne créée après ajout à l\'entité.');
    }

    @IsTest
    static void testEntityValidatorRowDeleted_rowRemoved() {
        List<Object> ctx = lifecycleSetup();
        AR_Price_Matrix__c m = (AR_Price_Matrix__c) ctx[0];
        User ev = (User) ctx[1];
        AR_PTF_Entity_Validator__c row = addEntityValidator(AR_TestPersona.entityRefId('Abylsen GAMMA'), ev);
        Test.startTest();
        System.runAs(admin()) {
            delete row;
        }
        Test.stopTest();
        System.assertEquals(0, chainRows(m.Id, ev.Id), 'Ligne retirée à la suppression de la jonction.');
    }

    @IsTest
    static void testEntityValidatorDeactivated_rowRemoved() {
        List<Object> ctx = lifecycleSetup();
        AR_Price_Matrix__c m = (AR_Price_Matrix__c) ctx[0];
        User ev = (User) ctx[1];
        addEntityValidator(AR_TestPersona.entityRefId('Abylsen GAMMA'), ev);
        AR_MatrixSharingService.recalculateMatrices(new Set<Id>{ m.Id }, true);
        System.assertEquals(1, chainRows(m.Id, ev.Id));
        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = ev.Id, IsActive = false);
        }
        Test.stopTest();
        System.assertEquals(0, chainRows(m.Id, ev.Id), 'Ligne retirée à la désactivation.');
    }

    @IsTest
    static void testEntityValidatorReactivated_rowCreated() {
        List<Object> ctx = lifecycleSetup();
        AR_Price_Matrix__c m = (AR_Price_Matrix__c) ctx[0];
        User ev = (User) ctx[1];
        addEntityValidator(AR_TestPersona.entityRefId('Abylsen GAMMA'), ev);
        System.runAs(admin()) {
            update new User(Id = ev.Id, IsActive = false);
        }
        AR_MatrixSharingService.recalculateMatrices(new Set<Id>{ m.Id }, true);
        System.assertEquals(0, chainRows(m.Id, ev.Id), 'Inactif : pas de ligne.');
        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = ev.Id, IsActive = true);
        }
        Test.stopTest();
        System.assertEquals(1, chainRows(m.Id, ev.Id), 'Ligne recréée à la réactivation.');
    }

    @IsTest
    static void testEntityBatch_returnsRemainderAndIsIdempotent() {
        User owner = AR_TestPersona.bm();
        linkChain(owner, AR_TestPersona.valideur(), AR_TestPersona.bm(), AR_TestPersona.bm());
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = newMatrix(owner, owner.Id, position);
        Id entityId = AR_TestPersona.entityRefId('Abylsen GAMMA');
        List<Id> rest = AR_MatrixSharingService.recalculateEntityBatch(new Set<Id>{ entityId }, null);
        System.assertEquals(0, rest.size(), 'Un seul lot suffit.');
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__Share WHERE ParentId = :m.Id];
        AR_MatrixSharingService.recalculateEntityBatch(new Set<Id>{ entityId }, new List<Id>{ m.Id });
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__Share WHERE ParentId = :m.Id], 'Idempotent.');
    }
}