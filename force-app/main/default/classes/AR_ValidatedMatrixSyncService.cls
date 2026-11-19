/**
 * Session 174 — Synchronise AR_Validated_Matrix__c (« Matrice validée ») depuis AR_Price_Matrix__c.
 * Appelé par AR_PriceMatrixTrigger (after insert / update / delete / undelete).
 *
 * Principe : pour chaque chaîne de négociation touchée (clé = AR_Root_Matrix__c, à défaut l'Id de la matrice),
 * on RECALCULE l'état voulu au lieu d'appliquer un delta — c'est ce qui rend la synchro idempotente et couvre
 * d'un seul mécanisme l'entrée, le remplacement par une nouvelle version, la sortie (refus, retour en
 * dérogation, suppression, besoin non Open), le renommage et la restauration depuis la corbeille.
 *  - une matrice est éligible si son statut est Validée / Validée par dérogation ET si son besoin est Open ;
 *  - par chaîne, seule l'éligible de plus haut AR_Negotiation_Version__c a une entrée (rang dans la chaîne,
 *    jamais AR_Version_Number__c, compteur de snapshots — cf. docs/173c §5) ;
 *  - l'écriture est un upsert sur AR_Matrix_Key__c (unique) : rejouer ne crée jamais de doublon ;
 *  - session 175 : la gagnante n'a d'entrée que si sa date de validation (AR_Validated_At__c, à défaut la date de
 *    création) n'est pas plus vieille que AR_General_Setting__c.AR_Validated_Matrix_Lifetime_Days__c jours (365 par
 *    défaut). La durée de vie fait partie de l'éligibilité, pas seulement du batch d'expiration : sans cela une
 *    réouverture de besoin ou un événement sur la matrice recréerait des entrées déjà expirées.
 *    Un changement de statut du BESOIN (Open ↔ autre) est suivi par AR_PositionStatusTrigger → handlePositions.
 *
 * without sharing : les matrices sont Private, l'entrée doit être trouvée/remplacée/supprimée quel que soit le
 * propriétaire de la matrice ou de l'entrée (même motif que AR_DerogationService.UnsharedDecisionWriter).
 *
 * Erreur technique : journalisée, jamais propagée — un échec de synchro ne doit pas empêcher d'enregistrer une
 * matrice (classé « journaliser », CLAUDE.md session 34). Le rattrapage est la reprise rejouable
 * (scripts/apex/174-reprise-matrices-validees.apex, qui appelle resyncAll).
 */
