/**
 * Source unique des valeurs par défaut du singleton AR_General_Setting__c (session 35).
 *
 * POURQUOI CETTE CLASSE EXISTE — le défaut qu'elle ferme :
 * `AR_General_Setting__c` porte 18 champs ; seuls les 3 `Checkbox` déclarent un `<defaultValue>` en
 * métadonnées, et un `<defaultValue>` ne s'applique de toute façon ni aux lignes déjà en base
 * (session 34) ni à un `insert` Apex. Les 14 champs numériques/picklist arrivent donc à `null` sur
 * un singleton fraîchement créé — en production, à la première ouverture de l'écran
 * d'administration. Le code consommateur se garde correctement partout (`!= null ? valeur :
 * constante`), donc AUCUN calcul n'est faux : c'est l'écran qui mentait par omission, en affichant
 * des cases vides pendant que le moteur appliquait des constantes que personne n'avait choisies.
 *
 * Ces constantes étaient jusqu'ici dispersées en littéraux dans trois classes
 * (AR_PricingCalculator, AR_DraftPurgeBatch, AR_DerogationReminderBatch). Les rassembler ici est la
 * condition pour que l'écran affiche « la valeur réellement appliquée » sans risquer de diverger :
 * une constante dupliquée pour l'affichage serait exactement le mensonge que ce bloc corrige.
 *
 * ⚠️ Le repli `!= null` des consommateurs n'est PAS supprimé : ces constantes le documentent et
 * l'alimentent, elles ne le remplacent pas. Rien ici ne change un résultat de calcul.
 */
public class AR_GeneralSettingDefaults {
  // --- Corridor et moteur de calcul (CLAUDE.md « Règles métier », maquette pricing-tool.html) ---
  // Réexposés depuis AR_PricingCalculator, qui reste la source pour le moteur lui-même.
  public static final Decimal FLOOR_PERCENT = AR_PricingCalculator.FLOOR_PERCENT_DEFAULT;
  public static final Decimal TARGET_PERCENT = AR_PricingCalculator.TARGET_PERCENT_DEFAULT;
  public static final Decimal IDEAL_PERCENT = AR_PricingCalculator.IDEAL_PERCENT_DEFAULT;
  public static final Decimal WORKING_DAYS_PER_YEAR = AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT;
  public static final Decimal MARKUP_PERCENT = AR_PricingCalculator.MARKUP_PERCENT_DEFAULT;
  public static final Decimal MARKUP_MAX = AR_PricingCalculator.MARKUP_MAX_DEFAULT;

  // --- Repères marché : poids du moteur pondéré (session 69) ---
  // Trois critères pondérés identifient les affaires comparables. Échelle 0-100, somme = 100.
  // Réglables sans déploiement depuis l'écran d'administration (AR_General_Setting__c).
  public static final Decimal WEIGHT_METIER = 50;
  public static final Decimal WEIGHT_SECTEUR = 30;
  public static final Decimal WEIGHT_CLIENT = 20;

  // --- Pénalité max de dérogation ---
  // ⚠️ Valeur NON documentée : 70 provient uniquement de scripts/apex/seed-admin-defaults.apex
  // (session 23), aucun docs/NN ne la justifie et AUCUNE classe du moteur ne lit ce champ
  // (règle de pénalité de la spec v0.6 jamais implémentée, cf. arAdminGeneralSettings.html et
  // docs/architecture-technique.md §5.2). Conservée à l'identique pour ne pas modifier une valeur
  // déjà en base en sandbox ; à confirmer avec Matthieu Szczesny le jour où le moteur la consomme.
  public static final Decimal MAX_DEROGATION_PENALTY = 70;

  // Dispense de dérogation (session 237) : MC2/jour en euros à partir de laquelle une matrice se valide
  // sans dérogation. Valeur du défaut de nouvel enregistrement seulement ; une valeur vidée reste vide.
  public static final Decimal DEROGATION_WAIVER_AMOUNT = 100;

  // --- Purge des brouillons (session 25, repli de AR_DraftPurgeBatch) ---
  // Livrée désactivée et non planifiée, cf. docs/deploiement-production.md.
  public static final Boolean DRAFT_PURGE_ENABLED = false;
  // 30 jours = « > 1 mois » de la décision client du 10/08/2026 (CLAUDE.md).
  public static final Decimal DRAFT_PURGE_DAYS = 30;
  // 5 et 200 : replis de AR_DraftPurgeBatch, non documentés dans un docs/NN.
  public static final Decimal DRAFT_PURGE_WARNING_DAYS = 5;
  public static final Decimal DRAFT_PURGE_MAX_PER_RUN = 200;

