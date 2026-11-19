/**
 * Session 282 — matrices (et donc leurs PTF et avenants, maître-détail) visibles en LECTURE par toute l'agence
 * du propriétaire (`User.TP_Agence__c`).
 *
 * Mécanique : un groupe public par agence (`AR_Agence_<valeur normalisée>`), dont les membres sont les
 * utilisateurs actifs de l'agence ; une ligne de partage par matrice (et par motif, `AR_Reason_Selection__c`,
 * lookup sans héritage) vers le groupe de l'agence du propriétaire, raison `AR_Agence_Matrice__c`, accès Lecture.
 * Propriétaire sans agence : aucune ligne. Aucun filtre sur les permission sets : sans accès à l'application, une
 * ligne de partage est sans effet. Un accès plus élevé (chaîne `AR_Chaine_Matrice__c`, Modification) reste
 * prioritaire : Salesforce retient l'accès le plus large, et ce service ne touche jamais aux lignes de la chaîne.
 *
 * Recalcul : à la création et au changement de propriétaire (synchrone, `AR_PriceMatrixTrigger` via
 * `AR_MatrixSharingService`), à l'ajout d'un motif, au changement d'agence ou d'activation d'un utilisateur
 * (`AR_UserTrigger`, asynchrone : groupes et membres sont des objets de configuration, DML mixte interdit avec
 * les lignes de partage). Idempotent, comme le partage de la chaîne : rattrapage
 * `scripts/apex/282-partage-agence.apex`, relançable sans effet de bord.
 *
 * Un échec de recalcul asynchrone n'affiche rien : il est journalisé (règle du 27/10).
 */
