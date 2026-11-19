/**
 * Gating qualification (session 21b) : empêche un besoin sans matrice de prix validée d'avancer un
 * candidat à l'étape de qualification. Politique unique et paramétrable (AR_Gating_Setting__mdt) —
 * cette classe ne distingue jamais elle-même "avertir" de "bloquer" au-delà d'un seul addError,
 * toute la logique de sévérité vit dans AR_QualificationGatingEvaluator.
 *
 * Ne se déclenche que sur la TRANSITION vers le statut "2. Qualification en cours" (référencé par Id,
 * jamais par libellé — cf. docs/21-gating.md §3, d'autres libellés de cxsrec__cxsWorkflow_status__c
 * ne sont pas uniques). Périmètre : besoins de record type Vacancy uniquement (docs/21-gating.md §4),
 * codé en dur ici car c'est un fait de structure de données, pas un paramètre métier.
 */
public class AR_QualificationGatingHandler {

    private static final String IN_SCOPE_RECORD_TYPE = 'Vacancy';

    private static Boolean configErrorAlerted = false;

    /**
     * DML sur les enregistrements de custom metadata n'est pas autorisée dans cet org, même en
     * contexte de test (constaté à l'implémentation) — les tests substituent la politique via ce
     * point d'extension plutôt que de modifier AR_Gating_Setting__mdt.Default.
     */
    @TestVisible
    private static AR_Gating_Setting__mdt testOverrideSettings = null;

    public static void beforeSave(
        List<cxsrec__cxsJob_application__c> newRecords,
        Map<Id, cxsrec__cxsJob_application__c> oldMap
    ) {
        AR_Gating_Setting__mdt settings = testOverrideSettings != null
            ? testOverrideSettings
            : AR_Gating_Setting__mdt.getInstance('Default');
        if (settings == null || !settings.AR_Gating_Enabled__c) {
            return;
        }
        if (FeatureManagement.checkPermission('AR_Bypass_Qualification_Gating')) {
            return;
        }

        String targetStatusId = settings.AR_Qualification_Status_Id__c;
        alertIfStatusReferenceUnresolvable(targetStatusId);

        List<cxsrec__cxsJob_application__c> transitioning = new List<cxsrec__cxsJob_application__c>();
        for (cxsrec__cxsJob_application__c newRecord : newRecords) {
            cxsrec__cxsJob_application__c oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            String previousStatus = oldRecord == null ? null : oldRecord.cxsrec__Workflow_status__c;
            if (previousStatus != targetStatusId && newRecord.cxsrec__Workflow_status__c == targetStatusId) {
                transitioning.add(newRecord);
            }
        }
        if (transitioning.isEmpty()) {
            return;
        }

        Set<Id> positionIds = new Set<Id>();
        for (cxsrec__cxsJob_application__c record : transitioning) {
            if (record.cxsrec__Position__c != null) {
                positionIds.add(record.cxsrec__Position__c);
            }
        }
        Map<Id, cxsrec__cxsPosition__c> positionsById = new Map<Id, cxsrec__cxsPosition__c>([
            SELECT Id, Name, RecordType.DeveloperName, cxsrec__Country__c, OwnerId, CreatedDate
            FROM cxsrec__cxsPosition__c
            WHERE Id IN :positionIds
        ]);

        Map<Id, List<AR_Price_Matrix__c>> matricesByPosition = new Map<Id, List<AR_Price_Matrix__c>>();
        for (AR_Price_Matrix__c matrix : [
            SELECT Id, AR_Position__c, AR_Status__c
            FROM AR_Price_Matrix__c
            WHERE AR_Position__c IN :positionIds
        ]) {
            if (!matricesByPosition.containsKey(matrix.AR_Position__c)) {
                matricesByPosition.put(matrix.AR_Position__c, new List<AR_Price_Matrix__c>());
            }
            matricesByPosition.get(matrix.AR_Position__c).add(matrix);
        }

        Set<Id> ownerIds = new Set<Id>();
        for (cxsrec__cxsPosition__c position : positionsById.values()) {
            if (position.OwnerId != null) {
                ownerIds.add(position.OwnerId);
            }
        }
        // Session 147 : le « manager » de l'avertissement est le premier niveau actif de la chaîne
        // DA → DD → Directeur du propriétaire (User.ManagerId est vide pour tous les utilisateurs).
        Map<Id, User> ownersById = AR_DerogationReminderBatch.loadOwnersWithHierarchy(ownerIds);

        Set<String> excludedCountries = parseExcludedCountries(settings.AR_Excluded_Countries__c);
        List<AR_NotificationService.GatingWarningNotice> warningNotices = new List<AR_NotificationService.GatingWarningNotice>();

        for (cxsrec__cxsJob_application__c record : transitioning) {
            cxsrec__cxsPosition__c position = positionsById.get(record.cxsrec__Position__c);
            if (position == null || position.RecordType.DeveloperName != IN_SCOPE_RECORD_TYPE) {
                continue;
            }
            if (excludedCountries.contains(position.cxsrec__Country__c)) {
                continue;
            }

            List<AR_Price_Matrix__c> matrices = matricesByPosition.containsKey(position.Id)
                ? matricesByPosition.get(position.Id)
                : new List<AR_Price_Matrix__c>();
            AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
                position,
                matrices,
                settings,
                Date.today()
            );

            User owner = ownersById.get(position.OwnerId);

            if (decision.blocked) {
                record.addError(Label.AR_Gating_Blocking_Message);
                continue;
            }

            record.AR_Gating_Case__c = caseLabel(decision.matchedCase);
            record.AR_Gating_Severity__c = severityLabel(decision.appliedSeverity);
            record.AR_Gating_Evaluated_Date__c = Date.today();
            record.AR_Gating_Country__c = position.cxsrec__Country__c;

            if (decision.appliedSeverity == AR_QualificationGatingEvaluator.Severity.WARNING && owner != null) {
                AR_NotificationService.GatingWarningNotice notice = new AR_NotificationService.GatingWarningNotice();
                User manager = AR_DerogationReminderBatch.hierarchyTarget(owner);
                notice.ownerEmail = owner.Email;
                notice.ownerId = owner.Id;
                notice.managerEmail = manager != null ? manager.Email : null;
                notice.managerId = manager != null ? manager.Id : null;
                notice.jobApplicationName = record.Name;
                notice.positionName = position.Name;
                notice.caseLabel = caseLabel(decision.matchedCase);
                warningNotices.add(notice);
            }
        }

