/**
 * Purge automatique des brouillons non modifiés depuis longtemps (session 22, cf.
 * docs/22-versioning-negociation.md) ET des aperçus PTF transitoires > 24 h (session 124).
 * No-op si AR_General_Setting__c.AR_Draft_Purge_Enabled__c = false (livré désactivé : ne pas
 * activer avant d'avoir confirmé que la duplication est utilisée en production, cf.
 * AR_MatrixChainService).
 *
 * Trois phases dans la même exécution, exécutées indépendamment :
 * 1. Avertissement brouillons — brouillon jamais averti, inactif depuis (purgeDays - warningDays)
 *    jours. Un seul e-mail de synthèse par propriétaire (AR_NotificationService.sendDraftPurgeWarningDigest),
 *    envoyé dans finish(), jamais un e-mail par matrice.
 * 2. Suppression brouillons — brouillon déjà averti depuis au moins warningDays jours ET toujours
 *    inactif depuis purgeDays jours (re-vérification explicite et redondante de LastModifiedDate à
 *    cette phase). Journalisé dans AR_Purge_Log__c avant suppression irréversible ; les
 *    AR_Reason_Selection__c liées disparaissent via Cascade.
 * 3. Suppression aperçus PTF — aperçus > 24 h (session 124). Pas d'avertissement : ces enregistrements
 *    sont transitoires et aucune donnée n'en dépend (aucune trace métier à journaliser).
 *
 * Le volume par exécution (avertissement + suppression brouillons) est plafonné par
 * AR_Draft_Purge_Max_Per_Run__c : même un stock existant important au premier passage ne produit
 * ni envoi massif d'e-mails, ni suppression massive le même jour.
 */
