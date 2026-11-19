/**
 * Relance et escalade des dérogations en attente (session 29, exigence §6.5 :
 * prompts/session-29-relances-et-notifications.md). No-op si
 * AR_General_Setting__c.AR_Derogation_Reminder_Enabled__c != true (livré désactivé : la bascule du
 * gating en mode blocage, question 2.2 du suivi client, n'a pas été décidée).
 *
 * Modelé sur AR_DraftPurgeBatch : deux paliers dans la même exécution, jamais l'un sans l'autre pour
 * une même dérogation, état porté sur l'enregistrement (AR_Reminder_Sent__c / AR_Escalated__c) pour
 * qu'un palier ne soit jamais franchi deux fois, digest par destinataire plutôt qu'un e-mail par
 * dérogation, plafond par exécution (AR_Derogation_Reminder_Max_Per_Run__c).
 *
 * - Palier 1 (relance) : dérogation En attente, jamais relancée, jamais escaladée, demandée depuis
 *   au moins AR_Derogation_Reminder_Hours__c heures → un e-mail au valideur sélectionné.
 * - Palier 2 (escalade) : soit le délai AR_Derogation_Escalation_Hours__c est écoulé après la
 *   relance, soit le valideur sélectionné est détecté absent (User.IsActive = false, ou aucun
 *   valideur sélectionné) — ce second cas escalade immédiatement, sans attendre le délai normal.
 *
 * Escalade — **session 132** (décision d'Alexis du 02/10/2026) : par la hiérarchie du PROPRIÉTAIRE de
 * la matrice, plus par entité ni par permission. Chaîne DA → DD → Directeur
 * (`User.TP_DA__c`, `User.TP_DD__c`, `User.TP_Directeur__c` du propriétaire, lus au moment du
 * passage, jamais figés). Une seule escalade, un seul destinataire : le niveau **au-dessus** du
 * valideur choisi dans cette chaîne (valideur = DA → DD ; valideur = DD → Directeur ; valideur hors
 * chaîne, ex. Matthieu en phase de test → DA). Niveau vide ou utilisateur inactif → niveau suivant.
 * Rien au-dessus → alerte administrateur (`AR_NotificationService.sendDerogationEscalationNoRecipientsEmail`)
 * et la dérogation reste `AR_Escalated__c = false`, retentée au prochain passage.
 * **Aucune vérification de permission** sur ces personnes : c'est aux administrateurs de donner
 * `AR_Pricing_Validator` aux bonnes personnes au déploiement — l'application ne compense jamais une
 * permission manquante chez quelqu'un d'autre. Aucun nouveau champ d'état : le booléen
 * `AR_Escalated__c` suffit.
 *
 * Aucune autre information d'absence n'est disponible dans cet org (pas de champ congé/absence sur
 * User au-delà de IsActive, vérifié avant conception en session 29).
 *
 * Une fois escaladée (AR_Escalated__c = true), une dérogation ne peut plus jamais générer de relance
 * ni de seconde escalade — la garde `AR_Escalated__c = false` couvre les deux branches de la
 * requête ci-dessous, palier 1 compris : une dérogation escaladée pour absence n'a donc pas besoin
 * qu'on force artificiellement AR_Reminder_Sent__c à true, la requête l'exclut déjà. Une escalade
 * bloquée par cercle vide n'est PAS marquée `AR_Escalated__c = true` (cf. ci-dessus) : elle reste
 * éligible et sera reclassifiée au prochain passage exactement comme aujourd'hui.
 */
