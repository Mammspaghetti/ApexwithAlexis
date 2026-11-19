/**
 * Emails du workflow de dérogation, envoyés directement par les services (pas de flow) via
 * Messaging.SingleEmailMessage. Textes en français portés par des Custom Labels (catégorie
 * AR_Pricing) — l'administrabilité complète des gabarits arrive au Jalon 1B.
 * Échec d'envoi (ex. Email Deliverability désactivé en sandbox) : logué en debug, jamais remonté
 * en exception — un email qui ne part pas ne doit jamais faire échouer la transaction métier.
 *
 * Refactoring de testabilité (session 27, prompts/session-27-filet-de-tests.md §2) : chaque email
 * est désormais construit par une méthode `build*` séparée de son envoi, avant `sendEmail(...)`.
 * Comportement observable inchangé (mêmes conditions d'envoi, mêmes destinataires, mêmes textes) —
 * seule la construction est désormais inspectable par un test sans mock ni envoi réel, ce
 * qu'aucune classe de test ne pouvait faire jusqu'ici (AR_NotificationServiceTest, nouveau).
 *
 * Session 29 (prompts/session-29-relances-et-notifications.md) : ajout de trois digests, sur le
 * même principe que sendDraftPurgeWarningDigest — relance de dérogation (palier 1), escalade de
 * dérogation (palier 2, cercle élargi à tous les valideurs habilités + manager du valideur
 * sélectionné), notification informative à la hiérarchie sur validation automatique.
 *
 * Session 34 (prompts/session-34-notifications-in-app.md) : canal in-app (cloche Salesforce) greffé
 * sur les 5 mêmes événements déjà couverts par e-mail — jamais un 6e événement inventé. Chaque
 * `EmailPreview` porte désormais aussi `recipientIds` (Set<Id> User, pas des adresses) et
 * `notificationTargetId` (cible du clic) : les deux canaux partent du même objet, construit une
 * seule fois, jamais deux constructions parallèles qui pourraient diverger. Un seul
 * `CustomNotificationType` (AR_Pricing_Notification) pour tout l'outil — titre/corps portent la
 * distinction, pas le type. Interrupteur `AR_General_Setting__c.AR_InApp_Notification_Enabled__c`
 * (par défaut true) ; l'e-mail n'est jamais affecté par ce booléen, les deux canaux restent
 * indépendants à l'envoi (l'échec de l'un ne bloque jamais l'autre).
 */
