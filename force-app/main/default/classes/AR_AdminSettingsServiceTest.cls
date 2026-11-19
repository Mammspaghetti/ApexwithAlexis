/**
 * Tests AR_AdminSettingsService : paramètres généraux (singleton), exceptions jours travaillés,
 * titres valideurs, paliers de séniorité — CRUD et refus d'accès non-admin (System.runAs).
 */
@IsTest
private class AR_AdminSettingsServiceTest {

    private static User newNonAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'AdminSettingsTest',
            FirstName = 'AR',
            Alias = 'arast',
            Email = 'ar.admin.settings.test@abylsengroup.com.invalid',
            Username = 'ar.admin.settings.test@abylsengroup.com.invalid.' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.admin.settings.test.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    @IsTest
    static void testGetGeneralSettings_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();

        Test.startTest();
        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminSettingsService.getGeneralSettings();
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'La lecture des paramètres généraux doit être réservée au domaine Paramètres généraux (AR_Admin_General_Settings)');
    }

    @IsTest
    static void testSaveGeneralSettings_nonAdmin_throws() {
        User nonAdmin = newNonAdminUser();
        String payload = JSON.serialize(
            new Map<String, Object>{ 'floorPercentDefault' => 20, 'workingDaysPerYear' => 218 }
        );

        Test.startTest();
        Boolean threw = false;
        System.runAs(nonAdmin) {
            try {
                AR_AdminSettingsService.saveGeneralSettings(payload);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_General_Setting__c],
            'Aucun enregistrement ne doit être créé par un utilisateur non-admin'
        );
        System.assert(threw, 'L\'écriture des paramètres généraux doit être réservée au domaine Paramètres généraux (AR_Admin_General_Settings)');
    }

    @IsTest
    static void testSaveGeneralSettings_createsThenUpdatesSingleton() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 20;
            dto.targetPercentDefault = 25;
            dto.idealPercentDefault = 30;
            dto.workingDaysPerYear = 218;
            dto.markupPercent = 18;
            dto.markupMax = 60;
            dto.maxDerogationPenalty = 70;
            dto.draftPurgeEnabled = false;
            dto.draftPurgeDays = 30;
            dto.draftPurgeWarningDays = 5;
            dto.draftPurgeMaxPerRun = 200;

            Test.startTest();
            AR_AdminSettingsService.GeneralSettingsDto created = AR_AdminSettingsService.saveGeneralSettings(
                JSON.serialize(dto)
            );
            System.assertNotEquals(null, created.id);

            created.workingDaysPerYear = 220;
            AR_AdminSettingsService.GeneralSettingsDto updated = AR_AdminSettingsService.saveGeneralSettings(
                JSON.serialize(created)
            );
            Test.stopTest();

            System.assertEquals(created.id, updated.id, 'Un second enregistrement du singleton doit mettre à jour, pas dupliquer');
            System.assertEquals(220, updated.workingDaysPerYear);
            System.assertEquals(
                1,
                [SELECT COUNT() FROM AR_General_Setting__c],
                'Le singleton ne doit jamais se dupliquer'
            );

            AR_AdminSettingsService.GeneralSettingsDto reloaded = AR_AdminSettingsService.getGeneralSettings();
            System.assertEquals(220, reloaded.workingDaysPerYear);
            System.assertNotEquals(null, reloaded.lastModifiedByName, 'La traçabilité (qui) doit être exposée');
            System.assertNotEquals(null, reloaded.lastModifiedDate, 'La traçabilité (quand) doit être exposée');
        }
    }

    /** Session 29 : les nouveaux paramètres de relance/escalade dérogation et de notification
     * hiérarchie doivent survivre à un aller-retour save/get, comme tout le reste du singleton. */
    @IsTest
    static void testSaveGeneralSettings_derogationReminderAndHierarchyFields_roundTrip() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 20;
            dto.targetPercentDefault = 25;
            dto.idealPercentDefault = 30;
            dto.workingDaysPerYear = 218;
            dto.markupPercent = 18;
            dto.markupMax = 60;
            dto.maxDerogationPenalty = 70;
            dto.draftPurgeEnabled = false;
            dto.draftPurgeDays = 30;
            dto.draftPurgeWarningDays = 5;
            dto.draftPurgeMaxPerRun = 200;
            dto.derogationReminderEnabled = true;
            dto.derogationReminderHours = 12;
            dto.derogationEscalationHours = 48;
            dto.derogationReminderMaxPerRun = 200;
            dto.derogationEscalationMaxRecipients = 20;
            dto.hierarchyNotificationFrequency = 'Hebdomadaire';
            dto.inAppNotificationEnabled = false;

            Test.startTest();
            AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            Test.stopTest();

            AR_AdminSettingsService.GeneralSettingsDto reloaded = AR_AdminSettingsService.getGeneralSettings();
            System.assertEquals(true, reloaded.derogationReminderEnabled);
            System.assertEquals(12, reloaded.derogationReminderHours);
            System.assertEquals(48, reloaded.derogationEscalationHours);
            System.assertEquals(200, reloaded.derogationReminderMaxPerRun);
            System.assertEquals(20, reloaded.derogationEscalationMaxRecipients);
            System.assertEquals('Hebdomadaire', reloaded.hierarchyNotificationFrequency);
            System.assertEquals(false, reloaded.inAppNotificationEnabled, 'la bascule in-app doit survivre à l\'aller-retour, décochée comme tout autre booléen');
        }
    }

    /** Session 34 : la case n'a jamais été décochée par personne (dto.inAppNotificationEnabled
     * null, ex. premier enregistrement du singleton) => défaut true, jamais un null explicite en DML
     * (même piège documenté pour AR_Derogation_Reminder_Enabled__c, avec le défaut inverse ici). */
    @IsTest
    static void testSaveGeneralSettings_inAppNotificationEnabledNull_defaultsToTrue() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 20;
            dto.targetPercentDefault = 25;
            dto.idealPercentDefault = 30;
            dto.workingDaysPerYear = 218;
            dto.markupPercent = 18;
            dto.markupMax = 60;
            dto.maxDerogationPenalty = 70;
            dto.draftPurgeEnabled = false;
            dto.draftPurgeDays = 30;
            dto.draftPurgeWarningDays = 5;
            dto.draftPurgeMaxPerRun = 200;

            Test.startTest();
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            Test.stopTest();

            System.assertEquals(true, saved.inAppNotificationEnabled, 'case jamais décochée => défaut true, pas un null qui ferait échouer le DML');
        }
    }

    /**
     * Le point le plus important de la session : une matrice déjà validée avec les seuils en
     * vigueur à ce moment-là ne doit jamais changer de valeur si les paramètres généraux sont
     * modifiés après coup — la donnée calculée est stockée sur la matrice, jamais recalculée à la
     * lecture.
     */
    @IsTest
    static void testChangingGeneralSettings_afterValidation_neverAffectsDecidedMatrix() {
        User admin = AR_TestPersona.adminGeneral();
        Account acc = new Account(
            Name = 'Client Non Regression',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Non Regression', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        dto.floorPercentDefault = 20;
        dto.targetPercentDefault = 25;
        dto.idealPercentDefault = 30;
        dto.workingDaysPerYear = 218;
        dto.markupPercent = 18;
        dto.markupMax = 60;
        dto.maxDerogationPenalty = 70;
        dto.draftPurgeEnabled = false;
        dto.draftPurgeDays = 30;
        dto.draftPurgeWarningDays = 5;
        dto.draftPurgeMaxPerRun = 200;
        System.runAs(admin) {
            AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
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
        input.proposedTjm = 700;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
        AR_Price_Matrix__c beforeChange = [
            SELECT AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_MC2_Percent__c, AR_Total_Daily_Cost__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];

        Test.startTest();
        // Changement radical des seuils par défaut après la décision.
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto changed = AR_AdminSettingsService.getGeneralSettings();
            changed.floorPercentDefault = 5;
            changed.targetPercentDefault = 8;
            changed.idealPercentDefault = 12;
            changed.workingDaysPerYear = 200;
            changed.markupPercent = 30;
            AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(changed));
        }
        Test.stopTest();

        AR_Price_Matrix__c afterChange = [
            SELECT AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_MC2_Percent__c, AR_Total_Daily_Cost__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(beforeChange.AR_TJM_Floor__c, afterChange.AR_TJM_Floor__c, 'Le plancher figé ne doit pas bouger');
        System.assertEquals(beforeChange.AR_TJM_Target__c, afterChange.AR_TJM_Target__c, 'La cible figée ne doit pas bouger');
        System.assertEquals(beforeChange.AR_TJM_Ideal__c, afterChange.AR_TJM_Ideal__c, 'L\'idéal figé ne doit pas bouger');
        System.assertEquals(beforeChange.AR_MC2_Percent__c, afterChange.AR_MC2_Percent__c, 'La MC2 % figée ne doit pas bouger');
        System.assertEquals(beforeChange.AR_Total_Daily_Cost__c, afterChange.AR_Total_Daily_Cost__c, 'Le coût total figé ne doit pas bouger');
    }

    @IsTest
    static void testWorkingDaysException_saveAndDelete() {
        // Session 168 : exceptions jours travaillés = vue/saisie de AR_PTF_Entity_Referential__c.AR_Working_Days__c
        AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Name = 'Test Entity', AR_Active__c = true);
        insert entity;
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            Test.startTest();
            AR_AdminSettingsService.saveWorkingDaysException(entity.Id, 210);
            List<AR_AdminSettingsService.WorkingDaysExceptionDto> exceptions = AR_AdminSettingsService.getWorkingDaysExceptions();
            System.assertEquals(1, exceptions.size());
            System.assertEquals(210, exceptions[0].workingDays);

            AR_AdminSettingsService.deleteWorkingDaysException(entity.Id);
            Test.stopTest();

            System.assertEquals(0, AR_AdminSettingsService.getWorkingDaysExceptions().size());
        }
    }

    @IsTest
    static void testWorkingDaysException_entityIsFicheId_roundTripsWithName() {
        // Session 168 : exceptions jours travaillés sont maintenant directement des entités PTF
        // avec AR_Working_Days__c non null. Aucune fiche AR_Working_Days_Exception__c.
        AR_PTF_Entity_Referential__c metz = new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN EST – Metz', AR_Active__c = true);
        insert metz;
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.saveWorkingDaysException(metz.Id, 205);
            List<AR_AdminSettingsService.WorkingDaysExceptionDto> exceptions = AR_AdminSettingsService.getWorkingDaysExceptions();
            System.assertEquals(1, exceptions.size());
            System.assertEquals('ABYLSEN EST – Metz', exceptions[0].entityName);
            System.assertEquals(205, exceptions[0].workingDays);
            System.assertEquals(true, exceptions[0].active);
        }
    }

    @IsTest
    static void testWorkingDaysException_missingEntity_throws() {
        User admin = AR_TestPersona.adminGeneral();
        Boolean threw = false;
        System.runAs(admin) {
            try {
                AR_AdminSettingsService.saveWorkingDaysException(null, 210);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'L\'entité est obligatoire');
    }

    @IsTest
    static void testWorkingDaysException_missingOrInvalidDays_throws() {
        AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Name = 'Test', AR_Active__c = true);
        insert entity;
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            Test.startTest();
            Boolean threwNull = false;
            try {
                AR_AdminSettingsService.saveWorkingDaysException(entity.Id, null);
            } catch (AuraHandledException e) {
                threwNull = true;
            }
            System.assert(threwNull, 'Jours null doit être rejeté');

            Boolean threwZero = false;
            try {
                AR_AdminSettingsService.saveWorkingDaysException(entity.Id, 0);
            } catch (AuraHandledException e) {
                threwZero = true;
            }
            System.assert(threwZero, 'Jours = 0 doit être rejeté');

            Boolean threwHigh = false;
            try {
                AR_AdminSettingsService.saveWorkingDaysException(entity.Id, 367);
            } catch (AuraHandledException e) {
                threwHigh = true;
            }
            System.assert(threwHigh, 'Jours > 366 doit être rejeté');
            Test.stopTest();
        }
    }

    // ------------------------------------------------------------------
    // Session 35 — le singleton ne porte pas ses valeurs par défaut.
    // ------------------------------------------------------------------

    /**
     * Le cas de la PRODUCTION au premier déploiement : aucun singleton en base. Avant ce bloc,
     * getGeneralSettings() renvoyait null, l'écran affichait un formulaire vide, et
     * l'administrateur concluait que rien n'était paramétré pendant que le moteur appliquait le
     * corridor 20/25/30 depuis ses constantes.
     */
    @IsTest
    static void testGetGeneralSettings_noSingleton_returnsEngineDefaultsNotNull() {
        System.assertEquals(0, [SELECT COUNT() FROM AR_General_Setting__c], 'Prérequis du test');
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
        Test.startTest();
        AR_AdminSettingsService.GeneralSettingsDto dto = AR_AdminSettingsService.getGeneralSettings();
        Test.stopTest();

        System.assertNotEquals(null, dto, 'L\'écran ne doit plus recevoir null quand la table est vide');
        System.assertEquals(true, dto.isUnsaved, 'L\'écran doit pouvoir dire que rien n\'est encore enregistré');
        System.assertEquals(null, dto.id);
        System.assertEquals(null, dto.floorPercentDefault, 'La valeur ENREGISTRÉE reste bien absente');
        System.assertNotEquals(null, dto.engineDefaults, 'Mais la valeur APPLIQUÉE doit être servie');
        System.assertEquals(
            AR_PricingCalculator.FLOOR_PERCENT_DEFAULT,
            dto.engineDefaults.floorPercentDefault,
            'Le défaut affiché doit être celui que le moteur applique réellement, pas une copie'
        );
        System.assertEquals(218, dto.engineDefaults.workingDaysPerYear);
        System.assertEquals(true, dto.engineDefaults.inAppNotificationEnabled);
        System.assertEquals('Désactivé', dto.engineDefaults.hierarchyNotificationFrequency);
        }
    }

    /**
     * Le défaut réel corrigé par ce bloc : vider un champ NUMÉRIQUE dans le formulaire écrivait
     * `null` en base sans garde, et le moteur retombait silencieusement sur sa constante — un
     * paramètre invisible à l'écran pilotant un calcul bien réel. Seuls les deux booléens étaient
     * gardés.
     */
    @IsTest
    static void testSaveGeneralSettings_nullNumericFields_neverWrittenAsNull() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        // Tout est null : c'est exactement ce que produit un formulaire dont on vide les champs.

        Test.startTest();
        AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(
            JSON.serialize(dto)
        );
        Test.stopTest();

        AR_General_Setting__c row = [
            SELECT AR_Floor_Percent_Default__c, AR_Target_Percent_Default__c, AR_Ideal_Percent_Default__c,
                   AR_Working_Days_Per_Year__c, AR_Markup_Percent__c, AR_Markup_Max__c,
                   AR_Max_Derogation_Penalty__c, AR_Draft_Purge_Days__c, AR_Draft_Purge_Warning_Days__c,
                   AR_Draft_Purge_Max_Per_Run__c, AR_Derogation_Reminder_Hours__c,
                   AR_Derogation_Escalation_Hours__c, AR_Derogation_Reminder_Max_Per_Run__c,
                   AR_Derogation_Escalation_Max_Recipients__c, AR_Hierarchy_Notification_Frequency__c,
                   AR_InApp_Notification_Enabled__c
            FROM AR_General_Setting__c
            WHERE Id = :saved.id
        ];
        System.assertEquals(20, row.AR_Floor_Percent_Default__c);
        System.assertEquals(25, row.AR_Target_Percent_Default__c);
        System.assertEquals(30, row.AR_Ideal_Percent_Default__c);
        System.assertEquals(218, row.AR_Working_Days_Per_Year__c);
        System.assertEquals(18, row.AR_Markup_Percent__c);
        System.assertEquals(60, row.AR_Markup_Max__c);
        System.assertEquals(70, row.AR_Max_Derogation_Penalty__c);
        System.assertEquals(30, row.AR_Draft_Purge_Days__c);
        System.assertEquals(5, row.AR_Draft_Purge_Warning_Days__c);
        System.assertEquals(200, row.AR_Draft_Purge_Max_Per_Run__c);
        System.assertEquals(12, row.AR_Derogation_Reminder_Hours__c);
        System.assertEquals(48, row.AR_Derogation_Escalation_Hours__c);
        System.assertEquals(200, row.AR_Derogation_Reminder_Max_Per_Run__c);
        System.assertEquals(20, row.AR_Derogation_Escalation_Max_Recipients__c);
        System.assertEquals('Désactivé', row.AR_Hierarchy_Notification_Frequency__c);
        System.assertEquals(true, row.AR_InApp_Notification_Enabled__c);
        }
    }

    /**
     * Une valeur explicitement saisie n'est JAMAIS remplacée par le défaut — la garde ne doit
     * traiter que le vide, sinon elle rendrait les paramètres non modifiables.
     */
    @IsTest
    static void testSaveGeneralSettings_explicitValues_neverReplacedByDefaults() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        dto.floorPercentDefault = 22;
        dto.workingDaysPerYear = 210;
        dto.derogationEscalationHours = 72;
        dto.inAppNotificationEnabled = false;

        Test.startTest();
        AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(
            JSON.serialize(dto)
        );
        Test.stopTest();

        System.assertEquals(22, saved.floorPercentDefault);
        System.assertEquals(210, saved.workingDaysPerYear);
        System.assertEquals(72, saved.derogationEscalationHours);
        System.assertEquals(false, saved.inAppNotificationEnabled);
        System.assertEquals(false, saved.isUnsaved);
        // Les champs non renseignés, eux, prennent bien le défaut du moteur.
        System.assertEquals(25, saved.targetPercentDefault);
        }
    }

    // ------------------------------------------------------------------
    // Session 43 — séparation par domaine : une garde ne doit jamais couvrir le domaine du voisin.
    // ------------------------------------------------------------------

    /** AR_AdminSettingsService sert deux domaines (Paramètres généraux + Référentiels), séparés par
     * la seule garde en tête de méthode : un porteur du seul domaine Référentiels ne doit pas
     * pouvoir écrire les paramètres généraux. */
    @IsTest
    static void testSaveGeneralSettings_adminReferentialsOnly_throws() {
        User adminReferentiels = AR_TestPersona.adminReferentiels();
        Boolean threw = false;
        System.runAs(adminReferentiels) {
            try {
                AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(new AR_AdminSettingsService.GeneralSettingsDto()));
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'Un porteur du seul domaine Référentiels ne doit pas administrer les paramètres généraux');
        System.assertEquals(0, [SELECT COUNT() FROM AR_General_Setting__c]);
    }


    /**
     * Garde-fou de cohérence : la table de correspondance DTO → champ doit couvrir exactement les
     * champs d'AR_GeneralSettingDefaults. Une divergence = un paramètre invisible à l'écran, le
     * défaut même que ce bloc corrige.
     */
    @IsTest
    static void testEngineDefaults_coverExactlyTheMappedFields() {
        Set<String> defaults = AR_GeneralSettingDefaults.asMap().keySet();
        Set<String> mapped = AR_AdminSettingsService.mappedFieldNames();
        System.assertEquals(23, defaults.size(), 'AR_General_Setting__c porte 23 champs paramétrables (18 + 3 poids depuis session 69b + durée de vie des matrices validées depuis session 175 + dispense de dérogation depuis session 237)');
        System.assertEquals(defaults, mapped, 'Aucun champ ne doit exister d\'un seul côté');
    }

    /** newDefaultRecord() doit poser les 22 valeurs (18 + 3 poids depuis session 69b + 1 durée de vie depuis session 175), y compris les booléens :
     * un `insert` nu ne le fait pas, quel que soit le <defaultValue> déclaré en métadonnées (piège session 34). */
    @IsTest
    static void testNewDefaultRecord_carriesAllEighteenValues() {
        AR_General_Setting__c record = AR_GeneralSettingDefaults.newDefaultRecord();
        Test.startTest();
        insert record;
        Test.stopTest();

        AR_General_Setting__c row = [
            SELECT AR_Working_Days_Per_Year__c, AR_InApp_Notification_Enabled__c,
                   AR_Draft_Purge_Enabled__c, AR_Derogation_Reminder_Enabled__c
            FROM AR_General_Setting__c
            WHERE Id = :record.Id
        ];
        System.assertEquals(218, row.AR_Working_Days_Per_Year__c);
        System.assertEquals(
            true,
            row.AR_InApp_Notification_Enabled__c,
            'Documenté « défaut true » partout : c\'est ce champ que la session 34 a trouvé à false'
        );
        System.assertEquals(false, row.AR_Draft_Purge_Enabled__c);
        System.assertEquals(false, row.AR_Derogation_Reminder_Enabled__c);
    }

    @IsTest
    static void testSaveGeneralSettings_weightsSumTo100_accepted() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 20;
            dto.targetPercentDefault = 25;
            dto.idealPercentDefault = 30;
            dto.workingDaysPerYear = 218;
            dto.weightMetier = 50;
            dto.weightSecteur = 30;
            dto.weightClient = 20;  // Sum = 100 ✓

            Test.startTest();
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(
                JSON.serialize(dto)
            );
            Test.stopTest();

            System.assertNotEquals(null, saved.id, 'Poids valides (somme=100) doivent être acceptés');
            System.assertEquals(50, saved.weightMetier);
            System.assertEquals(30, saved.weightSecteur);
            System.assertEquals(20, saved.weightClient);
        }
    }

    @IsTest
    static void testSaveGeneralSettings_weightsSumNotTo100_rejected() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 20;
            dto.targetPercentDefault = 25;
            dto.idealPercentDefault = 30;
            dto.workingDaysPerYear = 218;
            dto.weightMetier = 50;
            dto.weightSecteur = 30;
            dto.weightClient = 25;  // Sum = 105 ✗

            Test.startTest();
            Boolean threw = false;
            String errorMsg = '';
            try {
                AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            } catch (AuraHandledException e) {
                threw = true;
                errorMsg = e.getMessage();
            }
            Test.stopTest();

            System.assert(threw, 'Poids invalides (somme≠100) doivent être rejetés');
            System.assert(
                errorMsg.containsIgnoreCase('somme'),
                'Message d\'erreur doit mentionner la somme des poids : ' + errorMsg
            );
        }
    }

    // ------------------------------------------------------------------
    // Session 175 — durée de vie des entrées « Matrice validée »
    // ------------------------------------------------------------------

    private static AR_AdminSettingsService.GeneralSettingsDto validDto() {
        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        dto.floorPercentDefault = 20;
        dto.targetPercentDefault = 25;
        dto.idealPercentDefault = 30;
        dto.workingDaysPerYear = 218;
        dto.weightMetier = 50;
        dto.weightSecteur = 30;
        dto.weightClient = 20;
        return dto;
    }

    @IsTest
    static void testSaveGeneralSettings_validatedMatrixLifetime_savedAndReadBack() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.validatedMatrixLifetimeDays = 180;

            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));

            System.assertEquals(180, saved.validatedMatrixLifetimeDays, 'Durée de vie enregistrée et relue');
            System.assertEquals(180, [SELECT AR_Validated_Matrix_Lifetime_Days__c FROM AR_General_Setting__c WHERE Id = :saved.id].AR_Validated_Matrix_Lifetime_Days__c);
            System.assertEquals(365, saved.engineDefaults.validatedMatrixLifetimeDays, 'Le défaut du moteur est exposé à l\'écran : 365');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_validatedMatrixLifetime_emptyFallsBackOnDefault() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.validatedMatrixLifetimeDays = null;

            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));

            System.assertEquals(365, saved.validatedMatrixLifetimeDays, 'Champ vidé : le défaut 365 est écrit, donc visible');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_validatedMatrixLifetime_zeroNegativeOrFractionRejected() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            for (Decimal bad : new List<Decimal>{ 0, -5, 1.5 }) {
                AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
                dto.validatedMatrixLifetimeDays = bad;
                Boolean threw = false;
                String message = '';
                try {
                    AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
                } catch (AuraHandledException e) {
                    threw = true;
                    message = e.getMessage();
                }
                System.assert(threw, 'Durée ' + bad + ' refusée');
                System.assert(message.containsIgnoreCase('durée de vie'), 'Message nommant le paramètre : ' + message);
            }
            System.assertEquals(0, [SELECT COUNT() FROM AR_General_Setting__c WHERE AR_Validated_Matrix_Lifetime_Days__c IN (0, -5, 1.5)], 'Rien n\'a été écrit');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_ofiiTax_savedReadBackAndEmptyStaysEmpty() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.ofiiTaxRate = 55;
            dto.ofiiTaxCap = 2506.67;
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(55, saved.ofiiTaxRate, 'Taux OFII enregistré et relu');
            System.assertEquals(2506.67, saved.ofiiTaxCap, 'Plafond OFII enregistré et relu');
            AR_General_Setting__c row = [SELECT AR_Ofii_Tax_Rate__c, AR_Ofii_Tax_Cap__c FROM AR_General_Setting__c WHERE Id = :saved.id];
            System.assertEquals(55, row.AR_Ofii_Tax_Rate__c);
            System.assertEquals(2506.67, row.AR_Ofii_Tax_Cap__c);

            dto.id = saved.id;
            dto.ofiiTaxRate = null;
            dto.ofiiTaxCap = null;
            AR_AdminSettingsService.GeneralSettingsDto emptied = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(null, emptied.ofiiTaxRate, 'Taux vidé : reste vide, aucun défaut réécrit');
            System.assertEquals(null, emptied.ofiiTaxCap, 'Plafond vidé : reste vide, aucun défaut réécrit');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_ofiiTax_outOfRangeRejected() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            // Taux hors de 0 à 100, puis plafond négatif : chacun refusé avec un message nommant le paramètre.
            for (Decimal bad : new List<Decimal>{ -1, 100.5 }) {
                AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
                dto.ofiiTaxRate = bad;
                String message = saveExpectingError(dto);
                System.assert(message.contains('taux'), 'Message nommant le taux : ' + message);
            }
            AR_AdminSettingsService.GeneralSettingsDto capDto = validDto();
            capDto.ofiiTaxCap = -10;
            String capMessage = saveExpectingError(capDto);
            System.assert(capMessage.contains('plafond'), 'Message nommant le plafond : ' + capMessage);
        }
    }

    @IsTest
    static void testSaveGeneralSettings_ofiiTax_boundsAccepted() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.ofiiTaxRate = 100;
            dto.ofiiTaxCap = 0;
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(100, saved.ofiiTaxRate, 'Taux 100 accepté');
            System.assertEquals(0, saved.ofiiTaxCap, 'Plafond 0 accepté');
        }
    }

    // Session 237 : montant de dispense de dérogation — enregistré et relu, vide reste vide (règle désactivée),
    // négatif refusé avec un message qui nomme le paramètre.
    @IsTest
    static void testSaveGeneralSettings_derogationWaiver_savedReadBackAndEmptyStaysEmpty() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.derogationWaiverAmount = 120.5;
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(120.5, saved.derogationWaiverAmount, 'Montant de dispense enregistré et relu');
            System.assertEquals(120.5, [SELECT AR_Derogation_Waiver_Amount__c FROM AR_General_Setting__c WHERE Id = :saved.id].AR_Derogation_Waiver_Amount__c);

            dto.id = saved.id;
            dto.derogationWaiverAmount = null;
            AR_AdminSettingsService.GeneralSettingsDto emptied = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(null, emptied.derogationWaiverAmount, 'Montant vidé : reste vide, aucun défaut réécrit');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_derogationWaiver_negativeRejected() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.derogationWaiverAmount = -1;
            String message = saveExpectingError(dto);
            System.assert(message.contains('dispense'), 'Message nommant le montant de dispense : ' + message);
        }
    }

    // Session 250 : tranches MC2 du tableau de bord — relues, normalisées (virgule → point), vides autorisées, invalides refusées.
    @IsTest
    static void testSaveGeneralSettings_dashboardBands_savedNormalizedAndEmptyAllowed() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
            dto.dashboardMc2Bands = ' 5; 12,5 ;18;25 ';
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals('5;12.5;18;25', saved.dashboardMc2Bands);
            System.assertEquals('5;12.5;18;25', [SELECT AR_Dashboard_MC2_Bands__c FROM AR_General_Setting__c WHERE Id = :saved.id].AR_Dashboard_MC2_Bands__c);

            dto.id = saved.id;
            dto.dashboardMc2Bands = '';
            AR_AdminSettingsService.GeneralSettingsDto emptied = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(null, emptied.dashboardMc2Bands, 'Vide autorisé : défaut appliqué à la lecture');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_dashboardBands_invalidRejected() {
        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            for (String bad : new List<String>{ '20;10', '10;10', 'a;b', '-1;5', '10;101', '1;2;3;4;5;6;7', '10;;20' }) {
                AR_AdminSettingsService.GeneralSettingsDto dto = validDto();
                dto.dashboardMc2Bands = bad;
                String message = saveExpectingError(dto);
                System.assert(message.contains('MC2'), 'Message nommant les tranches pour « ' + bad + ' » : ' + message);
            }
        }
    }

    private static String saveExpectingError(AR_AdminSettingsService.GeneralSettingsDto dto) {
        try {
            AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        System.assert(false, 'Un refus était attendu');
        return '';
    }

    // ------------------------------------------------------------------
    // Session 131 — un administrateur ne doit pouvoir modifier que les fiches qu'il a créées.
    // ------------------------------------------------------------------

    /** Session 131 : domaine AR_Admin_General_Settings — un porteur du seul permission set de
     * ce domaine doit pouvoir modifier des fiches créées par un autre administrateur (breakable
     * seulement si modifyAllRecords=true). */
    @IsTest
    static void testSaveGeneralSettings_adminGeneralSettings_canModifyOthersRecords() {
        // Créer le singleton en contexte administrateur système.
        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        dto.floorPercentDefault = 20;
        dto.targetPercentDefault = 25;
        dto.idealPercentDefault = 30;
        dto.workingDaysPerYear = 218;
        dto.markupPercent = 18;
        dto.markupMax = 60;
        dto.maxDerogationPenalty = 70;
        dto.draftPurgeEnabled = false;
        dto.draftPurgeDays = 30;
        dto.draftPurgeWarningDays = 5;
        dto.draftPurgeMaxPerRun = 200;
        AR_AdminSettingsService.GeneralSettingsDto systemCreated = null;

        User admin = AR_TestPersona.adminGeneral();
        System.runAs(admin) {
            systemCreated = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
        }

        // Maintenant, modifier avec un autre porteur du même permission set (nouveau persona en
        // contexte minimum, assigné seul AR_Admin_General_Settings).
        User adminGeneralOnly = newNonAdminUser();
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Admin_General_Settings' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = adminGeneralOnly.Id, PermissionSetId = psId);
        }

        Test.startTest();
        Boolean threw = false;
        System.runAs(adminGeneralOnly) {
            try {
                AR_AdminSettingsService.GeneralSettingsDto toUpdate = AR_AdminSettingsService.getGeneralSettings();
                toUpdate.workingDaysPerYear = 220;
                AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(toUpdate));
            } catch (Exception e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(!threw, 'Un porteur du seul AR_Admin_General_Settings doit pouvoir modifier les fiches créées par d\'autres');
        AR_General_Setting__c updated = [SELECT AR_Working_Days_Per_Year__c FROM AR_General_Setting__c WHERE Id = :systemCreated.id];
        System.assertEquals(220, updated.AR_Working_Days_Per_Year__c, 'La modification doit avoir réussi');
    }
    // ---- Session 155 : garde de cohérence du corridor de base ----

    private static String saveCorridorDefaultsExpectingError(Decimal floorPct, Decimal targetPct, Decimal idealPct) {
        AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
        dto.floorPercentDefault = floorPct;
        dto.targetPercentDefault = targetPct;
        dto.idealPercentDefault = idealPct;
        try {
            AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void testSaveGeneralSettings_floorAboveTarget_rejectedWithReadableMessage() {
        System.runAs(AR_TestPersona.adminGeneral()) {
            String msg = saveCorridorDefaultsExpectingError(25, 20, 30);
            System.assertNotEquals(null, msg, 'plancher 25 > cible 20 doit être refusé');
            System.assert(msg.contains('Le plancher (25 %) doit être inférieur à la cible (20 %).'), msg);
            System.assertEquals(0, [SELECT COUNT() FROM AR_General_Setting__c], 'rien ne doit être écrit');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_targetEqualsIdeal_andOutOfRange_rejected() {
        System.runAs(AR_TestPersona.adminGeneral()) {
            String equalMsg = saveCorridorDefaultsExpectingError(15, 25, 25);
            System.assert(equalMsg != null && equalMsg.contains('La cible (25 %) doit être inférieure à l\'idéal (25 %).'), equalMsg);
            System.assertNotEquals(null, saveCorridorDefaultsExpectingError(0, 20, 25), 'plancher 0 refusé');
            System.assertNotEquals(null, saveCorridorDefaultsExpectingError(15, 20, 100), 'idéal 100 refusé');
        }
    }

    @IsTest
    static void testSaveGeneralSettings_validCorridor_15_20_25_savedAsIs() {
        System.runAs(AR_TestPersona.adminGeneral()) {
            AR_AdminSettingsService.GeneralSettingsDto dto = new AR_AdminSettingsService.GeneralSettingsDto();
            dto.floorPercentDefault = 15;
            dto.targetPercentDefault = 20;
            dto.idealPercentDefault = 25;
            AR_AdminSettingsService.GeneralSettingsDto saved = AR_AdminSettingsService.saveGeneralSettings(JSON.serialize(dto));
            System.assertEquals(15, saved.floorPercentDefault);
            System.assertEquals(20, saved.targetPercentDefault);
            System.assertEquals(25, saved.idealPercentDefault);
        }
    }
}