public class AR_DerogationReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static AR_General_Setting__c loadSettings() {
        List<AR_General_Setting__c> rows = [
            SELECT AR_Derogation_Reminder_Enabled__c, AR_Derogation_Reminder_Hours__c,
                   AR_Derogation_Escalation_Hours__c, AR_Derogation_Reminder_Max_Per_Run__c,
                   AR_Derogation_Escalation_Max_Recipients__c
            FROM AR_General_Setting__c
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private Integer reminderHours;
    private Integer escalationHours;

    private Map<String, List<AR_NotificationService.DerogationReminderItem>> reminderItemsByValidatorEmail =
        new Map<String, List<AR_NotificationService.DerogationReminderItem>>();
    private Map<String, List<AR_NotificationService.DerogationEscalationItem>> escalationItemsByRecipientEmail =
        new Map<String, List<AR_NotificationService.DerogationEscalationItem>>();
    // Id du destinataire par e-mail (session 34, notification in-app) : accumulés au même endroit
    // que les digests e-mail correspondants, jamais une seconde résolution divergente.
    private Map<String, Id> reminderValidatorIdByEmail = new Map<String, Id>();
    @TestVisible
    private Map<String, Id> escalationRecipientIdByEmail = new Map<String, Id>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AR_General_Setting__c settings = loadSettings();
        if (settings == null || settings.AR_Derogation_Reminder_Enabled__c != true) {
            return Database.getQueryLocator([SELECT Id FROM AR_Derogation__c WHERE Id = null]);
        }

        reminderHours = settings.AR_Derogation_Reminder_Hours__c != null
            ? settings.AR_Derogation_Reminder_Hours__c.intValue()
            : AR_GeneralSettingDefaults.DEROGATION_REMINDER_HOURS.intValue();
        escalationHours = settings.AR_Derogation_Escalation_Hours__c != null
            ? settings.AR_Derogation_Escalation_Hours__c.intValue()
            : AR_GeneralSettingDefaults.DEROGATION_ESCALATION_HOURS.intValue();
        Integer maxPerRun = settings.AR_Derogation_Reminder_Max_Per_Run__c != null
            ? settings.AR_Derogation_Reminder_Max_Per_Run__c.intValue()
            : AR_GeneralSettingDefaults.DEROGATION_REMINDER_MAX_PER_RUN.intValue();

        Datetime reminderThreshold = System.now().addHours(-reminderHours);
        Datetime escalationThreshold = System.now().addHours(-escalationHours);

        // <= plutôt que < : mêmes raisons que AR_DraftPurgeBatch (seuil atteint = déjà éligible).
        return Database.getQueryLocator([
            SELECT Id, AR_Requested_At__c, AR_Reminder_Sent__c, AR_Escalated__c,
                   AR_Price_Matrix__c, AR_Price_Matrix__r.Name, AR_Price_Matrix__r.AR_Position_Name__c,
                   AR_Price_Matrix__r.AR_Entity_Ref__r.Name, AR_Price_Matrix__r.OwnerId,
                   AR_Selected_Validator__c, AR_Selected_Validator__r.Name, AR_Selected_Validator__r.Email,
                   AR_Selected_Validator__r.IsActive, CreatedById
            FROM AR_Derogation__c
            WHERE AR_Decision__c = 'En attente'
              AND (
                (AR_Reminder_Sent__c = false AND AR_Escalated__c = false AND AR_Requested_At__c <= :reminderThreshold)
                OR
                (AR_Escalated__c = false AND AR_Reminder_Sent__c = true AND AR_Requested_At__c <= :escalationThreshold)
                OR
                (AR_Escalated__c = false AND AR_Selected_Validator__r.IsActive = false)
                OR
                (AR_Escalated__c = false AND AR_Selected_Validator__c = null)
              )
            ORDER BY AR_Requested_At__c ASC
            LIMIT :maxPerRun
        ]);
    }

