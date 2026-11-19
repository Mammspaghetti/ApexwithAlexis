public without sharing class AR_PTFHistoryService {
  private static AuraHandledException auraError(String msg) {
    AuraHandledException e = new AuraHandledException(msg);
    e.setMessage(msg);
    return e;
  }

  private static List<AR_PTF_Document__c> getEligibleDocuments(
    Id matrixId,
    String templateCode
  ) {
    AR_Price_Matrix__c matrix = [
      SELECT AR_Position__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
    ];

    Boolean useBesoinScope =
      AR_PTFDataService.TEMPLATES_USING_BESOIN_HISTORY_SCOPE.contains(templateCode) &&
      matrix.AR_Position__c != null;

    return useBesoinScope
      ? [
          SELECT Id, AR_Reference__c, AR_Generated_At__c, AR_Modification_Type__c, AR_Modification_Detail__c, CreatedBy.Name
          FROM AR_PTF_Document__c
          WHERE
            AR_Position__c = :matrix.AR_Position__c
            AND AR_Document_Type__c != 'Avenant'
            AND AR_Include_In_History__c = true
            AND (AR_Generation_Status__c = null OR AR_Generation_Status__c NOT IN ('Échec', 'En cours'))
          ORDER BY AR_Generated_At__c ASC, Id ASC
        ]
      : [
          SELECT Id, AR_Reference__c, AR_Generated_At__c, AR_Modification_Type__c, AR_Modification_Detail__c, CreatedBy.Name
          FROM AR_PTF_Document__c
          WHERE
            AR_Price_Matrix__c = :matrixId
            AND AR_Document_Type__c != 'Avenant'
            AND AR_Include_In_History__c = true
            AND (AR_Generation_Status__c = null OR AR_Generation_Status__c NOT IN ('Échec', 'En cours'))
          ORDER BY AR_Generated_At__c ASC, Id ASC
        ];
  }

  /**
   * Documents éligibles à l'historique (cochés, hors avenants, hors Échec/En cours), dans l'ordre des
   * rangs. Source unique pour le rang d'affichage ET pour les lignes figées dans le snapshot PTF
   * (session 138) : AR_PTFDataService ne refait aucune requête de son côté.
   */
  public static List<AR_PTF_Document__c> listEligibleDocuments(Id matrixId, String templateCode) {
    return getEligibleDocuments(matrixId, templateCode);
  }

  private static Boolean isValidModificationType(String type) {
    for (Schema.PicklistEntry entry : AR_PTF_Document__c.AR_Modification_Type__c.getDescribe().getPicklistValues()) {
      if (entry.getValue() == type) {
        return true;
      }
    }
    return false;
  }

  /**
   * Règle de saisie à la génération (session 138) : à partir du rang 2, un type de modification est
   * obligatoire (et un détail si « Autre ») ; au rang 1, ce qui est fourni est ignoré. Lève une
   * erreur lisible AVANT toute insertion — c'est l'appelant qui décide de n'insérer qu'après.
   */
  public static void requireModification(Integer rank, String type, String detail) {
    if (rank == null || rank < 2) {
      return;
    }
    if (String.isBlank(type)) {
      throw auraError(Label.AR_Msg_HIS_TypeRequired);
    }
    if (!isValidModificationType(type)) {
      throw auraError(AR_I18n.format(Label.AR_Msg_HIS_InvalidType, new List<Object>{ type }));
    }
    if (type == 'Autre' && String.isBlank(detail?.trim())) {
      throw auraError(Label.AR_Msg_HIS_DetailRequiredOther);
    }
  }

  public static Map<Id, Integer> computeRanks(Id matrixId, String templateCode) {
    List<AR_PTF_Document__c> rankedDocs = getEligibleDocuments(matrixId, templateCode);

    Map<Id, Integer> ranks = new Map<Id, Integer>();
    Integer rank = 1;
    for (AR_PTF_Document__c doc : rankedDocs) {
      ranks.put(doc.Id, rank++);
    }
    return ranks;
  }

  public static Integer nextDisplayRank(Id matrixId, String templateCode) {
    List<AR_PTF_Document__c> rankedDocs = getEligibleDocuments(matrixId, templateCode);
    return rankedDocs.size() + 1;
  }

  /**
   * Rang que prendra la PROCHAINE PTF générée (session 139) : l'interface décide avec lui d'ouvrir ou
   * non la fenêtre « quelle modification ? ». Lecture seule, même source que la génération
   * (getEligibleDocuments) — aucune règle de rang dupliquée côté LWC. Non cacheable : appelée en
   * impératif, juste avant la génération. Le serveur revérifie de toute façon (requireModification).
   */
  @AuraEnabled
  public static Integer getNextDisplayRank(Id matrixId, String templateCode) {
    try {
      return nextDisplayRank(matrixId, templateCode);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_HIS_NextRankAction);
    }
  }

  public static String getModificationLabel(
    AR_PTF_Document__c doc,
    Integer rank
  ) {
    if (rank == 1) {
      return '';
    }
    if (doc.AR_Modification_Type__c == 'Autre') {
      return doc.AR_Modification_Detail__c ?? '';
    }
    if (String.isNotBlank(doc.AR_Modification_Type__c)) {
      return doc.AR_Modification_Type__c;
    }
    return '';
  }

  @AuraEnabled
  public static List<PTFDocumentRow> setIncludedInHistory(Id ptfDocumentId, Boolean included) {
    AR_PTF_Document__c doc;
    try {
      List<AR_PTF_Document__c> docs = [SELECT Id, AR_Price_Matrix__c, AR_Template_Code__c, AR_Include_In_History__c FROM AR_PTF_Document__c WHERE Id = :ptfDocumentId];
      if (docs.isEmpty()) {
        throw auraError(Label.AR_Msg_HIS_NoEditRights);
      }
      doc = docs[0];
    } catch (QueryException e) {
      throw auraError(Label.AR_Msg_HIS_NoEditRights);
    }
    try {
      update new AR_PTF_Document__c(Id = doc.Id, AR_Include_In_History__c = included);
    } catch (DmlException e) {
      throw auraError(Label.AR_Msg_HIS_NoEditRights);
    }

    return buildDocumentRows(doc.AR_Price_Matrix__c, doc.AR_Template_Code__c);
  }

  @AuraEnabled
  public static List<PTFDocumentRow> setModification(
    Id ptfDocumentId,
    String type,
    String detail
  ) {
    AR_PTF_Document__c doc;
    try {
      List<AR_PTF_Document__c> docs = [
        SELECT Id, AR_Price_Matrix__c, AR_Template_Code__c, AR_Document_Type__c, AR_Modification_Type__c, AR_Modification_Detail__c
        FROM AR_PTF_Document__c
        WHERE Id = :ptfDocumentId
      ];
      if (docs.isEmpty()) {
        throw auraError(Label.AR_Msg_HIS_NoEditRights);
      }
      doc = docs[0];
    } catch (QueryException e) {
      throw auraError(Label.AR_Msg_HIS_NoEditRights);
    }

    if (doc.AR_Document_Type__c == 'Avenant') {
      throw auraError(Label.AR_Msg_HIS_NotOnAvenant);
    }

    String newType = null;
    String newDetail = null;
    if (type == 'Autre') {
      if (String.isBlank(detail?.trim())) {
        throw auraError(Label.AR_Msg_HIS_DetailRequiredOther);
      }
      newType = type;
      newDetail = detail.trim();
    } else if (String.isNotBlank(type)) {
      if (!isValidModificationType(type)) {
        throw auraError(AR_I18n.format(Label.AR_Msg_HIS_InvalidType, new List<Object>{ type }));
      }
      newType = type;
    }

    try {
      update new AR_PTF_Document__c(
        Id = doc.Id,
        AR_Modification_Type__c = newType,
        AR_Modification_Detail__c = newDetail
      );
    } catch (DmlException e) {
      throw auraError(Label.AR_Msg_HIS_NoEditRights);
    }

    return buildDocumentRows(doc.AR_Price_Matrix__c, doc.AR_Template_Code__c);
  }

  public static List<PTFDocumentRow> buildDocumentRows(Id matrixId, String templateCode) {
    Map<Id, Integer> ranks = computeRanks(matrixId, templateCode);

    // Session 180d : les avenants pilotés par une matrice avenant sont rattachés à CETTE matrice ;
    // la matrice d'origine les liste aussi (via la PTF qu'ils amendent), avec un renvoi « → V3 ».
    List<PTFDocumentRow> rows = new List<PTFDocumentRow>();
    for (AR_PTF_Document__c doc : [
      SELECT
        Id,
        AR_Reference__c,
        AR_Version_Number__c,
        AR_Generated_At__c,
        AR_Content_Document_Id__c,
        AR_Generation_Status__c,
        AR_Generation_Error__c,
        AR_Document_Type__c,
        AR_Avenant_Number__c,
        AR_Include_In_History__c,
        AR_Modification_Type__c,
        AR_Modification_Detail__c,
        AR_Price_Matrix__c,
        AR_Price_Matrix__r.Name,
        AR_Price_Matrix__r.AR_Negotiation_Version__c,
        AR_Snapshot__c
      FROM AR_PTF_Document__c
      WHERE AR_Price_Matrix__c = :matrixId OR AR_Parent_PTF__r.AR_Price_Matrix__c = :matrixId
      ORDER BY AR_Generated_At__c DESC
    ]) {
      PTFDocumentRow row = new PTFDocumentRow();
      row.ptfDocumentId = doc.Id;
      row.reference = doc.AR_Reference__c;
      row.versionNumber = Integer.valueOf(doc.AR_Version_Number__c);
      row.generatedAt = doc.AR_Generated_At__c;
      row.contentDocumentId = String.isNotBlank(doc.AR_Content_Document_Id__c)
        ? Id.valueOf(doc.AR_Content_Document_Id__c)
        : null;
      row.status = doc.AR_Generation_Status__c;
      row.errorMessage = doc.AR_Generation_Error__c;
      row.documentType = String.isNotBlank(doc.AR_Document_Type__c) ? doc.AR_Document_Type__c : 'PTF';
      row.avenantNumber = doc.AR_Avenant_Number__c != null ? Integer.valueOf(doc.AR_Avenant_Number__c) : null;
      row.includedInHistory = doc.AR_Include_In_History__c;
      row.modificationType = doc.AR_Modification_Type__c;
      row.modificationDetail = doc.AR_Modification_Detail__c;
      row.clientAddressModified = isClientAddressModified(doc.AR_Snapshot__c);
      if (doc.AR_Price_Matrix__c != matrixId) {
        row.avenantMatrixId = doc.AR_Price_Matrix__c;
        row.avenantMatrixName = doc.AR_Price_Matrix__r.Name;
        row.avenantMatrixLabel = doc.AR_Price_Matrix__r.AR_Negotiation_Version__c != null
          ? 'V' + Integer.valueOf(doc.AR_Price_Matrix__r.AR_Negotiation_Version__c)
          : doc.AR_Price_Matrix__r.Name;
      }
      row.displayRank = ranks.get(doc.Id);
      row.modificationLabel = getModificationLabel(doc, row.displayRank != null ? row.displayRank : 0);
      rows.add(row);
    }
    return rows;
  }

  public class PTFDocumentRow {
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
    @AuraEnabled
    public String documentType;
    @AuraEnabled
    public Integer avenantNumber;
    @AuraEnabled
    public Boolean includedInHistory;
    @AuraEnabled
    public String modificationType;
    @AuraEnabled
    public String modificationDetail;
    @AuraEnabled
    public Integer displayRank;
    @AuraEnabled
    public String modificationLabel;
    // Session 180d : renseignés seulement pour un avenant rattaché à une AUTRE matrice que celle
    // listée (la matrice avenant), pour afficher « Avenant AV1 → V3 » avec un lien vers elle.
    @AuraEnabled
    public Id avenantMatrixId;
    @AuraEnabled
    public String avenantMatrixName;
    @AuraEnabled
    public String avenantMatrixLabel;
    // Session 279 : document généré avec une adresse client saisie à la main (snapshot).
    @AuraEnabled
    public Boolean clientAddressModified;
  }

  /** Session 279 : lit l'indicateur `adresseClientModifiee` du snapshot (absent → false). */
  public static Boolean isClientAddressModified(String snapshot) {
    return String.isNotBlank(snapshot) && snapshot.contains('"adresseClientModifiee":true');
  }
}