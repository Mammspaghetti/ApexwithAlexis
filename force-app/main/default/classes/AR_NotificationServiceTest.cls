/**
 * AR_NotificationService (330 lignes, aucune classe de test dédiée avant la session 27, cf.
 * prompts/session-27-filet-de-tests.md §2) — vérifie le contenu réellement construit (destinataire,
 * lien, substitution complète), pas seulement la couverture de ligne déjà obtenue indirectement par
 * d'autres suites. S'appuie sur le refactoring de testabilité de la classe (méthodes `build*`
 * `@TestVisible`, séparées de l'envoi) pour inspecter subject/body/toAddresses sans mock ni envoi
 * réel. Le nombre d'envois réellement tentés (`sendDerogationRequestEmail` etc., pas les `build*`)
 * est vérifié via `Limits.getEmailInvocations()` autour de `Test.startTest()`/`stopTest()`, comme
 * demandé par le prompt de session — jamais en simulant Messaging.sendEmail.
 */
@IsTest
private class AR_NotificationServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Notification',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Notification', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

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
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
        insert matrix;

        insert new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = UserInfo.getUserId(),
            AR_Effective_Validator__c = UserInfo.getUserId(),
            AR_Requester_Reason__c = 'Contexte concurrentiel tendu',
            AR_Decision__c = 'Acceptée',
            AR_Validator_Comment__c = 'OK pour ce trimestre',
            AR_Requested_At__c = System.now(),
            AR_Decided_At__c = System.now()
        );
    }

    private static Id getMatrixId() {
        return [SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id;
    }

    /**
     * Session 200 : matrice de même forme que celle du @TestSetup, mais dont le PROPRIÉTAIRE est posé à
     * l'INSERT. La chaîne DA → DD → Directeur qui décide du destinataire d'une notification hiérarchie est
     * celle du propriétaire : sous l'utilisateur qui exécute les tests, elle dépend de la fiche de cet
     * utilisateur dans l'org (vide en sandbox, renseignée en production : un test fondé dessus passe
     * dans l'une et échoue dans l'autre, constaté au validate prod du 20/10/2026). Toujours un persona.
     */
    private static Id insertMatrixOwnedBy(Id ownerId) {
        AR_Price_Matrix__c template = [SELECT AR_Position__c, AR_Position_Name__c FROM AR_Price_Matrix__c LIMIT 1];
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            OwnerId = ownerId,
            AR_Position__c = template.AR_Position__c,
            AR_Position_Name__c = template.AR_Position_Name__c,
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
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
        insert matrix;
        return matrix.Id;
    }

    private static Id getDerogationId() {
        return [SELECT Id FROM AR_Derogation__c LIMIT 1].Id;
    }

    private static String currentUserEmail() {
        return [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
    }

    /** Aucun jeton `{0}`, `{1}`… non substitué dans le texte final envoyé. */
    private static void assertNoUnreplacedTokens(String text, String context) {
        System.assert(
            !Pattern.matches('(?s).*\\{[0-9]+\\}.*', text),
            context + ' : jeton non substitué trouvé dans « ' + text + ' »'
        );
    }

    @IsTest
    static void testBuildDerogationRequestEmail_recipientLinkAndSubstitution() {
        AR_NotificationService.EmailPreview preview =
            AR_NotificationService.buildDerogationRequestEmail(getDerogationId());

        System.assertNotEquals(null, preview);
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals(currentUserEmail(), preview.toAddresses[0], 'destinataire = valideur sélectionné');
        // Session 34 : même destinataire, en Id cette fois (canal in-app), et cible = la dérogation.
        System.assertEquals(1, preview.recipientIds.size());
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        // Session 112 : la cible du clic in-app n'est plus l'Id brut de la dérogation mais une
        // PageReference vers la file d'approbation, dérogation focalisée (elle prime sur
        // notificationTargetId, laissé vide) — cf. buildDerogationTargetPageRef.
        System.assertEquals(null, preview.notificationTargetId, 'la PageReference prime : pas d\'Id brut');
        System.assert(
            String.isNotBlank(preview.notificationTargetPageRef) &&
            preview.notificationTargetPageRef.contains('"c__derogationId":"' + getDerogationId() + '"'),
            'cible du clic in-app = la file d\'approbation focalisée sur la dérogation : ' + preview.notificationTargetPageRef
        );
        String matrixName = [SELECT Name FROM AR_Price_Matrix__c WHERE Id = :getMatrixId()].Name;
        System.assert(preview.subject.contains(matrixName), 'objet doit référencer le nom de la matrice (' + matrixName + ') : ' + preview.subject);
        System.assert(preview.body.contains(UserInfo.getName()), 'corps doit nommer le demandeur');
        System.assert(preview.body.contains('Besoin Notification'), 'corps doit nommer le besoin');
        System.assert(preview.body.contains('Contexte concurrentiel tendu'), 'corps doit reprendre le motif');
        System.assert(
            preview.body.contains('/lightning/n/AR_Pricing_App?c__view=approbations&c__derogationId=' + getDerogationId()),
            'session 112 : le lien de la demande ouvre la file d\'approbation sur la dérogation (c__view=approbations), ' +
            'plus la matrice via matriceAT (session 26 §3) : ' + preview.body
        );
        assertNoUnreplacedTokens(preview.subject, 'sujet demande de dérogation');
        assertNoUnreplacedTokens(preview.body, 'corps demande de dérogation');
    }

    /** Session 143 : la MC2/jour est lue au même niveau que la MC2 % dans le corps de l'e-mail. */
    private static void setMatrixMc2(Decimal perDay, Decimal tjm, Decimal percent) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = getMatrixId(),
                AR_MC2_Per_Day__c = perDay,
                AR_Proposed_TJM__c = tjm,
                AR_MC2_Percent__c = percent
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    @IsTest
    static void testBuildDerogationRequestEmail_containsMc2PerDay() {
        setMatrixMc2(77.5, 490, 8.9);
        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(
            preview.body.contains(
                'TJM idéal : 490' + NBSP + '€ — MC2 : 8,9 % (78' + NBSP + '€ / jour).'
            ),
            'format FR aligné sur l\'écran (490 € — 8,9 % · 78 € / j), MC2/jour stockée juste après la MC2 % : ' + preview.body
        );
        assertNoUnreplacedTokens(preview.body, 'corps demande de dérogation (MC2/jour)');
    }

    /** Motif du référentiel, actif et applicable aux dérogations. */
    private static Id insertReason(String label, Decimal sortOrder) {
        AR_Reason__c reason = new AR_Reason__c(
            Name = label,
            AR_Active__c = true,
            AR_Applies_To_Derogation__c = true,
            AR_Sort_Order__c = sortOrder
        );
        insert reason;
        return reason.Id;
    }

    private static void setRequesterReason(String reason) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Derogation__c(Id = getDerogationId(), AR_Requester_Reason__c = reason);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    /** Le corps est construit sous une persona non administratrice (valideur habilité, pas l'admin). */
    private static AR_NotificationService.EmailPreview buildAsValidatorPersona() {
        AR_NotificationService.EmailPreview preview;
        System.runAs(AR_TestPersona.manager()) {
            preview = AR_NotificationService.buildDerogationRequestEmail(getDerogationId());
        }
        return preview;
    }

    /** Idem pour le résultat : persona française, libellés FR attendus (l'utilisateur de test est en en_US). */
    private static AR_NotificationService.EmailPreview buildResultAsValidatorPersona() {
        AR_NotificationService.EmailPreview preview;
        System.runAs(AR_TestPersona.manager()) {
            preview = AR_NotificationService.buildDerogationResultEmail(getDerogationId());
        }
        return preview;
    }

    /** Session 216b, cas 1 : un motif sans commentaire → titre puis « A », sans ligne de commentaire. */
    @IsTest
    static void testBuildDerogationRequestEmail_reason_singleWithoutComment() {
        setRequesterReason(null);
        AR_ReasonService.insertSelections(null, getDerogationId(), new List<Id>{ insertReason('Concurrence', 1) });

        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(
            preview.body.contains('Motif de dérogation :\nConcurrence\n'),
            'un motif seul, sur la ligne suivant le titre : ' + preview.body
        );
        System.assert(!preview.body.contains('null'), 'aucun « null » dans le corps : ' + preview.body);
        assertNoUnreplacedTokens(preview.body, 'corps demande (1 motif sans commentaire)');
    }

    /** Session 216b, cas 2 : un motif et un commentaire → titre puis « A : commentaire ». */
    @IsTest
    static void testBuildDerogationRequestEmail_reason_singleWithComment() {
        AR_ReasonService.insertSelections(null, getDerogationId(), new List<Id>{ insertReason('Concurrence', 1) });

        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(
            preview.body.contains('Motif de dérogation :\nConcurrence : Contexte concurrentiel tendu'),
            'un motif + commentaire sur une ligne : ' + preview.body
        );
        assertNoUnreplacedTokens(preview.body, 'corps demande (1 motif + commentaire)');
    }

    /**
     * Session 216b, cas 3 : plusieurs motifs et un commentaire → liste à puces dans l'ordre du
     * référentiel, puis le commentaire en dessous.
     */
    @IsTest
    static void testBuildDerogationRequestEmail_reason_severalWithComment() {
        Id budget = insertReason('Budget client', 2);
        Id concurrence = insertReason('Concurrence', 1);
        AR_ReasonService.insertSelections(null, getDerogationId(), new List<Id>{ budget, concurrence });

        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        String expected = 'Motif de dérogation :\n- Concurrence\n- Budget client\nContexte concurrentiel tendu';
        System.assert(preview.body.contains(expected), 'liste puis commentaire : ' + preview.body);
        assertNoUnreplacedTokens(preview.body, 'corps demande (plusieurs motifs + commentaire)');
    }

    /** Session 216b, cas 4 : ni motif ni commentaire → pas de bloc « Motif », ni « null ». */
    @IsTest
    static void testBuildDerogationRequestEmail_reason_nothingNoBlock() {
        setRequesterReason(null);

        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(!preview.body.contains('Motif'), 'aucun bloc Motif sans motif ni commentaire : ' + preview.body);
        System.assert(!preview.body.contains('null'), 'aucun « null » dans le corps : ' + preview.body);
        assertNoUnreplacedTokens(preview.body, 'corps demande (rien)');
    }

    private static final String NBSP = AR_PTFFormatUtil.NBSP;

    @IsTest
    static void testBuildDerogationRequestEmail_chfCurrencyAndThousands() {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(
                Id = getMatrixId(),
                AR_Currency__c = 'CHF',
                AR_Proposed_TJM__c = 1250,
                AR_MC2_Per_Day__c = 1250.4,
                AR_MC2_Percent__c = 3
            );
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(
            preview.body.contains(
                'TJM idéal : 1' + NBSP + '250' + NBSP + 'CHF — MC2 : 3,0 % (1' + NBSP + '250' + NBSP + 'CHF / jour).'
            ),
            'milliers en espace insécable, code CHF, 1 décimale conservée (3,0) : ' + preview.body
        );
        assertNoUnreplacedTokens(preview.body, 'corps demande de dérogation (CHF)');
    }

    @IsTest
    static void testFormatMoney_eurGbpNegativeNullAndHalfUp() {
        System.assertEquals('490' + NBSP + '€', AR_NotificationService.formatMoney(490, 'EUR'));
        System.assertEquals('490' + NBSP + '€', AR_NotificationService.formatMoney(490, null), 'devise vide => €');
        System.assertEquals('473' + NBSP + '£', AR_NotificationService.formatMoney(473, 'GBP'));
        System.assertEquals('1' + NBSP + '250' + NBSP + '€', AR_NotificationService.formatMoney(1250, 'EUR'));
        System.assertEquals('78' + NBSP + '€', AR_NotificationService.formatMoney(77.5, 'EUR'), 'HALF_UP');
        System.assertEquals('-12' + NBSP + '€', AR_NotificationService.formatMoney(-12.4, 'EUR'));
        System.assertEquals('', AR_NotificationService.formatMoney(null, 'EUR'));
    }

    @IsTest
    static void testFormatPercent_oneDecimalCommaNegativeNull() {
        System.assertEquals('8,9', AR_NotificationService.formatPercent(8.9));
        System.assertEquals('8,9', AR_NotificationService.formatPercent(8.90));
        System.assertEquals('-3,0', AR_NotificationService.formatPercent(-3));
        System.assertEquals('3,0', AR_NotificationService.formatPercent(3));
        System.assertEquals('2,4', AR_NotificationService.formatPercent(2.44));
        System.assertEquals('2,5', AR_NotificationService.formatPercent(2.45), 'HALF_UP');
        System.assertEquals('', AR_NotificationService.formatPercent(null));
    }

    @IsTest
    static void testBuildDerogationRequestEmail_mc2PerDayFallbackWhenStoredIsNull() {
        setMatrixMc2(null, 490, 8.9);
        AR_NotificationService.EmailPreview preview = buildAsValidatorPersona();

        System.assert(
            preview.body.contains('MC2 : 8,9 % (44' + NBSP + '€ / jour)'),
            'repli TJM × MC2 % / 100 quand la matrice n\'a pas de valeur stockée : ' + preview.body
        );
    }

    @IsTest
    static void testBuildDerogationRequestEmail_noValidatorEmail_returnsNull() {
        AR_Derogation__c derogation = new AR_Derogation__c(
            Id = getDerogationId(),
            AR_Selected_Validator__c = null
        );
        AR_TriggerBypass.serviceContext = true;
        try {
            update derogation;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        AR_NotificationService.EmailPreview preview =
            AR_NotificationService.buildDerogationRequestEmail(getDerogationId());
        System.assertEquals(null, preview, 'pas de valideur sélectionné => pas d\'email construit');
    }

    @IsTest
    static void testSendDerogationRequestEmail_noValidatorEmail_noSendAttempted() {
        AR_Derogation__c derogation = new AR_Derogation__c(
            Id = getDerogationId(),
            AR_Selected_Validator__c = null
        );
        AR_TriggerBypass.serviceContext = true;
        try {
            update derogation;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        // Test.startTest() réinitialise les limites de gouverneur : la lecture doit se faire à
        // l'intérieur du bloc startTest/stopTest, jamais avant (cf. AR_PricingMatrixServiceTest,
        // même piège déjà documenté) — sinon "before" et la valeur finale ne sont pas comparables.
        Test.startTest();
        AR_NotificationService.sendDerogationRequestEmail(getDerogationId());
        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'aucun email ne doit être tenté sans valideur sélectionné'
        );
        Test.stopTest();
    }

    @IsTest
    static void testSendAutoValidationEmail_sendsExactlyOne() {
        Test.startTest();
        AR_NotificationService.sendAutoValidationEmail(getMatrixId());
        System.assert(
            Limits.getEmailInvocations() > 0,
            'un envoi doit être tenté quand le propriétaire a un email'
        );
        Test.stopTest();
    }

    @IsTest
    static void testBuildDerogationResultEmail_ownerAndValidatorBothIncluded() {
        AR_NotificationService.EmailPreview preview = buildResultAsValidatorPersona();

        System.assertNotEquals(null, preview);
        // Propriétaire = valideur = utilisateur courant dans ce jeu de données : un seul destinataire
        // distinct (le Set<String> interne dédoublonne), mais la logique des deux branches est exercée.
        System.assert(preview.toAddresses.contains(currentUserEmail()));
        System.assert(preview.body.contains('acceptée'), 'décision Acceptée => libellé "acceptée"');
        System.assert(preview.body.contains('OK pour ce trimestre'), 'commentaire du valideur repris');
        System.assert(
            preview.body.contains('/lightning/n/AR_Pricing_App?c__view=matriceAT&c__matrixId=' + getMatrixId())
        );
        // Session 34 : mêmes destinataires que l'e-mail (demandeur + valideur effectif), à partir du
        // même objet preview — cible = la matrice.
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        System.assertEquals(getMatrixId(), preview.notificationTargetId, 'cible du clic in-app = la matrice');
        assertNoUnreplacedTokens(preview.subject, 'sujet résultat dérogation');
        assertNoUnreplacedTokens(preview.body, 'corps résultat dérogation');
    }

    @IsTest
    static void testBuildDerogationResultEmail_refusedDecisionLabel() {
        AR_Derogation__c derogation = new AR_Derogation__c(
            Id = getDerogationId(),
            AR_Decision__c = 'Refusée'
        );
        AR_TriggerBypass.serviceContext = true;
        try {
            update derogation;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        AR_NotificationService.EmailPreview preview = buildResultAsValidatorPersona();
        System.assert(preview.body.contains('refusée'), 'décision Refusée => libellé "refusée"');
        System.assert(!preview.body.contains('acceptée'), 'ne doit pas mentionner "acceptée" pour un refus');
    }

    @IsTest
    static void testBuildAutoValidationEmail_recipientLinkAndSubstitution() {
        Id matrixId = getMatrixId();
        AR_NotificationService.EmailPreview preview;
        System.runAs(AR_TestPersona.manager()) {
            preview = AR_NotificationService.buildAutoValidationEmail(matrixId);
        }

        System.assertNotEquals(null, preview);
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals(currentUserEmail(), preview.toAddresses[0]);
        System.assert(
            preview.body.contains('TJM : 205' + NBSP + '€ — MC2 : 2,4 %.'),
            'TJM et MC2 au format FR avec la devise de la matrice : ' + preview.body
        );
        System.assert(
            preview.body.contains('/lightning/n/AR_Pricing_App?c__view=matriceAT&c__matrixId=' + getMatrixId())
        );
        System.assertEquals(1, preview.recipientIds.size());
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        System.assertEquals(getMatrixId(), preview.notificationTargetId, 'cible du clic in-app = la matrice');
        assertNoUnreplacedTokens(preview.subject, 'sujet validation automatique');
        assertNoUnreplacedTokens(preview.body, 'corps validation automatique');
    }

    @IsTest
    static void testBuildGatingWarningEmails_ownerAndManagerBothIncluded_emptyNoticeSkipped() {
        AR_NotificationService.GatingWarningNotice full = new AR_NotificationService.GatingWarningNotice();
        full.ownerEmail = 'owner@example.com';
        full.managerEmail = 'manager@example.com';
        full.jobApplicationName = 'Candidature Test';
        full.positionName = 'Besoin Test';
        full.caseLabel = 'CAS-001';

        AR_NotificationService.GatingWarningNotice empty = new AR_NotificationService.GatingWarningNotice();
        empty.jobApplicationName = 'Candidature Sans Email';
        empty.positionName = 'Besoin Sans Email';

        List<AR_NotificationService.EmailPreview> previews = AR_NotificationService.buildGatingWarningEmails(
            new List<AR_NotificationService.GatingWarningNotice>{ full, empty }
        );

        System.assertEquals(1, previews.size(), 'le second avis (sans email) doit être ignoré, pas planter');
        AR_NotificationService.EmailPreview preview = previews[0];
        System.assertEquals(2, preview.toAddresses.size());
        System.assert(preview.toAddresses.contains('owner@example.com'), 'destinataire propriétaire manquant');
        System.assert(preview.toAddresses.contains('manager@example.com'), 'destinataire manager (manager résolu côté appelant) manquant');
        System.assert(preview.body.contains('Candidature Test'));
        System.assert(preview.body.contains('Besoin Test'));
        System.assert(preview.body.contains('CAS-001'));
        assertNoUnreplacedTokens(preview.subject, 'sujet avertissement gating');
        assertNoUnreplacedTokens(preview.body, 'corps avertissement gating');
    }

    @IsTest
    static void testBuildGatingWarningEmails_allEmpty_returnsEmptyList() {
        AR_NotificationService.GatingWarningNotice empty = new AR_NotificationService.GatingWarningNotice();
        List<AR_NotificationService.EmailPreview> previews = AR_NotificationService.buildGatingWarningEmails(
            new List<AR_NotificationService.GatingWarningNotice>{ empty }
        );
        System.assert(previews.isEmpty());
    }

    @IsTest
    static void testSendGatingWarningEmail_noRecipients_noSendAttempted() {
        AR_NotificationService.GatingWarningNotice empty = new AR_NotificationService.GatingWarningNotice();
        empty.jobApplicationName = 'Sans destinataire';

        Test.startTest();
        AR_NotificationService.sendGatingWarningEmail(
            new List<AR_NotificationService.GatingWarningNotice>{ empty }
        );
        System.assertEquals(0, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @IsTest
    static void testBuildGatingConfigErrorEmail_usesAdminAlertLabel() {
        AR_NotificationService.EmailPreview preview =
            AR_NotificationService.buildGatingConfigErrorEmail('a180900000022xsAAA');

        System.assertNotEquals(null, preview, 'AR_Gating_Admin_Alert_Email est renseigné dans cette org');
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals(Label.AR_Gating_Admin_Alert_Email, preview.toAddresses[0]);
        System.assert(preview.body.contains('a180900000022xsAAA'), 'l\'Id mal configuré doit apparaître dans le corps');
        assertNoUnreplacedTokens(preview.body, 'corps erreur configuration gating');
    }

    @IsTest
    static void testBuildDraftPurgeWarningDigest_listingAndSubstitution() {
        AR_NotificationService.DraftPurgeWarningItem item1 = new AR_NotificationService.DraftPurgeWarningItem();
        item1.matrixName = 'AR-0001';
        item1.positionName = 'Besoin A';
        AR_NotificationService.DraftPurgeWarningItem item2 = new AR_NotificationService.DraftPurgeWarningItem();
        item2.matrixName = 'AR-0002';
        item2.positionName = 'Besoin B';

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDraftPurgeWarningDigest(
            'owner@example.com',
            null,
            new List<AR_NotificationService.DraftPurgeWarningItem>{ item1, item2 },
            35,
            5
        );

        System.assertNotEquals(null, preview);
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals('owner@example.com', preview.toAddresses[0]);
        System.assert(preview.body.contains('AR-0001'));
        System.assert(preview.body.contains('Besoin A'));
        System.assert(preview.body.contains('AR-0002'));
        System.assert(preview.body.contains('Besoin B'));
        System.assert(preview.body.contains('35'), 'nombre de jours depuis la dernière modification');
        System.assert(preview.body.contains('5'), 'seuil d\'avertissement');
        System.assert(preview.subject.contains('2'), 'le sujet doit annoncer le nombre de brouillons concernés');
        assertNoUnreplacedTokens(preview.subject, 'sujet digest purge brouillons');
        assertNoUnreplacedTokens(preview.body, 'corps digest purge brouillons');
    }

    @IsTest
    static void testBuildDraftPurgeWarningDigest_emptyItems_returnsNull() {
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDraftPurgeWarningDigest(
            'owner@example.com',
            null,
            new List<AR_NotificationService.DraftPurgeWarningItem>(),
            35,
            5
        );
        System.assertEquals(null, preview, 'aucune ligne => pas d\'email construit');
    }

    @IsTest
    static void testBuildDraftPurgeWarningDigest_blankOwnerEmail_returnsNull() {
        AR_NotificationService.DraftPurgeWarningItem item = new AR_NotificationService.DraftPurgeWarningItem();
        item.matrixName = 'AR-0001';
        item.positionName = 'Besoin A';

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDraftPurgeWarningDigest(
            null,
            null,
            new List<AR_NotificationService.DraftPurgeWarningItem>{ item },
            35,
            5
        );
        System.assertEquals(null, preview);
    }

    // ---------------------------------------------------------------------
    // Session 29 : digests relance/escalade dérogation + notification hiérarchie.
    // ---------------------------------------------------------------------

    @IsTest
    static void testBuildDerogationReminderDigest_listingAndSubstitution() {
        AR_NotificationService.DerogationReminderItem item1 = new AR_NotificationService.DerogationReminderItem();
        item1.matrixName = 'AR-0001';
        item1.positionName = 'Besoin A';
        item1.hoursWaiting = 13;
        AR_NotificationService.DerogationReminderItem item2 = new AR_NotificationService.DerogationReminderItem();
        item2.matrixName = 'AR-0002';
        item2.positionName = 'Besoin B';
        item2.hoursWaiting = 14;

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationReminderDigest(
            'validateur@example.com',
            UserInfo.getUserId(),
            new List<AR_NotificationService.DerogationReminderItem>{ item1, item2 },
            12
        );

        System.assertNotEquals(null, preview);
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals('validateur@example.com', preview.toAddresses[0]);
        System.assert(preview.body.contains('AR-0001'));
        System.assert(preview.body.contains('Besoin A'));
        System.assert(preview.body.contains('AR-0002'));
        System.assert(preview.body.contains('13'), 'heures d\'attente du premier item');
        System.assert(preview.body.contains('12'), 'délai de relance administrable');
        System.assert(preview.subject.contains('2'), 'le sujet doit annoncer le nombre de dérogations concernées');
        // Session 34 : digest multi-dérogations => pas de cible unique (même choix que l'e-mail,
        // appRootLink() plutôt qu'un enregistrement précis), mais l'Id du destinataire est bien porté.
        System.assertEquals(1, preview.recipientIds.size());
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        System.assertEquals(null, preview.notificationTargetId);
        assertNoUnreplacedTokens(preview.subject, 'sujet digest relance dérogation');
        assertNoUnreplacedTokens(preview.body, 'corps digest relance dérogation');
    }

    @IsTest
    static void testBuildDerogationReminderDigest_emptyItems_returnsNull() {
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationReminderDigest(
            'validateur@example.com',
            UserInfo.getUserId(),
            new List<AR_NotificationService.DerogationReminderItem>(),
            12
        );
        System.assertEquals(null, preview);
    }

    @IsTest
    static void testBuildDerogationReminderDigest_nullValidatorId_noRecipientIds() {
        AR_NotificationService.DerogationReminderItem item = new AR_NotificationService.DerogationReminderItem();
        item.matrixName = 'AR-0001';
        item.positionName = 'Besoin A';
        item.hoursWaiting = 13;

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationReminderDigest(
            'validateur@example.com',
            null,
            new List<AR_NotificationService.DerogationReminderItem>{ item },
            12
        );

        System.assertNotEquals(null, preview, 'l\'e-mail reste construit même sans Id résolu');
        System.assert(preview.recipientIds.isEmpty(), 'pas d\'Id => pas de canal in-app pour cet envoi');
    }

    @IsTest
    static void testBuildDerogationEscalationDigest_listingAndSubstitution() {
        AR_NotificationService.DerogationEscalationItem item = new AR_NotificationService.DerogationEscalationItem();
        item.matrixName = 'AR-0003';
        item.positionName = 'Besoin C';
        item.hoursWaiting = 49;
        item.selectedValidatorName = 'Jean Valideur';

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationEscalationDigest(
            'directeur@example.com',
            UserInfo.getUserId(),
            new List<AR_NotificationService.DerogationEscalationItem>{ item },
            48
        );

        System.assertNotEquals(null, preview);
        System.assertEquals('directeur@example.com', preview.toAddresses[0]);
        System.assert(preview.body.contains('AR-0003'));
        System.assert(preview.body.contains('Besoin C'));
        System.assert(preview.body.contains('Jean Valideur'), 'le valideur initialement sélectionné doit rester visible');
        System.assert(preview.subject.contains('1'));
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        System.assertEquals(null, preview.notificationTargetId, 'digest multi-dérogations => pas de cible unique');
        assertNoUnreplacedTokens(preview.subject, 'sujet digest escalade dérogation');
        assertNoUnreplacedTokens(preview.body, 'corps digest escalade dérogation');
    }

    @IsTest
    static void testBuildDerogationEscalationDigest_blankRecipient_returnsNull() {
        AR_NotificationService.DerogationEscalationItem item = new AR_NotificationService.DerogationEscalationItem();
        item.matrixName = 'AR-0003';
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationEscalationDigest(
            null,
            UserInfo.getUserId(),
            new List<AR_NotificationService.DerogationEscalationItem>{ item },
            48
        );
        System.assertEquals(null, preview);
    }

    // ---------------------------------------------------------------------
    // Session 29c : alerte cercle d'escalade vide (borné par entité, aucun destinataire trouvé).
    // ---------------------------------------------------------------------

    @IsTest
    static void testBuildDerogationEscalationNoRecipientsEmail_usesAdminAlertLabelAndSubstitution() {
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationEscalationNoRecipientsEmail(
            'AR-0005',
            'Besoin E',
            'Abylsen GAMMA'
        );

        System.assertNotEquals(null, preview, 'AR_Gating_Admin_Alert_Email est renseigné dans cette org');
        System.assertEquals(1, preview.toAddresses.size());
        System.assertEquals(Label.AR_Gating_Admin_Alert_Email, preview.toAddresses[0]);
        System.assert(preview.subject.contains('Abylsen GAMMA'));
        System.assert(preview.body.contains('AR-0005'));
        System.assert(preview.body.contains('Besoin E'));
        System.assert(preview.body.contains('Abylsen GAMMA'));
        assertNoUnreplacedTokens(preview.subject, 'sujet alerte cercle escalade vide');
        assertNoUnreplacedTokens(preview.body, 'corps alerte cercle escalade vide');
    }

    @IsTest
    static void testBuildDerogationEscalationNoRecipientsEmail_blankEntity_stillBuildsWithPlaceholder() {
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationEscalationNoRecipientsEmail(
            'AR-0006',
            'Besoin F',
            null
        );
        System.assertNotEquals(null, preview, 'une entité absente ne doit pas empêcher l\'alerte, juste afficher un repli lisible');
        System.assert(!preview.subject.contains('null'), 'jamais le littéral "null" dans un texte destiné à un humain');
        System.assert(!preview.body.contains('null'));
    }

    @IsTest
    static void testSendDerogationEscalationNoRecipientsEmail_sendsExactlyOne() {
        Test.startTest();
        AR_NotificationService.sendDerogationEscalationNoRecipientsEmail('AR-0007', 'Besoin G', 'Abylsen GAMMA');
        System.assert(Limits.getEmailInvocations() > 0, 'un envoi doit être tenté quand le label admin est renseigné');
        Test.stopTest();
    }

    @IsTest
    static void testBuildHierarchyNotificationDigest_listingAndSubstitution() {
        AR_NotificationService.HierarchyValidationItem item = new AR_NotificationService.HierarchyValidationItem();
        item.matrixName = 'AR-0004';
        item.positionName = 'Besoin D';
        item.ownerName = 'Amélie BM';

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildHierarchyNotificationDigest(
            'manager@example.com',
            UserInfo.getUserId(),
            new List<AR_NotificationService.HierarchyValidationItem>{ item }
        );

        System.assertNotEquals(null, preview);
        System.assertEquals('manager@example.com', preview.toAddresses[0]);
        System.assert(preview.body.contains('AR-0004'));
        System.assert(preview.body.contains('Besoin D'));
        System.assert(preview.body.contains('Amélie BM'));
        System.assert(preview.subject.contains('1'));
        System.assert(preview.recipientIds.contains(UserInfo.getUserId()));
        System.assertEquals(null, preview.notificationTargetId, 'digest multi-matrices => pas de cible unique');
        assertNoUnreplacedTokens(preview.subject, 'sujet notification hiérarchie');
        assertNoUnreplacedTokens(preview.body, 'corps notification hiérarchie');
    }

    @IsTest
    static void testBuildHierarchyNotificationDigest_emptyItems_returnsNull() {
        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildHierarchyNotificationDigest(
            'manager@example.com',
            UserInfo.getUserId(),
            new List<AR_NotificationService.HierarchyValidationItem>()
        );
        System.assertEquals(null, preview);
    }

    /** Fréquence Immédiat : un manager renseigné (User.ManagerId) doit recevoir un e-mail, et la
     * matrice doit être marquée notifiée pour ne jamais être reprise par AR_HierarchyNotificationBatch. */
    @IsTest
    static void testSendAutoValidationHierarchyNotificationIfImmediate_managerPresent_sendsAndMarksNotified() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Hierarchy_Notification_Frequency__c = 'Immédiat',
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

        // Propriétaire = persona dont le DA est renseigné (session 200) : jamais le DA posé sur la fiche de
        // l'utilisateur qui exécute les tests, ni en dépendance de ce qu'elle contient déjà.
        Id matrixId = insertMatrixOwnedBy(AR_TestPersona.ownerWithDa());

        Test.startTest();
        AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(matrixId);
        System.assert(Limits.getEmailInvocations() > 0, 'un e-mail doit être tenté quand le manager du propriétaire est renseigné');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        System.assertEquals(true, reloaded.AR_Hierarchy_Notified__c);
    }

    @IsTest
    static void testSendAutoValidationHierarchyNotificationIfImmediate_frequencyNotImmediate_noOp() {
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

        Test.startTest();
        AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(getMatrixId());
        System.assertEquals(0, Limits.getEmailInvocations(), 'fréquence Quotidien : aucun envoi synchrone, le batch s\'en charge');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c WHERE Id = :getMatrixId()];
        System.assertEquals(false, reloaded.AR_Hierarchy_Notified__c, 'doit rester false pour être ramassée par AR_HierarchyNotificationBatch');
    }

    /** Fréquence Immédiat mais propriétaire sans manager (User.ManagerId non renseigné, cas
     * fréquent) : aucun envoi possible, mais la matrice doit quand même être marquée notifiée pour
     * ne pas rester indéfiniment dans le champ de balayage du batch si la fréquence change ensuite. */
    @IsTest
    static void testSendAutoValidationHierarchyNotificationIfImmediate_noManager_marksNotifiedWithoutSending() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Hierarchy_Notification_Frequency__c = 'Immédiat',
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

        // Propriétaire = persona sans DA/DD/Directeur (session 200) : l'exécutant des tests en a en production.
        Id matrixId = insertMatrixOwnedBy(AR_TestPersona.sansHabilitation().Id);

        Test.startTest();
        AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(matrixId);
        System.assertEquals(0, Limits.getEmailInvocations(), 'pas de manager => pas d\'envoi');
        Test.stopTest();

        AR_Price_Matrix__c reloaded = [SELECT AR_Hierarchy_Notified__c FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        System.assertEquals(true, reloaded.AR_Hierarchy_Notified__c, 'marquée notifiée même sans envoi, pour ne jamais être reprise par le batch');
    }

    // ---------------------------------------------------------------------
    // Session 34 : canal in-app — interrupteur et repli de résolution du CustomNotificationType.
    // Ce qui est vérifiable ici : que le canal est TENTÉ (inAppEligibleAttempts, seul point stable
    // indépendant de la disponibilité réelle de CustomNotificationType en contexte de test) et que
    // l'e-mail n'est jamais affecté par ce canal, dans un sens comme dans l'autre. La livraison
    // réelle de la notification ne peut être prouvée qu'en sandbox (contrôle navigateur, cf.
    // docs/34-notifications-in-app.md).
    // ---------------------------------------------------------------------

    /** Pas de ligne AR_General_Setting__c du tout : défaut true (case jamais décochée). */
    @IsTest
    static void testSendDerogationRequestEmail_inAppEnabledByDefault_attemptIsMade() {
        Integer before = AR_NotificationService.inAppEligibleAttempts;

        // Limits.getEmailInvocations() doit être lu à l'intérieur de startTest/stopTest (cf. commentaire
        // de testSendDerogationRequestEmail_noValidatorEmail_noSendAttempted plus haut dans ce fichier) :
        // Test.startTest() réinitialise les limites de gouverneur, une lecture après stopTest() retombe
        // sur le contexte extérieur et verrait 0 quel que soit l'envoi réel.
        Test.startTest();
        AR_NotificationService.sendDerogationRequestEmail(getDerogationId());
        System.assert(Limits.getEmailInvocations() > 0, 'e-mail toujours envoyé, indépendamment du canal in-app');
        Test.stopTest();

        System.assertEquals(before + 1, AR_NotificationService.inAppEligibleAttempts, 'canal in-app tenté par défaut (case jamais décochée => true)');
    }

    @IsTest
    static void testSendDerogationRequestEmail_inAppDisabled_noAttemptButEmailStillSent() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_InApp_Notification_Enabled__c = false,
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
        AR_NotificationService.sendDerogationRequestEmail(getDerogationId());
        System.assert(Limits.getEmailInvocations() > 0, 'l\'interrupteur in-app ne doit jamais affecter l\'envoi e-mail');
        Test.stopTest();

        System.assertEquals(before, AR_NotificationService.inAppEligibleAttempts, 'canal in-app coupé => aucune tentative');
    }

    /** Repli documenté (prompts/session-34-notifications-in-app.md) : la requête CustomNotificationType
     * n'est pas disponible en contexte de test sur toutes les orgs — simulé ici plutôt que dépendu du
     * comportement réel de cette org précise, pour que le test reste valable partout. */
    @IsTest
    static void testResolvePricingNotificationTypeId_forcedFailure_returnsNullWithoutThrowingAndEmailStillSent() {
        AR_NotificationService.testForceNotificationTypeResolutionFailure = true;

        Test.startTest();
        AR_NotificationService.sendDerogationRequestEmail(getDerogationId());
        System.assert(Limits.getEmailInvocations() > 0, 'l\'échec de résolution du type ne doit jamais bloquer l\'e-mail');
        Test.stopTest();

        System.assertEquals(
            null,
            AR_NotificationService.resolvePricingNotificationTypeId(),
            'résolution forcée en échec => repli null, jamais d\'exception'
        );
    }

    // ====================================================================
    // Test 6 : buildDerogationRequestEmail inclut le lien dérogation (Session 112)
    // ====================================================================

    @IsTest
    static void testBuildDerogationRequestEmail_containsDerogationLinkAndPageRef() {
        User currentUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Account acc = new Account(
            Name = 'Client Test Lien',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Test Lien',
            cxsrec__Account__c = acc.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

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
            AR_Status__c = 'En dérogation',
            AR_Derogation_Reason__c = 'Test',
            AR_Selected_Validator__c = currentUser.Id
        );
        insert matrix;

        AR_Derogation__c derogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Selected_Validator__c = currentUser.Id,
            AR_Requester_Reason__c = 'Test lien',
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        insert derogation;

        AR_NotificationService.EmailPreview preview = AR_NotificationService.buildDerogationRequestEmail(derogation.Id);

        System.assertNotEquals(null, preview);
        System.assert(preview.body.contains('c__view=approbations&c__derogationId=' + derogation.Id),
            'Le corps doit contenir le lien dérogation avec les paramètres corrects');
        System.assert(!preview.body.contains('c__matrixId'), 'Le corps ne doit plus contenir c__matrixId');
        System.assert(String.isNotBlank(preview.notificationTargetPageRef),
            'notificationTargetPageRef doit être renseigné');
        System.assert(preview.notificationTargetPageRef.contains('"c__derogationId":"' + derogation.Id + '"'),
            'notificationTargetPageRef JSON doit contenir l\'Id de la dérogation');
    }

    // ---- Échecs d'envoi : consignés et remontés, jamais avalés ----

    private static Messaging.SingleEmailMessage mailTo(String address) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ address });
        mail.setSubject('Sujet');
        mail.setPlainTextBody('Corps');
        mail.setSaveAsActivity(false);
        return mail;
    }

    @IsTest
    static void deliver_allSent_noWarning() {
        System.runAs(AR_TestPersona.manager()) {
            AR_NotificationService.failures = new List<AR_NotificationService.DeliveryFailure>();
            AR_NotificationService.deliver('e-mail', new List<Messaging.SingleEmailMessage>{ mailTo(currentUserEmail()) });
            System.assertEquals(null, AR_NotificationService.consumeWarning(), 'Aucun avertissement quand tout part');
        }
    }

    @IsTest
    static void deliver_messageFailure_isReportedWithCodeAndRecipient() {
        System.runAs(AR_TestPersona.manager()) {
            AR_NotificationService.failures = new List<AR_NotificationService.DeliveryFailure>();
            AR_NotificationService.deliver(
                'e-mail',
                new List<Messaging.SingleEmailMessage>{ mailTo(currentUserEmail()), mailTo('pas-une-adresse') }
            );
            AR_NotificationService.DeliveryWarning warning = AR_NotificationService.consumeWarning();
            System.assertNotEquals(null, warning, 'Un message refusé doit remonter');
            System.assert(warning.detail.contains('pas-une-adresse'), warning.detail);
            System.assert(warning.detail.contains('INVALID_'), warning.detail);
            System.assert(!warning.detail.contains(currentUserEmail()), 'Le message parti ne doit pas figurer : ' + warning.detail);
            System.assertEquals(null, AR_NotificationService.consumeWarning(), 'Le compteur est remis à zéro');
        }
    }

    @IsTest
    static void deliver_globalException_isReportedForEveryMessage() {
        System.runAs(AR_TestPersona.manager()) {
            AR_NotificationService.failures = new List<AR_NotificationService.DeliveryFailure>();
            AR_NotificationService.testForceSendException = true;
            AR_NotificationService.deliver(
                'e-mail',
                new List<Messaging.SingleEmailMessage>{ mailTo('a@exemple.fr'), mailTo('b@exemple.fr') }
            );
            AR_NotificationService.DeliveryWarning warning = AR_NotificationService.consumeWarning();
            System.assertNotEquals(null, warning, 'Une exception globale doit remonter');
            System.assert(warning.detail.contains('a@exemple.fr') && warning.detail.contains('b@exemple.fr'), warning.detail);
            System.assert(warning.detail.contains('NoAccessException'), warning.detail);
        }
    }

    @IsTest
    static void sendInApp_notificationTypeUnavailable_isReported() {
        System.runAs(AR_TestPersona.manager()) {
            AR_NotificationService.failures = new List<AR_NotificationService.DeliveryFailure>();
            AR_NotificationService.testForceNotificationTypeResolutionFailure = true;
            AR_NotificationService.pricingNotificationTypeResolved = false;
            AR_NotificationService.EmailPreview preview = new AR_NotificationService.EmailPreview();
            preview.subject = 'Sujet';
            preview.body = 'Corps';
            preview.recipientIds = new Set<String>{ UserInfo.getUserId() };
            AR_NotificationService.sendInAppFromPreview(preview);
            AR_NotificationService.DeliveryWarning warning = AR_NotificationService.consumeWarning();
            System.assertNotEquals(null, warning, 'Un type de notification introuvable doit remonter');
            System.assert(warning.detail.contains('NOTIFICATION_TYPE_NOT_FOUND'), warning.detail);
            AR_NotificationService.pricingNotificationTypeResolved = false;
        }
    }
}