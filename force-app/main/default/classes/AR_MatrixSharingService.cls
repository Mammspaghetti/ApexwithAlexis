/**
 * Visibilité stricte des matrices. Une matrice n'est visible que par son créateur, son
 * propriétaire, les personnes désignées sur la fiche du propriétaire (RA, DA, DD, Directeur, Directeur
 * commercial, Directeur commercial groupe), les valideurs actifs de l'entité PTF de la matrice
 * (`AR_PTF_Entity_Validator__c`) et les valideurs de test. Les porteurs d'AR Pricing Manager
 * la voient par leur permission (viewAllRecords), jamais par ce partage.
 *
 * Mécanique : partage Apex sur AR_Price_Matrix__c et AR_Reason_Selection__c (lookup en cascade, donc sans
 * héritage du partage de la matrice), raison `AR_Chaine_Matrice__c`, accès Modification. Les lignes sont
 * recalculées à la création, au changement de propriétaire ou d'entité, quand un des six champs de la fiche
 * du propriétaire change, quand un valideur d'entité est ajouté, retiré, désactivé ou réactivé (file
 * asynchrone `AR_MatrixSharingQueueable`, par lots, déclenchée par `AR_UserTrigger` et
 * `AR_PTFEntityValidatorTrigger`).
 *
 * Idempotent : les lignes dues restent, les autres sont supprimées, les manquantes sont créées. Les scripts de
 * rattrapage `scripts/apex/199-recalcul-partage-matrices.apex` et `291-recalcul-partage-entites.apex` peuvent donc être relancé sans effet de bord.
 *
 * `without sharing` : la chaîne doit pouvoir créer des lignes de partage au nom de personnes qui n'ont pas
 * encore accès à la matrice. Le service ne remonte aucune donnée à l'écran.
 */
