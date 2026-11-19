/**
 * Orchestration de la génération PTF : gating serveur (matrice validée uniquement), snapshot
 * immuable (AR_PTF_Document__c), rendu PDF (AR_PTFTemplate.page) et stockage Files. Chaque appel
 * crée un nouveau document — aucun écrasement, cf. CLAUDE.md « traçabilité du parcours de prix ».
 * Le PDF est une restitution : un Files supprimé ne fait perdre aucune donnée, seul AR_Snapshot__c
 * fait foi (régénérable indéfiniment, y compris avec un nouveau gabarit).
 *
 * `without sharing`, comme AR_MatrixVersionService : le document PTF est un enregistrement système
 * (aucune permission Create/Edit utilisateur accordée sur AR_PTF_Document__c, cf. permission sets),
 * son insertion ne doit pas dépendre des règles de partage de l'utilisateur courant.
 *
 * Rendu en deux appels synchrones séparés (session 20b, cf. docs/20-generation-ptf.md §4.5) —
 * historique du choix, pour ne pas refaire les deux essais qui ne marchent pas :
 * 1. Rendu synchrone dans la MÊME transaction que l'insertion du snapshot (approche initiale,
 *    session 20) : `PageReference.getContentAsPDF()` ne voit pas le DML non committé de la
 *    transaction qui l'appelle — le PDF se rend avec une structure entièrement vide bien que le
 *    snapshot soit correct en base.
 * 2. Rendu différé via `Queueable` après commit (première tentative de cette session) :
 *    `getContentAsPDF()` lève `System.CalloutException: Callout not allowed from this future
 *    method` — la plateforme l'implémente en interne comme un callout, interdit depuis TOUT
 *    contexte asynchrone (Future, Queueable, Batch), pas seulement depuis `@future`.
 * Solution retenue : `generatePTF` insère le snapshot et retourne immédiatement ; le client (LWC)
 * enchaîne un second appel Apex synchrone, `renderAndStorePTF`, qui s'exécute dans une NOUVELLE
 * transaction (donc voit le snapshot committé par le premier appel) et n'est ni future, ni
 * queueable, ni batch (donc autorisé à appeler getContentAsPDF()). Conséquence UX assumée : le
 * bouton "Générer" déclenche deux appels serveur successifs, le second pouvant prendre plusieurs
 * secondes (rendu PDF) — le LWC affiche un état de chargement pendant ce second appel plutôt qu'un
 * jeu de sondage (« polling ») inutile ici, puisqu'aucune limite de gouverneur ne force à différer
 * le rendu au-delà du second appel.
 */
