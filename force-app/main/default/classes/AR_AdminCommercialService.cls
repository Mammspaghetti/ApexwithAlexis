/**
 * Administration des données commerciales — session 23, réunion du 10/08/2026. Deux domaines
 * distincts : la table de conversion des devises (une ligne par période — corrigible en place
 * depuis la session 50, jamais supprimable — cf. addCurrencyRate/updateCurrencyRate) et les données
 * commerciales par grand compte (RFA par défaut, contrat-cadre, grille tarifaire, paramètres
 * spécifiques). Domaines d'administration distincts depuis la session 42 : les devises sont gardées
 * par `AR_AdminAccessGuard.requireCurrency()`, les données commerciales par grand compte par
 * `requireReferentials()` (fourre-tout référentiels) — une seule classe sert deux domaines, la
 * séparation passe par la garde en tête de méthode, pas par classAccesses.
 */
public with sharing class AR_AdminCommercialService {

    // ---------------------------------------------------------------------
    // Table de conversion des devises
    // ---------------------------------------------------------------------

    public class CurrencyRateDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal rateToEur;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
        // Session 50 : distincts de createdDate/createdByName uniquement quand la ligne a été
        // corrigée (updateCurrencyRate) — le LWC s'en sert pour afficher « modifié le … par … ».
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    @AuraEnabled
    public static List<CurrencyRateDto> getCurrencyRates() {
        AR_AdminAccessGuard.requireCurrency();
        List<CurrencyRateDto> options = new List<CurrencyRateDto>();
        for (AR_Currency_Rate__c r : [
            SELECT Id, AR_Currency_Code__c, AR_Rate_To_EUR__c, AR_Effective_Date__c, CreatedDate, CreatedBy.Name,
                LastModifiedDate, LastModifiedBy.Name
            FROM AR_Currency_Rate__c
            ORDER BY AR_Currency_Code__c ASC, AR_Effective_Date__c DESC, CreatedDate DESC
        ]) {
            CurrencyRateDto dto = new CurrencyRateDto();
            dto.id = r.Id;
            dto.currencyCode = r.AR_Currency_Code__c;
            dto.rateToEur = r.AR_Rate_To_EUR__c;
            dto.effectiveDate = r.AR_Effective_Date__c;
            dto.createdDate = r.CreatedDate;
            dto.createdByName = r.CreatedBy.Name;
            dto.lastModifiedDate = r.LastModifiedDate;
            dto.lastModifiedByName = r.LastModifiedBy.Name;
            options.add(dto);
        }
        return options;
    }

    /** Geste d'évolution : une nouvelle période (nouvelle devise/date d'effet), jamais une
     * réécriture d'une période déjà enregistrée. Pour corriger une valeur mal saisie sur une
     * période existante, voir updateCurrencyRate — les deux gestes sont volontairement distincts
     * (session 50, docs/50-taux-modifiables.md) : ce qui distingue une correction d'une évolution,
     * c'est que la première ne change ni devise ni date d'effet. */
    @AuraEnabled
    public static Id addCurrencyRate(String currencyCode, Decimal rateToEur, Date effectiveDate) {
        AR_AdminAccessGuard.requireCurrency();
        if (String.isBlank(currencyCode) || rateToEur == null || effectiveDate == null) {
            throw newAuraException(Label.AR_Msg_ADM_RateFieldsRequired);
        }
        if (rateToEur <= 0) {
            throw newAuraException(Label.AR_Msg_ADM_RatePositive);
        }
        try {
            AR_Currency_Rate__c record = new AR_Currency_Rate__c(
                AR_Currency_Code__c = currencyCode,
                AR_Rate_To_EUR__c = rateToEur,
                AR_Effective_Date__c = effectiveDate
            );
            insert record;
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_AddRateAction);
        }
    }

    /** Geste de correction (session 50) : réécrit le taux d'une ligne déjà enregistrée, sans
     * toucher à sa devise ni à sa date d'effet — les changer ferait de cette correction une
     * évolution, le rôle d'addCurrencyRate. Tenable sans perdre la garantie de non-rétroactivité
     * du client (docs/23-administration.md §6, docs/24-multidevise.md) car une matrice décidée
     * porte son propre taux gelé (AR_Price_Matrix__c.AR_Currency_Rate_Applied__c) : réécrire une
     * ligne de la table ne peut pas l'altérer rétroactivement. Le suivi d'historique des champs
     * (AR_Currency_Rate__History, activé sur l'objet et sur AR_Rate_To_EUR__c) remplace la trace
     * que l'ajout seul offrait par construction. Aucune méthode de suppression n'existe — n'en
     * ajoute pas, même par symétrie. */
    @AuraEnabled
    public static Id updateCurrencyRate(Id rateId, Decimal rateToEur) {
        AR_AdminAccessGuard.requireCurrency();
        if (rateId == null || rateToEur == null) {
            throw newAuraException(Label.AR_Msg_ADM_RateAndRateToEurRequired);
        }
        if (rateToEur <= 0) {
            throw newAuraException(Label.AR_Msg_ADM_RatePositive);
        }
        List<AR_Currency_Rate__c> existing = [SELECT Id FROM AR_Currency_Rate__c WHERE Id = :rateId LIMIT 1];
        if (existing.isEmpty()) {
            throw newAuraException(Label.AR_Msg_ADM_RateNotFound);
        }
        try {
            AR_Currency_Rate__c record = new AR_Currency_Rate__c(Id = rateId, AR_Rate_To_EUR__c = rateToEur);
            update record;
            return record.Id;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_EditRateAction);
        }
    }

    // ---------------------------------------------------------------------
    // Données commerciales par grand compte
    // ---------------------------------------------------------------------

    /** Session 146b : résultat de résolution de RFA avec provenance. */
    public class RfaResult {
        @AuraEnabled public Decimal percent;
        @AuraEnabled public Id sourceAccountId;
        @AuraEnabled public String sourceAccountName;
        @AuraEnabled public Boolean inherited;
    }

    public class AccountCommercialDto {
        @AuraEnabled public Id id;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal defaultRfaPercent;
        @AuraEnabled public String frameworkAgreementReference;
        @AuraEnabled public String pricingGridNotes;
        @AuraEnabled public String specialTerms;
        // Surcharge du gabarit PTF pour ce compte (session 30) — vide = pas de surcharge, la
        // résolution retombe sur l'entité puis le générique (AR_PTFDataService.resolveTemplateCode).
        @AuraEnabled public String ptfTemplateCode;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    private static final String COMMERCIAL_FIELDS =
        'Id, AR_Account__c, AR_Account__r.Name, AR_Default_RFA_Percent__c, AR_Framework_Agreement_Reference__c, ' +
        'AR_Pricing_Grid_Notes__c, AR_Special_Terms__c, AR_PTF_Template_Code__c, LastModifiedDate, LastModifiedBy.Name';

    /** Gabarits de PTF proposés dans le formulaire d'un grand compte (session 176i) : liste servie
     * par AR_PTFDataService (même source que la résolution), sans l'avenant. */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPtfTemplateOptions() {
        AR_AdminAccessGuard.requireReferentials();
        return AR_PTFDataService.getPtfTemplateOptions();
    }

    @AuraEnabled
    public static List<AccountCommercialDto> getAccountCommercialData() {
        AR_AdminAccessGuard.requireReferentials();
        List<AccountCommercialDto> options = new List<AccountCommercialDto>();
        for (AR_Account_Commercial_Data__c d : Database.query(
            'SELECT ' + COMMERCIAL_FIELDS + ' FROM AR_Account_Commercial_Data__c ORDER BY AR_Account__r.Name'
        )) {
            options.add(toDto(d));
        }
        return options;
    }

    /** Une ligne par compte : réutilise la ligne existante si le compte en a déjà une, plutôt que
     * d'en créer une seconde (même convention que AR_Account_Corridor__c, cf. AR_PricingMatrixService.loadCorridorPercents). */
    @AuraEnabled
    public static AccountCommercialDto saveAccountCommercialData(String dtoJson) {
        AR_AdminAccessGuard.requireReferentials();
        if (String.isBlank(dtoJson)) {
            throw newAuraException(Label.AR_Msg_ADM_EmptyCommercialPayload);
        }
        AccountCommercialDto dto = (AccountCommercialDto) JSON.deserialize(dtoJson, AccountCommercialDto.class);
        if (dto.accountId == null) {
            throw newAuraException(Label.AR_Msg_ADM_AccountRequired);
        }

        Id targetId = dto.id;
        if (targetId == null) {
            List<AR_Account_Commercial_Data__c> existing = [
                SELECT Id FROM AR_Account_Commercial_Data__c WHERE AR_Account__c = :dto.accountId LIMIT 1
            ];
            if (!existing.isEmpty()) {
                targetId = existing[0].Id;
            }
        }

        try {
            AR_Account_Commercial_Data__c record = targetId != null
                ? new AR_Account_Commercial_Data__c(Id = targetId)
                : new AR_Account_Commercial_Data__c();
            record.AR_Account__c = dto.accountId;
            record.AR_Default_RFA_Percent__c = dto.defaultRfaPercent;
            record.AR_Framework_Agreement_Reference__c = dto.frameworkAgreementReference;
            record.AR_Pricing_Grid_Notes__c = dto.pricingGridNotes;
            record.AR_Special_Terms__c = dto.specialTerms;
            record.AR_PTF_Template_Code__c = dto.ptfTemplateCode;
            upsert record;

            Id savedId = record.Id;
            List<AR_Account_Commercial_Data__c> reloaded = Database.query(
                'SELECT ' + COMMERCIAL_FIELDS + ' FROM AR_Account_Commercial_Data__c WHERE Id = :savedId LIMIT 1'
            );
            return toDto(reloaded[0]);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_SaveCommercialAction);
        }
    }

    @AuraEnabled
    public static void deleteAccountCommercialData(Id recordId) {
        AR_AdminAccessGuard.requireReferentials();
        try {
            delete new AR_Account_Commercial_Data__c(Id = recordId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_DeleteCommercialAction);
        }
    }

    /** Préremplissage Zone 2 (arPriceMatrixSimulator) : pas de garde admin ici, un utilisateur
     * standard doit pouvoir lire le taux de RFA par défaut de son compte pour créer une matrice.
     * WITH SYSTEM_MODE : AR_Account__c est un champ obligatoire, donc aucune fieldPermissions
     * explicite n'est déployable dessus (contrainte plateforme) ; l'accès implicite à un champ
     * obligatoire ne suit que l'accès Create/Edit à l'objet, jamais le Read seul — AR_Pricing_User/
     * Validator (Read seul) n'auraient donc littéralement aucune visibilité sur ce champ sans ce
     * contournement, alors que le champ retourné (RFA) reste, lui, filtré par une FLS explicite. */
    @AuraEnabled(cacheable=true)
    public static Decimal getDefaultRfaPercentForAccount(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<AR_Account_Commercial_Data__c> rows = [
            SELECT AR_Default_RFA_Percent__c
            FROM AR_Account_Commercial_Data__c
            WHERE AR_Account__c = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].AR_Default_RFA_Percent__c;
    }

    /** Session 146b : résolution RFA avec héritage du grand compte. Remonte la hiérarchie
     * du compte et retourne la première RFA non nulle trouvée, avec sa provenance.
     * Pas de garde admin (même règle que getDefaultRfaPercentForAccount). */
    @AuraEnabled
    public static RfaResult getDefaultRfaPercentWithProvenance(Id accountId) {
        if (accountId == null) {
            return null;
        }

        try {
            List<Id> chain = AR_AccountHierarchy.chainFrom(accountId);
            if (chain == null || chain.isEmpty()) {
                return null;
            }

            Map<Id, AR_Account_Commercial_Data__c> commercialDataByAccountId = new Map<Id, AR_Account_Commercial_Data__c>();
            for (AR_Account_Commercial_Data__c d : [
                SELECT AR_Account__c, AR_Default_RFA_Percent__c, AR_Account__r.Name
                FROM AR_Account_Commercial_Data__c
                WHERE AR_Account__c IN :chain
                WITH SYSTEM_MODE
            ]) {
                if (!commercialDataByAccountId.containsKey(d.AR_Account__c)) {
                    commercialDataByAccountId.put(d.AR_Account__c, d);
                }
            }

            // Parcourir la chaîne : première RFA non nulle gagne
            Integer sourceIndex = -1;
            AR_Account_Commercial_Data__c sourceRfa = null;
            for (Integer i = 0; i < chain.size(); i++) {
                Id checkId = chain.get(i);
                if (commercialDataByAccountId.containsKey(checkId)) {
                    AR_Account_Commercial_Data__c candidate = commercialDataByAccountId.get(checkId);
                    if (candidate.AR_Default_RFA_Percent__c != null && candidate.AR_Default_RFA_Percent__c > 0) {
                        sourceIndex = i;
                        sourceRfa = candidate;
                        break;
                    }
                }
            }

            if (sourceRfa == null) {
                return null;
            }

            RfaResult result = new RfaResult();
            result.percent = sourceRfa.AR_Default_RFA_Percent__c;
            result.sourceAccountId = sourceRfa.AR_Account__c;
            result.sourceAccountName = sourceRfa.AR_Account__r.Name;
            result.inherited = sourceIndex > 0; // sourceIndex 0 = compte lui-même, > 0 = hérité
            return result;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_ADM_ReadDefaultRfaAction);
        }
    }

    private static AccountCommercialDto toDto(AR_Account_Commercial_Data__c d) {
        AccountCommercialDto dto = new AccountCommercialDto();
        dto.id = d.Id;
        dto.accountId = d.AR_Account__c;
        dto.accountName = d.AR_Account__r.Name;
        dto.defaultRfaPercent = d.AR_Default_RFA_Percent__c;
        dto.frameworkAgreementReference = d.AR_Framework_Agreement_Reference__c;
        dto.pricingGridNotes = d.AR_Pricing_Grid_Notes__c;
        dto.specialTerms = d.AR_Special_Terms__c;
        dto.ptfTemplateCode = d.AR_PTF_Template_Code__c;
        dto.lastModifiedDate = d.LastModifiedDate;
        dto.lastModifiedByName = d.LastModifiedBy.Name;
        return dto;
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}