public without sharing class AR_MatrixSharingService {

    /** Raison de partage portée par les lignes posées par ce service (API name de la raison, cf. objets). */
    public static final String ROW_CAUSE = 'AR_Chaine_Matrice__c';

    /** Champs de la fiche du propriétaire qui désignent la chaîne. */
    private static final Set<String> CHAIN_FIELDS = new Set<String>{
        'TP_DA__c', 'TP_DD__c', 'TP_Directeur__c', 'TP_RA__c', 'TP_Directeur_commercial__c', 'TP_Directeur_commercial_groupe__c'
    };

    /** Liste des valideurs de test, lue une fois par transaction (un recalcul par ligne ne doit pas relire le réglage). */
    private static Set<Id> testIdsCache;

    /** Fiches des propriétaires déjà lues dans cette transaction : une insertion par propriétaire, pas une par matrice. */
    private static Map<Id, User> chainOwnerCache = new Map<Id, User>();

    /**
     * Appelé par `AR_PriceMatrixTrigger` (after insert/update) : recalcule à la création (sans les motifs, qui
     * n'existent pas encore) et au changement de propriétaire (avec les motifs).
     */
    public static void handleMatrixSaved(List<AR_Price_Matrix__c> matrices, Map<Id, AR_Price_Matrix__c> oldMap) {
        List<AR_Price_Matrix__c> created = new List<AR_Price_Matrix__c>();
        Set<Id> reassigned = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            if (oldMap == null) {
                created.add(m);
            } else if (m.OwnerId != oldMap.get(m.Id).OwnerId || m.AR_Entity_Ref__c != oldMap.get(m.Id).AR_Entity_Ref__c) {
                reassigned.add(m.Id);
            }
        }
        insertDueShares(created);
        recalculateMatrices(reassigned, true);
        // Session 282 : partage en lecture avec l'agence du propriétaire (raison distincte, jamais mêlée à la chaîne).
        AR_AgencySharingService.insertAgencyShares(created, chainOwnerCache);
        AR_AgencySharingService.recalculateMatrices(reassigned, true);
    }

    /**
     * Partage d'une matrice qui vient d'être créée : elle n'a encore aucune ligne, donc on insère les lignes dues
     * sans relire les partages existants ni la matrice (le trigger la fournit). Une seule requête, sur les
     * propriétaires — le coût SOQL d'une création reste borné (le contrôle de la création d'avenant est à 80).
     */
    private static void insertDueShares(List<AR_Price_Matrix__c> created) {
        if (created.isEmpty()) {
            return;
        }
        loadOwners(created);
        if (testIdsCache == null) {
            testIdsCache = activeTestValidatorIds();
        }
        Map<Id, Set<Id>> entityValidators = entityValidatorIds(created);
        List<AR_Price_Matrix__Share> rows = new List<AR_Price_Matrix__Share>();
        for (AR_Price_Matrix__c m : created) {
            for (Id userId : dueUsers(m, chainOwnerCache.get(m.OwnerId), testIdsCache, entityValidators)) {
                rows.add(new AR_Price_Matrix__Share(ParentId = m.Id, UserOrGroupId = userId, AccessLevel = 'Edit', RowCause = ROW_CAUSE));
            }
        }
        if (rows.isEmpty()) {
            return;
        }
        // allOrNone = false : une ligne refusée (par exemple un compte système « Automated Process » désigné comme créateur)
        // ne doit pas faire échouer la création de la matrice. Elle est journalisée, jamais avalée sans trace.
        Integer refused = 0;
        for (Database.SaveResult r : Database.insert(rows, false, AccessLevel.SYSTEM_MODE)) {
            if (!r.isSuccess()) {
                refused++;
                System.debug(LoggingLevel.ERROR, 'Partage de la chaîne refusé : ' + r.getErrors()[0].getMessage());
            }
        }
        if (refused > 0) {
            System.debug(LoggingLevel.WARN, refused + ' ligne(s) de partage non créée(s) sur une création de matrice.');
        }
    }

    /** Fiches des propriétaires (chaîne + agence), une requête par transaction pour les propriétaires pas encore lus. */
    private static void loadOwners(List<AR_Price_Matrix__c> created) {
        Set<Id> missing = new Set<Id>();
        for (AR_Price_Matrix__c m : created) {
            if (!chainOwnerCache.containsKey(m.OwnerId)) {
                missing.add(m.OwnerId);
            }
        }
        if (!missing.isEmpty()) {
            chainOwnerCache.putAll(new Map<Id, User>(
                [
                    SELECT Id, TP_Agence__c,
                           TP_DA__r.IsActive, TP_DD__r.IsActive, TP_Directeur__r.IsActive,
                           TP_RA__r.IsActive, TP_Directeur_commercial__r.IsActive, TP_Directeur_commercial_groupe__r.IsActive
                    FROM User
                    WHERE Id IN :missing
                ]
            ));
        }
    }

    /** Appelé par `AR_Reason_SelectionTrigger` (after insert) : un motif ajouté suit le partage de sa matrice. */
    public static void handleReasonsInserted(List<AR_Reason_Selection__c> selections) {
        Set<Id> matrixIds = new Set<Id>();
        for (AR_Reason_Selection__c s : selections) {
            if (s.AR_Price_Matrix__c != null) {
                matrixIds.add(s.AR_Price_Matrix__c);
            }
        }
        recalculateMatrices(matrixIds, true);
        AR_AgencySharingService.shareInsertedReasons(selections);
    }

    /**
     * Appelé par `AR_UserTrigger` (after update) : seul un changement d'un des six champs de la chaîne
     * déclenche un recalcul, en asynchrone (DML sur User puis partage dans la même transaction = erreur
     * MIXED_DML_OPERATION).
     */
    public static void onUsersUpdated(List<User> users, Map<Id, User> oldMap) {
        entityValidatorCache = new Map<Id, Set<Id>>();
        Set<Id> changed = new Set<Id>();
        Set<Id> toggled = new Set<Id>();
        for (User u : users) {
            User previous = oldMap.get(u.Id);
            if (u.IsActive != previous.IsActive) {
                toggled.add(u.Id);
            }
            for (String field : CHAIN_FIELDS) {
                if (u.get(field) != previous.get(field)) {
                    changed.add(u.Id);
                    break;
                }
            }
        }
        // Un valideur d'entité désactivé ou réactivé : recalcul des matrices de ses entités.
        Set<Id> entityIds = new Set<Id>();
        if (!toggled.isEmpty()) {
            for (AR_PTF_Entity_Validator__c row : [
                SELECT AR_Entity_Ref__c FROM AR_PTF_Entity_Validator__c WHERE AR_User__c IN :toggled
            ]) {
                entityIds.add(row.AR_Entity_Ref__c);
            }
        }
        if (changed.isEmpty() && entityIds.isEmpty()) {
            return;
        }
        // Une mise à jour d'utilisateur ne doit jamais échouer à cause du partage : si la file est pleine, on ne lance
        // rien et on journalise. Le rattrapage (scripts/apex/199-recalcul-partage-matrices.apex) reprend ces matrices.
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new AR_MatrixSharingQueueable(changed, entityIds, null));
        } else {
            System.debug(LoggingLevel.WARN, 'File pleine : recalcul du partage non lancé pour ' + changed.size() +
                ' utilisateur(s). Rattrapage : scripts/apex/199-recalcul-partage-matrices.apex.');
        }
    }

    /** Taille d'un lot de recalcul par entité (une transaction de file) ; le reste est repris par la file suivante. */
    public static final Integer ENTITY_BATCH_SIZE = 200;

    /** Appelé par `AR_PTFEntityValidatorTrigger` (after insert/delete) : recalcul asynchrone des matrices de l'entité. */
    public static void onEntityValidatorsChanged(List<AR_PTF_Entity_Validator__c> rows) {
        entityValidatorCache = new Map<Id, Set<Id>>();
        Set<Id> entityIds = new Set<Id>();
        for (AR_PTF_Entity_Validator__c r : rows) {
            if (r.AR_Entity_Ref__c != null) {
                entityIds.add(r.AR_Entity_Ref__c);
            }
        }
        if (entityIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new AR_MatrixSharingQueueable(new Set<Id>(), entityIds, null));
        } else {
            System.debug(LoggingLevel.WARN, 'File pleine : recalcul du partage non lancé pour ' + entityIds.size() +
                ' entité(s). Rattrapage : scripts/apex/291-recalcul-partage-entites.apex.');
        }
    }

    /**
     * Recalcule un lot de matrices des entités données (`pending` = matrices restantes d'un lot précédent, sinon
     * lues sur les entités). Renvoie les matrices restantes, à reprendre par un nouveau travail de file.
     */
    public static List<Id> recalculateEntityBatch(Set<Id> entityIds, List<Id> pending) {
        List<Id> all = pending;
        if (all == null) {
            all = new List<Id>(new Map<Id, AR_Price_Matrix__c>(
                [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Entity_Ref__c IN :entityIds WITH SYSTEM_MODE ORDER BY Id]
            ).keySet());
        }
        Set<Id> batch = new Set<Id>();
        List<Id> rest = new List<Id>();
        for (Id id : all) {
            if (batch.size() < ENTITY_BATCH_SIZE) {
                batch.add(id);
            } else {
                rest.add(id);
            }
        }
        recalculateMatrices(batch, true);
        return rest;
    }

    /** Matrices dont le propriétaire figure dans `ownerIds` (file asynchrone). */
    public static void recalculateForOwners(Set<Id> ownerIds) {
        Set<Id> matrixIds = new Map<Id, AR_Price_Matrix__c>(
            [SELECT Id FROM AR_Price_Matrix__c WHERE OwnerId IN :ownerIds]
        ).keySet();
        recalculateMatrices(matrixIds, true);
    }

    /**
     * Aligne le partage de la chaîne sur les matrices données ; avec `withReasons`, aussi sur leurs motifs.
     * Une matrice qui vient d'être insérée n'a pas encore de motif : `withReasons = false` lui épargne une requête.
     */
    public static void recalculateMatrices(Set<Id> matrixIds, Boolean withReasons) {
        if (matrixIds == null || matrixIds.isEmpty()) {
            return;
        }
        List<AR_Price_Matrix__c> matrices = [
            SELECT Id, OwnerId, CreatedById, AR_Entity_Ref__c
            FROM AR_Price_Matrix__c
            WHERE Id IN :matrixIds
            WITH SYSTEM_MODE
        ];
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            ownerIds.add(m.OwnerId);
        }
        Map<Id, User> ownerById = new Map<Id, User>(
            [
                SELECT Id,
                       TP_DA__r.IsActive, TP_DD__r.IsActive, TP_Directeur__r.IsActive,
                       TP_RA__r.IsActive, TP_Directeur_commercial__r.IsActive, TP_Directeur_commercial_groupe__r.IsActive
                FROM User
                WHERE Id IN :ownerIds
                WITH SYSTEM_MODE
            ]
        );
        if (testIdsCache == null) {
            testIdsCache = activeTestValidatorIds();
        }
        Set<Id> testIds = testIdsCache;

        Map<Id, Set<Id>> entityValidators = entityValidatorIds(matrices);
        Map<Id, Set<Id>> dueByMatrix = new Map<Id, Set<Id>>();
        for (AR_Price_Matrix__c m : matrices) {
            dueByMatrix.put(m.Id, dueUsers(m, ownerById.get(m.OwnerId), testIds, entityValidators));
        }
        syncShares('AR_Price_Matrix__Share', dueByMatrix);
        if (!withReasons) {
            return;
        }

        Map<Id, Set<Id>> dueBySelection = new Map<Id, Set<Id>>();
        for (AR_Reason_Selection__c s : [
            SELECT Id, AR_Price_Matrix__c
            FROM AR_Reason_Selection__c
            WHERE AR_Price_Matrix__c IN :dueByMatrix.keySet()
            WITH SYSTEM_MODE
        ]) {
            dueBySelection.put(s.Id, dueByMatrix.get(s.AR_Price_Matrix__c));
        }
        syncShares('AR_Reason_Selection__Share', dueBySelection);
    }

    /** Valideurs de test actifs (réglage de phase de test ; une seule requête, et seulement s'il est renseigné). */
    private static Set<Id> activeTestValidatorIds() {
        Set<Id> configured = AR_ValidatorChain.testValidatorIds();
        if (configured.isEmpty()) {
            return configured;
        }
        return new Map<Id, User>([SELECT Id FROM User WHERE Id IN :configured AND IsActive = true]).keySet();
    }

    /** Personnes qui doivent voir la matrice par la chaîne : créateur, six champs du propriétaire, valideurs de test. */
    @TestVisible
    private static Set<Id> dueUsers(AR_Price_Matrix__c m, User owner, Set<Id> testIds) {
        return dueUsers(m, owner, testIds, null);
    }

    /** Valideurs actifs par entité, mémorisés pour la transaction (une requête par entité, pas une par insertion de matrice). */
    private static Map<Id, Set<Id>> entityValidatorCache = new Map<Id, Set<Id>>();

    /** Valideurs actifs par entité pour les matrices données (une requête par entité non encore lue, seulement si une entité est renseignée). */
    private static Map<Id, Set<Id>> entityValidatorIds(List<AR_Price_Matrix__c> matrices) {
        Set<Id> missing = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            if (m.AR_Entity_Ref__c != null && !entityValidatorCache.containsKey(m.AR_Entity_Ref__c)) {
                missing.add(m.AR_Entity_Ref__c);
            }
        }
        Map<Id, List<User>> users = AR_ValidatorChain.activeEntityValidators(missing);
        for (Id entityId : missing) {
            Set<Id> ids = new Set<Id>();
            if (users.containsKey(entityId)) {
                for (User u : users.get(entityId)) {
                    ids.add(u.Id);
                }
            }
            entityValidatorCache.put(entityId, ids);
        }
        return entityValidatorCache;
    }

    /** Personnes qui doivent voir la matrice par la chaîne : créateur, six champs, valideurs d'entité, valideurs de test. */
    @TestVisible
    private static Set<Id> dueUsers(AR_Price_Matrix__c m, User owner, Set<Id> testIds, Map<Id, Set<Id>> entityValidators) {
        Set<Id> due = new Set<Id>();
        addIfPresent(due, m.CreatedById);
        if (owner != null) {
            addIfActive(due, owner.TP_DA__r);
            addIfActive(due, owner.TP_DD__r);
            addIfActive(due, owner.TP_Directeur__r);
            addIfActive(due, owner.TP_RA__r);
            addIfActive(due, owner.TP_Directeur_commercial__r);
            addIfActive(due, owner.TP_Directeur_commercial_groupe__r);
        }
        if (entityValidators != null && m.AR_Entity_Ref__c != null && entityValidators.containsKey(m.AR_Entity_Ref__c)) {
            due.addAll(entityValidators.get(m.AR_Entity_Ref__c));
        }
        due.addAll(testIds);
        // Le propriétaire a déjà l'accès : pas de ligne pour lui.
        due.remove(m.OwnerId);
        return due;
    }

    /** Une personne inactive ne reçoit pas de partage (INACTIVE_OWNER_OR_USER) : même règle que AR_ValidatorChain. */
    private static void addIfActive(Set<Id> ids, User person) {
        if (person != null && person.IsActive) {
            ids.add(person.Id);
        }
    }

    private static void addIfPresent(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }

    /**
     * Aligne les lignes de partage de la raison `ROW_CAUSE` sur `dueByParent` (parent → personnes dues).
     * `shareObject` est le nom API de l'objet de partage (`X__Share`).
     */
    @TestVisible
    private static void syncShares(String shareObject, Map<Id, Set<Id>> dueByParent) {
        syncShares(shareObject, dueByParent, ROW_CAUSE, 'Edit');
    }

    /**
     * Même alignement pour une autre raison de partage (session 282 : `AR_Agence_Matrice__c`, Lecture) : seules les
     * lignes de `rowCause` sont lues, supprimées ou créées — jamais celles d'une autre raison.
     */
    public static void syncShares(String shareObject, Map<Id, Set<Id>> dueByParent, String rowCause, String shareAccess) {
        if (dueByParent.isEmpty()) {
            return;
        }
        Set<Id> parentIds = dueByParent.keySet();
        List<SObject> existing = Database.query(
            'SELECT Id, ParentId, UserOrGroupId FROM ' + shareObject +
            ' WHERE ParentId IN :parentIds AND RowCause = :rowCause'
        );

        List<SObject> stale = new List<SObject>();
        Map<Id, Set<Id>> kept = new Map<Id, Set<Id>>();
        for (SObject share : existing) {
            Id parentId = (Id) share.get('ParentId');
            Id userId = (Id) share.get('UserOrGroupId');
            Set<Id> due = dueByParent.get(parentId);
            if (due == null || !due.contains(userId)) {
                stale.add(share);
            } else {
                if (!kept.containsKey(parentId)) {
                    kept.put(parentId, new Set<Id>());
                }
                kept.get(parentId).add(userId);
            }
        }

        Schema.SObjectType shareType = Schema.getGlobalDescribe().get(shareObject);
        List<SObject> toInsert = new List<SObject>();
        for (Id parentId : dueByParent.keySet()) {
            Set<Id> already = kept.containsKey(parentId) ? kept.get(parentId) : new Set<Id>();
            for (Id userId : dueByParent.get(parentId)) {
                if (already.contains(userId)) {
                    continue;
                }
                SObject share = shareType.newSObject();
                share.put('ParentId', parentId);
                share.put('UserOrGroupId', userId);
                share.put('AccessLevel', shareAccess);
                share.put('RowCause', rowCause);
                toInsert.add(share);
            }
        }
        // SYSTEM_MODE : le recalcul s'exécute aussi sous l'identité du créateur ou du propriétaire, qui n'ont pas
        // forcément le droit de poser une ligne de partage (même motif que AR_DerogationService.UnsharedDecisionWriter).
        if (!stale.isEmpty()) {
            List<Database.DeleteResult> deleted = Database.delete(stale, AccessLevel.SYSTEM_MODE);
            for (Database.DeleteResult r : deleted) {
                if (!r.isSuccess()) {
                    throw new DmlException('Partage (' + rowCause + ') : suppression refusée (' + r.getErrors()[0].getMessage() + ')');
                }
            }
        }
        // Même règle que insertDueShares : une ligne refusée (compte non humain) est journalisée, sans faire échouer le recalcul.
        if (!toInsert.isEmpty()) {
            Integer refused = 0;
            for (Database.SaveResult r : Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE)) {
                if (!r.isSuccess()) {
                    refused++;
                    System.debug(LoggingLevel.ERROR, 'Partage (' + rowCause + ') refusé : ' + r.getErrors()[0].getMessage());
                }
            }
            if (refused > 0) {
                System.debug(LoggingLevel.WARN, refused + ' ligne(s) de partage ' + rowCause + ' non créée(s) au recalcul.');
            }
        }
    }
}