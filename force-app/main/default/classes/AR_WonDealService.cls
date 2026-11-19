/**
 * Affaire gagnée : liste des besoins « Gagné » à confirmer, détail d'un besoin et confirmation de la
 * version gagnante + prix signé. Confirmation réservée au propriétaire de la matrice et à son DA
 * (User.TP_DA__c). Une seule version gagnante par besoin.
 */
public with sharing class AR_WonDealService {
    public static final String WON_STATUS = 'Gagné';

    public class VersionDTO {
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Datetime validatedAt;
        @AuraEnabled public Decimal price1;
        @AuraEnabled public Decimal price2;
        @AuraEnabled public Decimal price3;
        @AuraEnabled public Boolean clientGrid;
        @AuraEnabled public Decimal mc2Percent;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Boolean won;
        @AuraEnabled public Decimal signedTjm;
        @AuraEnabled public String signedPriceLevel;
        @AuraEnabled public Date wonDate;
        @AuraEnabled public Boolean canConfirm;
    }

    public class WonDealDTO {
        @AuraEnabled public Id positionId;
        @AuraEnabled public String positionName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String consultantName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Datetime wonAt;
        @AuraEnabled public Boolean confirmed = false;
        @AuraEnabled public List<VersionDTO> versions = new List<VersionDTO>();
    }

    public class ConfirmRequest {
        public Id matrixId;
        public String priceLevel;
        public Decimal signedTjm;
        public Date signedDate;
    }

    private static final Set<String> LEVELS = new Set<String>{ 'P1', 'P2', 'P3' };

    // ---------- Lecture ----------

    public static List<WonDealDTO> getPendingWonDeals() {
        return buildDeals(null, true);
    }

    public static WonDealDTO getWonDeal(Id positionId) {
        List<WonDealDTO> deals = buildDeals(positionId, false);
        return deals.isEmpty() ? null : deals[0];
    }

    private static List<WonDealDTO> buildDeals(Id positionId, Boolean pendingOnly) {
        List<AR_Price_Matrix__c> rows = positionId == null ? queryRows(null) : queryRows(new Set<Id>{ positionId });
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : rows) {
            ownerIds.add(m.OwnerId);
        }
        Map<Id, Id> daByOwner = new Map<Id, Id>();
        for (User u : [SELECT Id, TP_DA__c FROM User WHERE Id IN :ownerIds]) {
            daByOwner.put(u.Id, u.TP_DA__c);
        }
        Id me = UserInfo.getUserId();
        Map<Id, WonDealDTO> byPosition = new Map<Id, WonDealDTO>();
        List<WonDealDTO> ordered = new List<WonDealDTO>();
        for (AR_Price_Matrix__c m : rows) {
            WonDealDTO deal = byPosition.get(m.AR_Position__c);
            if (deal == null) {
                deal = new WonDealDTO();
                deal.positionId = m.AR_Position__c;
                deal.positionName = m.AR_Position_Name__c;
                deal.accountName = m.AR_Account_Name__c;
                deal.consultantName = m.AR_Consultant__r != null ? m.AR_Consultant__r.Name : m.AR_Consultant_Name__c;
                deal.ownerName = m.Owner.Name;
                deal.wonAt = m.AR_Position_Won_At__c;
                byPosition.put(m.AR_Position__c, deal);
                ordered.add(deal);
            }
            VersionDTO v = new VersionDTO();
            v.matrixId = m.Id;
            v.name = m.Name;
            v.version = m.AR_Negotiation_Version__c;
            v.validatedAt = m.AR_Validated_At__c;
            v.price1 = m.AR_Proposed_TJM__c;
            v.price2 = m.AR_Nego_Price_2__c;
            v.price3 = m.AR_Nego_Price_3__c;
            v.clientGrid = m.AR_Client_Grid__c == true;
            v.mc2Percent = m.AR_MC2_Percent__c;
            v.currencyCode = m.AR_Currency__c;
            v.won = m.AR_Won__c == true;
            v.signedTjm = m.AR_Signed_TJM__c;
            v.signedPriceLevel = m.AR_Signed_Price_Level__c;
            v.wonDate = m.AR_Won_Date__c;
            v.canConfirm = m.OwnerId == me || (daByOwner.get(m.OwnerId) != null && daByOwner.get(m.OwnerId) == me);
            if (v.won) {
                deal.confirmed = true;
            }
            deal.versions.add(v);
        }
        if (!pendingOnly) {
            return ordered;
        }
        List<WonDealDTO> pending = new List<WonDealDTO>();
        for (WonDealDTO d : ordered) {
            if (!d.confirmed) {
                pending.add(d);
            }
        }
        return pending;
    }

    private static List<AR_Price_Matrix__c> queryRows(Set<Id> positionIds) {
        Set<String> validated = AR_ValidatedMatrixSyncService.VALIDATED_STATUSES;
        // Les matrices sont lues avec le partage de l'utilisateur ; le statut « Gagné » du besoin est lu hors partage
        // (session 286) : un DA voit la matrice de son BM sans forcément voir le besoin Connexys, et la condition
        // `AR_Position__r.cxsrec__Status__c` le faisait disparaître de la liste « à confirmer ».
        Set<Id> candidatePositions = new Set<Id>();
        for (AR_Price_Matrix__c m : [
            SELECT AR_Position__c FROM AR_Price_Matrix__c
            WHERE AR_Status__c IN :validated AND AR_Position__c != null
            LIMIT 10000
        ]) {
            if (positionIds == null || positionIds.contains(m.AR_Position__c)) {
                candidatePositions.add(m.AR_Position__c);
            }
        }
        Set<Id> wonPositions = new UnsharedWriter().wonPositionIds(candidatePositions);
        return [
            SELECT Id, Name, OwnerId, Owner.Name, AR_Position__c, AR_Position_Name__c, AR_Account_Name__c,
                   AR_Consultant__r.Name, AR_Consultant_Name__c, AR_Negotiation_Version__c, AR_Validated_At__c,
                   AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c, AR_Client_Grid__c,
                   AR_MC2_Percent__c, AR_Currency__c, AR_Won__c, AR_Signed_TJM__c, AR_Signed_Price_Level__c,
                   AR_Won_Date__c, AR_Position_Won_At__c
            FROM AR_Price_Matrix__c
            WHERE AR_Status__c IN :validated AND AR_Position__c IN :wonPositions
            ORDER BY AR_Position_Won_At__c DESC NULLS LAST, AR_Position__c, AR_Validated_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 2000
        ];
    }

    // ---------- Confirmation ----------

    public static void confirmWonDeal(Id matrixId, String priceLevel, Decimal signedTjm, Date signedDate) {
        List<AR_Price_Matrix__c> rows = new UnsharedWriter().matrixForConfirmation(matrixId);
        if (rows.isEmpty()) {
            throw newAuraException(Label.AR_Won_Err_NotFound);
        }
        AR_Price_Matrix__c m = rows[0];
        if (!AR_ValidatedMatrixSyncService.VALIDATED_STATUSES.contains(m.AR_Status__c)) {
            throw newAuraException(Label.AR_Won_Err_NotValidated);
        }
        if (m.AR_Position__c == null || new UnsharedWriter().positionStatus(m.AR_Position__c) != WON_STATUS) {
            throw newAuraException(Label.AR_Won_Err_NotWon);
        }
        if (!canConfirm(m.OwnerId)) {
            throw newAuraException(Label.AR_Won_Err_NotAllowed);
        }

        String level = String.isBlank(priceLevel) ? null : priceLevel;
        Decimal tjm = signedTjm;
        if (level != null) {
            if (!LEVELS.contains(level)) {
                throw newAuraException(Label.AR_Won_Err_BadLevel);
            }
            tjm = level == 'P1' ? m.AR_Proposed_TJM__c : (level == 'P2' ? m.AR_Nego_Price_2__c : m.AR_Nego_Price_3__c);
            if (tjm == null || (m.AR_Client_Grid__c == true && level != 'P1')) {
                throw newAuraException(Label.AR_Won_Err_BadLevel);
            }
        } else {
            if (signedTjm == null) {
                throw newAuraException(Label.AR_Won_Err_NoAmount);
            }
            level = AR_SignedPriceLevel.compute(signedTjm, m);
            if (level == null) {
                throw newAuraException(Label.AR_Won_Err_BadLevel);
            }
        }

        List<AR_Price_Matrix__c> updates = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c other : [
            SELECT Id FROM AR_Price_Matrix__c WHERE AR_Position__c = :m.AR_Position__c AND AR_Won__c = true AND Id != :matrixId
        ]) {
            updates.add(new AR_Price_Matrix__c(
                Id = other.Id, AR_Won__c = false, AR_Won_Date__c = null, AR_Signed_TJM__c = null,
                AR_Signed_Price_Level__c = null, AR_Won_Confirmed_By__c = null, AR_Won_Confirmed_At__c = null
            ));
        }
        updates.add(new AR_Price_Matrix__c(
            Id = matrixId,
            AR_Won__c = true,
            AR_Won_Date__c = signedDate != null ? signedDate : Date.today(),
            AR_Signed_TJM__c = tjm,
            AR_Signed_Price_Level__c = level,
            AR_Won_Confirmed_By__c = UserInfo.getUserId(),
            AR_Won_Confirmed_At__c = System.now()
        ));
        new UnsharedWriter().apply(updates);
    }

    private static Boolean canConfirm(Id ownerId) {
        Id me = UserInfo.getUserId();
        if (ownerId == me) {
            return true;
        }
        List<User> owners = [SELECT TP_DA__c FROM User WHERE Id = :ownerId LIMIT 1];
        return !owners.isEmpty() && owners[0].TP_DA__c != null && owners[0].TP_DA__c == me;
    }

    /** Écriture hors partage : l'habilitation (propriétaire ou DA) est déjà tranchée, le DA peut ne pas avoir l'accès en modification. */
    private without sharing class UnsharedWriter {
        // Statut du besoin lu hors partage : l'habilitation est tranchée sur la matrice (propriétaire ou DA), le DA
        // peut ne pas voir le besoin Connexys.
        List<AR_Price_Matrix__c> matrixForConfirmation(Id matrixId) {
            return Database.query(
                'SELECT Id, OwnerId, AR_Status__c, AR_Position__c, AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c, AR_Client_Grid__c ' +
                'FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
        }

        String positionStatus(Id positionId) {
            List<cxsrec__cxsPosition__c> rows = Database.query(
                'SELECT cxsrec__Status__c FROM cxsrec__cxsPosition__c WHERE Id = :positionId LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            return rows.isEmpty() ? null : rows[0].cxsrec__Status__c;
        }

        Set<Id> wonPositionIds(Set<Id> positionIds) {
            Set<Id> won = new Set<Id>();
            if (positionIds.isEmpty()) {
                return won;
            }
            for (SObject p : Database.queryWithBinds(
                'SELECT Id FROM cxsrec__cxsPosition__c WHERE Id IN :ids AND cxsrec__Status__c = :status',
                new Map<String, Object>{ 'ids' => positionIds, 'status' => WON_STATUS },
                AccessLevel.SYSTEM_MODE
            )) {
                won.add(p.Id);
            }
            return won;
        }

        void apply(List<AR_Price_Matrix__c> updates) {
            AR_TriggerBypass.serviceContext = true;
            try {
                Database.update(updates, AccessLevel.SYSTEM_MODE);
            } finally {
                AR_TriggerBypass.serviceContext = false;
            }
        }
    }

    // ---------- Façade Aura (paramètres en JSON String) ----------

    @AuraEnabled
    public static List<WonDealDTO> listPendingWonDeals() {
        try {
            return getPendingWonDeals();
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Won_Err_Action);
        }
    }

    @AuraEnabled
    public static WonDealDTO loadWonDeal(Id positionId) {
        try {
            return getWonDeal(positionId);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Won_Err_Action);
        }
    }

    @AuraEnabled
    public static void confirmWonDealJson(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw newAuraException(Label.AR_Won_Err_Payload);
        }
        try {
            ConfirmRequest req = (ConfirmRequest) JSON.deserialize(requestJson, ConfirmRequest.class);
            confirmWonDeal(req.matrixId, req.priceLevel, req.signedTjm, req.signedDate);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Won_Err_Action);
        }
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}