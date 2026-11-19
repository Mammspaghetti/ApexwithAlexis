/**
 * Catalogue des motifs standardisés (AR_Reason__c), partagé entre la dérogation et le changement
 * de version (cf. CLAUDE.md décisions client 10/08/2026 : fin de la saisie libre, liste
 * administrable et cumulative). `with sharing` : AR_Reason__c a un sharingModel Read, visible de
 * tout utilisateur du Pricing Tool.
 */
public with sharing class AR_ReasonService {

    public class ReasonOption {
        @AuraEnabled
        public Id reasonId;
        @AuraEnabled
        public String label;
    }

    /**
     * @param usage 'derogation' ou 'version' — filtre sur le flag applicable du catalogue.
     */
    @AuraEnabled(cacheable=true)
    public static List<ReasonOption> getReasonOptions(String usage) {
        List<ReasonOption> options = new List<ReasonOption>();
        String query = 'SELECT Id, Name FROM AR_Reason__c WHERE AR_Active__c = true';
        if (usage == 'derogation') {
            query += ' AND AR_Applies_To_Derogation__c = true';
        } else if (usage == 'version') {
            query += ' AND AR_Applies_To_Version__c = true';
        } else {
            throw new AuraHandledException(AR_I18n.format(Label.AR_Msg_RSN_UnknownUsage, new List<Object>{ usage }));
        }
        query += ' ORDER BY AR_Sort_Order__c ASC NULLS LAST, Name ASC';

        for (AR_Reason__c r : Database.query(query)) {
            ReasonOption opt = new ReasonOption();
            opt.reasonId = r.Id;
            opt.label = r.Name;
            options.add(opt);
        }
        return options;
    }

    public class ReasonAdminDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean appliesToDerogation;
        @AuraEnabled public Boolean appliesToVersion;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal sortOrder;
    }

    /** Page d'administration, domaine Référentiels (session 23, redécoupé session 42) : liste
     * complète y compris les motifs désactivés — la liste consommée par getReasonOptions() ne
     * montre jamais les inactifs, l'admin doit pouvoir les retrouver pour les réactiver ou vérifier
     * ce qui a été retiré. */
    @AuraEnabled
    public static List<ReasonAdminDto> getAllReasonsForAdmin() {
        AR_AdminAccessGuard.requireReferentials();
        List<ReasonAdminDto> options = new List<ReasonAdminDto>();
        for (AR_Reason__c r : [
            SELECT Id, Name, AR_Applies_To_Derogation__c, AR_Applies_To_Version__c, AR_Active__c, AR_Sort_Order__c
            FROM AR_Reason__c
            ORDER BY AR_Sort_Order__c ASC NULLS LAST, Name ASC
        ]) {
            ReasonAdminDto dto = new ReasonAdminDto();
            dto.id = r.Id;
            dto.label = r.Name;
            dto.appliesToDerogation = r.AR_Applies_To_Derogation__c;
            dto.appliesToVersion = r.AR_Applies_To_Version__c;
            dto.active = r.AR_Active__c;
            dto.sortOrder = r.AR_Sort_Order__c;
            options.add(dto);
        }
        return options;
    }

    @AuraEnabled
    public static Id saveReason(
        Id recordId,
        String label,
        Boolean appliesToDerogation,
        Boolean appliesToVersion,
        Boolean active,
        Decimal sortOrder
    ) {
        AR_AdminAccessGuard.requireReferentials();
        if (String.isBlank(label)) {
            throw new AuraHandledException(System.Label.AR_Msg_RSN_LabelRequired);
        }
        try {
            AR_Reason__c record = recordId != null ? new AR_Reason__c(Id = recordId) : new AR_Reason__c();
            record.Name = label;
            record.AR_Applies_To_Derogation__c = appliesToDerogation != null ? appliesToDerogation : false;
            record.AR_Applies_To_Version__c = appliesToVersion != null ? appliesToVersion : false;
            record.AR_Active__c = active != null ? active : true;
            record.AR_Sort_Order__c = sortOrder;
            // Session 100 : la vérification d'habilitation vient en premier (requireReferentials),
            // la Custom Permission AR_Admin_Referentials est l'autorité — seule elle gouverne l'accès.
            // CRUD/FLS ne contournent pas partage (AR_Reason__c a un sharingModel Read, non un
            // enjeu ici), seuls CRUD/FLS sont contournés. Même bypass que insertSelections et autres
            // objets de traçabilité du module.
            Database.upsert(record, AccessLevel.SYSTEM_MODE);
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, System.Label.AR_Msg_RSN_SaveAction);
        }
    }

    /**
     * Insère une ligne AR_Reason_Selection__c par motif, liée soit à une matrice, soit à une
     * dérogation (jamais les deux — cf. AR_ReasonSelectionTriggerHandler.beforeInsert qui
     * applique le même contrôle XOR côté serveur). Utilisé par AR_MatrixChainService et
     * AR_PricingMatrixService.requestDerogationInput.
     */
    public static void insertSelections(Id matrixId, Id derogationId, List<Id> reasonIds) {
        if (reasonIds == null || reasonIds.isEmpty()) {
            return;
        }
        List<AR_Reason_Selection__c> rows = new List<AR_Reason_Selection__c>();
        for (Id reasonId : reasonIds) {
            AR_Reason_Selection__c row = new AR_Reason_Selection__c();
            row.AR_Price_Matrix__c = matrixId;
            row.AR_Derogation__c = derogationId;
            row.AR_Reason__c = reasonId;
            rows.add(row);
        }
        // Session 41 : aucun permission set n'accorde allowCreate sur AR_Reason_Selection__c (objet
        // de traçabilité, jamais édité directement par l'utilisateur — cf. CLAUDE.md, décision
        // client 10/08/2026, fin de la saisie libre) — un BM réel obtenait
        // `DML operation INSERT not allowed on AR_Reason_Selection__c`, jamais vu avant cette session
        // (ni AR_PricingMatrixService.requestDerogationInput ni AR_MatrixChainService.duplicateMatrix
        // n'avaient été exercés sous System.runAs pour un non-administrateur). Même bypass que les
        // autres objets système de ce module (AR_Matrix_Version__c, AR_PTF_Document__c) : le partage
        // reste gouverné par la classe appelante (`with sharing`), seuls CRUD/FLS sont contournés ici.
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }
}