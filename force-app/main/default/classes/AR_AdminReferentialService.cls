/**
 * Administration des référentiels tarifaires déjà livrés (objets existants, écran manquant
 * jusqu'à cette session) : corridors par grand compte, indemnité VIE et CJM Nearshore par pays.
 * La majorité de la classe relève du domaine « Référentiels » (session 42, fourre-tout délibéré) :
 * `AR_AdminAccessGuard.requireReferentials()` en tête de chaque méthode. Les entités PTF (session 46)
 * font exception, domaine séparé : `AR_AdminAccessGuard.requirePtfEntities()`.
 */
public with sharing class AR_AdminReferentialService {

    public class AccountOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String label;
        /** Session 279 : ville de facturation, à défaut de livraison (null si aucune) — pour
         * distinguer les homonymes (filiales, sites). Affichée en style secondaire par les LWC. */
        @AuraEnabled public String city;
    }

    /** Session 279 : ville de facturation, à défaut ville de livraison ; null si aucune. */
    @TestVisible
    private static String accountCity(Account a) {
        if (String.isNotBlank(a.BillingCity)) {
            return a.BillingCity.trim();
        }
        if (String.isNotBlank(a.ShippingCity)) {
            return a.ShippingCity.trim();
        }
        return null;
    }

    /** Recherche de compte pour cibler un corridor ou une donnée commerciale — même contrat que
     * AR_PricingMatrixService.searchPositions (2 caractères minimum, 20 résultats max).
     * Account.Name est un champ standard obligatoire : aucune fieldPermissions explicite n'est
     * déployable dessus (Metadata API refuse, même piège que AR_Account_Commercial_Data__c.
     * AR_Account__c, cf. CLAUDE.md) — l'accès dépend de l'objectPermissions (Read) accordé par
     * AR_Admin_Referentials, sans FLS de champ dédiée possible. */
    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchAccounts(String searchTerm) {
        AR_AdminAccessGuard.requireReferentials();
        List<AccountOption> options = new List<AccountOption>();
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return options;
        }
        String likeTerm = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        for (Account a : [SELECT Id, Name, BillingCity, ShippingCity FROM Account WHERE Name LIKE :likeTerm ORDER BY Name LIMIT 20]) {
            AccountOption opt = new AccountOption();
            opt.accountId = a.Id;
            opt.label = a.Name;
            opt.city = accountCity(a);
            options.add(opt);
        }
        return options;
    }

    // ---------------------------------------------------------------------
    // Corridors grands comptes
    // ---------------------------------------------------------------------

    public class CorridorDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal floorPercent;
        @AuraEnabled public Decimal targetPercent;
        @AuraEnabled public Decimal idealPercent;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    @AuraEnabled
    public static List<CorridorDto> getCorridors() {
        AR_AdminAccessGuard.requireReferentials();
        List<CorridorDto> options = new List<CorridorDto>();
        for (AR_Account_Corridor__c c : [
            SELECT Id, AR_Account__c, AR_Account__r.Name, AR_Floor_Percent__c, AR_Target_Percent__c,
                   AR_Ideal_Percent__c, LastModifiedDate, LastModifiedBy.Name
            FROM AR_Account_Corridor__c
            ORDER BY AR_Account__r.Name
        ]) {
            CorridorDto dto = new CorridorDto();
            dto.id = c.Id;
            dto.accountId = c.AR_Account__c;
            dto.accountName = c.AR_Account__r.Name;
            dto.floorPercent = c.AR_Floor_Percent__c;
            dto.targetPercent = c.AR_Target_Percent__c;
            dto.idealPercent = c.AR_Ideal_Percent__c;
            dto.lastModifiedDate = c.LastModifiedDate;
            dto.lastModifiedByName = c.LastModifiedBy.Name;
            options.add(dto);
        }
        return options;
    }

    @AuraEnabled
    public static Id saveCorridor(
        Id recordId,
        Id accountId,
        Decimal floorPercent,
        Decimal targetPercent,
        Decimal idealPercent
    ) {
        AR_AdminAccessGuard.requireReferentials();
        if (accountId == null || floorPercent == null || targetPercent == null || idealPercent == null) {
            throw newAuraException(Label.AR_Msg_ADM_AccountAndThresholdsRequired);
        }
        if (floorPercent > targetPercent || targetPercent > idealPercent) {
            throw newAuraException(Label.AR_Msg_ADM_ThresholdsOrder);
        }
        try {
            AR_Account_Corridor__c record = recordId != null
                ? new AR_Account_Corridor__c(Id = recordId)
                : new AR_Account_Corridor__c();
            record.AR_Account__c = accountId;
            record.AR_Floor_Percent__c = floorPercent;
            record.AR_Target_Percent__c = targetPercent;
            record.AR_Ideal_Percent__c = idealPercent;
            upsert record;
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveCorridorAction);
        }
    }

    @AuraEnabled
    public static void deleteCorridor(Id recordId) {
        AR_AdminAccessGuard.requireReferentials();
        try {
            delete new AR_Account_Corridor__c(Id = recordId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_DeleteCorridorAction);
        }
    }

    // ---------------------------------------------------------------------
    // Référentiel VIE
    // ---------------------------------------------------------------------

    public class VieReferentialDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String country;
        @AuraEnabled public Decimal dailyAllowance;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    @AuraEnabled
    public static List<VieReferentialDto> getVieReferentials() {
        AR_AdminAccessGuard.requireReferentials();
        List<VieReferentialDto> options = new List<VieReferentialDto>();
        for (AR_VIE_Referential__c r : [
            SELECT Id, Name, AR_Daily_Allowance__c, AR_Currency__c, LastModifiedDate, LastModifiedBy.Name
            FROM AR_VIE_Referential__c
            ORDER BY Name
        ]) {
            VieReferentialDto dto = new VieReferentialDto();
            dto.id = r.Id;
            dto.country = r.Name;
            dto.dailyAllowance = r.AR_Daily_Allowance__c;
            dto.currencyCode = String.isNotBlank(r.AR_Currency__c) ? r.AR_Currency__c : 'EUR';
            dto.lastModifiedDate = r.LastModifiedDate;
            dto.lastModifiedByName = r.LastModifiedBy.Name;
            options.add(dto);
        }
        return options;
    }

    @AuraEnabled
    public static Id saveVieReferential(Id recordId, String country, Decimal dailyAllowance, String currencyCode) {
        AR_AdminAccessGuard.requireReferentials();
        if (String.isBlank(country) || dailyAllowance == null) {
            throw newAuraException(Label.AR_Msg_ADM_CountryAndAllowanceRequired);
        }
        try {
            AR_VIE_Referential__c record = recordId != null
                ? new AR_VIE_Referential__c(Id = recordId)
                : new AR_VIE_Referential__c();
            record.Name = country;
            record.AR_Daily_Allowance__c = dailyAllowance;
            record.AR_Currency__c = String.isNotBlank(currencyCode) ? currencyCode : 'EUR';
            upsert record;
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveVieAction);
        }
    }

    @AuraEnabled
    public static void deleteVieReferential(Id recordId) {
        AR_AdminAccessGuard.requireReferentials();
        try {
            delete new AR_VIE_Referential__c(Id = recordId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_DeleteVieAction);
        }
    }

    // ---------------------------------------------------------------------
    // Référentiel Nearshore
    // ---------------------------------------------------------------------

    public class NearshoreReferentialDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String country;
        @AuraEnabled public Decimal dailyRate;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String seniority;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    /** Rang d'une séniorité : DEFAULT d'abord, puis l'ordre du picklist, les valeurs inconnues à la fin. */
    private static Map<String, Integer> nearshoreSeniorityRanks() {
        Map<String, Integer> ranks = new Map<String, Integer>{ AR_PricingMatrixService.NEARSHORE_DEFAULT_SENIORITY => 0 };
        Schema.SObjectType candidate = Schema.getGlobalDescribe().get('cxsrec__cxsCandidate__c');
        Schema.SObjectField field = candidate == null ? null : candidate.getDescribe().fields.getMap().get('TP_Seniority__c');
        if (field != null) {
            for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
                ranks.put(e.getValue(), ranks.size());
            }
        }
        return ranks;
    }

    @AuraEnabled
    public static List<NearshoreReferentialDto> getNearshoreReferentials() {
        AR_AdminAccessGuard.requireReferentials();
        List<NearshoreReferentialDto> options = new List<NearshoreReferentialDto>();
        for (AR_Nearshore_Referential__c r : [
            SELECT Id, Name, AR_Daily_Rate__c, AR_Currency__c, AR_Seniority__c, LastModifiedDate, LastModifiedBy.Name
            FROM AR_Nearshore_Referential__c
            ORDER BY Name
        ]) {
            NearshoreReferentialDto dto = new NearshoreReferentialDto();
            dto.seniority = r.AR_Seniority__c;
            dto.id = r.Id;
            dto.country = r.Name;
            dto.dailyRate = r.AR_Daily_Rate__c;
            dto.currencyCode = String.isNotBlank(r.AR_Currency__c) ? r.AR_Currency__c : 'EUR';
            dto.lastModifiedDate = r.LastModifiedDate;
            dto.lastModifiedByName = r.LastModifiedBy.Name;
            options.add(dto);
        }
        Map<String, Integer> ranks = nearshoreSeniorityRanks();
        List<NearshoreSortKey> keys = new List<NearshoreSortKey>();
        for (NearshoreReferentialDto dto : options) {
            keys.add(new NearshoreSortKey(dto, ranks));
        }
        keys.sort();
        options.clear();
        for (NearshoreSortKey k : keys) {
            options.add(k.dto);
        }
        return options;
    }

    private class NearshoreSortKey implements Comparable {
        NearshoreReferentialDto dto;
        Integer rank;
        NearshoreSortKey(NearshoreReferentialDto dto, Map<String, Integer> ranks) {
            this.dto = dto;
            this.rank = ranks.containsKey(dto.seniority) ? ranks.get(dto.seniority) : 100000;
        }
        public Integer compareTo(Object other) {
            NearshoreSortKey o = (NearshoreSortKey) other;
            Integer byCountry = String.valueOf(dto.country).toLowerCase().compareTo(String.valueOf(o.dto.country).toLowerCase());
            if (byCountry != 0) {
                return byCountry < 0 ? -1 : 1;
            }
            if (rank != o.rank) {
                return rank < o.rank ? -1 : 1;
            }
            String a = String.valueOf(dto.seniority);
            String b = String.valueOf(o.dto.seniority);
            return a == b ? 0 : (a < b ? -1 : 1);
        }
    }

    @AuraEnabled
    public static Id saveNearshoreReferential(Id recordId, String country, String seniority, Decimal dailyRate, String currencyCode) {
        AR_AdminAccessGuard.requireReferentials();
        if (String.isBlank(country) || dailyRate == null) {
            throw newAuraException(Label.AR_Msg_ADM_CountryAndCostRequired);
        }
        if (String.isBlank(seniority)) {
            throw newAuraException(Label.AR_Msg_ADM_NearshoreSeniorityRequired);
        }
        for (AR_Nearshore_Referential__c twin : [
            SELECT Id
            FROM AR_Nearshore_Referential__c
            WHERE Name = :country AND AR_Seniority__c = :seniority AND Id != :recordId
            LIMIT 1
        ]) {
            String shown = seniority == AR_PricingMatrixService.NEARSHORE_DEFAULT_SENIORITY ? Label.AR_ANR_SeniorityDefault : seniority;
            throw newAuraException(AR_I18n.format(Label.AR_Msg_ADM_NearshoreDuplicate, new List<Object>{ country, shown }));
        }
        try {
            AR_Nearshore_Referential__c record = recordId != null
                ? new AR_Nearshore_Referential__c(Id = recordId)
                : new AR_Nearshore_Referential__c();
            record.Name = country;
            record.AR_Seniority__c = seniority;
            record.AR_Daily_Rate__c = dailyRate;
            record.AR_Currency__c = String.isNotBlank(currencyCode) ? currencyCode : 'EUR';
            upsert record;
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveNearshoreAction);
        }
    }

    @AuraEnabled
    public static void deleteNearshoreReferential(Id recordId) {
        AR_AdminAccessGuard.requireReferentials();
        try {
            delete new AR_Nearshore_Referential__c(Id = recordId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_DeleteNearshoreAction);
        }
    }

    // ---------------------------------------------------------------------
    // Entités PTF (session 46 : remplace l'administration via Setup > Custom Metadata Types de
    // AR_PTF_Entity__mdt par un écran de ce panneau — AR_PTF_Entity_Referential__c, objet standard,
    // permet un enregistrement synchrone avec retour immédiat, ce qu'un __mdt ne permet pas depuis
    // Apex sans passer par l'API Metadata asynchrone, cf. docs/23-administration.md §1). Domaine
    // d'habilitation séparé (AR_Admin_PTF_Entities), pas AR_Admin_Referentials : demande explicite du
    // client de pouvoir habiliter les entités PTF indépendamment des autres référentiels.
    // ---------------------------------------------------------------------

    public class PtfEntityDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String address;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public String siret;
        @AuraEnabled public String phone;
        @AuraEnabled public String fax;
        @AuraEnabled public String website;
        @AuraEnabled public String commercialEmail;
        @AuraEnabled public String bankName;
        @AuraEnabled public String iban;
        @AuraEnabled public String rib;
        @AuraEnabled public String bic;
        @AuraEnabled public String tribunalCompetent;
        @AuraEnabled public String templateCode;
        // Cascade calcul (session 48, réunion client du 03/09/2026) : coefficient/workingDays sont
        // les valeurs SAISIES sur cette entité (null = pas de surcharge). *Effective/*Source
        // donnent, en plus, ce qui s'applique RÉELLEMENT si le champ est vide — jamais une case vide
        // qui laisserait croire que rien ne s'applique (même défaut que AR_General_Setting__c en
        // session 35).
        @AuraEnabled public Decimal coefficient;
        @AuraEnabled public Decimal coefficientEffective;
        @AuraEnabled public String coefficientSource;
        @AuraEnabled public Decimal workingDays;
        @AuraEnabled public Decimal workingDaysEffective;
        @AuraEnabled public String workingDaysSource;
        // Session 252 : seuils propres à l'entité (facultatifs, tous les trois ou aucun). Null = l'entité
        // ne surcharge pas les seuils, le grand compte puis les paramètres généraux s'appliquent.
        @AuraEnabled public Decimal floorPercent;
        @AuraEnabled public Decimal targetPercent;
        @AuraEnabled public Decimal idealPercent;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
        // Session 47 : état de préparation PTF, pour chacun des 4 gabarits connus — ce qui manque
        // et pour quel gabarit, visible AVANT qu'un commercial ne heurte le blocage à la génération
        // (cf. prompts/session-47-blocages-en-amont.md §4). Vide = prête pour tous les gabarits.
        @AuraEnabled public List<TemplateReadinessDto> readinessIssues;
        // Valideurs rattachés à l'entité (en plus de ceux de la hiérarchie du propriétaire), triés par
        // nom ; inactiveValidatorCount = nombre de ceux dont l'utilisateur n'est plus actif.
        @AuraEnabled public List<EntityValidatorDto> validators;
        @AuraEnabled public Integer inactiveValidatorCount;
    }

    public class EntityValidatorDto {
        @AuraEnabled public Id rowId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public Boolean active;
    }

    public class UserSearchResultDto {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
    }

    public class TemplateReadinessDto {
        @AuraEnabled public String templateCode;
        @AuraEnabled public String templateLabel;
        @AuraEnabled public String missingFields;
    }

    /** Gabarits de PTF proposés dans le formulaire d'une entité (session 176i) : liste servie par
     * AR_PTFDataService (même source que la résolution), sans l'avenant. */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPtfTemplateOptions() {
        AR_AdminAccessGuard.requirePtfEntities();
        return AR_PTFDataService.getPtfTemplateOptions();
    }

    @AuraEnabled
    public static List<PtfEntityDto> getPtfEntities() {
        AR_AdminAccessGuard.requirePtfEntities();
        List<String> templateCodes = new List<String>(AR_PTFDataService.TEMPLATE_LABELS.keySet());
        templateCodes.sort();
        // Cascade calcul (session 48) : un seul niveau "paramètre général" lu ici, pas gardé par
        // requireGeneralSettings() (domaine d'habilitation séparé, cf. commentaire de tête) — cette
        // valeur n'est affichée qu'à titre indicatif, jamais écrite par cet écran.
        Decimal globalWorkingDays = currentGlobalWorkingDaysPerYear();
        Map<Id, List<EntityValidatorDto>> validatorsByEntity = loadValidatorsByEntity();
        List<PtfEntityDto> options = new List<PtfEntityDto>();
        for (AR_PTF_Entity_Referential__c e : [
            SELECT Id, Name, AR_Active__c, AR_Address__c, AR_Postal_Code__c, AR_City__c, AR_Country__c, AR_Siret__c,
                   AR_Phone__c, AR_Fax__c, AR_Website__c, AR_Commercial_Email__c, AR_Bank_Name__c,
                   AR_Iban__c, AR_Rib__c, AR_Bic__c, AR_Tribunal_Competent__c, AR_Template_Code__c, AR_Coefficient__c,
                   AR_Working_Days__c, AR_Floor_Percent__c, AR_Target_Percent__c, AR_Ideal_Percent__c,
                   LastModifiedDate, LastModifiedBy.Name
            FROM AR_PTF_Entity_Referential__c
            ORDER BY Name
        ]) {
            PtfEntityDto dto = new PtfEntityDto();
            dto.id = e.Id;
            dto.name = e.Name;
            dto.active = e.AR_Active__c;
            dto.address = e.AR_Address__c;
            dto.postalCode = e.AR_Postal_Code__c;
            dto.city = e.AR_City__c;
            dto.country = e.AR_Country__c;
            dto.siret = e.AR_Siret__c;
            dto.phone = e.AR_Phone__c;
            dto.fax = e.AR_Fax__c;
            dto.website = e.AR_Website__c;
            dto.commercialEmail = e.AR_Commercial_Email__c;
            dto.bankName = e.AR_Bank_Name__c;
            dto.iban = e.AR_Iban__c;
            dto.rib = e.AR_Rib__c;
            dto.bic = e.AR_Bic__c;
            dto.tribunalCompetent = e.AR_Tribunal_Competent__c;
            dto.templateCode = e.AR_Template_Code__c;
            dto.coefficient = e.AR_Coefficient__c;
            dto.workingDays = e.AR_Working_Days__c;
            dto.floorPercent = e.AR_Floor_Percent__c;
            dto.targetPercent = e.AR_Target_Percent__c;
            dto.idealPercent = e.AR_Ideal_Percent__c;
            // Coefficient : pas de niveau "paramètre général" fonctionnel aujourd'hui (session 28,
            // toujours découplé) — la cascade réelle s'arrête à la constante moteur.
            if (e.AR_Coefficient__c != null) {
                dto.coefficientEffective = e.AR_Coefficient__c;
                dto.coefficientSource = Label.AR_Msg_ADM_SourceEntity;
            } else {
                dto.coefficientEffective = AR_PricingCalculator.CONTRACT_COEFFICIENT_DEFAULT;
                dto.coefficientSource = Label.AR_Msg_ADM_SourceEngineDefault;
            }
            if (e.AR_Working_Days__c != null) {
                dto.workingDaysEffective = e.AR_Working_Days__c;
                dto.workingDaysSource = Label.AR_Msg_ADM_SourceEntity;
            } else if (globalWorkingDays != null) {
                dto.workingDaysEffective = globalWorkingDays;
                dto.workingDaysSource = Label.AR_Msg_ADM_SourceGeneralSetting;
            } else {
                dto.workingDaysEffective = AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT;
                dto.workingDaysSource = Label.AR_Msg_ADM_SourceEngineDefault;
            }
            dto.lastModifiedDate = e.LastModifiedDate;
            dto.lastModifiedByName = e.LastModifiedBy.Name;
            dto.validators = validatorsByEntity.containsKey(e.Id)
                ? validatorsByEntity.get(e.Id)
                : new List<EntityValidatorDto>();
            dto.inactiveValidatorCount = 0;
            for (EntityValidatorDto v : dto.validators) {
                if (v.active != true) {
                    dto.inactiveValidatorCount++;
                }
            }
            dto.readinessIssues = new List<TemplateReadinessDto>();
            for (String code : templateCodes) {
                String missing = AR_PTFDataService.missingFieldsForTemplate(code, e);
                if (missing != null) {
                    TemplateReadinessDto issue = new TemplateReadinessDto();
                    issue.templateCode = code;
                    issue.templateLabel = AR_PTFDataService.TEMPLATE_LABELS.get(code);
                    issue.missingFields = missing;
                    dto.readinessIssues.add(issue);
                }
            }
            options.add(dto);
        }
        return options;
    }

    private static Map<Id, List<EntityValidatorDto>> loadValidatorsByEntity() {
        Map<Id, List<EntityValidatorDto>> result = new Map<Id, List<EntityValidatorDto>>();
        for (AR_PTF_Entity_Validator__c row : [
            SELECT Id, AR_Entity_Ref__c, AR_User__c, AR_User__r.Name, AR_User__r.Title, AR_User__r.IsActive
            FROM AR_PTF_Entity_Validator__c
            WITH USER_MODE
            ORDER BY AR_User__r.Name, Id
        ]) {
            EntityValidatorDto v = new EntityValidatorDto();
            v.rowId = row.Id;
            v.userId = row.AR_User__c;
            v.name = row.AR_User__r.Name;
            v.title = row.AR_User__r.Title;
            v.active = row.AR_User__r.IsActive;
            if (!result.containsKey(row.AR_Entity_Ref__c)) {
                result.put(row.AR_Entity_Ref__c, new List<EntityValidatorDto>());
            }
            result.get(row.AR_Entity_Ref__c).add(v);
        }
        return result;
    }

    /** Recherche d'utilisateurs ACTIFS par nom pour l'ajout d'un valideur d'entité : 2 caractères
     * minimum, 20 résultats maximum. Jamais cacheable : appelée à chaque frappe, le résultat doit
     * refléter l'état réel des utilisateurs. */
    @AuraEnabled
    public static List<UserSearchResultDto> searchActiveUsers(String term) {
        AR_AdminAccessGuard.requirePtfEntities();
        List<UserSearchResultDto> results = new List<UserSearchResultDto>();
        String trimmed = String.isBlank(term) ? '' : term.trim();
        if (trimmed.length() < 2) {
            return results;
        }
        String pattern = '%' + trimmed.replace('%', '\\%').replace('_', '\\_') + '%';
        try {
            for (User u : [
                SELECT Id, Name, Title
                FROM User
                WHERE IsActive = true AND UserType = 'Standard' AND Name LIKE :pattern
                WITH USER_MODE
                ORDER BY Name
                LIMIT 20
            ]) {
                UserSearchResultDto dto = new UserSearchResultDto();
                dto.userId = u.Id;
                dto.name = u.Name;
                dto.title = u.Title;
                results.add(dto);
            }
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SearchValidatorAction);
        }
        return results;
    }

    /** Refuse un utilisateur présent deux fois dans la liste voulue (avant toute écriture). */
    private static Set<Id> distinctValidatorIds(List<Id> userIds) {
        Set<Id> distinct = new Set<Id>();
        for (Id userId : userIds) {
            if (userId != null && !distinct.add(userId)) {
                throw newAuraException(Label.AR_Msg_ADM_EntityValidatorDuplicate);
            }
        }
        return distinct;
    }

    /** Synchronise les valideurs d'une entité avec la liste complète voulue : ajoute les nouveaux,
     * retire les absents (dans la transaction de l'appelant). Un utilisateur déjà présent mais devenu
     * inactif est conservé tant qu'il figure dans la liste ; seuls les NOUVEAUX doivent être actifs. */
    private static void syncEntityValidators(Id entityId, List<Id> wantedUserIds) {
        Set<Id> wanted = distinctValidatorIds(wantedUserIds);
        Map<Id, AR_PTF_Entity_Validator__c> existingByUser = new Map<Id, AR_PTF_Entity_Validator__c>();
        for (AR_PTF_Entity_Validator__c row : [
            SELECT Id, AR_User__c FROM AR_PTF_Entity_Validator__c WHERE AR_Entity_Ref__c = :entityId WITH USER_MODE
        ]) {
            existingByUser.put(row.AR_User__c, row);
        }
        Set<Id> toAdd = new Set<Id>(wanted);
        toAdd.removeAll(existingByUser.keySet());
        List<AR_PTF_Entity_Validator__c> toDelete = new List<AR_PTF_Entity_Validator__c>();
        for (Id userId : existingByUser.keySet()) {
            if (!wanted.contains(userId)) {
                toDelete.add(existingByUser.get(userId));
            }
        }
        if (!toAdd.isEmpty()) {
            Set<Id> activeIds = new Map<Id, User>([
                SELECT Id FROM User WHERE Id IN :toAdd AND IsActive = true WITH USER_MODE
            ]).keySet();
            List<AR_PTF_Entity_Validator__c> toInsert = new List<AR_PTF_Entity_Validator__c>();
            for (Id userId : toAdd) {
                if (!activeIds.contains(userId)) {
                    throw newAuraException(Label.AR_Msg_ADM_EntityValidatorInactive);
                }
                toInsert.add(new AR_PTF_Entity_Validator__c(
                    AR_Entity_Ref__c = entityId,
                    AR_User__c = userId,
                    AR_Unique_Key__c = String.valueOf(entityId) + ':' + String.valueOf(userId)
                ));
            }
            try {
                insert as user toInsert;
            } catch (DmlException e) {
                if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                    throw newAuraException(Label.AR_Msg_ADM_EntityValidatorDuplicate);
                }
                throw e;
            }
        }
        if (!toDelete.isEmpty()) {
            delete as user toDelete;
        }
    }

    /**
     * Niveau "paramètre général" de la cascade jours travaillés (session 48) — lecture seule, sans
     * la garde requireGeneralSettings() : cet écran n'a pas cette habilitation (domaine séparé,
     * cf. commentaire de tête) et n'écrit jamais ce champ. Null si le singleton n'existe pas encore
     * (repli sur la constante moteur côté appelant).
     *
     * AccessLevel.SYSTEM_MODE nécessaire : AR_Admin_PTF_Entities n'accorde aucun accès objet à
     * AR_General_Setting__c (domaine délibérément séparé de AR_Admin_General_Settings), et une SOQL
     * ordinaire échoue alors avec « sObject type 'AR_General_Setting__c' is not supported » pour un
     * porteur réel de cette seule habilitation — constaté en test (System.runAs), pas une anomalie
     * de plateforme (cf. CLAUDE.md, protocole de vérification session 28). Lecture seule d'un champ
     * non sensible à titre indicatif seulement : ne contourne aucune écriture, aucun autre champ.
     */
    private static Decimal currentGlobalWorkingDaysPerYear() {
        List<AR_General_Setting__c> rows = Database.query(
            'SELECT AR_Working_Days_Per_Year__c FROM AR_General_Setting__c LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0].AR_Working_Days_Per_Year__c;
    }

    @AuraEnabled
    public static Id savePtfEntity(
        Id recordId,
        String name,
        Boolean active,
        String address,
        String postalCode,
        String city,
        String siret,
        String phone,
        String fax,
        String website,
        String commercialEmail,
        String bankName,
        String iban,
        String rib,
        String bic,
        String tribunalCompetent,
        String templateCode,
        Decimal coefficient,
        Decimal workingDays,
        String country,
        Decimal floorPercent,
        Decimal targetPercent,
        Decimal idealPercent,
        List<Id> validatorUserIds
    ) {
        AR_AdminAccessGuard.requirePtfEntities();
        if (String.isBlank(name)) {
            throw newAuraException(Label.AR_Msg_ADM_EntityNameRequired);
        }
        // Session 252 : tous les trois seuils ou aucun ; même garde d'ordre que le corridor grand compte.
        Boolean anyThreshold = floorPercent != null || targetPercent != null || idealPercent != null;
        Boolean allThresholds = floorPercent != null && targetPercent != null && idealPercent != null;
        if (anyThreshold && !allThresholds) {
            throw newAuraException(Label.AR_Msg_ADM_EntityThresholdsPartial);
        }
        if (allThresholds && (floorPercent > targetPercent || targetPercent > idealPercent)) {
            throw newAuraException(Label.AR_Msg_ADM_ThresholdsOrder);
        }
        if (validatorUserIds != null) {
            distinctValidatorIds(validatorUserIds);
        }
        try {
            AR_PTF_Entity_Referential__c record = recordId != null
                ? new AR_PTF_Entity_Referential__c(Id = recordId)
                : new AR_PTF_Entity_Referential__c();
            record.Name = name;
            record.AR_Active__c = active != null ? active : true;
            record.AR_Address__c = address;
            record.AR_Postal_Code__c = postalCode;
            record.AR_City__c = city;
            record.AR_Country__c = String.isBlank(country) ? null : country.trim();
            record.AR_Siret__c = siret;
            record.AR_Phone__c = phone;
            record.AR_Fax__c = fax;
            record.AR_Website__c = website;
            record.AR_Commercial_Email__c = commercialEmail;
            record.AR_Bank_Name__c = bankName;
            record.AR_Iban__c = iban;
            record.AR_Rib__c = rib;
            record.AR_Bic__c = bic;
            record.AR_Tribunal_Competent__c = String.isBlank(tribunalCompetent) ? null : tribunalCompetent.trim();
            record.AR_Template_Code__c = templateCode;
            record.AR_Coefficient__c = coefficient;
            record.AR_Working_Days__c = workingDays;
            record.AR_Floor_Percent__c = floorPercent;
            record.AR_Target_Percent__c = targetPercent;
            record.AR_Ideal_Percent__c = idealPercent;
            upsert record;
            // Liste complète des valideurs voulus ; null = ne pas toucher (appelants sans cette notion).
            if (validatorUserIds != null) {
                syncEntityValidators(record.Id, validatorUserIds);
            }
            return record.Id;
        } catch (AuraHandledException e) {
            // Message métier déjà lisible (doublon, utilisateur inactif) : on le laisse tel quel,
            // la transaction entière (entité comprise) est annulée par l'exception.
            throw e;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveEntityAction);
        }
    }

    @AuraEnabled
    public static void deletePtfEntity(Id recordId) {
        AR_AdminAccessGuard.requirePtfEntities();
        try {
            delete new AR_PTF_Entity_Referential__c(Id = recordId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_DeleteEntityAction);
        }
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}