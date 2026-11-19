/**
 * Tests d'intégration du trigger AR_QualificationGatingTrigger / AR_QualificationGatingHandler.
 * Données Connexys construites en @TestSetup (même moule que AR_MatrixListServiceTest et
 * LTNG_Mobilities_TEST). Le statut "2. Qualification en cours" est un cxsrec__cxsWorkflow_status__c
 * entièrement synthétique (pas de SeeAllData).
 *
 * La DML sur AR_Gating_Setting__mdt s'est révélée indisponible dans cet org, même en contexte de
 * test — chaque méthode configure la politique via AR_QualificationGatingHandler.testOverrideSettings
 * (point d'extension @TestVisible) plutôt que par mise à jour du record Default réel.
 */
@IsTest
private class AR_QualificationGatingHandlerTest {

    @TestSetup
    static void setup() {
        cxsrec__cxsWorkflow__c workflow = new cxsrec__cxsWorkflow__c(cxsrec__Default_user__c = UserInfo.getUserId());
        insert workflow;

        cxsrec__cxsWorkflow_status__c qualificationStatus = new cxsrec__cxsWorkflow_status__c(
            Name = 'Test Qualification en cours',
            cxsrec__Workflow__c = workflow.Id,
            cxsrec__Display_order__c = 1
        );
        insert qualificationStatus;

        Account acc = new Account(
            Name = 'Client Gating Test',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c vacancyPosition = new cxsrec__cxsPosition__c(
            Name = 'Besoin Gating Test', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert vacancyPosition; // record type par défaut = Vacancy

        Id externalCandidateRT = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName().get('External_candidate').getRecordTypeId();
        List<cxsrec__cxsCandidate__c> candidates = new List<cxsrec__cxsCandidate__c>();
        for (Integer i = 0; i < 210; i++) {
            candidates.add(new cxsrec__cxsCandidate__c(
                RecordTypeId = externalCandidateRT,
                cxsrec__First_name__c = 'Test' + i,
                cxsrec__Last_name__c = 'Candidat' + i
            ));
        }
        insert candidates;

        insert new cxsrec__cxsJob_application__c(
            Name = 'JA Gating Test',
            cxsrec__Position__c = vacancyPosition.Id,
            cxsrec__Candidate__c = candidates[0].Id
        );
    }

    private static Id qualificationStatusId() {
        return [SELECT Id FROM cxsrec__cxsWorkflow_status__c WHERE Name = 'Test Qualification en cours' LIMIT 1].Id;
    }

    /**
     * Construit une politique de gating complète en mémoire (baseline sûre + overrides) et
     * l'installe sur AR_QualificationGatingHandler.testOverrideSettings. À appeler en tout début de
     * chaque méthode de test qui exerce le trigger.
     */
    private static void configureGating(Map<String, Object> overrides) {
        AR_Gating_Setting__mdt settings = new AR_Gating_Setting__mdt(
            AR_Gating_Enabled__c = true,
            AR_Qualification_Status_Id__c = qualificationStatusId(),
            AR_Severity_No_Matrix__c = 'Warning',
            AR_Severity_Derogation_Pending__c = 'Warning',
            AR_Excluded_Countries__c = null,
            AR_Go_Live_Date__c = Date.newInstance(2020, 1, 1)
        );
        for (String fieldName : overrides.keySet()) {
            settings.put(fieldName, overrides.get(fieldName));
        }
        AR_QualificationGatingHandler.testOverrideSettings = settings;
    }

    private static cxsrec__cxsJob_application__c getSetupJobApplication() {
        return [
            SELECT Id, cxsrec__Workflow_status__c, cxsrec__Position__c, AR_Gating_Case__c, AR_Gating_Severity__c, AR_Gating_Evaluated_Date__c
            FROM cxsrec__cxsJob_application__c
            WHERE Name = 'JA Gating Test'
            LIMIT 1
        ];
    }

    private static cxsrec__cxsPosition__c getVacancyPosition() {
        return [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Gating Test' LIMIT 1];
    }

    private static User createTestUser(String uniqueSuffix) {
        User u = new User(
            LastName = 'GatingTest' + uniqueSuffix,
            Alias = 'gt' + uniqueSuffix.right(5),
            Email = 'ar.gating.test' + uniqueSuffix + '@hby.test.invalid',
            Username = 'ar.gating.test' + uniqueSuffix + '@hby.test.invalid',
            FederationIdentifier = 'ar.gating.test' + uniqueSuffix,
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'fr'
        );
        insert u;
        return u;
    }

    // 1. Test négatif obligatoire (session 21) : besoin avec matrice validée passe sans obstacle.
    @IsTest
    static void testValidatedMatrix_conformeNoBlock() {
        configureGating(new Map<String, Object>());
        cxsrec__cxsPosition__c position = getVacancyPosition();
        insert new AR_Price_Matrix__c(AR_Position__c = position.Id, AR_Status__c = 'Validée');
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();

        Test.startTest();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();
        update jobApp;
        Test.stopTest();

        cxsrec__cxsJob_application__c result = getSetupJobApplication();
        System.assertEquals('Conforme', result.AR_Gating_Case__c);
        System.assertEquals('Ignoré', result.AR_Gating_Severity__c);
        System.assertEquals(Date.today(), result.AR_Gating_Evaluated_Date__c);
    }

    @IsTest
    static void testValidatedByDerogation_conformeNoBlock() {
        configureGating(new Map<String, Object>());
        cxsrec__cxsPosition__c position = getVacancyPosition();
        insert new AR_Price_Matrix__c(AR_Position__c = position.Id, AR_Status__c = 'Validée par dérogation');
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();

        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();
        update jobApp;

        System.assertEquals('Conforme', getSetupJobApplication().AR_Gating_Case__c);
    }

    @IsTest
    static void testNoMatrix_warningConfig_noBlock() {
        configureGating(new Map<String, Object>());
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();

        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();
        update jobApp; // config par défaut = Warning

        cxsrec__cxsJob_application__c result = getSetupJobApplication();
        System.assertEquals('Sans matrice validée', result.AR_Gating_Case__c);
        System.assertEquals('Avertissement', result.AR_Gating_Severity__c);
    }

    @IsTest
    static void testNoMatrix_blockingConfig_addsErrorExactMessage() {
        configureGating(new Map<String, Object>{ 'AR_Severity_No_Matrix__c' => 'Blocking' });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(false, result.isSuccess());
        System.assertEquals(
            Label.AR_Gating_Blocking_Message,
            result.getErrors()[0].getMessage()
        );
    }

    // 2. Preuve que la sévérité "dérogation en attente" est un paramètre : même état de matrice,
    // seule la config change entre les deux méthodes ci-dessous.
    @IsTest
    static void testDerogationPending_warningConfig_noBlock() {
        cxsrec__cxsPosition__c position = getVacancyPosition();
        insert new AR_Price_Matrix__c(AR_Position__c = position.Id, AR_Status__c = 'En dérogation');
        configureGating(new Map<String, Object>{ 'AR_Severity_Derogation_Pending__c' => 'Warning' });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();

        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();
        update jobApp;

        cxsrec__cxsJob_application__c result = getSetupJobApplication();
        System.assertEquals('Dérogation en attente', result.AR_Gating_Case__c);
        System.assertEquals('Avertissement', result.AR_Gating_Severity__c);
    }

    @IsTest
    static void testDerogationPending_blockingConfig_addsError() {
        cxsrec__cxsPosition__c position = getVacancyPosition();
        insert new AR_Price_Matrix__c(AR_Position__c = position.Id, AR_Status__c = 'En dérogation');
        configureGating(new Map<String, Object>{ 'AR_Severity_Derogation_Pending__c' => 'Blocking' });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(false, result.isSuccess(), 'Même état de matrice qu\'en Warning : seule la config a changé, preuve que la sévérité est paramétrable');
    }

    @IsTest
    static void testBesoinAvantBascule_plafonneAvertissement_memeSiConfigBloquant() {
        // Position et Job Application dédiées, insérées dans cette même méthode : Test.setCreatedDate
        // ne s'applique pas de façon fiable à un enregistrement partagé venant de @TestSetup.
        Account acc = [SELECT Id FROM Account LIMIT 1];
        cxsrec__cxsPosition__c freshPosition = new cxsrec__cxsPosition__c(
            Name = 'Besoin Avant Bascule', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert freshPosition;
        Test.setCreatedDate(freshPosition.Id, Datetime.newInstance(2020, 1, 1, 0, 0, 0));

        configureGating(new Map<String, Object>{
            'AR_Severity_No_Matrix__c' => 'Blocking',
            'AR_Go_Live_Date__c' => Date.newInstance(2026, 1, 1)
        });
        cxsrec__cxsCandidate__c candidate = [SELECT Id FROM cxsrec__cxsCandidate__c LIMIT 1 OFFSET 2];
        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(
            Name = 'JA Avant Bascule', cxsrec__Position__c = freshPosition.Id, cxsrec__Candidate__c = candidate.Id
        );
        insert jobApp;
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(true, result.isSuccess(), 'Besoin créé avant la date de bascule : jamais bloquant');
        cxsrec__cxsJob_application__c reloaded = [SELECT AR_Gating_Severity__c FROM cxsrec__cxsJob_application__c WHERE Id = :jobApp.Id];
        System.assertEquals('Avertissement', reloaded.AR_Gating_Severity__c);
    }

    @IsTest
    static void testBesoinApresBascule_severiteConfigureeDirecte_sansDelai() {
        // Le besoin créé en @TestSetup a déjà une CreatedDate "maintenant", donc déjà postérieure à
        // n'importe quelle date de bascule passée — pas besoin de Test.setCreatedDate ici.
        configureGating(new Map<String, Object>{
            'AR_Severity_No_Matrix__c' => 'Blocking',
            'AR_Go_Live_Date__c' => Date.newInstance(2020, 1, 1)
        });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(false, result.isSuccess(), 'Besoin créé à partir de la date de bascule : sévérité configurée immédiatement, sans délai de grâce');
    }

    @IsTest
    static void testPaysExclu_horsPerimetre_aucunChampRenseigne() {
        configureGating(new Map<String, Object>{
            'AR_Severity_No_Matrix__c' => 'Blocking',
            'AR_Excluded_Countries__c' => 'Maroc;France'
        });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(true, result.isSuccess(), 'Pays exclu : jamais bloquant même en config Blocking');
        System.assertEquals(null, getSetupJobApplication().AR_Gating_Case__c, 'Hors périmètre : aucun champ renseigné');
    }

    /**
     * Le record type métier "Offre" (docs/21-gating.md §4, hors périmètre par construction) n'est
     * pas assignable par l'utilisateur technique qui exécute les tests dans cette sandbox — vérifié
     * en amont (isAvailable() = false), et confirmé par un échec INVALID_CROSS_REFERENCE_KEY à
     * l'implémentation. Cette exclusion précise est donc vérifiée par l'essai réel en sandbox
     * (docs/21-gating.md, protocole de vérification), pas ici. Ce test exerce la même ligne de garde
     * du handler (`position == null || ...`) via une Job Application non rattachée à un besoin —
     * un cas limite réel et légitime en soi (candidature orpheline).
     */
    @IsTest
    static void testBesoinIntrouvable_horsPerimetre_aucunChampRenseigne() {
        configureGating(new Map<String, Object>{ 'AR_Severity_No_Matrix__c' => 'Blocking' });
        cxsrec__cxsCandidate__c candidate = [SELECT Id FROM cxsrec__cxsCandidate__c LIMIT 1];
        cxsrec__cxsJob_application__c orphanJobApp = new cxsrec__cxsJob_application__c(
            Name = 'JA Sans Besoin Gating Test',
            cxsrec__Candidate__c = candidate.Id,
            cxsrec__Workflow_status__c = qualificationStatusId()
        );

        Database.SaveResult result = Database.insert(orphanJobApp, false);

        System.assertEquals(true, result.isSuccess(), 'Besoin introuvable/absent hors périmètre : jamais bloqué');
        cxsrec__cxsJob_application__c reloaded = [SELECT AR_Gating_Case__c FROM cxsrec__cxsJob_application__c WHERE Id = :orphanJobApp.Id];
        System.assertEquals(null, reloaded.AR_Gating_Case__c);
    }

    @IsTest
    static void testUtilisateurAvecPermissionBypass_ignoreTout_memeSiBloquant() {
        configureGating(new Map<String, Object>{ 'AR_Severity_No_Matrix__c' => 'Blocking' });
        User bypassUser = createTestUser('bypass');
        PermissionSet bypassPermSet = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Gating_Bypass' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = bypassUser.Id, PermissionSetId = bypassPermSet.Id);

        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        Id targetStatusId = qualificationStatusId();

        System.runAs(bypassUser) {
            jobApp.cxsrec__Workflow_status__c = targetStatusId;
            Database.SaveResult result = Database.update(jobApp, false);
            System.assertEquals(true, result.isSuccess(), 'Utilisateur avec permission bypass : jamais bloqué, même en config Blocking');
        }
        System.assertEquals(null, getSetupJobApplication().AR_Gating_Case__c, 'Bypass : aucune évaluation, aucun champ renseigné');
    }

    @IsTest
    static void test200EnregistrementsBulk_sansDepassementLimites() {
        configureGating(new Map<String, Object>());
        cxsrec__cxsPosition__c position = getVacancyPosition();
        List<cxsrec__cxsCandidate__c> candidates = [SELECT Id FROM cxsrec__cxsCandidate__c LIMIT 200 OFFSET 1];
        List<cxsrec__cxsJob_application__c> jobApps = new List<cxsrec__cxsJob_application__c>();
        for (Integer i = 0; i < candidates.size(); i++) {
            jobApps.add(new cxsrec__cxsJob_application__c(
                Name = 'JA Bulk ' + i,
                cxsrec__Position__c = position.Id,
                cxsrec__Candidate__c = candidates[i].Id
            ));
        }
        insert jobApps;
        Id targetStatusId = qualificationStatusId();
        for (cxsrec__cxsJob_application__c jobApp : jobApps) {
            jobApp.cxsrec__Workflow_status__c = targetStatusId;
        }

        Test.startTest();
        update jobApps;
        Test.stopTest();

        Integer nonNullCount = 0;
        for (cxsrec__cxsJob_application__c result : [
            SELECT AR_Gating_Case__c FROM cxsrec__cxsJob_application__c WHERE Id IN :jobApps
        ]) {
            if (result.AR_Gating_Case__c != null) {
                nonNullCount++;
            }
        }
        System.assertEquals(200, nonNullCount, 'Les 200 enregistrements doivent être évalués');
    }

    @IsTest
    static void testReferenceStatutIntrouvable_alerteVisible_pasDeNoOpSilencieux() {
        configureGating(new Map<String, Object>{ 'AR_Qualification_Status_Id__c' => '000000000000000AAA' });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();

        Test.startTest();
        jobApp.Name = 'JA Gating Test Renommée';
        update jobApp; // ne transite pas vers la qualification, mais le contrôle de résolution doit tout de même s'exécuter
        // Lu AVANT Test.stopTest() : le compteur repart à zéro après (piège déjà documenté dans
        // AR_NotificationServiceTest) — session 132, l'assertion placée après échouait alors que
        // l'e-mail partait bel et bien (EMAIL_QUEUE dans le journal d'exécution).
        System.assert(Limits.getEmailInvocations() > 0, 'Référence introuvable : une alerte doit être envoyée, pas un silence total');
        Test.stopTest();
    }

    /**
     * Session 132 : le gating est livré désactivé (AR_Gating_Setting__mdt.Default, pas assez mûr).
     * Aucune substitution de politique ici : c'est la VRAIE valeur déployée qui est exercée — une
     * transition vers « 2. Qualification en cours » sans aucune matrice n'est ni bloquée ni signalée.
     */
    @IsTest
    static void testGatingLivreDesactive_transitionNiBloqueeNiAvertie() {
        AR_QualificationGatingHandler.testOverrideSettings = null;
        System.assertEquals(
            false,
            AR_Gating_Setting__mdt.getInstance('Default').AR_Gating_Enabled__c,
            'Le gating doit être livré désactivé'
        );
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Test.startTest();
        Database.SaveResult result = Database.update(jobApp, false);
        System.assertEquals(0, Limits.getEmailInvocations(), 'Gating désactivé : aucun avertissement');
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Gating désactivé : aucun blocage');
        System.assertEquals(null, getSetupJobApplication().AR_Gating_Case__c, 'Aucune évaluation écrite');
    }

    @IsTest
    static void testArretUrgence_desactiveTout() {
        configureGating(new Map<String, Object>{
            'AR_Severity_No_Matrix__c' => 'Blocking',
            'AR_Gating_Enabled__c' => false
        });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.SaveResult result = Database.update(jobApp, false);

        System.assertEquals(true, result.isSuccess(), 'Arrêt d\'urgence actif : aucun contrôle, même en config Blocking');
        System.assertEquals(null, getSetupJobApplication().AR_Gating_Case__c);
    }

    @IsTest
    static void testDejaEnQualification_updateSansTransition_neSeRedeclenchePas() {
        configureGating(new Map<String, Object>());
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();
        update jobApp; // config Warning par défaut : passe, champs renseignés

        cxsrec__cxsJob_application__c afterFirstTransition = getSetupJobApplication();
        System.assertNotEquals(null, afterFirstTransition.AR_Gating_Case__c);

        configureGating(new Map<String, Object>{ 'AR_Severity_No_Matrix__c' => 'Blocking' });
        cxsrec__cxsJob_application__c sameRecord = getSetupJobApplication();
        sameRecord.Name = 'JA Gating Test Renommée Encore';
        Database.SaveResult result = Database.update(sameRecord, false);

        System.assertEquals(true, result.isSuccess(), 'Déjà en qualification, pas de transition : ne se redéclenche pas même en config Blocking');
    }

    @IsTest
    static void testInsertionDirecteEnQualification_transitionDetectee() {
        // Appel direct du handler (oldMap = null, comme au before insert) plutôt qu'une vraie DML
        // insert : un flow Connexys préexistant sur la création de Job Application ("Job Application
        // - create - after") échoue sur les données minimales de ce jeu de test pour une raison sans
        // rapport avec le gating (picklist "Type de parcours") — sans intérêt à contourner ici,
        // ce test isolé vérifie exactement la même branche de code (oldMap == null ⇒ transition
        // depuis rien) sans dépendre de cette automatisation tierce.
        configureGating(new Map<String, Object>());
        cxsrec__cxsPosition__c position = getVacancyPosition();

        cxsrec__cxsJob_application__c newJobApp = new cxsrec__cxsJob_application__c(
            cxsrec__Position__c = position.Id,
            cxsrec__Workflow_status__c = qualificationStatusId()
        );

        AR_QualificationGatingHandler.beforeSave(new List<cxsrec__cxsJob_application__c>{ newJobApp }, null);

        System.assertEquals('Sans matrice validée', newJobApp.AR_Gating_Case__c, 'Insertion directe (oldMap=null) dans le statut cible = une transition, doit être évaluée');
    }

    @IsTest
    static void testSeveriteBloquante_jamaisPersisteeeSurLeChamp() {
        configureGating(new Map<String, Object>{ 'AR_Severity_No_Matrix__c' => 'Blocking' });
        cxsrec__cxsJob_application__c jobApp = getSetupJobApplication();
        jobApp.cxsrec__Workflow_status__c = qualificationStatusId();

        Database.update(jobApp, false);

        cxsrec__cxsJob_application__c reloaded = getSetupJobApplication();
        System.assertNotEquals('Bloquant', reloaded.AR_Gating_Severity__c, 'Un enregistrement bloqué n\'est jamais committé : le champ ne peut jamais valoir Bloquant');
        System.assertEquals(null, reloaded.AR_Gating_Severity__c);
    }
}