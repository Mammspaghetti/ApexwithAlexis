/**
 * Helper partagé pour la remontée de hiérarchie de compte — utilisé par les corridors et la RFA.
 * Session 146b : extraction du code privé AR_PricingMatrixService.loadCorridorPercents.
 */
public with sharing class AR_AccountHierarchy {

  private static final Integer MAX_ACCOUNT_HIERARCHY_DEPTH = 20;

  // Lectures mémorisées pour la transaction, par utilisateur (partage `with sharing`) : un chemin qui recalcule
  // plusieurs fois la même matrice relit sinon les mêmes comptes et besoins (session 291c, limite SOQL).
  // Seuls les besoins trouvés et les parents lus sont mémorisés.
  private static Map<String, Id> parentCache = new Map<String, Id>();
  private static Map<String, Id> accountByPositionCache = new Map<String, Id>();

  /** Remonte la hiérarchie de compte en suivant ParentId, jusqu'à 20 niveaux.
   * Retourne la chaîne [compte, parent, grand-parent, ...] ou null si le compte est nul.
   * Lève une AuraHandledException si la hiérarchie dépasse 20 niveaux. */
  public static List<Id> chainFrom(Id accountId) {
    if (accountId == null) {
      return null;
    }

    List<Id> chain = new List<Id>();
    Id currentId = accountId;
    Integer depth = 0;

    while (currentId != null) {
      if (depth >= MAX_ACCOUNT_HIERARCHY_DEPTH) {
        // setMessage obligatoire : sans lui getMessage() renvoie « Script-thrown exception », que
        // AR_AuraErrors.wrap relaierait tel quel à l'utilisateur (cf. AR_AuraErrors.wrap).
        String message =
          AR_I18n.format(Label.AR_Msg_ACC_HierarchyTooDeep, new List<Object>{ MAX_ACCOUNT_HIERARCHY_DEPTH });
        AuraHandledException tooDeep = new AuraHandledException(message);
        tooDeep.setMessage(message);
        throw tooDeep;
      }
      chain.add(currentId);
      depth++;
      String key = UserInfo.getUserId() + '|' + currentId;
      if (parentCache.containsKey(key)) {
        currentId = parentCache.get(key);
        continue;
      }
      List<Account> rows = [SELECT ParentId FROM Account WHERE Id = :currentId LIMIT 1];
      Id parentId = rows.isEmpty() ? null : rows[0].ParentId;
      if (!rows.isEmpty()) {
        parentCache.put(key, parentId);
      }
      currentId = parentId;
    }

    return chain;
  }

  /** Compte d'un besoin : chaîne AB_Need_details__c → AB_Account__c d'abord (source de la matrice à l'écran,
   * décision du 25/09/2026), repli sur cxsrec__Account__c. Source unique pour toute lecture serveur du
   * paramétrage de compte (corridor, RFA, gabarit PTF) : session 184f — le serveur ne lisait que le
   * champ historique, vide sur les besoins rattachés par la jonction, et retombait sur le corridor par défaut. */
  public static Id accountOfPosition(Id positionId) {
    if (positionId == null) {
      return null;
    }
    return accountsOfPositions(new Set<Id>{ positionId }).get(positionId);
  }

  /** Même règle que accountOfPosition, pour un lot de besoins en une seule requête (file d'approbation).
   * Un besoin absent de la requête n'a pas d'entrée dans la map. */
  public static Map<Id, Id> accountsOfPositions(Set<Id> positionIds) {
    Map<Id, Id> accountByPosition = new Map<Id, Id>();
    Set<Id> ids = new Set<Id>();
    for (Id positionId : positionIds) {
      if (positionId != null) {
        String key = UserInfo.getUserId() + '|' + positionId;
        if (accountByPositionCache.containsKey(key)) {
          accountByPosition.put(positionId, accountByPositionCache.get(key));
        } else {
          ids.add(positionId);
        }
      }
    }
    if (ids.isEmpty()) {
      return accountByPosition;
    }
    for (cxsrec__cxsPosition__c position : [
      SELECT cxsrec__Account__c, AB_Need_details__r.AB_Account__c
      FROM cxsrec__cxsPosition__c
      WHERE Id IN :ids
    ]) {
      Id fromJunction = position.AB_Need_details__r?.AB_Account__c;
      Id accountId = fromJunction != null ? fromJunction : position.cxsrec__Account__c;
      accountByPosition.put(position.Id, accountId);
      accountByPositionCache.put(UserInfo.getUserId() + '|' + position.Id, accountId);
    }
    return accountByPosition;
  }
}