public without sharing class AR_PTFGenerationService {
  // Session 177 : constante unique pour l'entité ABYLSEN utilisée dans la nomenclature PTF.
  private static final String PTF_ENTITY_CODE = 'ABYLSEN';

  // Session 153b : au-delà, un document « En cours » est réputé abandonné (rendu mesuré à 2 s en
  // médiane, 6 s au maximum, session 153) et l'écran propose de reprendre le rendu.
  public static final Integer RENDER_RETRY_AFTER_SECONDS = 120;

  public class PTFGenerationResult {
    @AuraEnabled
    public Id ptfDocumentId;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public Integer versionNumber;
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String errorMessage;
    // Session 180d : document généré (status « Généré ») mais avec une réserve à afficher à
    // l'utilisateur — aujourd'hui, le fichier n'a pas pu être rattaché au besoin Connexys.
    @AuraEnabled
    public String warning;
  }

  public class PTFDocumentSummary {
    @AuraEnabled
    public Id ptfDocumentId;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public Integer versionNumber;
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String errorMessage;
    // Session 37 : 'PTF' (défaut, y compris les documents antérieurs sans valeur — cf.
    // AR_Document_Type__c.field-meta.xml) ou 'Avenant'. Le LWC s'en sert pour n'offrir « Créer un
    // avenant » que sur une PTF déjà générée, jamais sur un avenant (pas d'avenant à un avenant
    // dans l'interface — question ouverte, cf. docs/37-avenant.md).
    @AuraEnabled
    public String documentType;
    @AuraEnabled
    public Integer avenantNumber;
  }

  public class AR_PTFRenderException extends Exception {
  }

  public class PreviewResult {
    @AuraEnabled
    public Id previewId;
    @AuraEnabled
    public String pageUrl;
  }

  /**
   * Payload en String JSON, pas en classe wrapper — même contournement que AR_PricingMatrixService
   * (docs/19-payload-json.md §3) : Aura n'alimente aucun champ d'un paramètre de type classe Apex
   * définie par l'utilisateur dans cette org.
   */
  @AuraEnabled
  public static PTFGenerationResult generatePTF(String inputJson) {
    if (String.isBlank(inputJson)) {
      throw newAuraException(
        Label.AR_Msg_PTF_EmptyGenerationPayload
      );
    }
    try {
      AR_PTFDataService.GenerationInput input = (AR_PTFDataService.GenerationInput) JSON.deserialize(
        inputJson,
        AR_PTFDataService.GenerationInput.class
      );
      return generatePTFInput(input);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_GenerationAction);
    }
  }

  /**
   * Collecte et insère le snapshot — c'est la source de vérité, disponible immédiatement au retour
   * de cet appel. Ne rend PAS le PDF : c'est le rôle du second appel, `renderAndStorePTF`, dans une
   * transaction séparée (cf. commentaire d'en-tête de classe pour le pourquoi).
   */
  public static PTFGenerationResult generatePTFInput(
    AR_PTFDataService.GenerationInput input
  ) {
    AR_Price_Matrix__c m = [
      SELECT Id, AR_Position__c, AR_Status__c
      FROM AR_Price_Matrix__c
      WHERE Id = :input.matrixId
      LIMIT 1
    ];

    Integer nextVersion = nextVersionNumber(m.Id);
    // collect() revalide le statut (source unique de vérité du gating, appelée aussi par
    // getGenerationDefaults) : la requête ci-dessus ne sert qu'à obtenir AR_Position__c.
    AR_PTFData data = AR_PTFDataService.collect(
      m.Id,
      input,
      nextVersion
    );

    // Session 138 : à partir du rang 2, le type de modification est obligatoire — vérifié ICI,
    // avant toute insertion, pour qu'une saisie manquante ne laisse aucun document derrière elle.
    // Au rang 1, type et détail sont ignorés et ne sont pas stockés. Le rang vient de collect()
    // (data.displayRank), calculé sur le gabarit réellement résolu.
    Integer displayRank = data.displayRank;
    AR_PTFHistoryService.requireModification(displayRank, input.modificationType, input.modificationDetail);
    Boolean withModification = displayRank != null && displayRank >= 2;

    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = m.Id,
      AR_Position__c = m.AR_Position__c,
      AR_Reference__c = data.reference,
      // Compteur TECHNIQUE, inchangé : il ne suit pas le rang d'affichage (cases décochées).
      AR_Version_Number__c = nextVersion,
      AR_Snapshot__c = JSON.serialize(data),
      AR_Generated_At__c = data.generatedAt,
      AR_Generation_Status__c = 'En cours',
      AR_Template_Code__c = data.templateCode,
      AR_Include_In_History__c = true,
      AR_Modification_Type__c = withModification ? input.modificationType : null,
      AR_Modification_Detail__c = withModification && input.modificationType == 'Autre'
        ? input.modificationDetail.trim()
        : null
    );
    // Session 41 : `without sharing` seul ne suffit pas — aucune permission Create utilisateur n'est
    // accordée sur AR_PTF_Document__c par construction (cf. en-tête de classe), un BM réel obtenait
    // `DML operation INSERT not allowed on AR_PTF_Document__c` (System.TypeException). Même motif
    // déjà corrigé sur AR_MatrixVersionService.createSnapshot en session 40 : `without sharing`
    // bypass le partage, AccessLevel.SYSTEM_MODE bypass le CRUD/FLS — les deux sont nécessaires
    // ensemble. Jamais exercé sous System.runAs avant cette session.
    Database.insert(doc, AccessLevel.SYSTEM_MODE);

    PTFGenerationResult result = new PTFGenerationResult();
    result.ptfDocumentId = doc.Id;
    result.reference = data.reference;
    result.versionNumber = nextVersion;
    result.contentDocumentId = null;
    result.status = 'En cours';
    return result;
  }

  /**
   * Point d'entrée LWC pour la création d'un avenant — payload JSON, même contournement Aura que
   * generatePTF (cf. commentaire de tête de classe).
   */
  @AuraEnabled
  public static PTFGenerationResult generateAvenant(String inputJson) {
    if (String.isBlank(inputJson)) {
      throw newAuraException(
        Label.AR_Msg_PTF_EmptyAvenantPayload
      );
    }
    try {
      AR_PTFDataService.AvenantGenerationInput input = (AR_PTFDataService.AvenantGenerationInput) JSON.deserialize(
        inputJson,
        AR_PTFDataService.AvenantGenerationInput.class
      );
      return generateAvenantInput(input);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_AvenantGenerationAction);
    }
  }

  /**
   * Collecte et insère le snapshot d'un avenant — même principe en deux temps que generatePTFInput
   * (cf. commentaire de tête de classe) : ce premier appel n'insère PAS de PDF, `renderAndStorePTF`
   * (partagé avec la PTF, aiguillé par AR_Template_Code__c) reste le second appel, dans une nouvelle
   * transaction.
   *
   * Un avenant se rattache à un AR_PTF_Document__c EXISTANT (`input.ptfDocumentId`) : il ne consomme
   * pas son AR_Version_Number__c (nextAvenantNumber est un compteur séparé, cf. prompt de session)
   * et ne modifie JAMAIS ce document d'origine — aucun DML n'est émis dessus, prouvé en réel par une
   * requête avant/après (docs/37-avenant.md §4).
   */
  public static PTFGenerationResult generateAvenantInput(
    AR_PTFDataService.AvenantGenerationInput input
  ) {
    // Session 180d : avenant piloté par la matrice. Le document se rattache à la MATRICE AVENANT
    // (input.matrixId) et cite la PTF qu'elle amende (AR_Amended_PTF__c) ; sans matrixId, parcours
    // historique du formulaire (document rattaché à la matrice de la PTF d'origine).
    AR_Price_Matrix__c avenantMatrix = null;
    Id parentId = input.ptfDocumentId;
    if (input.matrixId != null) {
      avenantMatrix = loadAvenantMatrix(input.matrixId);
      if (input.ptfDocumentId != null && input.ptfDocumentId != avenantMatrix.AR_Amended_PTF__c) {
        throw newAuraException(
          Label.AR_Msg_PTF_WrongPtfForAvenant
        );
      }
      parentId = avenantMatrix.AR_Amended_PTF__c;
    }
    AR_PTF_Document__c parentDoc = [
      SELECT Id, AR_Price_Matrix__c, AR_Position__c, AR_Reference__c, AR_Generated_At__c,
             AR_Generation_Status__c, AR_Document_Type__c
      FROM AR_PTF_Document__c
      WHERE Id = :parentId
      LIMIT 1
    ];
    if (parentDoc.AR_Generation_Status__c != 'Généré') {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_AvenantNeedsGeneratedPtf, new List<Object>{ parentDoc.AR_Generation_Status__c })
      );
    }

    Integer avenantNumber = avenantMatrix == null
      ? nextAvenantNumber(parentDoc.Id)
      : avenantNumberFor(parentDoc.Id, avenantMatrix.Id);
    AR_PTFData data = AR_PTFDataService.collectAvenant(parentDoc, input, avenantNumber);

    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = avenantMatrix == null ? parentDoc.AR_Price_Matrix__c : avenantMatrix.Id,
      AR_Position__c = parentDoc.AR_Position__c,
      AR_Parent_PTF__c = parentDoc.Id,
      AR_Document_Type__c = 'Avenant',
      AR_Avenant_Number__c = avenantNumber,
      // Champ obligatoire de l'objet (cf. AR_Version_Number__c.field-meta.xml) mais dénué de sens
      // de version PTF pour un avenant : nextVersionNumber() l'ignore explicitement (filtre
      // AR_Document_Type__c != 'Avenant'), cf. commentaire de cette méthode ci-dessus.
      AR_Version_Number__c = avenantNumber,
      AR_Reference__c = data.reference,
      AR_Snapshot__c = JSON.serialize(data),
      AR_Generated_At__c = data.generatedAt,
      AR_Generation_Status__c = 'En cours',
      AR_Template_Code__c = data.templateCode
    );
    // Même bypass que generatePTFInput ci-dessus (session 41).
    Database.insert(doc, AccessLevel.SYSTEM_MODE);

    PTFGenerationResult result = new PTFGenerationResult();
    result.ptfDocumentId = doc.Id;
    result.reference = data.reference;
    result.versionNumber = avenantNumber;
    result.contentDocumentId = null;
    result.status = 'En cours';
    return result;
  }

  /**
   * Premier appel de la génération automatique d'un avenant (session 180d, Q10 B) : appelé par l'écran
   * juste après une validation directe (arAvenantModal) ou une décision de dérogation « Acceptée »
   * (arDerogationQueue, arDerogationPanel). Idempotent et sans effet hors avenant :
   *  - matrice qui n'est pas un avenant, ou pas (encore) validée → null, rien à faire ;
   *  - avenant déjà doté d'un document « Généré » ou « En cours » → null (double clic, deux onglets) ;
   *  - sinon insère le snapshot (premier temps du protocole en deux transactions) et le renvoie ; le
   *    client enchaîne `renderAndStorePTF` dans un appel distinct.
   * Un document « Échec » ne bloque pas : l'appel suivant en crée un nouveau, qui reprend son numéro AV.
   * Les contacts sont ceux de la règle de la session 145 (PTF d'origine > source actuelle).
   */
  @AuraEnabled
  public static PTFGenerationResult generateAvenantIfNeeded(Id matrixId) {
    try {
      List<AR_Price_Matrix__c> rows = [
        SELECT Id, AR_Version_Type__c, AR_Status__c
        FROM AR_Price_Matrix__c
        WHERE Id = :matrixId
        LIMIT 1
      ];
      if (
        rows.isEmpty() ||
        rows[0].AR_Version_Type__c != 'Avenant' ||
        (rows[0].AR_Status__c != 'Validée' && rows[0].AR_Status__c != 'Validée par dérogation')
      ) {
        return null;
      }
      if (hasLiveAvenantDocument(matrixId)) {
        return null;
      }
      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.matrixId = matrixId;
      return generateAvenantInput(input);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_AvenantGenerationAction);
    }
  }

  public class AvenantState {
    @AuraEnabled
    public Boolean isAvenant;
    @AuraEnabled
    public String matrixStatus;
    @AuraEnabled
    public Id amendedPtfId;
    @AuraEnabled
    public String amendedPtfReference;
    @AuraEnabled
    public Id amendedPtfContentDocumentId;
    @AuraEnabled
    public Id amendedPtfMatrixId;
    // Ce que le document imprimera, lu sur la matrice avenant (formulaire court : aperçu des lots).
    @AuraEnabled
    public Date effectiveDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Decimal proposedTjm;
    @AuraEnabled
    public String currencyCode;
    // Vrai si le tarif ou la période change : le document imprime alors le bloc tarif + échéancier.
    @AuraEnabled
    public Boolean printsPriceBlock;
  }

  /**
   * État « avenant » d'une matrice, pour arPtfPanel (session 180d) : sur une matrice avenant validée le
   * panneau propose « Générer l'avenant » (et non « Générer la PTF ») et cite la PTF amendée en lien.
   * Non cacheable : appel impératif à l'ouverture du panneau (piège de la session 51).
   */
  @AuraEnabled(cacheable=false)
  public static AvenantState getAvenantState(Id matrixId) {
    try {
      AvenantState state = new AvenantState();
      state.isAvenant = false;
      List<AR_Price_Matrix__c> rows = [
        SELECT Id, AR_Version_Type__c, AR_Status__c, AR_Amended_PTF__c, AR_Start_Date__c, AR_End_Date__c,
               AR_Proposed_TJM__c, AR_Currency__c, AR_Avenant_Changes__c
        FROM AR_Price_Matrix__c
        WHERE Id = :matrixId
        LIMIT 1
      ];
      if (rows.isEmpty() || rows[0].AR_Version_Type__c != 'Avenant') {
        return state;
      }
      state.isAvenant = true;
      state.matrixStatus = rows[0].AR_Status__c;
      state.effectiveDate = rows[0].AR_Start_Date__c;
      state.endDate = rows[0].AR_End_Date__c;
      state.proposedTjm = rows[0].AR_Proposed_TJM__c;
      state.currencyCode = rows[0].AR_Currency__c;
      String changes = rows[0].AR_Avenant_Changes__c == null ? '' : rows[0].AR_Avenant_Changes__c;
      state.printsPriceBlock = changes.contains('Tarif') || changes.contains('Période');
      if (rows[0].AR_Amended_PTF__c != null) {
        for (AR_PTF_Document__c ptf : [
          SELECT Id, AR_Reference__c, AR_Content_Document_Id__c, AR_Price_Matrix__c
          FROM AR_PTF_Document__c
          WHERE Id = :rows[0].AR_Amended_PTF__c
          LIMIT 1
        ]) {
          state.amendedPtfId = ptf.Id;
          state.amendedPtfReference = ptf.AR_Reference__c;
          state.amendedPtfMatrixId = ptf.AR_Price_Matrix__c;
          state.amendedPtfContentDocumentId = String.isNotBlank(ptf.AR_Content_Document_Id__c)
            ? Id.valueOf(ptf.AR_Content_Document_Id__c)
            : null;
        }
      }
      return state;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_AvenantStateReadAction);
    }
  }

  /**
   * Interrupteur de l'ancien formulaire d'avenant (session 180d, Q7 A du 14/10/2026 : « l'ancien parcours
   * est gardé de côté, réactivable par un réglage »). Faux si le réglage est absent ou décoché. Non
   * cacheable : le basculement doit être vu à l'ouverture suivante du panneau, sans cache client.
   */
  @AuraEnabled(cacheable=false)
  public static Boolean isLegacyAvenantFormEnabled() {
    try {
      List<AR_General_Setting__c> rows = [SELECT AR_Legacy_Avenant_Form_Enabled__c FROM AR_General_Setting__c LIMIT 1];
      return !rows.isEmpty() && rows[0].AR_Legacy_Avenant_Form_Enabled__c == true;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_LegacyAvenantSettingAction);
    }
  }

  /** Vrai si l'avenant porte déjà un document « Généré » ou « En cours » (un « Échec » ne compte pas). */
  private static Boolean hasLiveAvenantDocument(Id matrixId) {
    return ![
      SELECT Id
      FROM AR_PTF_Document__c
      WHERE
        AR_Price_Matrix__c = :matrixId
        AND AR_Document_Type__c = 'Avenant'
        AND AR_Generation_Status__c IN ('Généré', 'En cours')
      LIMIT 1
    ].isEmpty();
  }

  /** Matrice avenant à documenter : doit être un avenant, validé, et citer la PTF qu'il amende. */
  private static AR_Price_Matrix__c loadAvenantMatrix(Id matrixId) {
    List<AR_Price_Matrix__c> rows = [
      SELECT Id, AR_Version_Type__c, AR_Status__c, AR_Amended_PTF__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw newAuraException(Label.AR_Msg_PTF_AvenantMatrixNotFound);
    }
    AR_Price_Matrix__c m = rows[0];
    if (m.AR_Version_Type__c != 'Avenant') {
      throw newAuraException(Label.AR_Msg_PTF_NotAnAvenant);
    }
    if (m.AR_Status__c != 'Validée' && m.AR_Status__c != 'Validée par dérogation') {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_AvenantNotValidated, new List<Object>{ m.AR_Status__c })
      );
    }
    if (m.AR_Amended_PTF__c == null) {
      throw newAuraException(Label.AR_Msg_PTF_AvenantNoPtf);
    }
    return m;
  }

  /**
   * Second appel, déclenché par le LWC juste après `generatePTF` — nouvelle transaction, voit donc
   * le snapshot inséré par le premier appel. Requête tout ce dont elle a besoin depuis le document
   * lui-même (snapshot, matrice, besoin) plutôt que de recevoir ces valeurs en paramètre : plus
   * simple côté appelant, et cohérent avec « le contrôleur ne lit que le snapshot ».
   * Un échec (rendu ou stockage) est écrit dans AR_Generation_Error__c et le statut passe à Échec :
   * jamais un document d'apparence normale mais vide (corollaire de la session 20b).
   */
  @AuraEnabled
  public static PTFGenerationResult renderAndStorePTF(Id ptfDocumentId) {
    AR_PTF_Document__c doc = [
      SELECT AR_Price_Matrix__c, AR_Position__c, AR_Reference__c, AR_Version_Number__c, AR_Snapshot__c,
             AR_Template_Code__c
      FROM AR_PTF_Document__c
      WHERE Id = :ptfDocumentId
      LIMIT 1
    ];

    PTFGenerationResult result = new PTFGenerationResult();
    result.ptfDocumentId = ptfDocumentId;
    result.reference = doc.AR_Reference__c;
    result.versionNumber = Integer.valueOf(doc.AR_Version_Number__c);

    try {
      if (String.isBlank(doc.AR_Snapshot__c)) {
        throw new AR_PTFRenderException(
          AR_I18n.format(Label.AR_Msg_PTF_SnapshotMissing, new List<Object>{ ptfDocumentId })
        );
      }
      AR_PTFData data = (AR_PTFData) JSON.deserialize(
        doc.AR_Snapshot__c,
        AR_PTFData.class
      );

      // Le gabarit rendu est celui figé sur CE document (AR_Template_Code__c, copie de
      // data.templateCode au moment de sa propre génération) — jamais recalculé depuis la
      // résolution courante : un ancien document rendu à nouveau (usage debug/audit via
      // AR_PTFTemplateController) ressort sous son gabarit d'origine, même si la résolution
      // compte/entité a changé depuis, cf. docs/30-ptf-previsualisation-et-gabarits.md §3.
      Blob pdfBlob = renderPdf(ptfDocumentId, doc.AR_Template_Code__c);
      StoredFile stored = storeAsFile(
        doc.AR_Price_Matrix__c,
        doc.AR_Position__c,
        data,
        pdfBlob
      );
      Id contentDocumentId = stored.contentDocumentId;
      result.warning = stored.warning;

      // Même bypass que generatePTFInput (session 41) : AR_Content_Document_Id__c/
      // AR_Generation_Status__c ne sont pas éditables par l'utilisateur.
      Database.update(
        new AR_PTF_Document__c(
          Id = ptfDocumentId,
          AR_Content_Document_Id__c = contentDocumentId,
          AR_Generation_Status__c = 'Généré'
        ),
        AccessLevel.SYSTEM_MODE
      );

      result.contentDocumentId = contentDocumentId;
      result.status = 'Généré';
    } catch (Exception e) {
      String message = e.getTypeName() + ': ' + e.getMessage();
      String truncated = message.length() > 500
        ? message.substring(0, 500)
        : message;
      try {
        Database.update(
          new AR_PTF_Document__c(
            Id = ptfDocumentId,
            AR_Generation_Status__c = 'Échec',
            AR_Generation_Error__c = truncated
          ),
          AccessLevel.SYSTEM_MODE
        );
      } catch (Exception updateEx) {
        // Journalisé (classement session 34) : le résultat Échec est de toute façon renvoyé à
        // l'écran ci-dessous ; seule la trace en base manque.
        System.debug(LoggingLevel.ERROR, 'Statut Échec non enregistré : ' + updateEx.getMessage());
      }
      // Session 110 : plus de throw ici (ajouté en session 105). Une exception sortant d'une
      // méthode @AuraEnabled annule toute la transaction, y compris la mise à jour « Échec »
      // ci-dessus : le document restait « En cours » indéfiniment dans l'historique. Le contrat de
      // la session 20b est rétabli — l'échec est un résultat (status + errorMessage), affiché par
      // arPtfPanel dans un toast d'erreur.
      result.status = 'Échec';
      result.errorMessage = truncated;
    }
    return result;
  }

  /**
   * Reprise du rendu d'un document resté « En cours » (session 153b). Un échec capturé par
   * `renderAndStorePTF` devient « Échec » avec motif ; ce qui reste « En cours » est ce que cette
   * méthode ne voit jamais : second appel jamais reçu (onglet fermé entre les deux appels),
   * limite plateforme non rattrapable, coupure réseau. Garde-fous côté serveur, pas seulement côté
   * écran : le document doit être « En cours » ET plus ancien que RENDER_RETRY_AFTER_SECONDS —
   * sinon un second rendu pourrait doubler un rendu réellement en cours (deux fichiers stockés).
   * Aucun DML avant ces contrôles : le `throw` n'a rien à annuler.
   */
  @AuraEnabled
  public static PTFGenerationResult retryRenderPTF(Id ptfDocumentId) {
    try {
      List<AR_PTF_Document__c> rows = [
        SELECT AR_Generation_Status__c, CreatedDate
        FROM AR_PTF_Document__c
        WHERE Id = :ptfDocumentId
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw newAuraException(Label.AR_Msg_PTF_DocumentNotFound);
      }
      if (rows[0].AR_Generation_Status__c != 'En cours') {
        throw newAuraException(
          AR_I18n.format(Label.AR_Msg_PTF_NotPendingAnymore, new List<Object>{ rows[0].AR_Generation_Status__c })
        );
      }
      Long ageSeconds = (System.now().getTime() - rows[0].CreatedDate.getTime()) / 1000;
      if (ageSeconds < RENDER_RETRY_AFTER_SECONDS) {
        throw newAuraException(
          AR_I18n.format(Label.AR_Msg_PTF_GenerationTooRecent, new List<Object>{ (RENDER_RETRY_AFTER_SECONDS / 60) })
        );
      }
      return renderAndStorePTF(ptfDocumentId);
    } catch (Exception e) {
      // Les refus de garde ci-dessus sont déjà des AuraHandledException : `wrap` les laisse passer
      // tels quels (message lisible conservé).
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_ResumeRenderAction);
    }
  }

  /**
   * Appelée par l'écran quand `renderAndStorePTF` n'a rien renvoyé d'exploitable (exception Aura,
   * réseau, limite plateforme) : le document passe en « Échec » avec le motif, au lieu de rester
   * « En cours » sans trace (session 153b). Ne touche QUE un document encore « En cours » — un
   * rendu qui aurait fini entre-temps (« Généré ») n'est jamais écrasé.
   */
  @AuraEnabled
  public static void markRenderFailed(Id ptfDocumentId, String reason) {
    try {
      List<AR_PTF_Document__c> rows = [
        SELECT AR_Generation_Status__c
        FROM AR_PTF_Document__c
        WHERE Id = :ptfDocumentId
        LIMIT 1
      ];
      if (rows.isEmpty() || rows[0].AR_Generation_Status__c != 'En cours') {
        return;
      }
      String message =
        AR_I18n.format(Label.AR_Msg_PTF_RenderInterrupted, new List<Object>{ (String.isBlank(reason) ? Label.AR_Msg_UnknownReason : reason) });
      // Même bypass que renderAndStorePTF : AR_Generation_Status__c n'est pas éditable par l'utilisateur.
      Database.update(
        new AR_PTF_Document__c(
          Id = ptfDocumentId,
          AR_Generation_Status__c = 'Échec',
          AR_Generation_Error__c = message.length() > 500 ? message.substring(0, 500) : message
        ),
        AccessLevel.SYSTEM_MODE
      );
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_MarkFailedAction);
    }
  }

  /**
   * Liste des PTF déjà générées pour une matrice (régénération, accès aux versions précédentes).
   * Non cacheable (session 51) : appelée uniquement en impératif (chargement initial et bouton
   * Actualiser), jamais par un `@wire` — `cacheable=true` sur un appel impératif est servi par le
   * cache client et ne revoit jamais le serveur à paramètre identique, cf. CLAUDE.md.
   */
  @AuraEnabled
  public static List<AR_PTFHistoryService.PTFDocumentRow> listPTFDocuments(Id matrixId) {
    // Déterminer le template code depuis un document existant, ou "GENERIQUE" par défaut.
    // Le template code est utilisé pour calculer les rangs de l'historique (scope besoin vs matrice).
    String templateCode = 'GENERIQUE';
    List<AR_PTF_Document__c> docs = [
      SELECT AR_Template_Code__c
      FROM AR_PTF_Document__c
      WHERE AR_Price_Matrix__c = :matrixId
      ORDER BY AR_Generated_At__c DESC
      LIMIT 1
    ];
    if (!docs.isEmpty() && String.isNotBlank(docs[0].AR_Template_Code__c)) {
      templateCode = docs[0].AR_Template_Code__c;
    }

    // Réutiliser la méthode unique de construction des lignes (AR_PTFHistoryService),
    // pour que displayRank, includedInHistory, et les champs de modification soient toujours
    // présents, jamais dupliqués en deux endroits.
    return AR_PTFHistoryService.buildDocumentRows(matrixId, templateCode);
  }

  /**
   * Lecture pure (MAX() SOQL, aucune écriture) : peut être appelée à volonté sans effet de bord,
   * notamment par buildPreviewData pour "regarder" le prochain numéro sans le consommer — c'est ce
   * qui garantit qu'une prévisualisation ne décale jamais le numéro de version de la génération
   * réelle suivante (session 30, cf. docs/30-ptf-previsualisation-et-gabarits.md §2).
   */
  public static Integer nextVersionNumber(Id matrixId) {
    // Filtre AR_Document_Type__c != 'Avenant' (session 37) : un avenant porte lui aussi une valeur
    // dans AR_Version_Number__c (champ obligatoire de l'objet, cf. AR_PTF_Document__c), mais cette
    // valeur n'est PAS un numéro de version PTF et ne doit jamais influencer le prochain numéro de
    // version — sans ce filtre, générer un avenant après une PTF déciderait à tort le numéro de
    // version suivant de cette PTF (cf. prompt de session : « un avenant ne consomme pas le numéro
    // de version de la PTF d'origine », vérifié en réel §5 de docs/37-avenant.md).
    AggregateResult[] results = [
      SELECT MAX(AR_Version_Number__c) maxVersion
      FROM AR_PTF_Document__c
      WHERE AR_Price_Matrix__c = :matrixId AND AR_Document_Type__c != 'Avenant'
    ];
    Decimal maxVersion = (Decimal) results[0].get('maxVersion');
    return maxVersion == null ? 1 : Integer.valueOf(maxVersion) + 1;
  }

  /**
   * Numérotation propre à l'avenant (AV1, AV2…), rattachée à SA PTF d'origine — jamais mêlée au
   * compteur AR_Version_Number__c de la PTF (cf. nextVersionNumber). Lecture pure (MAX() SOQL),
   * même garantie qu'un aperçu ne décale jamais le numéro d'une génération réelle suivante.
   */
  public static Integer nextAvenantNumber(Id parentPtfDocumentId) {
    AggregateResult[] results = [
      SELECT MAX(AR_Avenant_Number__c) maxNumber
      FROM AR_PTF_Document__c
      WHERE AR_Parent_PTF__c = :parentPtfDocumentId
    ];
    Decimal maxNumber = (Decimal) results[0].get('maxNumber');
    return maxNumber == null ? 1 : Integer.valueOf(maxNumber) + 1;
  }

  /**
   * Numéro d'avenant d'un document piloté par la matrice (session 180d). Un rendu en échec ne consomme
   * pas de numéro : si le dernier document de CETTE matrice est « Échec », la nouvelle tentative reprend
   * son numéro (sinon le client recevrait un AV2 sans AV1). Dans tous les autres cas : numéro suivant de
   * la PTF amendée, comme nextAvenantNumber.
   */
  public static Integer avenantNumberFor(Id parentPtfDocumentId, Id avenantMatrixId) {
    List<AR_PTF_Document__c> last = [
      SELECT AR_Avenant_Number__c, AR_Generation_Status__c
      FROM AR_PTF_Document__c
      WHERE
        AR_Price_Matrix__c = :avenantMatrixId
        AND AR_Parent_PTF__c = :parentPtfDocumentId
        AND AR_Document_Type__c = 'Avenant'
        AND AR_Avenant_Number__c != null
      ORDER BY AR_Avenant_Number__c DESC, CreatedDate DESC
      LIMIT 1
    ];
    if (!last.isEmpty() && last[0].AR_Generation_Status__c == 'Échec') {
      return Integer.valueOf(last[0].AR_Avenant_Number__c);
    }
    return nextAvenantNumber(parentPtfDocumentId);
  }

  /**
   * Le moteur PDF de Visualforce (Flying Saucer) n'est pas exécutable en contexte de test — la
   * plateforme lève systématiquement une exception sur getContentAsPDF() pendant un test unitaire ;
   * Test.isRunningTest() est le contournement standard documenté par Salesforce.
   */
  private static Blob renderPdf(Id ptfDocumentId, String templateCode) {
    // Résolution AVANT le court-circuit de test (session 35) : c'est ici que se rejette un code de
    // gabarit inconnu, et cette règle doit être couverte par la suite automatisée — la placer après
    // le `return` de test la rendrait invérifiable autrement qu'en réel.
    PageReference pdfPage = resolveTemplatePage(templateCode);
    if (Test.isRunningTest()) {
      return Blob.valueOf('PDF de test — rendu non exécuté en contexte de test.');
    }
    pdfPage.getParameters().put('id', ptfDocumentId);
    return pdfPage.getContentAsPDF();
  }

  /**
   * Aiguillage réel des gabarits (session 35) — une page Visualforce par gabarit, décision
   * d'architecture assumée : ces documents sont contractuels, une régression de mise en page sur
   * l'un parce qu'on a touché l'autre coûte plus cher que du CSS répété. Ce n'est pas un moteur de
   * gabarits paramétré par blocs conditionnels et ça ne doit pas le devenir.
   *
   * Deux changements par rapport à la session 30, où toute valeur retombait sur Page.AR_PTFTemplate :
   * 1. les quatre codes pointent chacun sur leur page (les trois nouvelles sont des coquilles que
   *    les sessions 36-38 rempliront) ;
   * 2. un code INCONNU lève désormais une erreur nommant le code et les codes valides, au lieu de
   *    produire silencieusement un document sur le gabarit générique. Avec quatre gabarits
   *    contractuels, ce repli muet était le meilleur moyen d'envoyer au client un document sur le
   *    mauvais modèle sans que personne ne le voie.
   *
   * Un code vide reste le générique : les documents antérieurs à la session 30 n'en portent aucun,
   * et ils doivent continuer de se rendre à l'identique.
   */
  // `public` et non `private` : c'est la règle d'aiguillage du projet, et elle doit rester
  // vérifiable en réel par Apex anonyme — pas seulement par la suite de tests. AR_PTFRenderException
  // n'est pas une AuraHandledException : elle est levable hors contexte Aura, contrairement au
  // blocage de la résolution (cf. AR_PTFDataService.templateCodeError).
  public static PageReference resolveTemplatePage(String templateCode) {
    String code = String.isBlank(templateCode)
      ? AR_PTFDataService.GENERIC_TEMPLATE_CODE
      : templateCode;
    if (code == AR_PTFDataService.GENERIC_TEMPLATE_CODE) {
      return Page.AR_PTFTemplate;
    }
    if (code == 'ABYLSEN_AT_V11') {
      return Page.AR_PTFTemplateAbylsen;
    }
    if (code == 'AVENANT_AT_V11') {
      return Page.AR_PTFAvenant;
    }
    if (code == 'ABMI_DQ012') {
      return Page.AR_PTFTemplateAbmi;
    }
    List<String> valid = new List<String>(AR_PTFDataService.TEMPLATE_LABELS.keySet());
    valid.sort();
    throw new AR_PTFRenderException(
      AR_I18n.format(Label.AR_Msg_PTF_UnknownTemplateAtRender, new List<Object>{ code, String.join(valid, ', ') })
    );
  }

  /**
   * URL de la page Visualforce de PRÉVISUALISATION pour un gabarit (session 39) — jusqu'ici,
   * `arPtfPanel` ouvrait systématiquement `/apex/AR_PTFTemplate` (le gabarit générique) quel que
   * soit le gabarit résolu ou surchargé : correct à la session 30 (les trois autres pages étaient
   * encore des coquilles), plus du tout depuis que les sessions 36-38 les ont mises en page — un
   * aperçu Abylsen/avenant/ABMI montrait la mise en page générique, jamais celle qui serait
   * réellement générée. Réutilise `resolveTemplatePage`, seule source de vérité de l'aiguillage
   * gabarit → page (cf. son commentaire) : jamais une seconde correspondance codée en dur ici, qui
   * pourrait diverger de celle utilisée à la génération réelle.
   */
  @AuraEnabled(cacheable=true)
  public static String getPreviewPageUrl(String templateCode) {
    return resolveTemplatePage(templateCode).getUrl();
  }

  /**
   * Aperçu PTF par clé serveur (session 124) : crée un enregistrement `AR_PTF_Preview__c`
   * contenant les données sérialisées, puis retourne l'ID et l'URL de la page Visualforce.
   * Utilise le même calcul de données que `buildPreviewData` (même collect, même gating,
   * isPreview=true) mais persiste temporairement côté serveur pour éviter de passer plusieurs
   * dizaines de Ko dans l'URL. L'enregistrement n'est pas lisible par les autres utilisateurs
   * (OWD Privé) et sera supprimé après 24h par le batch de purge existant.
   */
  @AuraEnabled
  public static PreviewResult createPreview(String inputJson) {
    if (String.isBlank(inputJson)) {
      throw newAuraException(
        Label.AR_Msg_PTF_EmptyPreviewPayload
      );
    }
    try {
      AR_PTFDataService.GenerationInput input = (AR_PTFDataService.GenerationInput) JSON.deserialize(
        inputJson,
        AR_PTFDataService.GenerationInput.class
      );
      Integer peekedVersion = nextVersionNumber(input.matrixId);
      AR_PTFData data = AR_PTFDataService.collect(input.matrixId, input, peekedVersion);
      data.isPreview = true;

      AR_PTF_Preview__c preview = new AR_PTF_Preview__c(
        AR_Data__c = JSON.serialize(data),
        AR_Template_Code__c = data.templateCode
      );
      // Session 126 : enregistrement technique transitoire — écrit en SYSTEM_MODE pour ne pas dépendre
      // des permission sets (FLS AR_Data__c manquante = « fields being inaccessible »). La confidentialité
      // est assurée à la lecture : AR_PTFTemplateController ne sert que les aperçus créés par l'utilisateur.
      Database.insert(preview, AccessLevel.SYSTEM_MODE);

      PreviewResult result = new PreviewResult();
      result.previewId = preview.Id;
      result.pageUrl = resolveTemplatePage(data.templateCode).getUrl();
      return result;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_PreviewAction);
    }
  }

  /**
   * Prévisualisation transitoire (session 30) : recalcule exactement la même structure AR_PTFData
   * qu'une génération réelle (même AR_PTFDataService.collect(), même gating de statut) mais
   * n'insère RIEN — ni AR_PTF_Document__c, ni ContentVersion, ni numéro de version consommé
   * (nextVersionNumber est une lecture pure). Le JSON encodé en base64 est consommé par
   * AR_PTFTemplate.page via son paramètre `data` (AR_PTFTemplateController) : le rendu PDF reste
   * strictement le même gabarit que la génération réelle, contrairement à un aperçu HTML séparé qui
   * risquerait de diverger — cf. docs/30-ptf-previsualisation-et-gabarits.md §2 pour l'arbitrage.
   * Retourne le payload encodé, jamais une URL : construire l'URL (encodage des paramètres GET)
   * reste la responsabilité de l'appelant, qui connaît le contexte (nouvel onglet ou non).
   */
  @AuraEnabled
  public static String buildPreviewData(String inputJson) {
    if (String.isBlank(inputJson)) {
      throw newAuraException(
        Label.AR_Msg_PTF_EmptyPreviewPayload
      );
    }
    try {
      AR_PTFDataService.GenerationInput input = (AR_PTFDataService.GenerationInput) JSON.deserialize(
        inputJson,
        AR_PTFDataService.GenerationInput.class
      );
      Integer peekedVersion = nextVersionNumber(input.matrixId);
      AR_PTFData data = AR_PTFDataService.collect(input.matrixId, input, peekedVersion);
      data.isPreview = true;
      return EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(data)));
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_PreviewDataAction);
    }
  }

  private class StoredFile {
    Id contentDocumentId;
    String warning;
  }

  private static StoredFile storeAsFile(
    Id matrixId,
    Id positionId,
    AR_PTFData data,
    Blob pdfBlob
  ) {
    String fileName = normalizedFileName(data);
    ContentVersion cv = new ContentVersion(
      Title = fileName,
      PathOnClient = fileName + '.pdf',
      VersionData = pdfBlob,
      // Crée automatiquement le premier ContentDocumentLink, vers la matrice.
      FirstPublishLocationId = matrixId
    );
    insert cv;

    Id contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ]
    .ContentDocumentId;

    StoredFile stored = new StoredFile();
    stored.contentDocumentId = contentDocumentId;

    // Second lien : le besoin Connexys (spec §4 « Stocker » — lié à la matrice ET au besoin).
    // Session 180d : un valideur qui génère l'avenant à sa décision ne voit pas forcément le besoin du
    // BM — Salesforce refuse alors le lien (INVALID_CROSS_REFERENCE_KEY) et, avant, le rendu entier
    // tombait en « Échec » alors que le PDF était produit. Le fichier reste rattaché à la matrice (le
    // BM le retrouve dans le panneau PTF) ; le défaut de lien est AFFICHÉ (result.warning) et
    // journalisé, jamais avalé en silence (doctrine de la session 34).
    if (positionId != null) {
      Database.SaveResult linked = Database.insert(
        new ContentDocumentLink(
          LinkedEntityId = positionId,
          ContentDocumentId = contentDocumentId,
          ShareType = 'V',
          Visibility = 'AllUsers'
        ),
        false
      );
      if (!linked.isSuccess()) {
        String reason = linked.getErrors().isEmpty() ? Label.AR_Msg_UnknownReason : linked.getErrors()[0].getMessage();
        System.debug(LoggingLevel.ERROR, 'Fichier non rattaché au besoin ' + positionId + ' : ' + reason);
        stored.warning =
          AR_I18n.format(Label.AR_Msg_PTF_FileNotLinkedToNeed, new List<Object>{ reason });
      }
    }
    return stored;
  }

  /**
   * Nom de fichier envoyé au client — nomenclature CLIENT_TRIGRAMME_DATE évoquée par Matthieu en
   * réunion (session 37, question 5 de docs/34-plan-avant-prochaine-reunion.md). S'applique
   * au NOM DE FICHIER du ContentVersion. Session 184d : la même fonction calcule aussi la référence
   * affichée (AR_Reference__c, page de garde et pied de page) via AR_PTFDataService, pour que les
   * trois ne puissent plus diverger. La version reste dans sa propre case « Version n° ».
   */
  private static String normalizedFileName(AR_PTFData data) {
    String nomenclature = buildNomenclatureFileName(data);
    if (String.isNotBlank(nomenclature)) {
      return nomenclature;
    }
    // Repli (sessions 20/26) : ne devrait plus se produire pour une PTF issue d'une matrice validée
    // (le client est toujours renseigné), conservé pour ne perdre aucun cas limite déjà couvert.
    String clientPart = sanitizeForFileName(data.client);
    String datePart = Datetime.now().format('yyyyMMdd');
    return sanitizeForFileName(data.reference) +
      (String.isNotBlank(clientPart) ? '_' + clientPart : '') +
      '_' +
      datePart;
  }

  /**
   * Session 177 : PTF_ABYLSEN_<TRI_MANAGER>_<CLIENT>_<TRI_CONSULTANT>_<AAAAMMJJ-AAAAMMJJ>
   * - PTF_ABYLSEN : préfixe littéral avec l'entité (PTF_ENTITY_CODE)
   * - TRI_MANAGER : trigramme du business manager (propriétaire de la matrice)
   * - CLIENT : nom du compte client (obligatoire pour construire ce nom — sans lui, repli sur
   *   l'ancien schéma dans normalizedFileName ci-dessus)
   * - TRI_CONSULTANT : trois lettres dérivées du nom du consultant positionné. Absent tant qu'aucun
   *   consultant n'est positionné sur le besoin (segment omis, jamais "XXX")
   * - DATE : période de couverture de la mission (dates de début/fin), au format AAAAMMJJ[-AAAAMMJJ]
   */
  public static String buildNomenclatureFileName(AR_PTFData data) {
    String clientPart = sanitizeForFileName(data.client);
    if (String.isBlank(clientPart)) {
      return null;
    }

    List<String> segments = new List<String>{ 'PTF', PTF_ENTITY_CODE };

    String managerTrigramme = userTrigramme(data.managerName);
    if (String.isNotBlank(managerTrigramme)) {
      segments.add(managerTrigramme);
    }

    segments.add(clientPart);

    String consultantTrigramme = userTrigramme(data.consultantNom);
    if (String.isNotBlank(consultantTrigramme)) {
      segments.add(consultantTrigramme);
    }

    String coverage = coveragePeriod(data.dateDebut, data.dateFin);
    if (String.isNotBlank(coverage)) {
      segments.add(coverage);
    }

    // Session 180d (Q6 A) : un avenant porte le numéro AV{n} en suffixe, pour ne plus être
    // indiscernable d'une PTF dans une liste de fichiers. Période = celle de la matrice avenant.
    if (data.templateCode == 'AVENANT_AT_V11' && String.isNotBlank(data.version) && data.version.startsWith('AV')) {
      segments.add(sanitizeForFileName(data.version));
    }

    return String.join(segments, '_');
  }

  /**
   * Session 177 : trigramme d'un utilisateur selon la nouvelle convention :
   * 1ère lettre du prénom + 2 premières lettres du nom, majuscules, sans accent.
   * Exemple : Alexis ROQUES → ARO
   *
   * Dérivation pure à partir du nom complet : aucun champ trigramme n'existe en org (vérifié en
   * session 177b sur User, Contact et cxsrec__cxsCandidate__c). Possible si au moins 2 tokens, le
   * dernier ayant au moins 2 lettres ; sinon null. Les accents sont retirés AVANT de filtrer les
   * non-lettres, sinon « Éric » perdrait son É et donnerait « R… ».
   */
  @TestVisible
  private static String userTrigramme(String fullName) {
    if (String.isBlank(fullName)) {
      return null;
    }

    List<String> parts = removeAccents(fullName.trim().toLowerCase()).split('\\s+');
    if (parts.size() < 2) {
      return null;
    }

    String firstName = parts[0].replaceAll('[^a-zA-Z]', '');
    String lastName = parts[parts.size() - 1].replaceAll('[^a-zA-Z]', '');

    if (firstName.length() < 1 || lastName.length() < 2) {
      return null;
    }

    String trigram = firstName.substring(0, 1) + lastName.substring(0, 2);
    return trigram.toUpperCase();
  }

  /**
   * Supprime les accents d'une chaîne : é→e, è→e, ç→c, etc.
   */
  private static String removeAccents(String input) {
    if (String.isBlank(input)) {
      return input;
    }
    String normalized = input.replaceAll('[éèêë]', 'e')
      .replaceAll('[ÉÈÊË]', 'E')
      .replaceAll('[àâäá]', 'a')
      .replaceAll('[ÀÂÄÁ]', 'A')
      .replaceAll('[ùûüú]', 'u')
      .replaceAll('[ÙÛÜÚ]', 'U')
      .replaceAll('[ôöó]', 'o')
      .replaceAll('[ÔÖÓ]', 'O')
      .replaceAll('[îïí]', 'i')
      .replaceAll('[ÎÏÍ]', 'I')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C')
      .replaceAll('ñ', 'n')
      .replaceAll('Ñ', 'N')
      .replaceAll('ÿ', 'y')
      .replaceAll('Ÿ', 'Y')
      .replaceAll('œ', 'oe')
      .replaceAll('Œ', 'OE')
      .replaceAll('æ', 'ae')
      .replaceAll('Æ', 'AE')
      .replaceAll('ß', 'ss');
    return normalized;
  }

  private static String coveragePeriod(Date startDate, Date endDate) {
    if (startDate == null) {
      return null;
    }
    String startLabel = isoCompactDate(startDate);
    return endDate == null ? startLabel : startLabel + '-' + isoCompactDate(endDate);
  }

  private static String isoCompactDate(Date d) {
    String month = d.month() < 10 ? '0' + d.month() : String.valueOf(d.month());
    String day = d.day() < 10 ? '0' + d.day() : String.valueOf(d.day());
    return String.valueOf(d.year()) + month + day;
  }

  @TestVisible
  private static String sanitizeForFileName(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    return removeAccents(value).replaceAll('[^a-zA-Z0-9\\-]+', '_');
  }

  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}