/**
 * Administration des paramètres généraux du moteur (AR_General_Setting__c, singleton — remplace
 * AR_Settings__mdt) et des exceptions jours travaillés. Gardés par
 * `AR_AdminAccessGuard.requireGeneralSettings()` — une seule classe, une seule garde en tête de
 * méthode.
 *
 * `saveGeneralSettings` prend un `String` JSON (pas un wrapper Apex en paramètre) : contrainte de
 * plateforme documentée dans docs/19-payload-json.md — Aura n'alimente aucun champ d'un paramètre
 * de type classe Apex définie par l'utilisateur. Les méthodes à paramètres scalaires (Id, String,
 * Decimal, Boolean) n'ont pas ce problème et sont exposées directement.
 */
public with sharing class AR_AdminSettingsService {

    // ---------------------------------------------------------------------
    // Paramètres généraux (singleton)
    // ---------------------------------------------------------------------

    public class GeneralSettingsDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal floorPercentDefault;
        @AuraEnabled public Decimal targetPercentDefault;
        @AuraEnabled public Decimal idealPercentDefault;
        @AuraEnabled public Decimal workingDaysPerYear;
        @AuraEnabled public Decimal markupPercent;
        @AuraEnabled public Decimal markupMax;
        // Coefficients CDI/CDD (session 28) : null = défaut moteur 2,02 (AR_PricingCalculator.
        // CONTRACT_COEFFICIENT_DEFAULT), jamais recalculé rétroactivement sur une matrice déjà
        // décidée (AR_Price_Matrix__c.AR_Contract_Coefficient_Applied__c fige la valeur au calcul).
        @AuraEnabled public Decimal cdiCoefficient;
        @AuraEnabled public Decimal cddCoefficient;
        @AuraEnabled public Decimal maxDerogationPenalty;
        @AuraEnabled public Boolean draftPurgeEnabled;
        @AuraEnabled public Decimal draftPurgeDays;
        @AuraEnabled public Decimal draftPurgeWarningDays;
        @AuraEnabled public Decimal draftPurgeMaxPerRun;
        // Durée de vie des entrées « Matrice validée » (session 175) : null = 365 (AR_GeneralSettingDefaults).
        @AuraEnabled public Decimal validatedMatrixLifetimeDays;
        // Taxe OFII proposée dans la matrice : taux (% du salaire mensuel brut) et plafond (euros). Pas de
        // défaut moteur : vide = la liste de la matrice ne propose que N/A (donc absents de
        // AR_GeneralSettingDefaults et d'engineDefaults).
        @AuraEnabled public Decimal ofiiTaxRate;
        @AuraEnabled public Decimal ofiiTaxCap;
        // Dispense de dérogation (session 237) : MC2/jour en euros. Vide = règle désactivée, jamais substitué.
        @AuraEnabled public Decimal derogationWaiverAmount;
        @AuraEnabled public String dashboardMc2Bands;
        // Relances/escalades de dérogation + notification hiérarchie (session 29).
        @AuraEnabled public Boolean derogationReminderEnabled;
        @AuraEnabled public Decimal derogationReminderHours;
        @AuraEnabled public Decimal derogationEscalationHours;
        @AuraEnabled public Decimal derogationReminderMaxPerRun;
        // Plafond de destinataires par escalade (session 29c, borne le cercle élargi à l'entité).
        @AuraEnabled public Decimal derogationEscalationMaxRecipients;
        @AuraEnabled public String hierarchyNotificationFrequency;
        // Notifications in-app (session 34) : par défaut true, indépendant de l'e-mail.
        @AuraEnabled public Boolean inAppNotificationEnabled;
        // Moteur pondéré (session 69) : poids des trois critères de similarité (métier, secteur, client).
        // Doivent sommer à 100 % (validation en saveGeneralSettings, session 69b).
        @AuraEnabled public Decimal weightMetier;
        @AuraEnabled public Decimal weightSecteur;
        @AuraEnabled public Decimal weightClient;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
        // Session 35 : true quand AUCUN singleton n'existe encore en base (cas de la production au
        // premier déploiement). L'écran affiche alors les valeurs par défaut du moteur en les
        // signalant comme telles, au lieu d'un formulaire vide qui laisserait croire que rien n'est
        // paramétré pendant que le moteur applique ses constantes.
        @AuraEnabled public Boolean isUnsaved;
        // Session 35 : valeurs par défaut réellement appliquées par le moteur quand le champ est
        // null en base (AR_GeneralSettingDefaults, source unique partagée avec les batchs). Sert à
        // l'écran d'administration pour afficher « valeur par défaut du moteur » plutôt qu'un vide.
        // Un DTO de même forme plutôt qu'une Map<String, Object> : Apex refuse de sérialiser une
        // valeur typée `Object` en JSON (« Apex Type unsupported in JSON: Object »), et une
        // Map<String, String> ferait perdre le typage des nombres et des booléens côté LWC — où
        // « false » deviendrait une chaîne vraie. Toujours null sur l'instance imbriquée, pour ne
        // pas récurser.
        @AuraEnabled public GeneralSettingsDto engineDefaults;
    }

    // Coefficients CDI/CDD administrables : découplés temporairement (session 28, incident
    // post-livraison) — AR_General_Setting__c.AR_CDI_Coefficient__c/AR_CDD_Coefficient__c existent
    // en métadonnées mais restent invisibles en SOQL/DML malgré suppression/redéploiement. Retirés
    // de cette liste et de saveGeneralSettings()/toDto() ci-dessous ; GeneralSettingsDto.
    // cdiCoefficient/cddCoefficient restent déclarés (toujours null) pour ne pas casser le contrat
    // JSON avec arAdminGeneralSettings. À rebrancher une fois l'org débloquée, cf.
    // docs/28-ecarts-contractuels.md.
    private static final String GENERAL_SETTINGS_FIELDS =
        'Id, AR_Floor_Percent_Default__c, AR_Target_Percent_Default__c, AR_Ideal_Percent_Default__c, ' +
        'AR_Working_Days_Per_Year__c, AR_Markup_Percent__c, AR_Markup_Max__c, ' +
        'AR_Max_Derogation_Penalty__c, ' +
        'AR_Draft_Purge_Enabled__c, AR_Draft_Purge_Days__c, AR_Draft_Purge_Warning_Days__c, AR_Draft_Purge_Max_Per_Run__c, ' +
        'AR_Validated_Matrix_Lifetime_Days__c, AR_Ofii_Tax_Rate__c, AR_Ofii_Tax_Cap__c, AR_Derogation_Waiver_Amount__c, AR_Dashboard_MC2_Bands__c, ' +
        'AR_Derogation_Reminder_Enabled__c, AR_Derogation_Reminder_Hours__c, AR_Derogation_Escalation_Hours__c, ' +
        'AR_Derogation_Reminder_Max_Per_Run__c, AR_Derogation_Escalation_Max_Recipients__c, ' +
        'AR_Hierarchy_Notification_Frequency__c, AR_InApp_Notification_Enabled__c, ' +
        'AR_Weight_Metier__c, AR_Weight_Secteur__c, AR_Weight_Client__c, ' +
        'LastModifiedDate, LastModifiedBy.Name';

    /**
     * Correspondance propriété du DTO → nom d'API du champ (session 35). Sert uniquement à traduire
     * AR_GeneralSettingDefaults.asMap() (indexée par nom d'API, comme le script de création du
     * singleton) en une carte indexée comme le DTO, consommable telle quelle par le LWC. Une seule
     * table de valeurs, deux indexations — jamais deux listes de valeurs à maintenir en parallèle.
     */
    private static final Map<String, String> FIELD_BY_DTO_PROPERTY = new Map<String, String>{
        'floorPercentDefault' => 'AR_Floor_Percent_Default__c',
        'targetPercentDefault' => 'AR_Target_Percent_Default__c',
        'idealPercentDefault' => 'AR_Ideal_Percent_Default__c',
        'workingDaysPerYear' => 'AR_Working_Days_Per_Year__c',
        'markupPercent' => 'AR_Markup_Percent__c',
        'markupMax' => 'AR_Markup_Max__c',
        'maxDerogationPenalty' => 'AR_Max_Derogation_Penalty__c',
        'derogationWaiverAmount' => 'AR_Derogation_Waiver_Amount__c',
        'draftPurgeEnabled' => 'AR_Draft_Purge_Enabled__c',
        'draftPurgeDays' => 'AR_Draft_Purge_Days__c',
        'draftPurgeWarningDays' => 'AR_Draft_Purge_Warning_Days__c',
        'draftPurgeMaxPerRun' => 'AR_Draft_Purge_Max_Per_Run__c',
        'validatedMatrixLifetimeDays' => 'AR_Validated_Matrix_Lifetime_Days__c',
        'derogationReminderEnabled' => 'AR_Derogation_Reminder_Enabled__c',
        'derogationReminderHours' => 'AR_Derogation_Reminder_Hours__c',
        'derogationEscalationHours' => 'AR_Derogation_Escalation_Hours__c',
        'derogationReminderMaxPerRun' => 'AR_Derogation_Reminder_Max_Per_Run__c',
        'derogationEscalationMaxRecipients' => 'AR_Derogation_Escalation_Max_Recipients__c',
        'hierarchyNotificationFrequency' => 'AR_Hierarchy_Notification_Frequency__c',
        'inAppNotificationEnabled' => 'AR_InApp_Notification_Enabled__c',
        'weightMetier' => 'AR_Weight_Metier__c',
        'weightSecteur' => 'AR_Weight_Secteur__c',
        'weightClient' => 'AR_Weight_Client__c'
    };

    /**
     * Retourne TOUJOURS un DTO, jamais null (changement session 35). Avant : `null` quand la table
     * était vide, ce que le LWC traduisait en formulaire entièrement vide — l'administrateur en
     * production concluait que rien n'était paramétré pendant que le moteur appliquait ses
     * constantes. Maintenant : un DTO marqué `isUnsaved`, porteur des valeurs par défaut du moteur,
     * pour que l'écran montre ce qui s'applique réellement et permette de le surcharger sciemment.
     */
    @AuraEnabled
    public static GeneralSettingsDto getGeneralSettings() {
        AR_AdminAccessGuard.requireGeneralSettings();
        try {
            List<AR_General_Setting__c> rows = Database.query(
                'SELECT ' + GENERAL_SETTINGS_FIELDS + ' FROM AR_General_Setting__c LIMIT 1'
            );
            if (rows.isEmpty()) {
                GeneralSettingsDto empty = new GeneralSettingsDto();
                empty.isUnsaved = true;
                empty.engineDefaults = engineDefaultsDto();
                return empty;
            }
            return toDto(rows[0]);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_ReadSettingsAction);
        }
    }

    /**
     * Les défauts du moteur, servis dans un DTO de même forme que les paramètres eux-mêmes — le LWC
     * lit `settings.engineDefaults.floorPercentDefault` exactement comme il lit
     * `settings.floorPercentDefault`. Les valeurs viennent d'AR_GeneralSettingDefaults, indexées
     * par nom d'API de champ comme le script de création du singleton : une seule table de valeurs.
     */
    private static GeneralSettingsDto engineDefaultsDto() {
        Map<String, Object> byField = AR_GeneralSettingDefaults.asMap();
        GeneralSettingsDto d = new GeneralSettingsDto();
        d.floorPercentDefault = (Decimal) byField.get('AR_Floor_Percent_Default__c');
        d.targetPercentDefault = (Decimal) byField.get('AR_Target_Percent_Default__c');
        d.idealPercentDefault = (Decimal) byField.get('AR_Ideal_Percent_Default__c');
        d.workingDaysPerYear = (Decimal) byField.get('AR_Working_Days_Per_Year__c');
        d.markupPercent = (Decimal) byField.get('AR_Markup_Percent__c');
        d.markupMax = (Decimal) byField.get('AR_Markup_Max__c');
        d.maxDerogationPenalty = (Decimal) byField.get('AR_Max_Derogation_Penalty__c');
        d.draftPurgeEnabled = (Boolean) byField.get('AR_Draft_Purge_Enabled__c');
        d.draftPurgeDays = (Decimal) byField.get('AR_Draft_Purge_Days__c');
        d.draftPurgeWarningDays = (Decimal) byField.get('AR_Draft_Purge_Warning_Days__c');
        d.draftPurgeMaxPerRun = (Decimal) byField.get('AR_Draft_Purge_Max_Per_Run__c');
        d.validatedMatrixLifetimeDays = (Decimal) byField.get('AR_Validated_Matrix_Lifetime_Days__c');
        d.derogationReminderEnabled = (Boolean) byField.get('AR_Derogation_Reminder_Enabled__c');
        d.derogationReminderHours = (Decimal) byField.get('AR_Derogation_Reminder_Hours__c');
        d.derogationEscalationHours = (Decimal) byField.get('AR_Derogation_Escalation_Hours__c');
        d.derogationReminderMaxPerRun = (Decimal) byField.get('AR_Derogation_Reminder_Max_Per_Run__c');
        d.derogationEscalationMaxRecipients = (Decimal) byField.get('AR_Derogation_Escalation_Max_Recipients__c');
        d.hierarchyNotificationFrequency = (String) byField.get('AR_Hierarchy_Notification_Frequency__c');
        d.inAppNotificationEnabled = (Boolean) byField.get('AR_InApp_Notification_Enabled__c');
        d.weightMetier = (Decimal) byField.get('AR_Weight_Metier__c');
        d.weightSecteur = (Decimal) byField.get('AR_Weight_Secteur__c');
        d.weightClient = (Decimal) byField.get('AR_Weight_Client__c');
        return d;
    }

    /**
     * Garde-fou de cohérence : la table de correspondance ci-dessus doit couvrir exactement les
     * champs d'AR_GeneralSettingDefaults. Une divergence signifierait qu'un champ ajouté d'un côté
     * est absent de l'autre — et donc un paramètre invisible à l'écran. Exercé par les tests.
     */
    @TestVisible
    private static Set<String> mappedFieldNames() {
        return new Set<String>(FIELD_BY_DTO_PROPERTY.values());
    }

    @AuraEnabled
    public static GeneralSettingsDto saveGeneralSettings(String dtoJson) {
        AR_AdminAccessGuard.requireGeneralSettings();
        if (String.isBlank(dtoJson)) {
            throw newAuraException(Label.AR_Msg_ADM_EmptySettingsPayload);
        }
        GeneralSettingsDto dto = (GeneralSettingsDto) JSON.deserialize(dtoJson, GeneralSettingsDto.class);

        // Validation des poids (session 69b) : somme des trois critères doit égaler 100 ± 0,01
        validateWeightsSum(dto);
        validateCorridorDefaults(dto);
        validateValidatedMatrixLifetime(dto);
        validateOfiiTax(dto);
        validateDerogationWaiver(dto);
        dto.dashboardMc2Bands = normalizeDashboardBands(dto.dashboardMc2Bands);

        try {
            AR_General_Setting__c record = dto.id != null
                ? new AR_General_Setting__c(Id = dto.id)
                : new AR_General_Setting__c(Name = 'Default');
            // Garde de nullité sur TOUS les paramètres, pas seulement les booléens (session 35).
            // Avant : seuls les deux Checkbox étaient gardés (le DML rejette un null explicite sur un
            // Checkbox) ; un champ numérique vidé dans le formulaire écrivait `null` en base et le
            // moteur retombait silencieusement sur sa constante — un paramètre invisible à l'écran
            // pilotant un calcul bien réel, exactement la classe de défaut balayée côté LWC en session
            // 34 et restée intacte côté Apex. Vider un champ signifie maintenant « revenir au défaut du
            // moteur », et ce défaut est écrit en base, donc visible.
            record.AR_Floor_Percent_Default__c = defaulted(dto.floorPercentDefault, AR_GeneralSettingDefaults.FLOOR_PERCENT);
            record.AR_Target_Percent_Default__c = defaulted(dto.targetPercentDefault, AR_GeneralSettingDefaults.TARGET_PERCENT);
            record.AR_Ideal_Percent_Default__c = defaulted(dto.idealPercentDefault, AR_GeneralSettingDefaults.IDEAL_PERCENT);
            record.AR_Working_Days_Per_Year__c = defaulted(dto.workingDaysPerYear, AR_GeneralSettingDefaults.WORKING_DAYS_PER_YEAR);
            record.AR_Markup_Percent__c = defaulted(dto.markupPercent, AR_GeneralSettingDefaults.MARKUP_PERCENT);
            record.AR_Markup_Max__c = defaulted(dto.markupMax, AR_GeneralSettingDefaults.MARKUP_MAX);
            record.AR_Max_Derogation_Penalty__c = defaulted(dto.maxDerogationPenalty, AR_GeneralSettingDefaults.MAX_DEROGATION_PENALTY);
            record.AR_Draft_Purge_Enabled__c = dto.draftPurgeEnabled == null ? AR_GeneralSettingDefaults.DRAFT_PURGE_ENABLED : dto.draftPurgeEnabled;
            record.AR_Draft_Purge_Days__c = defaulted(dto.draftPurgeDays, AR_GeneralSettingDefaults.DRAFT_PURGE_DAYS);
            record.AR_Draft_Purge_Warning_Days__c = defaulted(dto.draftPurgeWarningDays, AR_GeneralSettingDefaults.DRAFT_PURGE_WARNING_DAYS);
            record.AR_Draft_Purge_Max_Per_Run__c = defaulted(dto.draftPurgeMaxPerRun, AR_GeneralSettingDefaults.DRAFT_PURGE_MAX_PER_RUN);
            record.AR_Validated_Matrix_Lifetime_Days__c = defaulted(dto.validatedMatrixLifetimeDays, AR_GeneralSettingDefaults.VALIDATED_MATRIX_LIFETIME_DAYS);
            // Vidés = aucun montant calculé dans la matrice (pas de retour à un défaut : cf. DTO).
            record.AR_Ofii_Tax_Rate__c = dto.ofiiTaxRate;
            record.AR_Ofii_Tax_Cap__c = dto.ofiiTaxCap;
            // Vide = règle désactivée : pas de défaut substitué (session 237).
            record.AR_Derogation_Waiver_Amount__c = dto.derogationWaiverAmount;
            // Vide = défaut 10;15;20 appliqué à la lecture par AR_DashboardService (pas de valeur substituée ici).
            record.AR_Dashboard_MC2_Bands__c = dto.dashboardMc2Bands;
            record.AR_Derogation_Reminder_Enabled__c = dto.derogationReminderEnabled == null
                ? AR_GeneralSettingDefaults.DEROGATION_REMINDER_ENABLED
                : dto.derogationReminderEnabled;
            record.AR_Derogation_Reminder_Hours__c = defaulted(dto.derogationReminderHours, AR_GeneralSettingDefaults.DEROGATION_REMINDER_HOURS);
            record.AR_Derogation_Escalation_Hours__c = defaulted(dto.derogationEscalationHours, AR_GeneralSettingDefaults.DEROGATION_ESCALATION_HOURS);
            record.AR_Derogation_Reminder_Max_Per_Run__c = defaulted(dto.derogationReminderMaxPerRun, AR_GeneralSettingDefaults.DEROGATION_REMINDER_MAX_PER_RUN);
            record.AR_Derogation_Escalation_Max_Recipients__c = defaulted(dto.derogationEscalationMaxRecipients, AR_GeneralSettingDefaults.DEROGATION_ESCALATION_MAX_RECIPIENTS);
            record.AR_Hierarchy_Notification_Frequency__c = String.isBlank(dto.hierarchyNotificationFrequency)
                ? AR_GeneralSettingDefaults.HIERARCHY_NOTIFICATION_FREQUENCY
                : dto.hierarchyNotificationFrequency;
            record.AR_InApp_Notification_Enabled__c = dto.inAppNotificationEnabled == null
                ? AR_GeneralSettingDefaults.INAPP_NOTIFICATION_ENABLED
                : dto.inAppNotificationEnabled;
            record.AR_Weight_Metier__c = defaulted(dto.weightMetier, AR_GeneralSettingDefaults.WEIGHT_METIER);
            record.AR_Weight_Secteur__c = defaulted(dto.weightSecteur, AR_GeneralSettingDefaults.WEIGHT_SECTEUR);
            record.AR_Weight_Client__c = defaulted(dto.weightClient, AR_GeneralSettingDefaults.WEIGHT_CLIENT);
            upsert record;
            // Session 237 : le montant de dispense lu pendant la transaction ne doit pas survivre à l'enregistrement.
            AR_PricingMatrixService.resetDispenseAmountCache();

            Id savedId = record.Id;
            List<AR_General_Setting__c> reloaded = Database.query(
                'SELECT ' + GENERAL_SETTINGS_FIELDS + ' FROM AR_General_Setting__c WHERE Id = :savedId LIMIT 1'
            );
            return toDto(reloaded[0]);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveSettingsAction);
        }
    }

    private static Decimal defaulted(Decimal value, Decimal fallback) {
        return value == null ? fallback : value;
    }

    /**
     * Garde de cohérence du corridor de base (session 155) : plancher < cible < idéal, chacun strictement
     * entre 0 et 100. Un champ vide revient à la constante du moteur (cf. `defaulted`), donc la garde
     * porte sur les valeurs qui seront réellement écrites.
     */
    @TestVisible
    private static void validateCorridorDefaults(GeneralSettingsDto dto) {
        Decimal floorPct = defaulted(dto.floorPercentDefault, AR_GeneralSettingDefaults.FLOOR_PERCENT);
        Decimal targetPct = defaulted(dto.targetPercentDefault, AR_GeneralSettingDefaults.TARGET_PERCENT);
        Decimal idealPct = defaulted(dto.idealPercentDefault, AR_GeneralSettingDefaults.IDEAL_PERCENT);
        for (Decimal pct : new List<Decimal>{ floorPct, targetPct, idealPct }) {
            if (pct <= 0 || pct >= 100) {
                throw newAuraException(Label.AR_Msg_ADM_ThresholdsRange);
            }
        }
        if (floorPct >= targetPct) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_FloorBelowTarget, new List<Object>{ floorPct, targetPct })
            );
        }
        if (targetPct >= idealPct) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_TargetBelowIdeal, new List<Object>{ targetPct, idealPct })
            );
        }
    }

    private static void validateWeightsSum(GeneralSettingsDto dto) {
        // Validation des poids (session 69b) : la somme des trois critères doit égaler 100 ± 0,01.
        // Tolerance = 0.01 pour couvrir les arrondis en calcul flottant.
        Decimal w1 = dto.weightMetier != null ? dto.weightMetier : AR_GeneralSettingDefaults.WEIGHT_METIER;
        Decimal w2 = dto.weightSecteur != null ? dto.weightSecteur : AR_GeneralSettingDefaults.WEIGHT_SECTEUR;
        Decimal w3 = dto.weightClient != null ? dto.weightClient : AR_GeneralSettingDefaults.WEIGHT_CLIENT;
        Decimal sum = w1 + w2 + w3;
        Decimal tolerance = 0.01;

        if (Math.abs(sum - 100) > tolerance) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_WeightsSum, new List<Object>{ w1, w2, w3, sum })
            );
        }
    }

    /**
     * Durée de vie des entrées « Matrice validée » (session 175) : entier d'au moins 1 jour. Zéro ou négatif
     * ferait expirer toutes les entrées au prochain passage du batch ; un champ vide, lui, revient au défaut (365).
     */
    @TestVisible
    private static void validateValidatedMatrixLifetime(GeneralSettingsDto dto) {
        Decimal days = dto.validatedMatrixLifetimeDays;
        if (days == null) {
            return;
        }
        if (days < 1 || days != days.setScale(0)) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_LifetimeInvalid, new List<Object>{ days })
            );
        }
    }

    /** Taxe OFII : taux vide ou entre 0 et 100, plafond vide ou au moins 0. */
    @TestVisible
    private static void validateOfiiTax(GeneralSettingsDto dto) {
        if (dto.ofiiTaxRate != null && (dto.ofiiTaxRate < 0 || dto.ofiiTaxRate > 100)) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_OfiiRateInvalid, new List<Object>{ dto.ofiiTaxRate })
            );
        }
        if (dto.ofiiTaxCap != null && dto.ofiiTaxCap < 0) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_OfiiCapInvalid, new List<Object>{ dto.ofiiTaxCap })
            );
        }
    }

    /**
     * Tranches MC2 du tableau de bord (session 250) : 1 à 6 nombres entre 0 et 100, strictement
     * croissants, séparés par « ; », virgule ou point décimal acceptés. Retourne la forme canonique
     * (points décimaux, ex. « 10;15.5;20 ») ; vide → null (défaut appliqué à la lecture).
     */
    @TestVisible
    private static String normalizeDashboardBands(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        List<String> canonical = new List<String>();
        Decimal previous = null;
        List<String> tokens = raw.split(';');
        Boolean valid = tokens.size() >= 1 && tokens.size() <= 6;
        for (Integer i = 0; valid && i < tokens.size(); i++) {
            String token = tokens[i].trim().replace(',', '.');
            Decimal bound;
            try {
                bound = Decimal.valueOf(token);
            } catch (Exception ex) {
                valid = false;
                break;
            }
            if (bound < 0 || bound > 100 || (previous != null && bound <= previous)) {
                valid = false;
                break;
            }
            previous = bound;
            canonical.add(bound.stripTrailingZeros().toPlainString());
        }
        if (!valid) {
            throw newAuraException(Label.AR_AGS_DashboardMc2BandsInvalid);
        }
        return String.join(canonical, ';');
    }

    private static void validateDerogationWaiver(GeneralSettingsDto dto) {
        if (dto.derogationWaiverAmount != null && dto.derogationWaiverAmount < 0) {
            throw newAuraException(
                AR_I18n.format(Label.AR_Msg_ADM_WaiverInvalid, new List<Object>{ dto.derogationWaiverAmount })
            );
        }
    }

    private static GeneralSettingsDto toDto(AR_General_Setting__c s) {
        GeneralSettingsDto dto = new GeneralSettingsDto();
        dto.id = s.Id;
        dto.isUnsaved = false;
        dto.engineDefaults = engineDefaultsDto();
        dto.floorPercentDefault = s.AR_Floor_Percent_Default__c;
        dto.targetPercentDefault = s.AR_Target_Percent_Default__c;
        dto.idealPercentDefault = s.AR_Ideal_Percent_Default__c;
        dto.workingDaysPerYear = s.AR_Working_Days_Per_Year__c;
        dto.markupPercent = s.AR_Markup_Percent__c;
        dto.markupMax = s.AR_Markup_Max__c;
        dto.maxDerogationPenalty = s.AR_Max_Derogation_Penalty__c;
        dto.draftPurgeEnabled = s.AR_Draft_Purge_Enabled__c;
        dto.draftPurgeDays = s.AR_Draft_Purge_Days__c;
        dto.draftPurgeWarningDays = s.AR_Draft_Purge_Warning_Days__c;
        dto.draftPurgeMaxPerRun = s.AR_Draft_Purge_Max_Per_Run__c;
        dto.validatedMatrixLifetimeDays = s.AR_Validated_Matrix_Lifetime_Days__c;
        dto.ofiiTaxRate = s.AR_Ofii_Tax_Rate__c;
        dto.ofiiTaxCap = s.AR_Ofii_Tax_Cap__c;
        dto.derogationWaiverAmount = s.AR_Derogation_Waiver_Amount__c;
        dto.dashboardMc2Bands = s.AR_Dashboard_MC2_Bands__c;
        dto.derogationReminderEnabled = s.AR_Derogation_Reminder_Enabled__c;
        dto.derogationReminderHours = s.AR_Derogation_Reminder_Hours__c;
        dto.derogationEscalationHours = s.AR_Derogation_Escalation_Hours__c;
        dto.derogationReminderMaxPerRun = s.AR_Derogation_Reminder_Max_Per_Run__c;
        dto.derogationEscalationMaxRecipients = s.AR_Derogation_Escalation_Max_Recipients__c;
        dto.hierarchyNotificationFrequency = s.AR_Hierarchy_Notification_Frequency__c;
        dto.inAppNotificationEnabled = s.AR_InApp_Notification_Enabled__c;
        dto.weightMetier = s.AR_Weight_Metier__c;
        dto.weightSecteur = s.AR_Weight_Secteur__c;
        dto.weightClient = s.AR_Weight_Client__c;
        dto.lastModifiedDate = s.LastModifiedDate;
        dto.lastModifiedByName = s.LastModifiedBy.Name;
        return dto;
    }

    // ---------------------------------------------------------------------
    // Exceptions jours travaillés (session 168) : vue/saisie de AR_PTF_Entity_Referential__c.AR_Working_Days__c
    // ---------------------------------------------------------------------

    public class WorkingDaysExceptionDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String entityName;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal workingDays;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    @AuraEnabled
    public static List<WorkingDaysExceptionDto> getWorkingDaysExceptions() {
        AR_AdminAccessGuard.requireGeneralSettings();
        List<WorkingDaysExceptionDto> options = new List<WorkingDaysExceptionDto>();
        for (AR_PTF_Entity_Referential__c e : [
            SELECT Id, Name, AR_Active__c, AR_Working_Days__c, LastModifiedDate, LastModifiedBy.Name
            FROM AR_PTF_Entity_Referential__c
            WHERE AR_Working_Days__c != null
            ORDER BY Name
        ]) {
            WorkingDaysExceptionDto dto = new WorkingDaysExceptionDto();
            dto.id = e.Id;
            dto.entityName = e.Name;
            dto.active = e.AR_Active__c;
            dto.workingDays = e.AR_Working_Days__c;
            dto.lastModifiedDate = e.LastModifiedDate;
            dto.lastModifiedByName = e.LastModifiedBy.Name;
            options.add(dto);
        }
        return options;
    }

    @AuraEnabled
    public static void saveWorkingDaysException(Id entityId, Decimal workingDays) {
        AR_AdminAccessGuard.requireGeneralSettings();
        if (entityId == null) {
            throw newAuraException(Label.AR_Msg_ADM_EntityRequired);
        }
        if (workingDays == null || workingDays < 1 || workingDays > 366) {
            throw newAuraException(Label.AR_Msg_ADM_WorkingDaysRange);
        }
        try {
            AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Id = entityId);
            entity.AR_Working_Days__c = workingDays;
            update entity;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveWorkingDaysAction);
        }
    }

    @AuraEnabled
    public static void deleteWorkingDaysException(Id entityId) {
        AR_AdminAccessGuard.requireGeneralSettings();
        if (entityId == null) {
            throw newAuraException(Label.AR_Msg_ADM_EntityRequired);
        }
        try {
            AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Id = entityId);
            entity.AR_Working_Days__c = null;
            update entity;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_RemoveWorkingDaysAction);
        }
    }


    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}