        if (!warningNotices.isEmpty()) {
            AR_NotificationService.sendGatingWarningEmail(warningNotices);
        }
    }

    /**
     * Vérifie une fois par transaction que la référence de statut configurée résout vers un
     * enregistrement réel. Introuvable ⇒ alerte visible (email + debug ERROR), jamais un `if` qui ne
     * se déclenche jamais en silence. Le gating continue malgré tout avec l'Id brut : une erreur de
     * configuration ne doit jamais bloquer la qualification (cf. docs/21-gating.md §3).
     */
    private static void alertIfStatusReferenceUnresolvable(String targetStatusId) {
        if (configErrorAlerted) {
            return;
        }
        Boolean resolvable = String.isNotBlank(targetStatusId)
            && !new List<cxsrec__cxsWorkflow_status__c>([
                SELECT Id FROM cxsrec__cxsWorkflow_status__c WHERE Id = :targetStatusId LIMIT 1
            ]).isEmpty();
        if (!resolvable) {
            configErrorAlerted = true;
            System.debug(
                LoggingLevel.ERROR,
                'AR_QualificationGatingHandler: AR_Gating_Setting__mdt.Default.AR_Qualification_Status_Id__c ' +
                'ne résout vers aucun cxsrec__cxsWorkflow_status__c existant (valeur : ' + targetStatusId + ').'
            );
            AR_NotificationService.sendGatingConfigErrorEmail(targetStatusId);
        }
    }

    private static Set<String> parseExcludedCountries(String rawValue) {
        Set<String> excluded = new Set<String>();
        if (String.isBlank(rawValue)) {
            return excluded;
        }
        for (String country : rawValue.split(';')) {
            if (String.isNotBlank(country)) {
                excluded.add(country.trim());
            }
        }
        return excluded;
    }

    private static String caseLabel(AR_QualificationGatingEvaluator.GatingCase matchedCase) {
        switch on matchedCase {
            when CONFORME { return 'Conforme'; }
            when DEROGATION_PENDING { return 'Dérogation en attente'; }
            when else { return 'Sans matrice validée'; }
        }
    }

    private static String severityLabel(AR_QualificationGatingEvaluator.Severity severityValue) {
        return severityValue == AR_QualificationGatingEvaluator.Severity.WARNING ? 'Avertissement' : 'Ignoré';
    }
}