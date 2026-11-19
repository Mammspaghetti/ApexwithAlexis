/**
 * Tests AR_AgencySharingService (session 282) : matrices et PTF visibles en lecture par l'agence du propriétaire.
 * Chaque vérification d'accès se fait sous System.runAs avec un persona (AR_TestPersona), jamais avec
 * l'administrateur qui lance la suite. Les écritures sur User/Group/GroupMember (objets de configuration) se font
 * dans un System.runAs administrateur, séparées des écritures de partage (DML mixte).
 */
@IsTest
private class AR_AgencySharingServiceTest {

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
            Name = 'Client Agence 282',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert new AR_Reason__c(
            Name = 'Motif Agence 282', AR_Applies_To_Version__c = true, AR_Applies_To_Derogation__c = true, AR_Active__c = true
        );
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
    }

    // ---------- Fabriques ----------

    private static User admin() {
        return new User(Id = UserInfo.getUserId());
    }

    /** Agence posée par l'administrateur, puis appartenance aux groupes alignée (ce que fait le travail asynchrone). */
    private static void setAgencies(Map<User, String> agencies) {
        System.runAs(admin()) {
            List<User> updates = new List<User>();
            Set<Id> ids = new Set<Id>();
            for (User u : agencies.keySet()) {
                updates.add(new User(Id = u.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = agencies.get(u)));
                ids.add(u.Id);
            }
            update updates;
            AR_AgencySharingService.syncMemberships(ids);
        }
    }

    private static cxsrec__cxsPosition__c newPosition(User owner) {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Agence 282' LIMIT 1];
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Agence 282', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        AR_TestPersona.makePositionOwner(position.Id, owner.Id);
        return position;
    }

    private static AR_Price_Matrix__c newMatrix(User owner) {
        cxsrec__cxsPosition__c position = newPosition(owner);
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = owner.Id,
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
        System.runAs(owner) {
            insert m;
        }
        return m;
    }

    private static AR_PTF_Document__c newPtf(AR_Price_Matrix__c m) {
        AR_PTF_Document__c ptf = new AR_PTF_Document__c(
            AR_Price_Matrix__c = m.Id,
            AR_Position__c = m.AR_Position__c,
            AR_Reference__c = 'PTF-282-' + Datetime.now().getTime(),
            AR_Version_Number__c = 1,
            AR_Generated_At__c = System.now(),
            AR_Generation_Status__c = 'Généré'
        );
        insert ptf;
        return ptf;
    }

    private static Integer visible(User u, Id matrixId) {
        Integer n;
        System.runAs(u) {
            n = [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        }
        return n;
    }

    private static UserRecordAccess accessOf(User u, Id recordId) {
        return [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :u.Id AND RecordId = :recordId
        ];
    }

    private static Integer agencyShares(Id matrixId) {
        return [
            SELECT COUNT() FROM AR_Price_Matrix__Share
            WHERE ParentId = :matrixId AND RowCause = :AR_AgencySharingService.ROW_CAUSE
        ];
    }

    private static Id groupOf(String agency) {
        return [SELECT Id FROM Group WHERE DeveloperName = :AR_AgencySharingService.groupDeveloperName(agency)].Id;
    }

    // ---------- Tests ----------

    @IsTest
    static void testColleagueReadsMatrixPtfAndFile_cannotEdit_otherAgencySeesNothing() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        User other = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ owner => 'Paris', colleague => 'Paris', other => 'Lyon' });

        AR_Price_Matrix__c m = newMatrix(owner);
        AR_PTF_Document__c ptf = newPtf(m);
        ContentVersion cv = new ContentVersion(
            Title = 'PTF 282', PathOnClient = 'PTF-282.pdf', VersionData = Blob.valueOf('%PDF-1.4'), FirstPublishLocationId = m.Id
        );
        insert cv;
        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        AR_Price_Matrix__Share share = [
            SELECT UserOrGroupId, AccessLevel FROM AR_Price_Matrix__Share
            WHERE ParentId = :m.Id AND RowCause = :AR_AgencySharingService.ROW_CAUSE
        ];
        System.assertEquals(groupOf('Paris'), share.UserOrGroupId, 'Une ligne vers le groupe de l’agence du propriétaire.');
        System.assertEquals('Read', share.AccessLevel, 'Jamais Modification.');

        System.assertEquals(1, visible(colleague, m.Id), 'Le collègue de la même agence voit la matrice.');
        UserRecordAccess ura = accessOf(colleague, m.Id);
        System.assertEquals(true, ura.HasReadAccess);
        System.assertEquals(false, ura.HasEditAccess, 'Lecture seule pour le collègue.');
        System.runAs(colleague) {
            System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :m.Id], 'Il voit la PTF.');
            System.assertEquals(1, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :documentId],
                'Il voit le PDF lié à la matrice.');
            Boolean refused = false;
            try {
                update new AR_Price_Matrix__c(Id = m.Id, AR_Proposed_TJM__c = 480);
            } catch (DmlException e) {
                refused = true;
            }
            System.assert(refused, 'Le collègue ne peut pas modifier la matrice.');
            refused = false;
            try {
                update new AR_PTF_Document__c(Id = ptf.Id, AR_Modification_Detail__c = 'essai');
            } catch (DmlException e) {
                refused = true;
            }
            System.assert(refused, 'Le collègue ne peut pas modifier la PTF.');
        }
        System.assertEquals(0, visible(other, m.Id), 'Une autre agence ne voit rien.');
        System.runAs(other) {
            System.assertEquals(0, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :m.Id]);
        }
    }

    @IsTest
    static void testMatrixInput_exposesReadOnlyForTheColleague_andEditForTheOwner() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ owner => 'Paris', colleague => 'Paris' });
        AR_Price_Matrix__c m = newMatrix(owner);

        AR_PricingMatrixService.MatrixInput asColleague;
        AR_PricingMatrixService.MatrixInput asOwner;
        System.runAs(colleague) {
            asColleague = AR_PricingMatrixService.getMatrixInput(m.Id);
        }
        System.runAs(owner) {
            asOwner = AR_PricingMatrixService.getMatrixInput(m.Id);
        }
        String ownerName = [SELECT Name FROM User WHERE Id = :owner.Id].Name;
        System.assertEquals(false, asColleague.canEdit, 'Collègue : lecture seule (UserRecordAccess).');
        System.assertEquals(ownerName, asColleague.ownerName, 'Nom du propriétaire pour le bandeau.');
        System.assertEquals(true, asOwner.canEdit, 'Propriétaire : modification.');
    }

    @IsTest
    static void testOwnerWithoutAgency_noAgencyShare() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ colleague => 'Paris' });
        AR_Price_Matrix__c m = newMatrix(owner);

        System.assertEquals(0, agencyShares(m.Id), 'Propriétaire sans agence : aucune ligne d’agence.');
        System.assertEquals(0, visible(colleague, m.Id));
    }

    @IsTest
    static void testChainDaKeepsEditAccess() {
        User owner = AR_TestPersona.bm();
        User da = AR_TestPersona.valideur();
        setAgencies(new Map<User, String>{ owner => 'Paris', da => 'Paris' });
        System.runAs(admin()) {
            update new User(Id = owner.Id, TP_DA__c = da.Id);
        }
        AR_Price_Matrix__c m = newMatrix(owner);

        System.assertEquals(1, agencyShares(m.Id), 'La ligne d’agence est posée en plus de la chaîne.');
        System.assertEquals(true, accessOf(da, m.Id).HasEditAccess, 'La DA garde la modification (chaîne prioritaire).');
        System.assertEquals(1, [
            SELECT COUNT() FROM AR_Price_Matrix__Share
            WHERE ParentId = :m.Id AND RowCause = :AR_MatrixSharingService.ROW_CAUSE AND UserOrGroupId = :da.Id AND AccessLevel = 'Edit'
        ], 'La ligne de la chaîne est intacte.');
    }

    @IsTest
    static void testOwnerChangesAgency_oldAgencyLosesAccess_newAgencyGainsIt() {
        User owner = AR_TestPersona.bm();
        User paris = AR_TestPersona.bm();
        User lyon = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ owner => 'Paris', paris => 'Paris', lyon => 'Lyon' });
        AR_Price_Matrix__c m = newMatrix(owner);
        System.assertEquals(1, visible(paris, m.Id));
        System.assertEquals(0, visible(lyon, m.Id));

        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = owner.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Lyon');
        }
        Test.stopTest(); // étape « configuration » : le propriétaire rejoint le groupe Lyon

        // Étape « partage », enchaînée hors test : exécutée ici directement.
        System.runAs(admin()) {
            new AR_AgencySharingService.MatrixJob(new Set<Id>{ owner.Id }).execute(null);
        }
        System.assertEquals(0, visible(paris, m.Id), 'L’ancienne agence perd l’accès.');
        System.assertEquals(1, visible(lyon, m.Id), 'La nouvelle agence gagne l’accès.');
        System.assertEquals(1, agencyShares(m.Id), 'Une seule ligne d’agence.');
        System.assertEquals(1, [
            SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :owner.Id AND GroupId = :groupOf('Lyon')
        ], 'Le propriétaire est membre du groupe Lyon.');
    }

    @IsTest
    static void testMemberChangesAgency_losesOldAgencyMatrices_gainsNewOnes() {
        User parisOwner = AR_TestPersona.bm();
        User lyonOwner = AR_TestPersona.bm();
        User mover = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ parisOwner => 'Paris', lyonOwner => 'Lyon', mover => 'Paris' });
        AR_Price_Matrix__c parisMatrix = newMatrix(parisOwner);
        AR_Price_Matrix__c lyonMatrix = newMatrix(lyonOwner);
        System.assertEquals(1, visible(mover, parisMatrix.Id));
        System.assertEquals(0, visible(mover, lyonMatrix.Id));

        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = mover.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Lyon');
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :mover.Id AND GroupId = :groupOf('Paris')],
            'Il quitte le groupe Paris.');
        System.assertEquals(1, [SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :mover.Id AND GroupId = :groupOf('Lyon')],
            'Il rejoint le groupe Lyon.');
        System.assertEquals(0, visible(mover, parisMatrix.Id), 'Il perd les matrices de son ancienne agence.');
        System.assertEquals(1, visible(mover, lyonMatrix.Id), 'Il voit celles de sa nouvelle agence.');
    }

    @IsTest
    static void testDeactivatedUser_leavesTheGroup_newUserWithAgencyJoinsIt() {
        User leaver = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ leaver => 'Paris' });
        Id parisGroup = groupOf('Paris');
        User newcomer;
        Test.startTest();
        System.runAs(admin()) {
            update new User(Id = leaver.Id, IsActive = false);
            newcomer = new User(
                LastName = 'Nouveau 282', Email = 'nouveau282@example.com.invalid',
                Username = 'ar.282.nouveau.' + Datetime.now().getTime() + '@example.com.invalid',
                Alias = 'nv282', TimeZoneSidKey = 'Europe/Paris', LocaleSidKey = 'fr_FR', LanguageLocaleKey = 'fr',
                EmailEncodingKey = 'UTF-8', FederationIdentifier = 'ar.282.nouveau.' + Datetime.now().getTime(), TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Paris',
                ProfileId = [SELECT Id FROM Profile WHERE Name IN ('Utilisateur standard', 'Standard User') LIMIT 1].Id
            );
            insert newcomer;
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :leaver.Id AND GroupId = :parisGroup],
            'Un utilisateur désactivé quitte le groupe.');
        System.assertEquals(1, [SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :newcomer.Id AND GroupId = :parisGroup],
            'Un utilisateur créé avec une agence rejoint son groupe.');
    }

    @IsTest
    static void testReasonsFollowTheAgencyShare() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ owner => 'Paris', colleague => 'Paris' });
        AR_Price_Matrix__c m = newMatrix(owner);
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Agence 282' LIMIT 1].Id;
        System.runAs(owner) {
            AR_ReasonService.insertSelections(m.Id, null, new List<Id>{ reasonId });
        }
        System.runAs(colleague) {
            System.assertEquals(1, [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :m.Id],
                'Le collègue voit les motifs de la matrice.');
        }
    }

    @IsTest
    static void testBackfillTwice_sameNumberOfRows() {
        User owner = AR_TestPersona.bm();
        User colleague = AR_TestPersona.bm();
        setAgencies(new Map<User, String>{ owner => 'Paris', colleague => 'Paris' });
        AR_Price_Matrix__c m = newMatrix(owner);
        // Matrice antérieure au partage d'agence : on retire sa ligne, comme en production avant le rattrapage.
        delete [SELECT Id FROM AR_Price_Matrix__Share WHERE ParentId = :m.Id AND RowCause = :AR_AgencySharingService.ROW_CAUSE];
        System.assertEquals(0, visible(colleague, m.Id));

        System.runAs(admin()) {
            AR_AgencySharingService.backfillMemberships();
        }
        Integer membersAfterFirst = [SELECT COUNT() FROM GroupMember WHERE Group.DeveloperName LIKE 'AR_Agence_%'];
        System.assert(membersAfterFirst >= 2, 'Les deux personas sont membres : ' + membersAfterFirst);
        System.runAs(admin()) {
            AR_AgencySharingService.backfillMemberships();
        }
        System.assertEquals(membersAfterFirst, [SELECT COUNT() FROM GroupMember WHERE Group.DeveloperName LIKE 'AR_Agence_%'],
            'Membres : relancer ne change rien.');

        Set<Id> all = new Map<Id, AR_Price_Matrix__c>([SELECT Id FROM AR_Price_Matrix__c]).keySet();
        AR_AgencySharingService.recalculateMatrices(all, false);
        Integer sharesAfterFirst = [SELECT COUNT() FROM AR_Price_Matrix__Share WHERE RowCause = :AR_AgencySharingService.ROW_CAUSE];
        AR_AgencySharingService.recalculateMatrices(all, false);
        System.assertEquals(sharesAfterFirst, [SELECT COUNT() FROM AR_Price_Matrix__Share WHERE RowCause = :AR_AgencySharingService.ROW_CAUSE],
            'Lignes : relancer ne change rien.');
        System.assertEquals(1, agencyShares(m.Id));
        System.assertEquals(1, visible(colleague, m.Id), 'Le rattrapage rend la matrice visible à l’agence.');
    }

    @IsTest
    static void testMissingGroup_isCreatedAsynchronously() {
        User owner = AR_TestPersona.bm();
        System.runAs(admin()) {
            update new User(Id = owner.Id, TP_Perimetre__c = 'House of ABY', TP_Agence__c = 'Brest');
        }
        System.assertEquals(0, [SELECT COUNT() FROM Group WHERE DeveloperName = 'AR_Agence_Brest']);
        AR_Price_Matrix__c m;
        Test.startTest();
        m = newMatrix(owner);
        Test.stopTest();

        System.assertEquals(0, agencyShares(m.Id), 'Sans groupe, rien n’est posé dans la transaction de création.');
        System.assertEquals(1, [SELECT COUNT() FROM Group WHERE DeveloperName = 'AR_Agence_Brest'], 'Le groupe est créé en asynchrone.');
        System.runAs(admin()) {
            new AR_AgencySharingService.MatrixJob(new Set<Id>{ owner.Id }).execute(null);
        }
        System.assertEquals(1, agencyShares(m.Id), 'Puis la ligne est posée par l’étape « partage ».');
    }

    @IsTest
    static void testGroupDeveloperName_normalizesPicklistValues() {
        System.assertEquals('AR_Agence_Paris', AR_AgencySharingService.groupDeveloperName('Paris'));
        System.assertEquals('AR_Agence_Liege', AR_AgencySharingService.groupDeveloperName('Liège'));
        System.assertEquals('AR_Agence_Villeneuve_d_Ascq', AR_AgencySharingService.groupDeveloperName('Villeneuve-d\'Ascq'));
        System.assertEquals('AR_Agence_Elancourt', AR_AgencySharingService.groupDeveloperName(' Élancourt '));
        System.assertEquals(null, AR_AgencySharingService.groupDeveloperName(' '));
        System.assertEquals(null, AR_AgencySharingService.groupDeveloperName('---'));
        System.assertEquals(80, AR_AgencySharingService.groupDeveloperName('x'.repeat(120)).length());
        System.assertEquals('AR Agence Paris', AR_AgencySharingService.groupLabel('Paris'));
    }
}