public without sharing class AR_AgencySharingService {

    public static final String ROW_CAUSE = 'AR_Agence_Matrice__c';
    public static final String ACCESS_LEVEL = 'Read';
    public static final String GROUP_PREFIX = 'AR_Agence_';

    /** Compteurs de la transaction, lus par le script de rattrapage (compte rendu du nombre d'objets créés). */
    public static Integer groupsCreated = 0;
    public static Integer membersAdded = 0;
    public static Integer membersRemoved = 0;

    /** Groupes d'agence (DeveloperName → Id), lus une fois par transaction. */
    private static Map<String, Id> groupIdCache;

    /**
     * Matrices créées dans cette transaction → groupe d'agence posé (null : aucun). Les motifs insérés juste après
     * (avenant, duplication) suivent ce partage sans aucune requête : la création d'avenant est proche de la limite.
     */
    private static Map<Id, Id> groupByCreatedMatrix = new Map<Id, Id>();

    private static final Map<String, String> ACCENTS = new Map<String, String>{
        'à' => 'a', 'á' => 'a', 'â' => 'a', 'ã' => 'a', 'ä' => 'a', 'å' => 'a',
        'ç' => 'c', 'è' => 'e', 'é' => 'e', 'ê' => 'e', 'ë' => 'e',
        'ì' => 'i', 'í' => 'i', 'î' => 'i', 'ï' => 'i', 'ñ' => 'n',
        'ò' => 'o', 'ó' => 'o', 'ô' => 'o', 'õ' => 'o', 'ö' => 'o',
        'ù' => 'u', 'ú' => 'u', 'û' => 'u', 'ü' => 'u', 'ý' => 'y', 'ÿ' => 'y',
        'œ' => 'oe', 'æ' => 'ae'
    };

    // ---------- Groupes ----------

    /**
     * Nom API du groupe d'une agence : préfixe + valeur sans accents, tout caractère hors lettres et chiffres
     * remplacé par `_` (jamais deux de suite, ni en fin), 80 caractères au plus. Null pour une agence vide.
     */
    public static String groupDeveloperName(String agency) {
        if (String.isBlank(agency)) {
            return null;
        }
        String ascii = '';
        String source = agency.trim();
        for (Integer i = 0; i < source.length(); i++) {
            String ch = source.substring(i, i + 1);
            String lower = ch.toLowerCase();
            if (ACCENTS.containsKey(lower)) {
                String mapped = ACCENTS.get(lower);
                // == est insensible à la casse en Apex : equals() distingue « É » de « é ».
                ascii += ch.equals(lower) ? mapped : mapped.capitalize();
            } else {
                ascii += ch;
            }
        }
        String cleaned = ascii.replaceAll('[^A-Za-z0-9]+', '_').replaceAll('^_+', '').replaceAll('_+$', '');
        if (String.isBlank(cleaned)) {
            return null;
        }
        return (GROUP_PREFIX + cleaned).left(80).replaceAll('_+$', '');
    }

    /** Libellé du groupe (40 caractères au plus) : « AR Agence <valeur> ». */
    public static String groupLabel(String agency) {
        return ('AR Agence ' + agency.trim()).left(40);
    }

    private static Map<String, Id> agencyGroups() {
        if (groupIdCache == null) {
            groupIdCache = new Map<String, Id>();
            for (Group g : [
                SELECT Id, DeveloperName FROM Group WHERE Type = 'Regular' AND DeveloperName LIKE 'AR_Agence_%'
            ]) {
                // LIKE sans échappement (« _ » y est un joker) : filtre exact sur le préfixe ici.
                if (g.DeveloperName.startsWith(GROUP_PREFIX)) {
                    groupIdCache.put(g.DeveloperName, g.Id);
                }
            }
        }
        return groupIdCache;
    }

    /** Groupe de l'agence (créé s'il manque). Objet de configuration : jamais dans une transaction de partage. */
    public static Map<String, Id> ensureGroups(Set<String> agencies) {
        Map<String, Id> groups = agencyGroups();
        Map<String, Group> toCreate = new Map<String, Group>();
        for (String agency : agencies) {
            String name = groupDeveloperName(agency);
            if (name != null && !groups.containsKey(name) && !toCreate.containsKey(name)) {
                toCreate.put(name, new Group(
                    Name = groupLabel(agency), DeveloperName = name, Type = 'Regular', DoesIncludeBosses = false
                ));
            }
        }
        if (!toCreate.isEmpty()) {
            insert toCreate.values();
            for (Group g : toCreate.values()) {
                groups.put(g.DeveloperName, g.Id);
            }
            groupsCreated += toCreate.size();
        }
        return groups;
    }

    // ---------- Membres ----------

    /**
     * Appelé par `AR_UserTrigger` (after insert/update) : un utilisateur créé avec une agence, ou dont l'agence ou
     * l'activation change, est rangé dans le bon groupe en asynchrone, puis les matrices dont il est propriétaire
     * sont réalignées sur son nouveau groupe.
     */
    public static void onUsersChanged(List<User> users, Map<Id, User> oldMap) {
        Set<Id> changed = new Set<Id>();
        for (User u : users) {
            User previous = oldMap == null ? null : oldMap.get(u.Id);
            if (previous == null) {
                if (String.isNotBlank(u.TP_Agence__c)) {
                    changed.add(u.Id);
                }
            } else if (u.TP_Agence__c != previous.TP_Agence__c || u.IsActive != previous.IsActive) {
                changed.add(u.Id);
            }
        }
        if (changed.isEmpty()) {
            return;
        }
        // Une mise à jour d'utilisateur ne doit jamais échouer à cause du partage : file pleine → journalisé,
        // le rattrapage (scripts/apex/282-partage-agence.apex) reprend ces utilisateurs.
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new MembershipJob(changed, true));
        } else {
            System.debug(LoggingLevel.WARN, 'File pleine : appartenance aux groupes d’agence non recalculée pour ' +
                changed.size() + ' utilisateur(s). Rattrapage : scripts/apex/282-partage-agence.apex.');
        }
    }

    /**
     * Aligne l'appartenance aux groupes d'agence des utilisateurs donnés : un utilisateur actif (standard) ayant
     * une agence est membre de ce seul groupe d'agence ; tout autre appartenance à un groupe `AR_Agence_*` est
     * retirée. Idempotent. Objets de configuration seulement (Group, GroupMember).
     */
    public static void syncMemberships(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        List<User> users = [SELECT Id, TP_Agence__c, IsActive, UserType FROM User WHERE Id IN :userIds];
        Set<String> agencies = new Set<String>();
        for (User u : users) {
            if (isMemberCandidate(u)) {
                agencies.add(u.TP_Agence__c);
            }
        }
        Map<String, Id> groups = ensureGroups(agencies);

        Map<Id, Id> dueGroupByUser = new Map<Id, Id>();
        for (User u : users) {
            if (isMemberCandidate(u)) {
                Id groupId = groups.get(groupDeveloperName(u.TP_Agence__c));
                if (groupId != null) {
                    dueGroupByUser.put(u.Id, groupId);
                }
            }
        }

        List<GroupMember> stale = new List<GroupMember>();
        Set<Id> alreadyMember = new Set<Id>();
        for (GroupMember gm : [
            SELECT Id, GroupId, UserOrGroupId, Group.DeveloperName
            FROM GroupMember
            WHERE UserOrGroupId IN :userIds AND Group.Type = 'Regular' AND Group.DeveloperName LIKE 'AR_Agence_%'
        ]) {
            if (!gm.Group.DeveloperName.startsWith(GROUP_PREFIX)) {
                continue;
            }
            if (dueGroupByUser.get(gm.UserOrGroupId) == gm.GroupId) {
                alreadyMember.add(gm.UserOrGroupId);
            } else {
                stale.add(gm);
            }
        }
        List<GroupMember> toAdd = new List<GroupMember>();
        for (Id userId : dueGroupByUser.keySet()) {
            if (!alreadyMember.contains(userId)) {
                toAdd.add(new GroupMember(GroupId = dueGroupByUser.get(userId), UserOrGroupId = userId));
            }
        }
        if (!stale.isEmpty()) {
            delete stale;
            membersRemoved += stale.size();
        }
        if (!toAdd.isEmpty()) {
            insert toAdd;
            membersAdded += toAdd.size();
        }
    }

    private static Boolean isMemberCandidate(User u) {
        return u.IsActive && u.UserType == 'Standard' && groupDeveloperName(u.TP_Agence__c) != null;
    }

    /** Rattrapage, étape 1 : tous les utilisateurs ayant une agence ou déjà membres d'un groupe d'agence. */
    public static void backfillMemberships() {
        Set<Id> userIds = new Map<Id, User>([SELECT Id FROM User WHERE TP_Agence__c != null]).keySet().clone();
        for (GroupMember gm : [
            SELECT UserOrGroupId, Group.DeveloperName FROM GroupMember
            WHERE Group.Type = 'Regular' AND Group.DeveloperName LIKE 'AR_Agence_%'
        ]) {
            if (gm.Group.DeveloperName.startsWith(GROUP_PREFIX) && gm.UserOrGroupId.getSobjectType() == User.SObjectType) {
                userIds.add(gm.UserOrGroupId);
            }
        }
        syncMemberships(userIds);
    }

    // ---------- Lignes de partage ----------

    /**
     * Matrices tout juste créées : aucune ligne existante, on insère sans relire. `owners` porte `TP_Agence__c`
     * (lu par `AR_MatrixSharingService` dans la même requête que la chaîne). Groupe absent → création
     * asynchrone du groupe, puis réalignement des matrices du propriétaire.
     */
    public static void insertAgencyShares(List<AR_Price_Matrix__c> created, Map<Id, User> owners) {
        if (created == null || created.isEmpty()) {
            return;
        }
        Map<Id, String> nameByMatrix = new Map<Id, String>();
        for (AR_Price_Matrix__c m : created) {
            User owner = owners.get(m.OwnerId);
            String name = owner == null ? null : groupDeveloperName(owner.TP_Agence__c);
            groupByCreatedMatrix.put(m.Id, null);
            if (name != null) {
                nameByMatrix.put(m.Id, name);
            }
        }
        // Aucun propriétaire avec agence : pas même la lecture des groupes.
        if (nameByMatrix.isEmpty()) {
            return;
        }
        Map<String, Id> groups = agencyGroups();
        List<AR_Price_Matrix__Share> rows = new List<AR_Price_Matrix__Share>();
        Set<Id> ownersWithoutGroup = new Set<Id>();
        for (AR_Price_Matrix__c m : created) {
            String name = nameByMatrix.get(m.Id);
            if (name == null) {
                continue;
            }
            Id groupId = groups.get(name);
            if (groupId == null) {
                ownersWithoutGroup.add(m.OwnerId);
                continue;
            }
            groupByCreatedMatrix.put(m.Id, groupId);
            rows.add(new AR_Price_Matrix__Share(ParentId = m.Id, UserOrGroupId = groupId, AccessLevel = ACCESS_LEVEL, RowCause = ROW_CAUSE));
        }
        if (!rows.isEmpty()) {
            Integer refused = 0;
            for (Database.SaveResult r : Database.insert(rows, false, AccessLevel.SYSTEM_MODE)) {
                if (!r.isSuccess()) {
                    refused++;
                    System.debug(LoggingLevel.ERROR, 'Partage d’agence refusé : ' + r.getErrors()[0].getMessage());
                }
            }
            if (refused > 0) {
                System.debug(LoggingLevel.WARN, refused + ' ligne(s) de partage d’agence non créée(s) sur une création de matrice.');
            }
        }
        createGroupsLater(ownersWithoutGroup);
    }

    /** Matrices dont le propriétaire figure dans `ownerIds` (après un changement d'agence). */
    public static void recalculateForOwners(Set<Id> ownerIds, Boolean allowGroupCreation) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return;
        }
        Set<Id> matrixIds = new Map<Id, AR_Price_Matrix__c>(
            [SELECT Id FROM AR_Price_Matrix__c WHERE OwnerId IN :ownerIds]
        ).keySet();
        recalculateMatrices(matrixIds, allowGroupCreation);
    }

    /**
     * Aligne les lignes `AR_Agence_Matrice__c` des matrices données et de leurs motifs sur le groupe de l'agence
     * du propriétaire. `allowGroupCreation` : un groupe manquant est créé en asynchrone (faux dans les travaux
     * asynchrones eux-mêmes, pour ne jamais boucler).
     */
    public static void recalculateMatrices(Set<Id> matrixIds, Boolean allowGroupCreation) {
        if (matrixIds == null || matrixIds.isEmpty()) {
            return;
        }
        Map<Id, Set<Id>> dueByMatrix = dueGroupsByMatrix(matrixIds, allowGroupCreation);
        AR_MatrixSharingService.syncShares('AR_Price_Matrix__Share', dueByMatrix, ROW_CAUSE, ACCESS_LEVEL);
        syncReasonShares(dueByMatrix);
    }

    /**
     * Motifs ajoutés (after insert) : ils reçoivent la ligne d'agence de leur matrice. Matrice créée dans la même
     * transaction : groupe connu, aucune requête ; sinon une lecture des lignes d'agence existantes de la matrice.
     */
    public static void shareInsertedReasons(List<AR_Reason_Selection__c> selections) {
        Map<Id, Id> groupByMatrix = new Map<Id, Id>();
        Set<Id> unknown = new Set<Id>();
        for (AR_Reason_Selection__c s : selections) {
            Id matrixId = s.AR_Price_Matrix__c;
            if (matrixId == null) {
                continue;
            }
            if (groupByCreatedMatrix.containsKey(matrixId)) {
                groupByMatrix.put(matrixId, groupByCreatedMatrix.get(matrixId));
            } else {
                unknown.add(matrixId);
            }
        }
        if (!unknown.isEmpty()) {
            for (AR_Price_Matrix__Share sh : [
                SELECT ParentId, UserOrGroupId FROM AR_Price_Matrix__Share
                WHERE ParentId IN :unknown AND RowCause = :ROW_CAUSE
            ]) {
                groupByMatrix.put(sh.ParentId, sh.UserOrGroupId);
            }
        }
        List<AR_Reason_Selection__Share> rows = new List<AR_Reason_Selection__Share>();
        for (AR_Reason_Selection__c s : selections) {
            Id groupId = groupByMatrix.get(s.AR_Price_Matrix__c);
            if (groupId != null) {
                rows.add(new AR_Reason_Selection__Share(
                    ParentId = s.Id, UserOrGroupId = groupId, AccessLevel = ACCESS_LEVEL, RowCause = ROW_CAUSE
                ));
            }
        }
        if (rows.isEmpty()) {
            return;
        }
        for (Database.SaveResult r : Database.insert(rows, false, AccessLevel.SYSTEM_MODE)) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Partage d’agence d’un motif refusé : ' + r.getErrors()[0].getMessage());
            }
        }
    }

    private static Map<Id, Set<Id>> dueGroupsByMatrix(Set<Id> matrixIds, Boolean allowGroupCreation) {
        List<AR_Price_Matrix__c> matrices = [SELECT Id, OwnerId FROM AR_Price_Matrix__c WHERE Id IN :matrixIds];
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            ownerIds.add(m.OwnerId);
        }
        Map<Id, User> owners = new Map<Id, User>([SELECT Id, TP_Agence__c FROM User WHERE Id IN :ownerIds]);
        Map<String, Id> groups = agencyGroups();
        // Un groupe créé depuis la première lecture (travail asynchrone précédent) : relecture unique.
        for (User owner : owners.values()) {
            String name = groupDeveloperName(owner.TP_Agence__c);
            if (name != null && !groups.containsKey(name)) {
                groupIdCache = null;
                groups = agencyGroups();
                break;
            }
        }
        Map<Id, Set<Id>> due = new Map<Id, Set<Id>>();
        Set<Id> ownersWithoutGroup = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            Set<Id> groupIds = new Set<Id>();
            User owner = owners.get(m.OwnerId);
            String name = owner == null ? null : groupDeveloperName(owner.TP_Agence__c);
            if (name != null) {
                if (groups.containsKey(name)) {
                    groupIds.add(groups.get(name));
                } else {
                    ownersWithoutGroup.add(m.OwnerId);
                }
            }
            due.put(m.Id, groupIds);
        }
        if (allowGroupCreation) {
            createGroupsLater(ownersWithoutGroup);
        } else if (!ownersWithoutGroup.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'Groupe d’agence absent pour ' + ownersWithoutGroup.size() +
                ' propriétaire(s) : lignes d’agence non posées. Rattrapage : scripts/apex/282-partage-agence.apex.');
        }
        return due;
    }

    private static void syncReasonShares(Map<Id, Set<Id>> dueByMatrix) {
        if (dueByMatrix.isEmpty()) {
            return;
        }
        Map<Id, Set<Id>> dueBySelection = new Map<Id, Set<Id>>();
        for (AR_Reason_Selection__c s : [
            SELECT Id, AR_Price_Matrix__c FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c IN :dueByMatrix.keySet()
        ]) {
            dueBySelection.put(s.Id, dueByMatrix.get(s.AR_Price_Matrix__c));
        }
        AR_MatrixSharingService.syncShares('AR_Reason_Selection__Share', dueBySelection, ROW_CAUSE, ACCESS_LEVEL);
    }

    /** Groupe manquant pour ces propriétaires : création asynchrone, puis réalignement de leurs matrices. */
    private static void createGroupsLater(Set<Id> ownerIds) {
        if (ownerIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new MembershipJob(ownerIds, true));
        } else {
            System.debug(LoggingLevel.WARN, 'File pleine : groupe d’agence non créé pour ' + ownerIds.size() +
                ' propriétaire(s). Rattrapage : scripts/apex/282-partage-agence.apex.');
        }
    }

    // ---------- Travaux asynchrones ----------

    /**
     * Étape « configuration » : groupes et membres des utilisateurs donnés ; puis, si demandé, enchaîne l'étape
     * « partage » (autre transaction, DML mixte interdit) sur les matrices dont ils sont propriétaires.
     */
    public class MembershipJob implements Queueable {
        private final Set<Id> userIds;
        private final Boolean thenMatrices;

        public MembershipJob(Set<Id> userIds, Boolean thenMatrices) {
            this.userIds = userIds;
            this.thenMatrices = thenMatrices;
        }

        public void execute(QueueableContext context) {
            try {
                syncMemberships(userIds);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Groupes d’agence : recalcul en échec (' + e.getMessage() + ')');
                return;
            }
            // Un travail asynchrone ne peut pas en enchaîner un autre dans un test Apex.
            if (thenMatrices && !Test.isRunningTest()) {
                System.enqueueJob(new MatrixJob(userIds));
            }
        }
    }

    /** Étape « partage » : réalignement des matrices des propriétaires donnés, sans recréer de groupe. */
    public class MatrixJob implements Queueable {
        private final Set<Id> ownerIds;

        public MatrixJob(Set<Id> ownerIds) {
            this.ownerIds = ownerIds;
        }

        public void execute(QueueableContext context) {
            try {
                recalculateForOwners(ownerIds, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Partage d’agence : recalcul en échec (' + e.getMessage() + ')');
            }
        }
    }
}