    public void execute(Database.BatchableContext bc, List<AR_Derogation__c> scope) {
        if (scope.isEmpty()) {
            return;
        }
        Datetime escalationThreshold = System.now().addHours(-escalationHours);
        List<AR_Derogation__c> toRemind = new List<AR_Derogation__c>();
        List<AR_Derogation__c> escalationCandidates = new List<AR_Derogation__c>();
        List<Boolean> escalationCandidateAbsentFlags = new List<Boolean>();
        Set<Id> ownerIds = new Set<Id>();

        for (AR_Derogation__c d : scope) {
            // « Absent » = aucun valideur choisi ou valideur désactivé. Jamais de contrôle de
            // permission (session 132) : un valideur actif mais sans AR_Approve_Derogation n'est pas
            // « absent », c'est un défaut de déploiement des permissions.
            Boolean validatorAbsent = d.AR_Selected_Validator__c == null
                || d.AR_Selected_Validator__r.IsActive != true;
            Boolean escalationDelayPassed = d.AR_Reminder_Sent__c == true && d.AR_Requested_At__c <= escalationThreshold;

            if (validatorAbsent || escalationDelayPassed) {
                escalationCandidates.add(d);
                escalationCandidateAbsentFlags.add(validatorAbsent);
                if (d.AR_Price_Matrix__r.OwnerId != null) {
                    ownerIds.add(d.AR_Price_Matrix__r.OwnerId);
                }
            } else if (d.AR_Reminder_Sent__c != true) {
                remind(d);
                toRemind.add(
                    new AR_Derogation__c(Id = d.Id, AR_Reminder_Sent__c = true, AR_Reminder_Sent_Date__c = System.now())
                );
            }
        }

        Map<Id, User> ownersById = loadOwnersWithHierarchy(ownerIds);

        List<AR_Derogation__c> toEscalate = new List<AR_Derogation__c>();
        for (Integer i = 0; i < escalationCandidates.size(); i++) {
            AR_Derogation__c d = escalationCandidates[i];
            Boolean validatorAbsent = escalationCandidateAbsentFlags[i];
            if (!escalate(d, ownersById.get(d.AR_Price_Matrix__r.OwnerId))) {
                continue;
            }
            toEscalate.add(
                new AR_Derogation__c(
                    Id = d.Id,
                    AR_Escalated__c = true,
                    AR_Escalated_Date__c = System.now(),
                    AR_Escalation_Reason__c = validatorAbsent ? 'Valideur absent' : 'Délai dépassé'
                )
            );
        }

        AR_TriggerBypass.serviceContext = true;
        try {
            if (!toRemind.isEmpty()) {
                update toRemind;
            }
            if (!toEscalate.isEmpty()) {
                update toEscalate;
            }
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    /** Propriétaires des matrices avec leur hiérarchie (DA/DD/Directeur) et les e-mails/état actif de
     * chaque niveau, en une seule requête par chunk — lus au moment du passage, jamais figés. */
    public static Map<Id, User> loadOwnersWithHierarchy(Set<Id> ownerIds) {
        if (ownerIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Id, Email, TP_DA__c, TP_DA__r.Email, TP_DA__r.IsActive,
                   TP_DD__c, TP_DD__r.Email, TP_DD__r.IsActive,
                   TP_Directeur__c, TP_Directeur__r.Email, TP_Directeur__r.IsActive
            FROM User
            WHERE Id IN :ownerIds
        ]);
    }

    /** Niveaux de la chaîne dans l'ordre DA → DD → Directeur (null pour un niveau vide). */
    private static List<User> hierarchyChain(User owner) {
        return AR_ValidatorChain.levels(owner);
    }

    /**
     * Destinataire de l'escalade : premier niveau de la chaîne du propriétaire situé AU-DESSUS du
     * valideur choisi (valideur hors chaîne → on part du DA). Un niveau vide, sans e-mail, inactif,
     * ou qui est le valideur lui-même est sauté. Null si rien au-dessus. public static pour rester
     * testable directement.
     */
    public static User escalationTarget(User owner, Id selectedValidatorId) {
        return escalationTarget(owner, selectedValidatorId, null);
    }

    /** Idem, en sautant aussi le demandeur et le propriétaire : ils ne traitent pas leur propre demande. */
    public static User escalationTarget(User owner, Id selectedValidatorId, Id requesterId) {
        if (owner == null) {
            return null;
        }
        List<User> chain = hierarchyChain(owner);
        Integer start = 0;
        for (Integer i = 0; i < chain.size(); i++) {
            if (chain[i] != null && selectedValidatorId != null && chain[i].Id == selectedValidatorId) {
                start = i + 1;
            }
        }
        for (Integer i = start; i < chain.size(); i++) {
            User level = chain[i];
            if (level != null && level.IsActive == true && String.isNotBlank(level.Email) && level.Id != selectedValidatorId
                && level.Id != requesterId && level.Id != owner.Id) {
                return level;
            }
        }
        return null;
    }

    /**
     * Session 147 : destinataire des notifications informatives à la hiérarchie (digest des
     * validations automatiques, avertissement de gating) — même chaîne DA → DD → Directeur du
     * propriétaire que l'escalade, même résolution (`escalationTarget`), jamais `User.ManagerId`
     * (vide pour les 351 utilisateurs actifs de la sandbox). Le propriétaire est traité comme un
     * valideur de la chaîne : s'il en occupe un niveau, on part du niveau au-dessus ; sinon du DA.
     * Null si rien n'est résolvable — l'appelant journalise (jamais d'échec silencieux).
     */
    public static User hierarchyTarget(User owner) {
        return owner == null ? null : escalationTarget(owner, owner.Id);
    }

    private void remind(AR_Derogation__c d) {
        if (d.AR_Selected_Validator__r == null || String.isBlank(d.AR_Selected_Validator__r.Email)) {
            return;
        }
        String email = d.AR_Selected_Validator__r.Email;
        if (!reminderItemsByValidatorEmail.containsKey(email)) {
            reminderItemsByValidatorEmail.put(email, new List<AR_NotificationService.DerogationReminderItem>());
        }
        reminderValidatorIdByEmail.put(email, d.AR_Selected_Validator__c);
        AR_NotificationService.DerogationReminderItem item = new AR_NotificationService.DerogationReminderItem();
        item.matrixName = d.AR_Price_Matrix__r.Name;
        item.positionName = d.AR_Price_Matrix__r.AR_Position_Name__c;
        item.hoursWaiting = hoursSince(d.AR_Requested_At__c);
        reminderItemsByValidatorEmail.get(email).add(item);
    }

    /**
     * Retourne true si l'escalade a trouvé un destinataire (l'appelant marque alors
     * AR_Escalated__c = true) ; false si rien n'existe au-dessus du valideur dans la chaîne du
     * propriétaire — l'alerte administrateur est déjà partie, l'appelant ne doit rien marquer, la
     * dérogation reste éligible au prochain passage.
     */
    private Boolean escalate(AR_Derogation__c d, User owner) {
        User target = escalationTarget(owner, d.AR_Selected_Validator__c, d.CreatedById);
        if (target == null) {
            AR_NotificationService.sendDerogationEscalationNoRecipientsEmail(
                d.AR_Price_Matrix__r.Name,
                d.AR_Price_Matrix__r.AR_Position_Name__c,
                d.AR_Price_Matrix__r.AR_Entity_Ref__r == null ? null : d.AR_Price_Matrix__r.AR_Entity_Ref__r.Name
            );
            return false;
        }

        AR_NotificationService.DerogationEscalationItem item = new AR_NotificationService.DerogationEscalationItem();
        item.matrixName = d.AR_Price_Matrix__r.Name;
        item.positionName = d.AR_Price_Matrix__r.AR_Position_Name__c;
        item.hoursWaiting = hoursSince(d.AR_Requested_At__c);
        item.selectedValidatorName = d.AR_Selected_Validator__r != null ? d.AR_Selected_Validator__r.Name : Label.AR_Msg_NTF_NoValidatorSelected;

        if (!escalationItemsByRecipientEmail.containsKey(target.Email)) {
            escalationItemsByRecipientEmail.put(target.Email, new List<AR_NotificationService.DerogationEscalationItem>());
        }
        escalationItemsByRecipientEmail.get(target.Email).add(item);
        escalationRecipientIdByEmail.put(target.Email, target.Id);
        return true;
    }

    private Integer hoursSince(Datetime requestedAt) {
        Long millis = System.now().getTime() - requestedAt.getTime();
        return (Integer) (millis / (1000 * 60 * 60));
    }

    public void finish(Database.BatchableContext bc) {
        for (String email : reminderItemsByValidatorEmail.keySet()) {
            AR_NotificationService.sendDerogationReminderDigest(
                email,
                reminderValidatorIdByEmail.get(email),
                reminderItemsByValidatorEmail.get(email),
                reminderHours
            );
        }
        for (String email : escalationItemsByRecipientEmail.keySet()) {
            AR_NotificationService.sendDerogationEscalationDigest(
                email,
                escalationRecipientIdByEmail.get(email),
                escalationItemsByRecipientEmail.get(email),
                escalationHours
            );
        }
    }
}