public class AR_DraftPurgeBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Session 23 : AR_Settings__mdt migré vers AR_General_Setting__c (objet custom, écriture DML
    // synchrone depuis la page d'administration) — les tests peuvent désormais insérer/mettre à
    // jour un vrai enregistrement en @TestSetup plutôt que passer par un point d'injection dédié.
    private static AR_General_Setting__c loadSettings() {
        List<AR_General_Setting__c> rows = [
            SELECT AR_Draft_Purge_Enabled__c, AR_Draft_Purge_Days__c, AR_Draft_Purge_Warning_Days__c, AR_Draft_Purge_Max_Per_Run__c
            FROM AR_General_Setting__c
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private Integer purgeDays;
    private Integer warningDays;
    private Integer daysSinceModifiedAtWarning;

    private Map<Id, List<AR_NotificationService.DraftPurgeWarningItem>> warnedItemsByOwner = new Map<Id, List<AR_NotificationService.DraftPurgeWarningItem>>();
    private Map<Id, String> ownerEmails = new Map<Id, String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AR_General_Setting__c settings = loadSettings();
        if (settings == null || settings.AR_Draft_Purge_Enabled__c != true) {
            return Database.getQueryLocator([SELECT Id FROM AR_Price_Matrix__c WHERE Id = null]);
        }

        purgeDays = settings.AR_Draft_Purge_Days__c != null ? settings.AR_Draft_Purge_Days__c.intValue() : AR_GeneralSettingDefaults.DRAFT_PURGE_DAYS.intValue();
        warningDays = settings.AR_Draft_Purge_Warning_Days__c != null ? settings.AR_Draft_Purge_Warning_Days__c.intValue() : AR_GeneralSettingDefaults.DRAFT_PURGE_WARNING_DAYS.intValue();
        daysSinceModifiedAtWarning = purgeDays - warningDays;
        Integer maxPerRun = settings.AR_Draft_Purge_Max_Per_Run__c != null ? settings.AR_Draft_Purge_Max_Per_Run__c.intValue() : AR_GeneralSettingDefaults.DRAFT_PURGE_MAX_PER_RUN.intValue();

        Datetime warnThreshold = System.now().addDays(-daysSinceModifiedAtWarning);
        Datetime purgeThreshold = System.now().addDays(-purgeDays);
        Date warnedLongEnoughAgo = Date.today().addDays(-warningDays);

        // <= plutôt que < : un brouillon modifié exactement au moment du seuil est déjà éligible,
        // pas besoin d'attendre un tick d'horloge supplémentaire — évite aussi une dépendance
        // fragile à la résolution de Datetime dans des scénarios de test à seuil 0 jour.
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, AR_Position_Name__c, AR_Account_Name__c, CreatedDate,
                   AR_Root_Matrix__c, AR_Entity_Ref__c, AR_Entity_Ref__r.Name, AR_Position__r.TP_P_rim_tre__c,
                   LastModifiedDate, AR_Purge_Warning_Sent__c, AR_Purge_Warning_Sent_Date__c
            FROM AR_Price_Matrix__c
            WHERE AR_Status__c = 'Brouillon'
              AND (
                (AR_Purge_Warning_Sent__c = false AND LastModifiedDate <= :warnThreshold)
                OR
                (AR_Purge_Warning_Sent__c = true
                 AND AR_Purge_Warning_Sent_Date__c <= :warnedLongEnoughAgo
                 AND LastModifiedDate <= :purgeThreshold)
              )
            ORDER BY LastModifiedDate ASC
            LIMIT :maxPerRun
        ]);
    }

    public void execute(Database.BatchableContext bc, List<AR_Price_Matrix__c> scope) {
        if (scope.isEmpty()) {
            return;
        }
        Datetime purgeThreshold = System.now().addDays(-purgeDays);

        List<AR_Price_Matrix__c> toWarn = new List<AR_Price_Matrix__c>();
        List<AR_Price_Matrix__c> toPurge = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : scope) {
            if (m.AR_Purge_Warning_Sent__c == true) {
                // Re-vérification explicite et volontairement redondante (cf. commentaire de classe).
                if (m.LastModifiedDate <= purgeThreshold) {
                    toPurge.add(m);
                }
            } else {
                toWarn.add(m);
            }
        }

        AR_TriggerBypass.serviceContext = true;
        try {
            warnDrafts(toWarn);
            purgeDrafts(toPurge);
            purgePreviews();
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    private void warnDrafts(List<AR_Price_Matrix__c> toWarn) {
        if (toWarn.isEmpty()) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : toWarn) {
            ownerIds.add(m.OwnerId);
        }
        for (User u : [SELECT Id, Email FROM User WHERE Id IN :ownerIds]) {
            ownerEmails.put(u.Id, u.Email);
        }

        List<AR_Price_Matrix__c> updates = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : toWarn) {
            if (!warnedItemsByOwner.containsKey(m.OwnerId)) {
                warnedItemsByOwner.put(m.OwnerId, new List<AR_NotificationService.DraftPurgeWarningItem>());
            }
            AR_NotificationService.DraftPurgeWarningItem item = new AR_NotificationService.DraftPurgeWarningItem();
            item.matrixName = m.Name;
            item.positionName = m.AR_Position_Name__c;
            warnedItemsByOwner.get(m.OwnerId).add(item);

            updates.add(
                new AR_Price_Matrix__c(
                    Id = m.Id,
                    AR_Purge_Warning_Sent__c = true,
                    AR_Purge_Warning_Sent_Date__c = Date.today()
                )
            );
        }
        update updates;
    }

    private void purgeDrafts(List<AR_Price_Matrix__c> toPurge) {
        if (toPurge.isEmpty()) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : toPurge) {
            ownerIds.add(m.OwnerId);
        }
        Map<Id, String> ownerNames = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
            ownerNames.put(u.Id, u.Name);
        }

        List<AR_Purge_Log__c> logs = new List<AR_Purge_Log__c>();
        for (AR_Price_Matrix__c m : toPurge) {
            AR_Purge_Log__c log = new AR_Purge_Log__c();
            log.AR_Matrix_Name__c = m.Name;
            log.AR_Position_Name__c = m.AR_Position_Name__c;
            log.AR_Account_Name__c = m.AR_Account_Name__c;
            log.AR_Owner_Name__c = ownerNames.get(m.OwnerId);
            log.AR_Matrix_Created_Date__c = m.CreatedDate;
            log.AR_Owner_Id__c = String.valueOf(m.OwnerId);
            log.AR_Entity_Id__c = m.AR_Entity_Ref__c == null ? null : String.valueOf(m.AR_Entity_Ref__c);
            log.AR_Entity_Name__c = m.AR_Entity_Ref__r == null ? null : m.AR_Entity_Ref__r.Name;
            log.AR_Perimeter__c = m.AR_Position__r == null ? null : m.AR_Position__r.TP_P_rim_tre__c;
            log.AR_Was_Root__c = m.AR_Root_Matrix__c == null;
            log.AR_Purged_At__c = System.now();
            logs.add(log);
        }
        // Journalisé avant la suppression irréversible : la donnée d'origine disparaît, ce
        // journal reste. Les AR_Reason_Selection__c liées disparaissent via Cascade.
        insert logs;
        delete toPurge;
    }

    private void purgePreviews() {
        // Session 124 : aperçus PTF transitoires de plus de 24 h. Aucun avertissement, aucune trace :
        // ces enregistrements sont destinés à être supprimés après usage.
        Datetime previewThreshold = System.now().addHours(-24);
        List<AR_PTF_Preview__c> oldPreviews = [
            SELECT Id
            FROM AR_PTF_Preview__c
            WHERE CreatedDate <= :previewThreshold
        ];
        if (!oldPreviews.isEmpty()) {
            delete oldPreviews;
        }
    }

    public void finish(Database.BatchableContext bc) {
        for (Id ownerId : warnedItemsByOwner.keySet()) {
            AR_NotificationService.sendDraftPurgeWarningDigest(
                ownerEmails.get(ownerId),
                ownerId,
                warnedItemsByOwner.get(ownerId),
                daysSinceModifiedAtWarning,
                warningDays
            );
        }
    }
}