public without sharing class AR_NotificationService {
  /** Aperçu d'un envoi prêt à partir (e-mail et/ou in-app), jamais envoyé par lui-même — utilisé
   * par les tests et par sendEmail()/sendInAppFromPreview(). */
  @TestVisible
  private class EmailPreview {
    @TestVisible
    List<String> toAddresses = new List<String>();
    @TestVisible
    String subject;
    @TestVisible
    String body;
    // Ids User (jamais des adresses, cf. Messaging.CustomNotification.send()) — vide ⇒ pas de canal
    // in-app pour cet envoi (ex. digest sans destinataire résolu).
    @TestVisible
    Set<String> recipientIds = new Set<String>();
    // Cible du clic (dérogation ou matrice selon l'événement) ; null pour un digest multi-lignes,
    // exactement comme l'e-mail équivalent pointe alors vers appRootLink() plutôt qu'un enregistrement
    // précis — même choix, pas une divergence entre les deux canaux.
    @TestVisible
    Id notificationTargetId;
    // Session 112 : PageReference sérialisée en JSON pour setTargetPageRef() (navigation vers l'app
    // avec paramètres d'état). Si renseigné, prime sur notificationTargetId.
    @TestVisible
    String notificationTargetPageRef;
  }

  // ---------------------------------------------------------------------
  // Échecs d'envoi
  // ---------------------------------------------------------------------

  /** Un envoi (e-mail ou cloche) qui n'est pas parti. */
  @TestVisible
  private class DeliveryFailure {
    String channel;
    List<String> recipients;
    String code;
    String reason;
  }

  /** Détail des envois échoués de la transaction, journalisé côté client (console), jamais affiché. */
  public class DeliveryWarning {
    @AuraEnabled
    public String detail;
  }

  @TestVisible
  private static List<DeliveryFailure> failures = new List<DeliveryFailure>();

  private static void recordFailure(String channel, List<String> recipients, String code, String reason) {
    DeliveryFailure failure = new DeliveryFailure();
    failure.channel = channel;
    failure.recipients = recipients == null ? new List<String>() : recipients;
    failure.code = code;
    failure.reason = String.isBlank(reason) ? code : reason;
    failures.add(failure);
    System.debug(
      LoggingLevel.ERROR,
      'AR_NotificationService: envoi ' + channel + ' échoué [' + code + '] ' + failure.reason +
      ' — destinataires : ' + String.join(failure.recipients, ', ')
    );
  }

  /**
   * Renvoie les échecs d'envoi accumulés depuis le dernier appel (null s'il n'y en a pas) et
   * remet le compteur à zéro. À appeler juste après les envois d'une action lancée depuis l'écran.
   */
  public static DeliveryWarning consumeWarning() {
    if (failures.isEmpty()) {
      return null;
    }
    List<String> details = new List<String>();
    for (DeliveryFailure failure : failures) {
      details.add(
        failure.channel + ' | ' + String.join(failure.recipients, ', ') + ' | ' + failure.code + ' | ' + failure.reason
      );
    }
    failures = new List<DeliveryFailure>();
    DeliveryWarning warning = new DeliveryWarning();
    warning.detail = String.join(details, ' || ');
    return warning;
  }

  /** Bascule de test : simule une exception globale de Messaging.sendEmail (délivrabilité coupée). */
  @TestVisible
  private static Boolean testForceSendException = false;

  /** Envoie les messages sans tout-ou-rien et consigne chaque échec, par message ou global. */
  @TestVisible
  private static void deliver(String channel, List<Messaging.SingleEmailMessage> mails) {
    try {
      if (testForceSendException) {
        throw new System.NoAccessException();
      }
      List<Messaging.SendEmailResult> results = Messaging.sendEmail(mails, false);
      for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
          continue;
        }
        for (Messaging.SendEmailError err : results[i].getErrors()) {
          recordFailure(channel, mails[i].getToAddresses(), String.valueOf(err.getStatusCode()), err.getMessage());
        }
      }
    } catch (Exception e) {
      for (Messaging.SingleEmailMessage mail : mails) {
        recordFailure(channel, mail.getToAddresses(), e.getTypeName(), e.getMessage());
      }
    }
  }

  // ---------------------------------------------------------------------
  // Canal in-app (session 34)
  // ---------------------------------------------------------------------

  @TestVisible
  private static Id pricingNotificationTypeId;
  @TestVisible
  private static Boolean pricingNotificationTypeResolved = false;
  /** Bascule de test (session 34) : simule un org où la requête CustomNotificationType est
   * indisponible en contexte de test, sans dépendre du comportement réel de CETTE org — cf. le
   * repli documenté dans prompts/session-34-notifications-in-app.md. */
  @TestVisible
  private static Boolean testForceNotificationTypeResolutionFailure = false;
  /** Nombre d'envois in-app ayant passé le contrôle interrupteur + destinataires non vide, avant
   * résolution du type — seul point stable pour tester la bascule AR_InApp_Notification_Enabled__c
   * indépendamment de la disponibilité de CustomNotificationType dans le contexte d'exécution. */
  @TestVisible
  private static Integer inAppEligibleAttempts = 0;

  @TestVisible
  private static Id resolvePricingNotificationTypeId() {
    if (pricingNotificationTypeResolved) {
      return pricingNotificationTypeId;
    }
    pricingNotificationTypeResolved = true;
    if (testForceNotificationTypeResolutionFailure) {
      pricingNotificationTypeId = null;
      return null;
    }
    try {
      List<CustomNotificationType> types = [
        SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'AR_Pricing_Notification' LIMIT 1
      ];
      pricingNotificationTypeId = types.isEmpty() ? null : types[0].Id;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'AR_NotificationService: résolution de AR_Pricing_Notification impossible (' + e.getMessage() + ') — canal in-app désactivé pour cette transaction.'
      );
      pricingNotificationTypeId = null;
    }
    return pricingNotificationTypeId;
  }

  private static Boolean inAppNotificationsEnabled() {
    List<AR_General_Setting__c> rows = [SELECT AR_InApp_Notification_Enabled__c FROM AR_General_Setting__c LIMIT 1];
    // Pas de ligne de paramètres, ou case jamais décochée (null) : défaut true (cf. description du champ).
    return rows.isEmpty() || rows[0].AR_InApp_Notification_Enabled__c != false;
  }

  /**
   * Envoie la notification in-app portée par `preview`, si le canal est activé et qu'il y a au
   * moins un destinataire. Échec de résolution ou d'envoi : consigné (recordFailure), jamais levé — même contrat
   * que sendEmail(), les deux canaux sont indépendants l'un de l'autre.
   */
  @TestVisible
  private static void sendInAppFromPreview(EmailPreview preview) {
    if (preview == null || preview.recipientIds.isEmpty() || !inAppNotificationsEnabled()) {
      return;
    }
    inAppEligibleAttempts++;
    Id typeId = resolvePricingNotificationTypeId();
    if (typeId == null) {
      recordFailure(
        'in-app',
        new List<String>(preview.recipientIds),
        'NOTIFICATION_TYPE_NOT_FOUND',
        'type de notification AR_Pricing_Notification introuvable'
      );
      return;
    }
    try {
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setTitle(preview.subject);
      notification.setBody(preview.body);
      notification.setNotificationTypeId(typeId);
      // Session 112 : notificationTargetPageRef prime sur notificationTargetId pour naviguer
      // dans l'app avec paramètres d'état (ex. vers la file d'approbation avec dérogation).
      if (String.isNotBlank(preview.notificationTargetPageRef)) {
        notification.setTargetPageRef(preview.notificationTargetPageRef);
      } else if (preview.notificationTargetId != null) {
        notification.setTargetId(preview.notificationTargetId);
      }
      notification.send(preview.recipientIds);
    } catch (Exception e) {
      recordFailure('in-app', new List<String>(preview.recipientIds), e.getTypeName(), e.getMessage());
    }
  }

  /**
   * Session 284 : notification in-app seule (pas d'e-mail) « Affaire gagnée — <compte> » vers le
   * tableau de bord, onglet affaires gagnées. Échec : consigné par sendInAppFromPreview, jamais levé.
   */
  /** Destinataires de chaque envoi « affaire gagnée » (un élément par appel) — point de contrôle des tests. */
  @TestVisible
  private static List<Set<Id>> wonDealRecipientsSent = new List<Set<Id>>();

  public static void sendWonDealInApp(String accountName, Set<Id> recipientIds) {
    if (recipientIds == null || recipientIds.isEmpty()) {
      return;
    }
    wonDealRecipientsSent.add(recipientIds.clone());
    EmailPreview preview = new EmailPreview();
    preview.subject = String.format(Label.AR_Won_Notif_Title, new List<String>{ String.valueOf(accountName) });
    preview.body = Label.AR_Won_Notif_Body;
    for (Id recipientId : recipientIds) {
      preview.recipientIds.add(String.valueOf(recipientId));
    }
    preview.notificationTargetPageRef = JSON.serialize(
      new Map<String, Object>{
        'type' => 'standard__navItemPage',
        'attributes' => new Map<String, Object>{ 'apiName' => 'AR_Pricing_App' },
        'state' => new Map<String, Object>{ 'c__view' => 'dashboard', 'c__tab' => 'won' }
      }
    );
    sendInAppFromPreview(preview);
  }

  public static void sendDerogationRequestEmail(Id derogationId) {
    EmailPreview preview = buildDerogationRequestEmail(derogationId);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildDerogationRequestEmail(Id derogationId) {
    AR_Derogation__c derogation = [
      SELECT
        AR_Requester_Reason__c,
        AR_Price_Matrix__c,
        AR_Price_Matrix__r.Name,
        AR_Price_Matrix__r.AR_Position_Name__c,
        AR_Price_Matrix__r.AR_Proposed_TJM__c,
        AR_Price_Matrix__r.AR_TJM_Weighted__c,
        AR_Price_Matrix__r.AR_TJM_Periods__c,
        AR_Price_Matrix__r.AR_Number_Of_Days__c, AR_Price_Matrix__r.AR_Planned_Leave_Days__c,
        AR_Price_Matrix__r.AR_MC2_Percent__c,
        AR_Price_Matrix__r.AR_MC2_Per_Day__c,
        AR_Price_Matrix__r.AR_Currency__c,
        AR_Price_Matrix__r.AR_Total_Daily_Cost__c,
        AR_Price_Matrix__r.AR_RFA_Percent__c,
        AR_Price_Matrix__r.AR_RPLSR_Enabled__c,
        AR_Price_Matrix__r.AR_RPLSR_Days_Sold__c,
        AR_Price_Matrix__r.AR_RPLSR_Days_Produced__c,
        AR_Selected_Validator__r.Email
      FROM AR_Derogation__c
      WHERE Id = :derogationId
      LIMIT 1
    ];
    if (
      derogation.AR_Selected_Validator__r == null ||
      String.isBlank(derogation.AR_Selected_Validator__r.Email)
    ) {
      System.debug(
        LoggingLevel.WARN,
        'AR_NotificationService: aucun email de valideur pour la dérogation ' +
        derogationId
      );
      return null;
    }

    List<String> reasonLabels = AR_DerogationService.reasonLabelsByDerogation(new Set<Id>{ derogationId })
      .get(derogationId);

    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ derogation.AR_Selected_Validator__r.Email };
    preview.subject = String.format(
      Label.AR_Email_Derogation_Request_Subject,
      new List<String>{ derogation.AR_Price_Matrix__r.Name }
    );
    preview.body = String.format(
      Label.AR_Email_Derogation_Request_Body,
      new List<String>{
        UserInfo.getName(),
        derogation.AR_Price_Matrix__r.Name,
        String.valueOf(derogation.AR_Price_Matrix__r.AR_Position_Name__c),
        tjmWithPeriods(derogation.AR_Price_Matrix__r),
        formatPercent(derogation.AR_Price_Matrix__r.AR_MC2_Percent__c),
        reasonBlock(reasonLabels, derogation.AR_Requester_Reason__c),
        derogationLink(derogationId),
        // Session 143 : {7}, ajouté en dernier pour ne pas renuméroter les autres paramètres.
        formatMoney(
          AR_DerogationService.resolveMc2PerDay(
            derogation.AR_Price_Matrix__r.AR_MC2_Per_Day__c,
            AR_PricingMatrixService.effectiveTjm(derogation.AR_Price_Matrix__r),
            derogation.AR_Price_Matrix__r.AR_MC2_Percent__c
          ),
          derogation.AR_Price_Matrix__r.AR_Currency__c
        )
      }
    ) + rplsrLine(derogation.AR_Price_Matrix__r);
    // Session 112 : cible in-app navigue vers la file d'approbation avec la dérogation focalisée.
    preview.notificationTargetPageRef = buildDerogationTargetPageRef(derogationId);
    preview.recipientIds = new Set<String>{ derogation.AR_Selected_Validator__c };
    return preview;
  }

  /**
   * Bloc « Motif de dérogation » du corps de la demande, même rendu que la file d'approbation :
   * un motif seul (« A », ou « A : commentaire ») ; plusieurs motifs en liste à puces, le
   * commentaire dessous ; commentaire seul ; rien → pas de bloc.
   */
  private static String reasonBlock(List<String> reasonLabels, String comment) {
    String text = String.isBlank(comment) ? null : comment.trim();
    String block;
    if (reasonLabels == null || reasonLabels.isEmpty()) {
      block = text;
    } else if (reasonLabels.size() == 1) {
      block = text == null
        ? reasonLabels[0]
        : AR_I18n.format(Label.AR_DQ_ReasonWithComment, new List<Object>{ reasonLabels[0], text });
    } else {
      block = '- ' + String.join(reasonLabels, '\n- ');
      if (text != null) {
        block += '\n' + text;
      }
    }
    return block == null ? '' : Label.AR_DQ_ReasonTitle + '\n' + block;
  }

  public static void sendDerogationResultEmails(Id derogationId) {
    EmailPreview preview = buildDerogationResultEmail(derogationId);
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildDerogationResultEmail(Id derogationId) {
    AR_Derogation__c derogation = [
      SELECT
        AR_Decision__c,
        AR_Validator_Comment__c,
        AR_Price_Matrix__c,
        AR_Price_Matrix__r.Name,
        AR_Price_Matrix__r.AR_Position_Name__c,
        AR_Price_Matrix__r.AR_Total_Daily_Cost__c,
        AR_Price_Matrix__r.AR_RFA_Percent__c,
        AR_Price_Matrix__r.AR_TJM_Weighted__c,
        AR_Price_Matrix__r.AR_Proposed_TJM__c,
        AR_Price_Matrix__r.AR_TJM_Periods__c,
        AR_Price_Matrix__r.AR_RPLSR_Enabled__c,
        AR_Price_Matrix__r.AR_RPLSR_Days_Sold__c,
        AR_Price_Matrix__r.AR_RPLSR_Days_Produced__c,
        AR_Price_Matrix__r.OwnerId,
        AR_Effective_Validator__r.Name,
        AR_Effective_Validator__r.Email
      FROM AR_Derogation__c
      WHERE Id = :derogationId
      LIMIT 1
    ];

    String decisionLabel = derogation.AR_Decision__c == 'Acceptée'
      ? Label.AR_Msg_NTF_DecisionAccepted
      : Label.AR_Msg_NTF_DecisionRejected;

    EmailPreview preview = new EmailPreview();
    preview.subject = String.format(
      Label.AR_Email_Derogation_Result_Subject,
      new List<String>{ derogation.AR_Price_Matrix__r.Name }
    );
    preview.body = String.format(
      Label.AR_Email_Derogation_Result_Body,
      new List<String>{
        derogation.AR_Price_Matrix__r.Name,
        String.valueOf(derogation.AR_Price_Matrix__r.AR_Position_Name__c),
        decisionLabel,
        derogation.AR_Effective_Validator__r != null
          ? derogation.AR_Effective_Validator__r.Name
          : '',
        String.valueOf(derogation.AR_Validator_Comment__c),
        appLink(derogation.AR_Price_Matrix__c)
      }
    ) + rplsrLine(derogation.AR_Price_Matrix__r);

    Set<String> recipients = new Set<String>();
    String ownerEmailAddress = ownerEmail(derogation.AR_Price_Matrix__r.OwnerId);
    if (String.isNotBlank(ownerEmailAddress)) {
      recipients.add(ownerEmailAddress);
    }
    if (
      derogation.AR_Effective_Validator__r != null &&
      String.isNotBlank(derogation.AR_Effective_Validator__r.Email)
    ) {
      recipients.add(derogation.AR_Effective_Validator__r.Email);
    }
    preview.toAddresses = new List<String>(recipients);

    // In-app : mêmes destinataires que l'e-mail ci-dessus (demandeur + valideur effectif), à partir
    // du même objet preview — pas une seconde règle de destinataires qui pourrait diverger.
    Set<String> recipientIds = new Set<String>();
    if (derogation.AR_Price_Matrix__r.OwnerId != null) {
      recipientIds.add(derogation.AR_Price_Matrix__r.OwnerId);
    }
    if (derogation.AR_Effective_Validator__c != null) {
      recipientIds.add(derogation.AR_Effective_Validator__c);
    }
    preview.recipientIds = recipientIds;
    // Cible du clic : la matrice (session 34, table des événements).
    preview.notificationTargetId = derogation.AR_Price_Matrix__c;
    return preview;
  }

  public static void sendAutoValidationEmail(Id matrixId) {
    EmailPreview preview = buildAutoValidationEmail(matrixId);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildAutoValidationEmail(Id matrixId) {
    AR_Price_Matrix__c matrix = [
      SELECT
        Name,
        AR_Position_Name__c,
        AR_Proposed_TJM__c,
        AR_TJM_Weighted__c,
        AR_TJM_Periods__c,
        AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
        AR_MC2_Percent__c,
        AR_Currency__c,
        OwnerId
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    String ownerEmailAddress = ownerEmail(matrix.OwnerId);
    if (String.isBlank(ownerEmailAddress)) {
      System.debug(
        LoggingLevel.WARN,
        'AR_NotificationService: aucun email de propriétaire pour la matrice ' +
        matrixId
      );
      return null;
    }

    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ ownerEmailAddress };
    preview.subject = String.format(
      Label.AR_Email_Auto_Validation_Subject,
      new List<String>{ matrix.Name }
    );
    preview.body = String.format(
      Label.AR_Email_Auto_Validation_Body,
      new List<String>{
        matrix.Name,
        String.valueOf(matrix.AR_Position_Name__c),
        tjmWithPeriods(matrix),
        formatPercent(matrix.AR_MC2_Percent__c),
        appLink(matrixId)
      }
    );
    preview.recipientIds = new Set<String>{ matrix.OwnerId };
    // Cible du clic : la matrice (session 34, table des événements).
    preview.notificationTargetId = matrixId;
    return preview;
  }

  /** Un avis à notifier pour AR_QualificationGatingHandler : construit en mémoire, sans SOQL ici. */
  public class GatingWarningNotice {
    public String ownerEmail;
    public String managerEmail;
    // Session 147 : Ids User des deux destinataires, pour le canal in-app (cloche).
    public Id ownerId;
    public Id managerId;
    public String jobApplicationName;
    public String positionName;
    public String caseLabel;
  }

  /**
   * Un seul appel Messaging.sendEmail bulk quel que soit le nombre d'avis — jamais dans une boucle
   * appelante. Échec d'envoi : consigné et journalisé, jamais levé (même contrat que le reste du fichier).
   */
  @TestVisible
  private static final Integer GATING_IN_APP_MAX_PER_TRANSACTION = 10;

  public static void sendGatingWarningEmail(List<GatingWarningNotice> notices) {
    List<EmailPreview> previews = buildGatingWarningEmails(notices);
    if (previews.isEmpty()) {
      return;
    }
    // Plafond in-app par transaction : un déclencheur peut traiter 200 candidatures d'un coup, et
    // chaque notification coûte une requête (interrupteur) + un envoi. L'e-mail part toujours pour
    // tous ; ce qui dépasse le plafond est journalisé, jamais perdu en silence.
    Integer inAppSent = 0;
    for (EmailPreview preview : previews) {
      if (inAppSent >= GATING_IN_APP_MAX_PER_TRANSACTION) {
        System.debug(
          LoggingLevel.WARN,
          'AR_NotificationService: plafond de ' + GATING_IN_APP_MAX_PER_TRANSACTION +
          ' notifications in-app de gating atteint — le reste part par e-mail uniquement.'
        );
        break;
      }
      inAppSent++;
      sendInAppFromPreview(preview);
    }
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (EmailPreview preview : previews) {
      if (preview.toAddresses.isEmpty()) {
        continue;
      }
      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(preview.toAddresses);
      mail.setSubject(preview.subject);
      mail.setPlainTextBody(preview.body);
      // Corps en texte brut : la signature de l'expéditeur (Mes paramètres d'e-mail) est stockée
      // en HTML et Salesforce l'ajoute telle quelle, donc les balises s'affichent en clair dans
      // le message reçu. On la coupe ici — la signature du service est déjà dans le Label.
      mail.setUseSignature(false);
      mail.setSaveAsActivity(false);
      mails.add(mail);
    }
    if (mails.isEmpty()) {
      return;
    }
    deliver('e-mail (avertissement gating)', mails);
  }

  @TestVisible
  private static List<EmailPreview> buildGatingWarningEmails(List<GatingWarningNotice> notices) {
    List<EmailPreview> previews = new List<EmailPreview>();
    for (GatingWarningNotice notice : notices) {
      List<String> recipients = new List<String>();
      if (String.isNotBlank(notice.ownerEmail)) {
        recipients.add(notice.ownerEmail);
      }
      if (String.isNotBlank(notice.managerEmail)) {
        recipients.add(notice.managerEmail);
      }
      Set<String> userIds = new Set<String>();
      if (notice.ownerId != null) {
        userIds.add(notice.ownerId);
      }
      if (notice.managerId != null) {
        userIds.add(notice.managerId);
      }
      if (recipients.isEmpty() && userIds.isEmpty()) {
        continue;
      }
      EmailPreview preview = new EmailPreview();
      preview.toAddresses = recipients;
      preview.recipientIds = userIds;
      preview.subject = String.format(
        Label.AR_Email_Gating_Warning_Subject,
        new List<String>{ String.valueOf(notice.positionName) }
      );
      preview.body = String.format(
        Label.AR_Email_Gating_Warning_Body,
        new List<String>{
          String.valueOf(notice.jobApplicationName),
          String.valueOf(notice.positionName),
          String.valueOf(notice.caseLabel),
          appRootLink()
        }
      );
      previews.add(preview);
    }
    return previews;
  }

  /**
   * Alerte de configuration invalide (session 21b) : destinataire administrable via le Custom Label
   * AR_Gating_Admin_Alert_Email, volontairement hors des cinq paramètres métier de
   * AR_Gating_Setting__mdt. Label vide ⇒ pas d'envoi (le System.debug ERROR déjà loggé par l'appelant
   * reste la trace minimale).
   */
  public static void sendGatingConfigErrorEmail(String configuredStatusId) {
    EmailPreview preview = buildGatingConfigErrorEmail(configuredStatusId);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
  }

  @TestVisible
  private static EmailPreview buildGatingConfigErrorEmail(String configuredStatusId) {
    String adminEmail = Label.AR_Gating_Admin_Alert_Email;
    if (String.isBlank(adminEmail)) {
      return null;
    }
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ adminEmail };
    preview.subject = Label.AR_Email_Gating_Config_Error_Subject;
    preview.body = String.format(
      Label.AR_Email_Gating_Config_Error_Body,
      new List<String>{ String.valueOf(configuredStatusId) }
    );
    return preview;
  }

  /** Une ligne de brouillon concerné, pour le digest de purge (session 22). */
  public class DraftPurgeWarningItem {
    public String matrixName;
    public String positionName;
  }

  /**
   * Un seul e-mail de synthèse par propriétaire (pas un par matrice), listant tous ses brouillons
   * concernés — cf. AR_DraftPurgeBatch. Évite l'envoi massif d'e-mails individuels au premier
   * passage sur un stock de brouillons déjà anciens.
   */
  public static void sendDraftPurgeWarningDigest(
    String ownerEmail,
    Id ownerId,
    List<DraftPurgeWarningItem> items,
    Integer daysSinceModified,
    Integer warningDays
  ) {
    EmailPreview preview = buildDraftPurgeWarningDigest(ownerEmail, ownerId, items, daysSinceModified, warningDays);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    // Session 147 : un e-mail à un utilisateur interne part aussi en notification in-app.
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildDraftPurgeWarningDigest(
    String ownerEmail,
    Id ownerId,
    List<DraftPurgeWarningItem> items,
    Integer daysSinceModified,
    Integer warningDays
  ) {
    if (String.isBlank(ownerEmail) || items == null || items.isEmpty()) {
      return null;
    }
    String listing = '';
    for (DraftPurgeWarningItem item : items) {
      listing +=
        '- ' +
        item.matrixName +
        ' (' +
        String.valueOf(item.positionName) +
        ')\n';
    }
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ ownerEmail };
    if (ownerId != null) {
      preview.recipientIds = new Set<String>{ ownerId };
    }
    preview.subject = String.format(
      Label.AR_Email_Draft_Purge_Warning_Subject,
      new List<String>{ String.valueOf(items.size()) }
    );
    preview.body = String.format(
      Label.AR_Email_Draft_Purge_Warning_Body,
      new List<String>{
        String.valueOf(items.size()),
        String.valueOf(daysSinceModified),
        String.valueOf(warningDays),
        listing
      }
    );
    return preview;
  }

  /** Une ligne de dérogation en attente, pour le digest de relance (palier 1, session 29). */
  public class DerogationReminderItem {
    public String matrixName;
    public String positionName;
    public Integer hoursWaiting;
  }

  /**
   * Un seul e-mail de synthèse par valideur sélectionné (pas un par dérogation), listant toutes ses
   * dérogations qui viennent de franchir le délai de relance — cf. AR_DerogationReminderBatch.
   */
  public static void sendDerogationReminderDigest(
    String validatorEmail,
    Id validatorId,
    List<DerogationReminderItem> items,
    Integer reminderHours
  ) {
    EmailPreview preview = buildDerogationReminderDigest(validatorEmail, validatorId, items, reminderHours);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildDerogationReminderDigest(
    String validatorEmail,
    Id validatorId,
    List<DerogationReminderItem> items,
    Integer reminderHours
  ) {
    if (String.isBlank(validatorEmail) || items == null || items.isEmpty()) {
      return null;
    }
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ validatorEmail };
    // Digest multi-dérogations : pas de cible unique, même choix que l'e-mail (appRootLink() ci-dessous
    // plutôt qu'un lien vers une dérogation précise) — recipientIds vide si l'Id n'a pas pu être résolu
    // (ex. valideur retrouvé seulement par e-mail dans un chemin d'appel qui ne l'a pas), pas d'exception.
    if (validatorId != null) {
      preview.recipientIds = new Set<String>{ validatorId };
    }
    preview.subject = String.format(
      Label.AR_Email_Derogation_Reminder_Subject,
      new List<String>{ String.valueOf(items.size()) }
    );
    preview.body = String.format(
      Label.AR_Email_Derogation_Reminder_Body,
      new List<String>{
        String.valueOf(items.size()),
        String.valueOf(reminderHours),
        derogationListing(items),
        appRootLink()
      }
    );
    return preview;
  }

  /** Une ligne de dérogation en attente, pour le digest d'escalade (palier 2, session 29). */
  public class DerogationEscalationItem {
    public String matrixName;
    public String positionName;
    public Integer hoursWaiting;
    public String selectedValidatorName;
  }

  /**
   * Un seul e-mail de synthèse par destinataire du cercle élargi (tout valideur habilité actif +
   * manager du valideur sélectionné, cf. AR_DerogationReminderBatch), listant toutes les dérogations
   * escaladées dans cette exécution.
   */
  public static void sendDerogationEscalationDigest(
    String recipientEmail,
    Id recipientId,
    List<DerogationEscalationItem> items,
    Integer escalationHours
  ) {
    EmailPreview preview = buildDerogationEscalationDigest(recipientEmail, recipientId, items, escalationHours);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildDerogationEscalationDigest(
    String recipientEmail,
    Id recipientId,
    List<DerogationEscalationItem> items,
    Integer escalationHours
  ) {
    if (String.isBlank(recipientEmail) || items == null || items.isEmpty()) {
      return null;
    }
    String listing = '';
    for (DerogationEscalationItem item : items) {
      listing +=
        AR_I18n.format(Label.AR_Msg_NTF_EscalationLine, new List<Object>{ item.matrixName, String.valueOf(item.positionName), String.valueOf(item.selectedValidatorName) }) +
        '\n';
    }
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ recipientEmail };
    // Digest multi-dérogations : pas de cible unique, même choix que l'e-mail ci-dessous.
    if (recipientId != null) {
      preview.recipientIds = new Set<String>{ recipientId };
    }
    preview.subject = String.format(
      Label.AR_Email_Derogation_Escalation_Subject,
      new List<String>{ String.valueOf(items.size()) }
    );
    preview.body = String.format(
      Label.AR_Email_Derogation_Escalation_Body,
      new List<String>{ String.valueOf(items.size()), listing, appRootLink() }
    );
    return preview;
  }

  /**
   * Alerte de configuration invalide (session 29c) : le cercle d'escalade borné par entité
   * (AR_DerogationReminderBatch) n'a trouvé aucun valideur habilité actif pour l'entité de la
   * matrice. Même modèle que sendGatingConfigErrorEmail — même destinataire
   * (AR_Gating_Admin_Alert_Email, volontairement générique malgré son nom : c'est déjà l'adresse
   * d'alerte technique/administrative de l'app, pas un label spécifique au gating), pas de nouveau
   * Custom Label de destinataire. Label vide ⇒ pas d'envoi.
   */
  public static void sendDerogationEscalationNoRecipientsEmail(
    String matrixName,
    String positionName,
    String entity
  ) {
    EmailPreview preview = buildDerogationEscalationNoRecipientsEmail(matrixName, positionName, entity);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
  }

  @TestVisible
  private static EmailPreview buildDerogationEscalationNoRecipientsEmail(
    String matrixName,
    String positionName,
    String entity
  ) {
    String adminEmail = Label.AR_Gating_Admin_Alert_Email;
    if (String.isBlank(adminEmail)) {
      return null;
    }
    String entityLabel = String.isNotBlank(entity) ? entity : Label.AR_Common_NotProvided_Fem;
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ adminEmail };
    preview.subject = String.format(
      Label.AR_Email_Derogation_Escalation_No_Recipients_Subject,
      new List<String>{ entityLabel }
    );
    preview.body = String.format(
      Label.AR_Email_Derogation_Escalation_No_Recipients_Body,
      new List<String>{
        String.valueOf(matrixName),
        String.valueOf(positionName),
        entityLabel
      }
    );
    return preview;
  }

  /** Une matrice validée automatiquement, pour le digest de notification hiérarchie (session 29). */
  public class HierarchyValidationItem {
    public String matrixName;
    public String positionName;
    public String ownerName;
  }

  /**
   * Un seul e-mail de synthèse par destinataire hiérarchique (session 147 : DA → DD → Directeur du
   * propriétaire de la matrice, cf. AR_DerogationReminderBatch.hierarchyTarget) — appelé
   * soit immédiatement avec un seul item (fréquence Immédiat), soit par AR_HierarchyNotificationBatch
   * avec tous les items accumulés depuis le dernier envoi (Quotidien/Hebdomadaire).
   */
  public static void sendHierarchyNotificationDigest(String managerEmail, Id managerId, List<HierarchyValidationItem> items) {
    EmailPreview preview = buildHierarchyNotificationDigest(managerEmail, managerId, items);
    if (preview == null) {
      return;
    }
    sendEmail(preview.toAddresses, preview.subject, preview.body);
    sendInAppFromPreview(preview);
  }

  @TestVisible
  private static EmailPreview buildHierarchyNotificationDigest(String managerEmail, Id managerId, List<HierarchyValidationItem> items) {
    if (String.isBlank(managerEmail) || items == null || items.isEmpty()) {
      return null;
    }
    String listing = '';
    for (HierarchyValidationItem item : items) {
      listing +=
        '- ' +
        item.matrixName +
        ' (' +
        String.valueOf(item.positionName) +
        ') — ' +
        String.valueOf(item.ownerName) +
        '\n';
    }
    EmailPreview preview = new EmailPreview();
    preview.toAddresses = new List<String>{ managerEmail };
    // Digest multi-matrices : pas de cible unique, même choix que l'e-mail ci-dessous.
    if (managerId != null) {
      preview.recipientIds = new Set<String>{ managerId };
    }
    preview.subject = String.format(
      Label.AR_Email_Hierarchy_Notification_Subject,
      new List<String>{ String.valueOf(items.size()) }
    );
    preview.body = String.format(
      Label.AR_Email_Hierarchy_Notification_Body,
      new List<String>{ String.valueOf(items.size()), listing, appRootLink() }
    );
    return preview;
  }

  /**
   * Hook synchrone appelé par AR_PricingMatrixService.validateInput juste après
   * sendAutoValidationEmail. No-op sauf si AR_General_Setting__c.AR_Hierarchy_Notification_Frequency__c
   * = 'Immédiat' — les fréquences Quotidien/Hebdomadaire sont couvertes par
   * AR_HierarchyNotificationBatch, jamais ici (AR_Price_Matrix__c.AR_Hierarchy_Notified__c reste
   * false pour que le batch les ramasse). Aucun destinataire résolu dans la chaîne : pas
   * d'envoi (journalisé), mais la matrice est quand même marquée notifiée pour ne pas rester indéfiniment dans
   * le champ de balayage du batch si la fréquence change ensuite.
   */
  public static void sendAutoValidationHierarchyNotificationIfImmediate(Id matrixId) {
    List<AR_General_Setting__c> settingsRows = [
      SELECT AR_Hierarchy_Notification_Frequency__c
      FROM AR_General_Setting__c
      LIMIT 1
    ];
    if (settingsRows.isEmpty() || settingsRows[0].AR_Hierarchy_Notification_Frequency__c != 'Immédiat') {
      return;
    }

    AR_Price_Matrix__c matrix = [
      SELECT Name, AR_Position_Name__c, OwnerId, Owner.Name
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    // Session 147 : chaîne DA → DD → Directeur du propriétaire (même résolution que l'escalade des
    // relances), plus User.ManagerId — vide pour tous les utilisateurs actifs de la sandbox.
    User target = AR_DerogationReminderBatch.hierarchyTarget(
      AR_DerogationReminderBatch.loadOwnersWithHierarchy(new Set<Id>{ matrix.OwnerId }).get(matrix.OwnerId)
    );

    if (target != null) {
      HierarchyValidationItem item = new HierarchyValidationItem();
      item.matrixName = matrix.Name;
      item.positionName = matrix.AR_Position_Name__c;
      item.ownerName = matrix.Owner.Name;
      sendHierarchyNotificationDigest(target.Email, target.Id, new List<HierarchyValidationItem>{ item });
    } else {
      System.debug(
        LoggingLevel.WARN,
        'AR_NotificationService: aucun DA/DD/Directeur actif pour le propriétaire de ' + matrix.Name +
        ' (' + matrix.Owner.Name + ') — notification hiérarchie non envoyée.'
      );
    }

    AR_TriggerBypass.serviceContext = true;
    try {
      // SYSTEM_MODE : le drapeau est en lecture seule pour tous les permission sets (écrit par le
      // service seulement) ; appelé depuis la validation automatique, donc sous l'utilisateur BM —
      // l'update par défaut échouait en « fields being inaccessible » (session 147, runAs BM).
      Database.update(
        new AR_Price_Matrix__c(Id = matrixId, AR_Hierarchy_Notified__c = true),
        AccessLevel.SYSTEM_MODE
      );
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }
  }

  private static String derogationListing(List<DerogationReminderItem> items) {
    String listing = '';
    for (DerogationReminderItem item : items) {
      listing +=
        AR_I18n.format(Label.AR_Msg_NTF_ReminderLine, new List<Object>{ item.matrixName, String.valueOf(item.positionName), String.valueOf(item.hoursWaiting) }) +
        '\n';
    }
    return listing;
  }

  private static String ownerEmail(Id ownerId) {
    // OwnerId est polymorphe (User ou Group) ; une matrice de prix appartient toujours à un User
    // dans ce périmètre, une Queue ne renverra simplement aucune ligne ici.
    List<User> owners = [SELECT Email FROM User WHERE Id = :ownerId LIMIT 1];
    return owners.isEmpty() ? null : owners[0].Email;
  }

  private static void sendEmail(
    List<String> toAddresses,
    String subject,
    String body
  ) {
    if (toAddresses.isEmpty()) {
      return;
    }
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(toAddresses);
    mail.setSubject(subject);
    mail.setPlainTextBody(body);
    // Voir sendGatingWarningEmail : sans ceci la signature HTML de l'expéditeur est collée en
    // clair à la fin d'un corps texte brut.
    mail.setUseSignature(false);
    mail.setSaveAsActivity(false);
    deliver('e-mail', new List<Messaging.SingleEmailMessage>{ mail });
  }

  /**
   * Lien d'email cible désormais l'app (session 13) plutôt que la record page : ouvre directement
   * la Matrice AT correspondante via le routeur URL de arPricingApp (docs/13-navigation-etat.md).
   */
  private static String appLink(Id matrixId) {
    return URL.getOrgDomainUrl().toExternalForm() +
      '/lightning/n/AR_Pricing_App?c__view=matriceAT&c__matrixId=' +
      matrixId;
  }

  /** Session 112 : lien de dérogation pour les emails de demande, ouvre directement la file
   * d'approbation avec la dérogation ciblée et dépliée (c__view=approbations&c__derogationId). */
  private static String derogationLink(Id derogationId) {
    return URL.getOrgDomainUrl().toExternalForm() +
      '/lightning/n/AR_Pricing_App?c__view=approbations&c__derogationId=' +
      derogationId;
  }

  /** Lien générique vers l'app, pour les e-mails de digest qui couvrent plusieurs enregistrements
   * (aucune cible individuelle pertinente) — session 21b (buildGatingWarningEmails), réutilisé
   * telle quelle par les digests de relance/escalade/hiérarchie (session 29). */
  private static String appRootLink() {
    return URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/AR_Pricing_App';
  }

  /**
   * Fallback documenté (session 13) : ancien lien direct vers la record page, utilisé avant que
   * l'app ne sache ouvrir une matrice précise depuis l'URL. Conservé pour un retour arrière rapide
   * (remplacer les appels à appLink() par recordPageLink() ci-dessus) si l'ouverture depuis l'app
   * pose un problème en production.
   */
  private static String recordPageLink(Id recordId) {
    return URL.getOrgDomainUrl().toExternalForm() +
      '/lightning/r/AR_Price_Matrix__c/' +
      recordId +
      '/view';
  }

  /** Session 112 : construit la PageReference JSON pour la notification in-app vers la file
   * d'approbation avec la dérogation focalisée. */
  private static String buildDerogationTargetPageRef(Id derogationId) {
    Map<String, Object> state = new Map<String, Object>{
      'c__view' => 'approbations',
      'c__derogationId' => derogationId
    };
    Map<String, Object> pageRef = new Map<String, Object>{
      'type' => 'standard__navItemPage',
      'attributes' => new Map<String, Object>{
        'apiName' => 'AR_Pricing_App'
      },
      'state' => state
    };
    return JSON.serialize(pageRef);
  }

  /**
   * Session 143b : montant au format de l'écran (`formatMoney` d'arPricingEngine) — arrondi à
   * l'euro, milliers en espace insécable, symbole de la devise de la matrice (« € » si vide).
   * Réutilise le formateur FR du PTF plutôt qu'un second.
   */
  @TestVisible
  private static String formatMoney(Decimal value, String currencyCode) {
    if (value == null) {
      return '';
    }
    return AR_PTFFormatUtil.formatNumberFr(
      value,
      0,
      AR_PTFFormatUtil.currencySymbol(currencyCode)
    );
  }

  /**
   * TJM affiché dans un e-mail (docs/254 §11.2) : le TJM moyen pondéré, suivi du détail des périodes quand
   * la mission évolue (« 650 € · 60 j → 700 € · 60 j »). Sans évolution : le TJM seul, comme avant.
   */
  private static String tjmWithPeriods(AR_Price_Matrix__c m) {
    String weighted = formatMoney(AR_PricingMatrixService.effectiveTjm(m), m.AR_Currency__c);
    List<AR_PricingResult.TjmPeriod> periods = AR_PricingMatrixService.tjmPeriodsOf(m);
    if (periods.size() < 2) {
      return weighted;
    }
    List<String> parts = new List<String>();
    for (AR_PricingResult.TjmPeriod p : periods) {
      String days = p.days == null ? '?' : String.valueOf(p.days.intValue());
      parts.add(formatMoney(p.tjm, m.AR_Currency__c) + ' · ' + days + ' j');
    }
    String detail = String.format(Label.AR_Email_TjmWeightedDetail, new List<String>{ String.join(parts, ' → ') });
    return weighted + ' (' + detail + ')';
  }

  /** Régie sans régule (docs/265c §7) : mention secondaire du corps de l'e-mail, vide hors mode actif. */
  private static String rplsrLine(AR_Price_Matrix__c m) {
    String mention = AR_PricingMatrixService.rplsrMention(m);
    return mention == null ? '' : '\n\n' + mention;
  }

  /**
   * Session 143b : pourcentage au format de l'écran (`formatPercent`) — 1 décimale toujours
   * affichée, virgule. Le « % » reste dans le label. `formatNumberFr` supprime les zéros
   * non significatifs : on rétablit « ,0 » pour garder « 3,0 » comme l'écran.
   */
  @TestVisible
  private static String formatPercent(Decimal value) {
    if (value == null) {
      return '';
    }
    String formatted = AR_PTFFormatUtil.formatNumberFr(value.setScale(1, RoundingMode.HALF_UP), 1);
    return formatted.contains(',') ? formatted : formatted + ',0';
  }
}