  // --- Liste « Matrice validée » (session 175) ---
  // Durée de vie d'une entrée à compter de la validation de la matrice : 365 jours, valeur validée par
  // Alexis (prompt de la session 175). Vide en base = cette valeur (AR_ValidatedMatrixSyncService).
  public static final Decimal VALIDATED_MATRIX_LIFETIME_DAYS = 365;

  // --- Relances et escalades de dérogation (session 29, replis de AR_DerogationReminderBatch) ---
  public static final Boolean DEROGATION_REMINDER_ENABLED = false;
  public static final Decimal DEROGATION_REMINDER_HOURS = 12;
  public static final Decimal DEROGATION_ESCALATION_HOURS = 48;
  public static final Decimal DEROGATION_REMINDER_MAX_PER_RUN = 200;
  public static final Decimal DEROGATION_ESCALATION_MAX_RECIPIENTS = 20;

  // --- Notifications ---
  // « Désactivé » : arbitrage Matthieu en attente (session 29, question 2.3 du suivi).
  public static final String HIERARCHY_NOTIFICATION_FREQUENCY = 'Désactivé';
  // true (session 34) — indépendant du canal e-mail.
  public static final Boolean INAPP_NOTIFICATION_ENABLED = true;

  /**
   * Les 21 valeurs par défaut, indexées par nom d'API de champ. Consommée par
   * AR_AdminSettingsService (affichage « valeur par défaut du moteur » et garde de nullité) et par
   * scripts/apex/create-and-verify-general-settings.apex.
   */
  public static Map<String, Object> asMap() {
    return new Map<String, Object>{
      'AR_Floor_Percent_Default__c' => FLOOR_PERCENT,
      'AR_Target_Percent_Default__c' => TARGET_PERCENT,
      'AR_Ideal_Percent_Default__c' => IDEAL_PERCENT,
      'AR_Working_Days_Per_Year__c' => WORKING_DAYS_PER_YEAR,
      'AR_Markup_Percent__c' => MARKUP_PERCENT,
      'AR_Markup_Max__c' => MARKUP_MAX,
      'AR_Weight_Metier__c' => WEIGHT_METIER,
      'AR_Weight_Secteur__c' => WEIGHT_SECTEUR,
      'AR_Weight_Client__c' => WEIGHT_CLIENT,
      'AR_Max_Derogation_Penalty__c' => MAX_DEROGATION_PENALTY,
      'AR_Derogation_Waiver_Amount__c' => DEROGATION_WAIVER_AMOUNT,
      'AR_Draft_Purge_Enabled__c' => DRAFT_PURGE_ENABLED,
      'AR_Draft_Purge_Days__c' => DRAFT_PURGE_DAYS,
      'AR_Draft_Purge_Warning_Days__c' => DRAFT_PURGE_WARNING_DAYS,
      'AR_Draft_Purge_Max_Per_Run__c' => DRAFT_PURGE_MAX_PER_RUN,
      'AR_Validated_Matrix_Lifetime_Days__c' => VALIDATED_MATRIX_LIFETIME_DAYS,
      'AR_Derogation_Reminder_Enabled__c' => DEROGATION_REMINDER_ENABLED,
      'AR_Derogation_Reminder_Hours__c' => DEROGATION_REMINDER_HOURS,
      'AR_Derogation_Escalation_Hours__c' => DEROGATION_ESCALATION_HOURS,
      'AR_Derogation_Reminder_Max_Per_Run__c' => DEROGATION_REMINDER_MAX_PER_RUN,
      'AR_Derogation_Escalation_Max_Recipients__c' => DEROGATION_ESCALATION_MAX_RECIPIENTS,
      'AR_Hierarchy_Notification_Frequency__c' => HIERARCHY_NOTIFICATION_FREQUENCY,
      'AR_InApp_Notification_Enabled__c' => INAPP_NOTIFICATION_ENABLED
    };
  }

  /**
   * Un singleton portant explicitement les 18 valeurs par défaut. Utilisé par le script de création
   * en production : `new AR_General_Setting__c(Name = 'Default')` seul produirait `false` sur les
   * booléens et `null` sur les numériques, quel que soit le `<defaultValue>` déclaré en
   * métadonnées — c'est précisément le piège de la session 34, qui se reproduirait tel quel en
   * production si le singleton y était créé par un `insert` nu.
   */
  public static AR_General_Setting__c newDefaultRecord() {
    AR_General_Setting__c s = new AR_General_Setting__c(Name = 'Default');
    for (String field : asMap().keySet()) {
      s.put(field, asMap().get(field));
    }
    return s;
  }
}