public without sharing class AR_ValidatedMatrixSyncService {
    public static final Set<String> VALIDATED_STATUSES = new Set<String>{ 'Validée', 'Validée par dérogation' };
    public static final String OPEN_POSITION_STATUS = 'Open';
    public static final Integer NAME_MAX_LENGTH = 80;
    public static final String AVENANT_TYPE = 'Avenant';
    private static final String ACCOUNT_MISSING = 'Compte non renseigné';
    private static final String CONSULTANT_MISSING = 'consultant non renseigné';
    private static final String ELLIPSIS = '…';
    private static final String DISPLAY_TIME_ZONE = 'Europe/Paris';
    private static final Integer ACCOUNT_FLOOR = 10;

    // Point d'injection de test : erreur technique à l'intérieur du bloc protégé.
    @testVisible
    private static Boolean throwExceptionForTest = false;

    public class SyncException extends Exception {
    }

    // Champs dont la modification peut changer l'entrée (éligibilité, chaîne ou libellé).
    private static final List<Schema.SObjectField> WATCHED_FIELDS = new List<Schema.SObjectField>{
        AR_Price_Matrix__c.AR_Status__c,
        AR_Price_Matrix__c.AR_Position__c,
        AR_Price_Matrix__c.AR_Root_Matrix__c,
        AR_Price_Matrix__c.AR_Negotiation_Version__c,
        AR_Price_Matrix__c.AR_Account_Name__c,
        AR_Price_Matrix__c.AR_Consultant_Name__c,
        AR_Price_Matrix__c.AR_Consultant__c,
        AR_Price_Matrix__c.AR_Validated_At__c,
        AR_Price_Matrix__c.AR_Version_Type__c
    };

    // ---------- Point d'entrée du trigger ----------

    public static void handle(
        List<AR_Price_Matrix__c> records,
        Map<Id, AR_Price_Matrix__c> oldMap,
        Boolean isDelete
    ) {
        try {
            Set<String> rootKeys = affectedRootKeys(records, oldMap, isDelete);
            if (rootKeys.isEmpty()) {
                return;
            }
            AR_General_Setting__c settings = loadSettings();
            if (!isSyncEnabled(settings)) {
                return;
            }
            syncRootKeys(rootKeys, cutoffFor(settings));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AR_ValidatedMatrixSyncService : ' + e.getTypeName() + ' — '
                + e.getMessage() + ' — ' + e.getStackTraceString());
        }
    }

    // Reprise / rattrapage : recalcule toutes les chaînes ayant au moins une matrice validée, ainsi que
    // toutes les entrées existantes (pour retirer celles devenues inutiles). Ignore l'interrupteur : c'est
    // l'outil qui sert justement à amorcer les données avant de l'activer. Les erreurs remontent à l'appelant.
    public static Integer resyncAll() {
        Set<String> rootKeys = new Set<String>();
        for (AR_Price_Matrix__c matrix : [
            SELECT Id, AR_Root_Matrix__c FROM AR_Price_Matrix__c WHERE AR_Status__c IN :VALIDATED_STATUSES
        ]) {
            rootKeys.add(rootKeyOf(matrix));
        }
        for (AR_Validated_Matrix__c entry : [SELECT AR_Root_Key__c FROM AR_Validated_Matrix__c]) {
            if (entry.AR_Root_Key__c != null) {
                rootKeys.add(entry.AR_Root_Key__c);
            }
        }
        Datetime cutoff = cutoffFor(loadSettings());
        // Les chaînes sont traitées par blocs : une requête de chaînes et une d'entrées par bloc.
        List<String> keys = new List<String>(rootKeys);
        Integer blockSize = 500;
        for (Integer start = 0; start < keys.size(); start += blockSize) {
            Set<String> block = new Set<String>();
            for (Integer i = start; i < Math.min(start + blockSize, keys.size()); i++) {
                block.add(keys[i]);
            }
            syncRootKeys(block, cutoff);
        }
        return keys.size();
    }

    // Une seule requête de réglages par appel : interrupteur et durée de vie viennent du même enregistrement.
    public static AR_General_Setting__c loadSettings() {
        List<AR_General_Setting__c> settings = [
            SELECT AR_Validated_Matrix_Sync_Enabled__c, AR_Validated_Matrix_Lifetime_Days__c
            FROM AR_General_Setting__c
            LIMIT 1
        ];
        return settings.isEmpty() ? null : settings[0];
    }

    public static Boolean isSyncEnabled(AR_General_Setting__c settings) {
        return settings != null && settings.AR_Validated_Matrix_Sync_Enabled__c == true;
    }

    // Durée de vie en jours : valeur enregistrée, sinon 365. Une valeur < 1 (saisie directe en base, l'écran
    // d'administration la refuse) retombe aussi sur le défaut plutôt que d'expirer toutes les entrées.
    public static Integer lifetimeDays(AR_General_Setting__c settings) {
        Decimal days = settings == null ? null : settings.AR_Validated_Matrix_Lifetime_Days__c;
        if (days == null || days < 1) {
            days = AR_GeneralSettingDefaults.VALIDATED_MATRIX_LIFETIME_DAYS;
        }
        return days.intValue();
    }

    // Une entrée dont la date de validation est antérieure à ce seuil est expirée (exactement N jours : conservée).
    public static Datetime cutoffFor(AR_General_Setting__c settings) {
        return System.now().addDays(-lifetimeDays(settings));
    }

    // ---------- Changement de statut du besoin (session 175) ----------

    /**
     * Appelé par AR_PositionStatusTrigger (after update sur cxsrec__cxsPosition__c, objet Connexys). Ne réagit qu'à un
     * changement de cxsrec__Status__c dont l'un des deux côtés est Open : un besoin qui quitte Open perd ses entrées,
     * un besoin qui y revient retrouve une entrée par chaîne (dernière version validée) — le recalcul de la chaîne
     * fait les deux, comme pour une matrice. Un passage entre deux statuts non Open ne change aucune éligibilité.
     *
     * Protégé : une erreur de ce code ne doit JAMAIS empêcher Connexys d'enregistrer un besoin → tout est dans un
     * try/catch (journaliser, rattrapage = resyncAll). Les limites Apex, elles, ne sont pas interceptables : le code
     * vérifie donc avant d'agir qu'il reste de la marge dans la transaction du besoin et s'abstient sinon.
     */
    public static void handlePositions(
        List<cxsrec__cxsPosition__c> records,
        Map<Id, cxsrec__cxsPosition__c> oldMap
    ) {
        try {
            Set<Id> positionIds = statusChangedPositionIds(records, oldMap);
            if (positionIds.isEmpty()) {
                return;
            }
            if (!hasRoomForPositionSync()) {
                System.debug(LoggingLevel.ERROR, 'AR_ValidatedMatrixSyncService : marge de limites insuffisante dans la transaction du besoin, '
                    + positionIds.size() + ' besoin(s) non synchronisé(s) — rattrapage par resyncAll.');
                return;
            }
            AR_General_Setting__c settings = loadSettings();
            if (!isSyncEnabled(settings)) {
                return;
            }
            Set<String> rootKeys = new Set<String>();
            for (AR_Price_Matrix__c matrix : [
                SELECT Id, AR_Root_Matrix__c FROM AR_Price_Matrix__c
                WHERE AR_Position__c IN :positionIds AND AR_Status__c IN :VALIDATED_STATUSES
            ]) {
                rootKeys.add(rootKeyOf(matrix));
            }
            for (AR_Validated_Matrix__c entry : [
                SELECT AR_Root_Key__c FROM AR_Validated_Matrix__c WHERE AR_Position__c IN :positionIds
            ]) {
                if (entry.AR_Root_Key__c != null) {
                    rootKeys.add(entry.AR_Root_Key__c);
                }
            }
            if (rootKeys.isEmpty()) {
                return;
            }
            if (Limits.getLimitDmlRows() - Limits.getDmlRows() < 2 * rootKeys.size()) {
                System.debug(LoggingLevel.ERROR, 'AR_ValidatedMatrixSyncService : marge de lignes DML insuffisante pour '
                    + rootKeys.size() + ' chaîne(s) — rattrapage par resyncAll.');
                return;
            }
            syncRootKeys(rootKeys, cutoffFor(settings));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AR_ValidatedMatrixSyncService.handlePositions : ' + e.getTypeName() + ' — '
                + e.getMessage() + ' — ' + e.getStackTraceString());
        }
    }

    private static Set<Id> statusChangedPositionIds(
        List<cxsrec__cxsPosition__c> records,
        Map<Id, cxsrec__cxsPosition__c> oldMap
    ) {
        Set<Id> positionIds = new Set<Id>();
        if (records == null || oldMap == null) {
            return positionIds;
        }
        for (cxsrec__cxsPosition__c record : records) {
            cxsrec__cxsPosition__c oldRecord = oldMap.get(record.Id);
            if (oldRecord == null || record.cxsrec__Status__c == oldRecord.cxsrec__Status__c) {
                continue;
            }
            if (record.cxsrec__Status__c == OPEN_POSITION_STATUS || oldRecord.cxsrec__Status__c == OPEN_POSITION_STATUS) {
                positionIds.add(record.Id);
            }
        }
        return positionIds;
    }

    // Requêtes : 1 (réglages) + 2 (matrices, entrées) + 2 (chaînes, entrées) ; DML : 3 (suppression, repointage, upsert).
    private static Boolean hasRoomForPositionSync() {
        return Limits.getLimitQueries() - Limits.getQueries() >= 8
            && Limits.getLimitDmlStatements() - Limits.getDmlStatements() >= 5;
    }

    // ---------- Chaînes touchées ----------

    private static Set<String> affectedRootKeys(
        List<AR_Price_Matrix__c> records,
        Map<Id, AR_Price_Matrix__c> oldMap,
        Boolean isDelete
    ) {
        Set<String> rootKeys = new Set<String>();
        for (AR_Price_Matrix__c record : records) {
            AR_Price_Matrix__c oldRecord = oldMap != null && !isDelete ? oldMap.get(record.Id) : null;
            if (oldRecord == null) {
                // Insert, suppression ou restauration : une matrice jamais validée n'a aucun effet sur la liste.
                if (isDelete || VALIDATED_STATUSES.contains(record.AR_Status__c)) {
                    rootKeys.add(rootKeyOf(record));
                }
            } else if (hasWatchedChange(record, oldRecord)) {
                rootKeys.add(rootKeyOf(record));
                rootKeys.add(rootKeyOf(oldRecord));
            }
        }
        return rootKeys;
    }

    private static Boolean hasWatchedChange(AR_Price_Matrix__c record, AR_Price_Matrix__c oldRecord) {
        for (Schema.SObjectField field : WATCHED_FIELDS) {
            if (record.get(field) != oldRecord.get(field)) {
                return true;
            }
        }
        return false;
    }

    @testVisible
    private static String rootKeyOf(AR_Price_Matrix__c matrix) {
        return String.valueOf(matrix.AR_Root_Matrix__c != null ? matrix.AR_Root_Matrix__c : matrix.Id);
    }

    // ---------- Recalcul ----------

    private static void syncRootKeys(Set<String> rootKeys, Datetime cutoff) {
        if (throwExceptionForTest) {
            throw new SyncException('Erreur technique simulée (test)');
        }

        // Un Set<String> ne se lie pas à un champ Id : conversion explicite.
        Set<Id> rootIds = new Set<Id>();
        for (String key : rootKeys) {
            rootIds.add((Id) key);
        }

        // Latest éligible par chaîne. Les matrices supprimées n'apparaissent plus (corbeille exclue).
        Map<String, AR_Price_Matrix__c> latestByRoot = new Map<String, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c matrix : [
            SELECT Id, AR_Status__c, AR_Position__c, AR_Root_Matrix__c, AR_Negotiation_Version__c,
                   AR_Account_Name__c, AR_Consultant_Name__c, AR_Consultant__r.Name, AR_Validated_At__c, AR_Version_Type__c,
                   CreatedDate
            FROM AR_Price_Matrix__c
            WHERE (Id IN :rootIds OR AR_Root_Matrix__c IN :rootIds)
            AND AR_Status__c IN :VALIDATED_STATUSES
            AND AR_Position__r.cxsrec__Status__c = :OPEN_POSITION_STATUS
        ]) {
            String key = rootKeyOf(matrix);
            AR_Price_Matrix__c current = latestByRoot.get(key);
            if (current == null || isNewer(matrix, current)) {
                latestByRoot.put(key, matrix);
            }
        }

        // Entrées voulues : une par chaîne dont la gagnante n'est pas expirée.
        // Session 175 : la gagnante expirée n'a pas d'entrée, et on ne retombe PAS sur une version plus ancienne
        // de la chaîne (plus ancienne = a fortiori trop vieille, et ce n'est de toute façon pas « la dernière »).
        Map<String, AR_Price_Matrix__c> winnerByRoot = new Map<String, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c winner : latestByRoot.values()) {
            if (validatedOn(winner) >= cutoff) {
                winnerByRoot.put(rootKeyOf(winner), winner);
            }
        }

        // Session 180a : l'entrée d'une chaîne est RÉUTILISÉE quand la gagnante change (nouvelle version validée),
        // jamais supprimée puis recréée. Une suppression vide en SetNull le champ « Matrice de prix »
        // (Step.AR_Validated_Matrix__c) de l'étape Connexys en plein processus ; une mise à jour de l'entrée le
        // laisse rempli et le libellé suit la version en vigueur. Une entrée n'est supprimée que lorsque la chaîne
        // n'a plus de gagnante (refus, retour en dérogation sans version validée, besoin non Open, expiration).
        Map<String, List<AR_Validated_Matrix__c>> existingByRoot = new Map<String, List<AR_Validated_Matrix__c>>();
        for (AR_Validated_Matrix__c entry : [
            SELECT Id, AR_Matrix_Key__c, AR_Root_Key__c FROM AR_Validated_Matrix__c
            WHERE AR_Root_Key__c IN :rootKeys ORDER BY Id
        ]) {
            if (!existingByRoot.containsKey(entry.AR_Root_Key__c)) {
                existingByRoot.put(entry.AR_Root_Key__c, new List<AR_Validated_Matrix__c>());
            }
            existingByRoot.get(entry.AR_Root_Key__c).add(entry);
        }

        List<AR_Validated_Matrix__c> toDelete = new List<AR_Validated_Matrix__c>();
        List<AR_Validated_Matrix__c> toUpdate = new List<AR_Validated_Matrix__c>();
        List<AR_Validated_Matrix__c> toUpsert = new List<AR_Validated_Matrix__c>();
        for (String rootKey : rootKeys) {
            List<AR_Validated_Matrix__c> existing = existingByRoot.get(rootKey);
            if (existing == null) {
                existing = new List<AR_Validated_Matrix__c>();
            }
            AR_Price_Matrix__c winner = winnerByRoot.get(rootKey);
            if (winner == null) {
                toDelete.addAll(existing);
                continue;
            }
            String matrixKey = String.valueOf(winner.Id);
            AR_Validated_Matrix__c kept = null;
            for (AR_Validated_Matrix__c entry : existing) {
                if (entry.AR_Matrix_Key__c == matrixKey) {
                    kept = entry;
                    break;
                }
            }
            if (kept == null && !existing.isEmpty()) {
                kept = existing[0];
            }
            for (AR_Validated_Matrix__c entry : existing) {
                if (entry.Id != kept?.Id) {
                    toDelete.add(entry); // doublon de chaîne (anormal) : on n'en garde qu'un
                }
            }
            AR_Validated_Matrix__c wanted = new AR_Validated_Matrix__c(
                AR_Matrix_Key__c = matrixKey,
                AR_Price_Matrix__c = winner.Id,
                AR_Position__c = winner.AR_Position__c,
                AR_Root_Key__c = rootKey,
                Name = buildName(winner)
            );
            if (kept != null && kept.AR_Matrix_Key__c != matrixKey) {
                wanted.Id = kept.Id; // entrée de la version précédente, repointée sur la nouvelle gagnante
                toUpdate.add(wanted);
            } else {
                toUpsert.add(wanted);
            }
        }

        // Suppression d'abord (doublons et chaînes sans gagnante), puis repointage, puis upsert idempotent :
        // jamais deux entrées de la même chaîne en même temps.
        // Session 180b : SYSTEM_MODE explicite. L'objet n'accorde aucun droit d'écriture aux permission sets
        // fonctionnels (liste tenue par le système, jamais saisie) : sous un BM réel, un DML en mode utilisateur
        // échouait en « DML operation UPDATE not allowed on AR_Validated_Matrix__c » — erreur avalée par handle(),
        // donc une liste jamais mise à jour pour un non-administrateur. Invisible aux tests joués en administrateur.
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, true, AccessLevel.SYSTEM_MODE);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
        if (!toUpsert.isEmpty()) {
            Database.upsert(toUpsert, AR_Validated_Matrix__c.AR_Matrix_Key__c, true, AccessLevel.SYSTEM_MODE);
        }
    }

    // Date de validation de la matrice ; à défaut (matrices validées avant que le champ existe) sa date de création.
    @testVisible
    private static Datetime validatedOn(AR_Price_Matrix__c matrix) {
        return matrix.AR_Validated_At__c != null ? matrix.AR_Validated_At__c : matrix.CreatedDate;
    }

    // Plus grand rang gagne ; égalité (anormale) : la plus récemment créée, puis l'Id, pour un résultat stable.
    private static Boolean isNewer(AR_Price_Matrix__c candidate, AR_Price_Matrix__c current) {
        Decimal candidateVersion = candidate.AR_Negotiation_Version__c != null ? candidate.AR_Negotiation_Version__c : 0;
        Decimal currentVersion = current.AR_Negotiation_Version__c != null ? current.AR_Negotiation_Version__c : 0;
        if (candidateVersion != currentVersion) {
            return candidateVersion > currentVersion;
        }
        if (candidate.CreatedDate != current.CreatedDate) {
            return candidate.CreatedDate > current.CreatedDate;
        }
        return String.valueOf(candidate.Id) > String.valueOf(current.Id);
    }

    // ---------- Libellé ----------

    /**
     * « {Compte} - {Consultant}, V{version} ({JJ/MM/AAAA}) », 80 caractères au plus. Session 180a : une version
     * avenant (AR_Version_Type__c = Avenant) donne « …, V{version} Avenant ({JJ/MM/AAAA}) ». Le compte est tronqué en
     * premier ; la version et la date ne sont jamais coupées. Le consultant n'est raccourci qu'en dernier recours
     * (compte déjà réduit à ACCOUNT_FLOOR caractères) — cas pathologique, nom de consultant démesuré.
     * Date : AR_Validated_At__c ; à défaut (matrices validées avant que le champ existe) la date de création.
     */
    @testVisible
    private static String buildName(AR_Price_Matrix__c matrix) {
        String account = String.isNotBlank(matrix.AR_Account_Name__c) ? matrix.AR_Account_Name__c.trim() : ACCOUNT_MISSING;
        String consultant = consultantNameOf(matrix);
        String version = matrix.AR_Negotiation_Version__c != null
            ? String.valueOf(Integer.valueOf(matrix.AR_Negotiation_Version__c))
            : '?';
        Datetime validated = validatedOn(matrix);
        String versionLabel = matrix.AR_Version_Type__c == AVENANT_TYPE ? version + ' ' + AVENANT_TYPE : version;
        String suffix = ', V' + versionLabel + ' (' + (validated == null ? '--/--/----' : validated.format('dd/MM/yyyy', DISPLAY_TIME_ZONE)) + ')';
        String separator = ' - ';

        Integer accountBudget = NAME_MAX_LENGTH - separator.length() - consultant.length() - suffix.length();
        if (accountBudget < ACCOUNT_FLOOR) {
            accountBudget = ACCOUNT_FLOOR;
        }
        account = truncate(account, accountBudget);

        Integer consultantBudget = NAME_MAX_LENGTH - account.length() - separator.length() - suffix.length();
        consultant = truncate(consultant, consultantBudget);

        return account + separator + consultant + suffix;
    }

    // Nom de la fiche Connexys liée (saisie réelle depuis la session 54) ; à défaut le texte libre historique.
    private static String consultantNameOf(AR_Price_Matrix__c matrix) {
        if (matrix.AR_Consultant__c != null && matrix.AR_Consultant__r != null && String.isNotBlank(matrix.AR_Consultant__r.Name)) {
            return matrix.AR_Consultant__r.Name.trim();
        }
        if (String.isNotBlank(matrix.AR_Consultant_Name__c)) {
            return matrix.AR_Consultant_Name__c.trim();
        }
        return CONSULTANT_MISSING;
    }

    private static String truncate(String value, Integer maxLength) {
        if (maxLength <= 0) {
            return '';
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return maxLength == 1 ? ELLIPSIS : value.substring(0, maxLength - 1).trim() + ELLIPSIS;
    }
}