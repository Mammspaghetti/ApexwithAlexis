/**
 * Notification informative à la hiérarchie sur validation automatique (session 29, question 2.3 du
 * suivi client du 10/08/2026 : prompts/session-29-relances-et-notifications.md §4). Couvre les
 * fréquences Quotidien et Hebdomadaire de AR_General_Setting__c.AR_Hierarchy_Notification_Frequency__c
 * — la fréquence Immédiat est traitée synchrone par
 * AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate, appelée directement
 * depuis AR_PricingMatrixService.validateInput, ce batch ne la retouche jamais.
 *
 * Destinataire (session 147) : premier niveau actif de la chaîne DA → DD → Directeur du propriétaire
 * (AR_DerogationReminderBatch.hierarchyTarget), plus User.ManagerId.
 *
 * Portée strictement les matrices AR_Status__c = 'Validée' (validation automatique, MC2 ≥ plancher) —
 * jamais 'Validée par dérogation', qui a déjà son propre e-mail de résultat de dérogation.
 * AR_Hierarchy_Notified__c porte l'état, même principe qu'AR_Purge_Warning_Sent__c : une matrice
 * notifiée (immédiat ou batch) ne l'est jamais deux fois, quel que soit un changement ultérieur de
 * fréquence.
 *
 * Pas de plafond par exécution (contrairement à AR_DraftPurgeBatch/AR_DerogationReminderBatch) :
 * le volume est celui des validations automatiques du jour/de la semaine, pas un stock pouvant
 * s'accumuler indéfiniment côté serveur (aucune suppression ni email individuel massif possible ici,
 * le digest est par manager) — cf. docs/29-relances-et-notifications.md §4.
 */
public class AR_HierarchyNotificationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static AR_General_Setting__c loadSettings() {
        List<AR_General_Setting__c> rows = [
            SELECT AR_Hierarchy_Notification_Frequency__c
            FROM AR_General_Setting__c
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private Map<String, List<AR_NotificationService.HierarchyValidationItem>> itemsByManagerEmail =
        new Map<String, List<AR_NotificationService.HierarchyValidationItem>>();
    // Id du manager par e-mail (session 34, notification in-app) : accumulé au même endroit que le
    // digest e-mail, jamais une seconde résolution divergente.
    private Map<String, Id> managerIdByEmail = new Map<String, Id>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AR_General_Setting__c settings = loadSettings();
        String frequency = settings == null ? null : settings.AR_Hierarchy_Notification_Frequency__c;

        Boolean noOp = frequency == null
            || frequency == 'Désactivé'
            || frequency == 'Immédiat'
            || (frequency == 'Hebdomadaire' && !isWeeklyDispatchDay());
        if (noOp) {
            return Database.getQueryLocator([SELECT Id FROM AR_Price_Matrix__c WHERE Id = null]);
        }

        return Database.getQueryLocator([
            SELECT Id, Name, AR_Position_Name__c, OwnerId, Owner.Name
            FROM AR_Price_Matrix__c
            WHERE AR_Status__c = 'Validée' AND AR_Hierarchy_Notified__c = false
            ORDER BY AR_Validated_At__c ASC
        ]);
    }

    /** Jour d'envoi hebdomadaire : lundi (jour ISO 1). Les matrices validées en cours de semaine
     * s'accumulent (AR_Hierarchy_Notified__c reste false) jusqu'à ce jour, sans e-mail entre-temps.
     * Le jour réel n'est pas maîtrisable depuis un test (pas d'équivalent Test.setCreatedDate pour
     * Datetime.now()) : testOverrideIsWeeklyDispatchDay permet de forcer les deux branches. */
    @TestVisible
    private static Boolean testOverrideIsWeeklyDispatchDay = null;

    @TestVisible
    private static Boolean isWeeklyDispatchDay() {
        return testOverrideIsWeeklyDispatchDay != null
            ? testOverrideIsWeeklyDispatchDay
            : Datetime.now().format('u') == '1';
    }

    public void execute(Database.BatchableContext bc, List<AR_Price_Matrix__c> scope) {
        if (scope.isEmpty()) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : scope) {
            ownerIds.add(m.OwnerId);
        }
        // Session 147 : chaîne DA → DD → Directeur du propriétaire (même résolution que l'escalade des
        // relances), plus User.ManagerId — vide pour tous les utilisateurs actifs de la sandbox.
        Map<Id, User> ownersById = AR_DerogationReminderBatch.loadOwnersWithHierarchy(ownerIds);

        List<AR_Price_Matrix__c> toMarkNotified = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : scope) {
            User target = AR_DerogationReminderBatch.hierarchyTarget(ownersById.get(m.OwnerId));
            if (target != null) {
                String managerEmail = target.Email;
                if (!itemsByManagerEmail.containsKey(managerEmail)) {
                    itemsByManagerEmail.put(managerEmail, new List<AR_NotificationService.HierarchyValidationItem>());
                }
                managerIdByEmail.put(managerEmail, target.Id);
                AR_NotificationService.HierarchyValidationItem item = new AR_NotificationService.HierarchyValidationItem();
                item.matrixName = m.Name;
                item.positionName = m.AR_Position_Name__c;
                item.ownerName = m.Owner.Name;
                itemsByManagerEmail.get(managerEmail).add(item);
            } else {
                System.debug(
                    LoggingLevel.WARN,
                    'AR_HierarchyNotificationBatch: aucun DA/DD/Directeur actif pour le propriétaire de ' + m.Name +
                    ' (' + m.Owner.Name + ') — notification hiérarchie non envoyée.'
                );
            }
            // Marquée notifiée que le destinataire existe ou non : sans destinataire résolu, il n'y a rien à
            // envoyer, mais la matrice ne doit pas rester indéfiniment dans le champ de balayage.
            toMarkNotified.add(new AR_Price_Matrix__c(Id = m.Id, AR_Hierarchy_Notified__c = true));
        }

        AR_TriggerBypass.serviceContext = true;
        try {
            update toMarkNotified;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    public void finish(Database.BatchableContext bc) {
        for (String managerEmail : itemsByManagerEmail.keySet()) {
            AR_NotificationService.sendHierarchyNotificationDigest(
                managerEmail,
                managerIdByEmail.get(managerEmail),
                itemsByManagerEmail.get(managerEmail)
            );
        }
    }
}