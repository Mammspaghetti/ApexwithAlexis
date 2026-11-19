/**
 * Session 147 : chaque événement de notification produit les destinataires in-app (`recipientIds`)
 * attendus, sous les personas réels (BM propriétaire, valideur, manager Pricing — Matthieu est un
 * manager Pricing) — jamais seulement sous l'administrateur qui exécute les tests. La matrice
 * événements × destinataires est dans docs/147-notifications-par-profil.md.
 */
@IsTest
private class AR_NotificationRecipientsTest {
    private static User bm;
    private static User valideur;
    private static User manager;

    private static void createPersonas() {
        bm = AR_TestPersona.bm();
        valideur = AR_TestPersona.valideur();
        manager = AR_TestPersona.manager();
    }

    private static void setHierarchy(Id ownerId, Id da, Id dd, Id directeur) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = ownerId, TP_DA__c = da, TP_DD__c = dd, TP_Directeur__c = directeur);
        }
    }

    // Un seul compte/besoin par test : deux comptes aux noms proches déclenchent DUPLICATES_DETECTED
    // (règle de doublon de l'org), cf. session 54.
    private static Id sharedPositionId;

    private static Id positionId() {
        if (sharedPositionId != null) {
            return sharedPositionId;
        }
        Account acc = new Account(
            Name = 'Client Destinataires ' + Datetime.now().getTime(),
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Destinataires', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        sharedPositionId = position.Id;
        return sharedPositionId;
    }

    private static Id newMatrixOwnedBy(Id ownerId, String status) {
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = positionId(),
            AR_Position_Name__c = 'Besoin Destinataires',
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = status,
            AR_Proposed_TJM__c = 480,
            AR_MC2_Percent__c = 8.9,
            AR_Validated_At__c = System.now(),
            OwnerId = ownerId
        );
        insert matrix;
        return matrix.Id;
    }

    private static Id newDerogation(Id matrixId, Id selectedValidator, Id effectiveValidator, String decision) {
        AR_Derogation__c d = new AR_Derogation__c(
            AR_Price_Matrix__c = matrixId,
            AR_Selected_Validator__c = selectedValidator,
            AR_Effective_Validator__c = effectiveValidator,
            AR_Requester_Reason__c = 'Contexte concurrentiel',
            AR_Decision__c = decision,
            AR_Validator_Comment__c = 'Commentaire',
            AR_Requested_At__c = System.now()
        );
        insert d;
        return d.Id;
    }

    private static void insertImmediateSettings() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Hierarchy_Notification_Frequency__c = 'Immédiat',
            AR_InApp_Notification_Enabled__c = true,
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
    }

    private static Set<String> idSet(Id a) {
        return new Set<String>{ a };
    }

    // ---------------------------------------------------------------------
    // Événements e-mail + in-app existants : destinataires attendus par persona.
    // ---------------------------------------------------------------------

    /** Demande de dérogation : seul le valideur SÉLECTIONNÉ est notifié, pas le demandeur ni un autre valideur. */
    @IsTest
    static void testDerogationRequest_recipientIsSelectedValidator() {
        createPersonas();
        Id matrixId = newMatrixOwnedBy(bm.Id, 'En dérogation');
        Id derogationId = newDerogation(matrixId, valideur.Id, null, 'En attente');

        AR_NotificationService.EmailPreview preview;
        System.runAs(bm) {
            preview = AR_NotificationService.buildDerogationRequestEmail(derogationId);
        }
        System.assertNotEquals(null, preview);
        System.assertEquals(idSet(valideur.Id), preview.recipientIds, 'le valideur sélectionné, et lui seul');
    }

    /** Résultat de dérogation : le propriétaire de la matrice (BM) ET le valideur effectif (manager). */
    @IsTest
    static void testDerogationResult_recipientsAreOwnerAndEffectiveValidator() {
        createPersonas();
        Id matrixId = newMatrixOwnedBy(bm.Id, 'Validée par dérogation');
        Id derogationId = newDerogation(matrixId, valideur.Id, manager.Id, 'Acceptée');

        AR_NotificationService.EmailPreview preview;
        System.runAs(manager) {
            preview = AR_NotificationService.buildDerogationResultEmail(derogationId);
        }
        System.assertEquals(new Set<String>{ bm.Id, manager.Id }, preview.recipientIds);
        System.assert(!preview.recipientIds.contains(valideur.Id), 'le valideur sélectionné qui n\'a pas décidé n\'est pas notifié du résultat');
    }

    /** Validation automatique : le propriétaire de la matrice. */
    @IsTest
    static void testAutoValidation_recipientIsOwner() {
        createPersonas();
        Id matrixId = newMatrixOwnedBy(bm.Id, 'Validée');

        AR_NotificationService.EmailPreview preview;
        System.runAs(bm) {
            preview = AR_NotificationService.buildAutoValidationEmail(matrixId);
        }
        System.assertNotEquals(null, preview);
        System.assertEquals(idSet(bm.Id), preview.recipientIds);
    }

    /** Relance et escalade : le destinataire résolu atteint le canal in-app (Id porté par le digest). */
    @IsTest
    static void testReminderAndEscalationDigests_carryRecipientId() {
        createPersonas();
        AR_NotificationService.DerogationReminderItem r = new AR_NotificationService.DerogationReminderItem();
        r.matrixName = 'MAT-1';
        r.positionName = 'Besoin';
        r.hoursWaiting = 30;
        AR_NotificationService.DerogationEscalationItem e = new AR_NotificationService.DerogationEscalationItem();
        e.matrixName = 'MAT-1';
        e.positionName = 'Besoin';
        e.hoursWaiting = 80;
        e.selectedValidatorName = 'Valideur';

        System.runAs(valideur) {
            System.assertEquals(
                idSet(valideur.Id),
                AR_NotificationService.buildDerogationReminderDigest(
                    valideur.Email, valideur.Id, new List<AR_NotificationService.DerogationReminderItem>{ r }, 24
                ).recipientIds
            );
            System.assertEquals(
                idSet(manager.Id),
                AR_NotificationService.buildDerogationEscalationDigest(
                    manager.Email, manager.Id, new List<AR_NotificationService.DerogationEscalationItem>{ e }, 72
                ).recipientIds
            );
        }
    }

    /** Purge des brouillons (session 147) : le propriétaire reçoit aussi la cloche, plus seulement l'e-mail. */
    @IsTest
    static void testDraftPurgeWarningDigest_recipientIsOwner() {
        createPersonas();
        AR_NotificationService.DraftPurgeWarningItem item = new AR_NotificationService.DraftPurgeWarningItem();
        item.matrixName = 'MAT-1';
        item.positionName = 'Besoin';

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDraftPurgeWarningDigest(
            bm.Email, bm.Id, new List<AR_NotificationService.DraftPurgeWarningItem>{ item }, 30, 5
        );
        System.assertEquals(idSet(bm.Id), preview.recipientIds);

        Integer before = AR_NotificationService.inAppEligibleAttempts;
        System.runAs(bm) {
            AR_NotificationService.sendDraftPurgeWarningDigest(
                bm.Email, bm.Id, new List<AR_NotificationService.DraftPurgeWarningItem>{ item }, 30, 5
            );
        }
        System.assertEquals(before + 1, AR_NotificationService.inAppEligibleAttempts, 'canal in-app tenté pour la purge');
    }

    /** Avertissement de gating (session 147) : propriétaire ET destinataire hiérarchique reçoivent la cloche. */
    @IsTest
    static void testGatingWarning_ownerAndHierarchyRecipientGetInApp() {
        createPersonas();
        AR_NotificationService.GatingWarningNotice notice = new AR_NotificationService.GatingWarningNotice();
        notice.ownerEmail = bm.Email;
        notice.ownerId = bm.Id;
        notice.managerEmail = manager.Email;
        notice.managerId = manager.Id;
        notice.jobApplicationName = 'JA-1';
        notice.positionName = 'Besoin';
        notice.caseLabel = 'CAS-1';

        List<AR_NotificationService.EmailPreview> previews = AR_NotificationService.buildGatingWarningEmails(
            new List<AR_NotificationService.GatingWarningNotice>{ notice }
        );
        System.assertEquals(1, previews.size());
        System.assertEquals(new Set<String>{ bm.Id, manager.Id }, previews[0].recipientIds);

        // Ids seuls, sans e-mail : l'avis n'est plus ignoré, la cloche part.
        AR_NotificationService.GatingWarningNotice idsOnly = new AR_NotificationService.GatingWarningNotice();
        idsOnly.ownerId = bm.Id;
        idsOnly.jobApplicationName = 'JA-2';
        idsOnly.positionName = 'Besoin';
        idsOnly.caseLabel = 'CAS-1';
        List<AR_NotificationService.EmailPreview> idsOnlyPreviews = AR_NotificationService.buildGatingWarningEmails(
            new List<AR_NotificationService.GatingWarningNotice>{ idsOnly }
        );
        System.assertEquals(1, idsOnlyPreviews.size());
        System.assertEquals(idSet(bm.Id), idsOnlyPreviews[0].recipientIds);
        System.assert(idsOnlyPreviews[0].toAddresses.isEmpty());
    }

    // ---------------------------------------------------------------------
    // Hiérarchie : DA → DD → Directeur du propriétaire (plus User.ManagerId).
    // ---------------------------------------------------------------------

    @IsTest
    static void testHierarchyTarget_firstActiveLevelOfChain() {
        createPersonas();
        // BM propriétaire, valideur = DA, manager (Matthieu) = DD : le DA passe en premier.
        setHierarchy(bm.Id, valideur.Id, manager.Id, null);
        User target = AR_DerogationReminderBatch.hierarchyTarget(
            AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ bm.Id }).get(bm.Id)
        );
        System.assertEquals(valideur.Id, target.Id);

        // Sans DA : le DD.
        setHierarchy(bm.Id, null, manager.Id, valideur.Id);
        target = AR_DerogationReminderBatch.hierarchyTarget(
            AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ bm.Id }).get(bm.Id)
        );
        System.assertEquals(manager.Id, target.Id);

        // Sans DA ni DD : le Directeur.
        setHierarchy(bm.Id, null, null, valideur.Id);
        target = AR_DerogationReminderBatch.hierarchyTarget(
            AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ bm.Id }).get(bm.Id)
        );
        System.assertEquals(valideur.Id, target.Id);
    }

    @IsTest
    static void testHierarchyTarget_emptyChain_returnsNull() {
        createPersonas();
        setHierarchy(bm.Id, null, null, null);
        System.assertEquals(
            null,
            AR_DerogationReminderBatch.hierarchyTarget(
                AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ bm.Id }).get(bm.Id)
            )
        );
        System.assertEquals(null, AR_DerogationReminderBatch.hierarchyTarget(null));
    }

    /** Gating en masse : le plafond in-app est respecté, l'e-mail part pour tous. */
    @IsTest
    static void testGatingWarning_inAppCappedPerTransaction() {
        createPersonas();
        List<AR_NotificationService.GatingWarningNotice> notices = new List<AR_NotificationService.GatingWarningNotice>();
        for (Integer i = 0; i < 25; i++) {
            AR_NotificationService.GatingWarningNotice n = new AR_NotificationService.GatingWarningNotice();
            n.ownerEmail = bm.Email;
            n.ownerId = bm.Id;
            n.jobApplicationName = 'JA-' + i;
            n.positionName = 'Besoin';
            n.caseLabel = 'CAS-1';
            notices.add(n);
        }
        Integer before = AR_NotificationService.inAppEligibleAttempts;
        Test.startTest();
        AR_NotificationService.sendGatingWarningEmail(notices);
        Test.stopTest();
        System.assertEquals(
            before + AR_NotificationService.GATING_IN_APP_MAX_PER_TRANSACTION,
            AR_NotificationService.inAppEligibleAttempts
        );
    }

    /** Fréquence Immédiat : la cloche part vers le DA du propriétaire, sous chacun des trois personas. */
    @IsTest
    static void testHierarchyImmediate_inAppReachesDaUnderEachPersona() {
        createPersonas();
        insertImmediateSettings();
        setHierarchy(bm.Id, manager.Id, null, null);
        // Le valideur hors chaîne ne voit pas la matrice d'un autre : il ne peut pas déclencher la notification.
        // Les déclencheurs sont le propriétaire et le Manager (qui voit toutes les matrices).
        List<User> runners = new List<User>{ bm, manager };
        for (User runner : runners) {
            Id matrixId = newMatrixOwnedBy(bm.Id, 'Validée');
            Integer before = AR_NotificationService.inAppEligibleAttempts;
            System.runAs(runner) {
                AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(matrixId);
            }
            System.assertEquals(
                before + 1,
                AR_NotificationService.inAppEligibleAttempts,
                'cloche tentée vers le DA, exécutée par ' + runner.LastName
            );
            System.assertEquals(
                true,
                [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c WHERE Id = :matrixId].AR_Hierarchy_Notified__c
            );
        }
    }

    /** Aucun niveau résolvable : rien ne part, la matrice est quand même marquée notifiée (journalisé). */
    @IsTest
    static void testHierarchyImmediate_emptyChain_noInAppButMarkedNotified() {
        createPersonas();
        insertImmediateSettings();
        setHierarchy(bm.Id, null, null, null);
        Id matrixId = newMatrixOwnedBy(bm.Id, 'Validée');
        Integer before = AR_NotificationService.inAppEligibleAttempts;

        System.runAs(bm) {
            AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(matrixId);
        }

        System.assertEquals(before, AR_NotificationService.inAppEligibleAttempts);
        System.assertEquals(
            true,
            [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c WHERE Id = :matrixId].AR_Hierarchy_Notified__c
        );
    }

    /** Digest quotidien : un seul envoi in-app par destinataire, même avec deux propriétaires différents
     * qui partagent le même DA. */
    @IsTest
    static void testHierarchyBatch_sameDaForTwoOwners_singleDigest() {
        createPersonas();
        User otherBm = AR_TestPersona.bm();
        setHierarchy(bm.Id, manager.Id, null, null);
        setHierarchy(otherBm.Id, manager.Id, null, null);
        newMatrixOwnedBy(bm.Id, 'Validée');
        newMatrixOwnedBy(otherBm.Id, 'Validée');
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Hierarchy_Notification_Frequency__c = 'Quotidien',
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
        Integer before = AR_NotificationService.inAppEligibleAttempts;

        Test.startTest();
        AR_HierarchyNotificationBatch batch = new AR_HierarchyNotificationBatch();
        List<AR_Price_Matrix__c> scope = new List<AR_Price_Matrix__c>();
        Database.QueryLocatorIterator it = batch.start(null).iterator();
        while (it.hasNext()) {
            scope.add((AR_Price_Matrix__c) it.next());
        }
        batch.execute(null, scope);
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(before + 1, AR_NotificationService.inAppEligibleAttempts, 'un seul digest pour le DA commun');
    }
}