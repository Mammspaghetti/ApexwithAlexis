/**
 * Traitement de la dérogation côté valideur. `with sharing` : le contexte est lisible par tout
 * utilisateur ayant accès à la matrice (panneau en lecture seule pour un non-valideur), mais seule
 * la décision est réservée aux Users détenteurs de la Custom Permission AR_Approve_Derogation
 * (session 40 — remplace l'ancienne règle par TP_Job_Title__c/AR_Validator_Job_Title__c, cf.
 * docs/40-habilitation-par-permission.md). Une seule règle : qui a la permission peut valider.
 */
public with sharing class AR_DerogationService {

    /** Ligne de la file d'approbation (app Pricing Tool, vue « File d'approbation »). */
    public class DerogationListItem {
        @AuraEnabled public Id derogationId;
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String matrixName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String positionName;
        @AuraEnabled public String accountCountry;
        // Régie sans régule (docs/265c §7) : « N j produits pour M j vendus · MC2 régie classique x % », null hors mode actif.
        @AuraEnabled public String rplsrMention;
        // Session 28 §5 : filtre "agence/BU" de la file d'approbation. Session 132 : Nom de la fiche
        // d'entité de la matrice (AR_Entity_Ref__c), libellé d'affichage et valeur du filtre.
        @AuraEnabled public String entity;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal proposedTjm;
        @AuraEnabled public List<AR_PricingResult.TjmPeriod> tjmPeriods;
        @AuraEnabled public Decimal tjmFloor;
        @AuraEnabled public Decimal tjmTarget;
        @AuraEnabled public Decimal tjmIdeal;
        @AuraEnabled public Decimal mc2PercentHuman;
        @AuraEnabled public Decimal mc2PerDay;
        @AuraEnabled public String corridorSegment;
        @AuraEnabled public Decimal gapVsFloor;
        // RFA de la matrice et RFA enregistrée pour le compte du besoin (héritage parent → enfant), information seule.
        @AuraEnabled public Decimal matrixRfaPercent;
        @AuraEnabled public Decimal accountRfaPercent;
        @AuraEnabled public String decision;
        @AuraEnabled public String requesterReason;
        // Motifs cochés par le demandeur, libellés du référentiel, dans son ordre (jamais null).
        @AuraEnabled public List<String> reasonLabels;
        @AuraEnabled public String requesterName;
        @AuraEnabled public Datetime requestedAt;
        @AuraEnabled public String selectedValidatorName;
        @AuraEnabled public String effectiveValidatorName;
        @AuraEnabled public String validatorComment;
        @AuraEnabled public Datetime decidedAt;
        // Session 33 : distingue « visible » de « adressée à moi » (valideur sélectionné, ou membre
        // du cercle d'escalade de l'entité) — sert de base au filtre par défaut « À traiter par moi ».
        @AuraEnabled public Boolean isAddressedToCurrentUser;
        // Demandeur ou propriétaire de la matrice : lecture seule, jamais « à traiter ».
        @AuraEnabled public Boolean isOwnRequest;
    }

    /** Session 112 : encart dans la matrice simulateur, proposant de traiter une dérogation en attente. */
    public class PendingDerogationDTO {
        @AuraEnabled public Id derogationId;
        @AuraEnabled public String requesterName;
        @AuraEnabled public Datetime requestedAt;
        @AuraEnabled public String selectedValidatorName;
        @AuraEnabled public Boolean isAddressedToCurrentUser;
    }

    /**
     * File d'approbation : toutes les dérogations visibles de l'utilisateur courant (`with sharing`
     * — Private + viewAllRecords pour Validator/Admin, cf. docs/architecture-technique.md §5). Le
     * filtre par statut (Toutes/En attente/Approuvées/Refusées) est fait côté LWC.
     *
     * Session 136 : réservée aux porteurs de AR_Approve_Derogation (viewAllRecords) ; liste vide sinon.
     */
    @AuraEnabled(cacheable=true)
    public static List<DerogationListItem> listDerogations() {
        // Session 136, décision 1 : seule la permission AR_Approve_Derogation ouvre la file. Être
        // DA/DD/Directeur d'un BM sert à proposer et escalader, jamais à voir ni à décider.
        if (!isCurrentUserValidator()) {
            return new List<DerogationListItem>();
        }

        List<AR_Derogation__c> records = [
            SELECT Id, AR_Decision__c, AR_Requester_Reason__c, AR_Validator_Comment__c,
                   AR_Requested_At__c, AR_Decided_At__c, CreatedBy.Name, CreatedById, AR_Selected_Validator__c,
                   AR_Selected_Validator__r.Name, AR_Effective_Validator__r.Name, AR_Price_Matrix__r.OwnerId,
                   AR_Price_Matrix__c, AR_Price_Matrix__r.Name, AR_Price_Matrix__r.AR_Account_Name__c,
                   AR_Price_Matrix__r.AR_Position_Name__c, AR_Price_Matrix__r.AR_Account_Country__c,
                   AR_Price_Matrix__r.AR_Entity_Ref__r.Name, AR_Price_Matrix__r.AR_Currency__c,
                   AR_Price_Matrix__r.AR_Proposed_TJM__c, AR_Price_Matrix__r.AR_TJM_Weighted__c, AR_Price_Matrix__r.AR_TJM_Periods__c, AR_Price_Matrix__r.AR_Number_Of_Days__c, AR_Price_Matrix__r.AR_Planned_Leave_Days__c, AR_Price_Matrix__r.AR_TJM_Floor__c,
                   AR_Price_Matrix__r.AR_TJM_Target__c, AR_Price_Matrix__r.AR_TJM_Ideal__c,
                   AR_Price_Matrix__r.AR_MC2_Percent__c, AR_Price_Matrix__r.AR_MC2_Per_Day__c,
                   AR_Price_Matrix__r.AR_Corridor_Segment__c, AR_Price_Matrix__r.AR_RFA_Percent__c,
                   AR_Price_Matrix__r.AR_Position__c, AR_Price_Matrix__r.AR_Total_Daily_Cost__c,
                   AR_Price_Matrix__r.AR_RPLSR_Enabled__c, AR_Price_Matrix__r.AR_RPLSR_Days_Sold__c,
                   AR_Price_Matrix__r.AR_RPLSR_Days_Produced__c
            FROM AR_Derogation__c
            ORDER BY AR_Requested_At__c DESC
        ];

        Set<Id> derogationIds = new Set<Id>();
        Set<Id> positionIds = new Set<Id>();
        for (AR_Derogation__c d : records) {
            derogationIds.add(d.Id);
            positionIds.add(d.AR_Price_Matrix__r.AR_Position__c);
        }
        Map<Id, List<String>> reasonsByDerogation = reasonLabelsByDerogation(derogationIds);
        // Une requête pour tous les besoins, puis une résolution de RFA par compte distinct (pas par ligne).
        Map<Id, Id> accountByPosition = AR_AccountHierarchy.accountsOfPositions(positionIds);
        Map<Id, AR_AdminCommercialService.RfaResult> rfaByAccount = accountRfaByAccount(
            new Set<Id>(accountByPosition.values())
        );

        List<DerogationListItem> items = new List<DerogationListItem>();
        for (AR_Derogation__c d : records) {
            DerogationListItem item = new DerogationListItem();
            item.derogationId = d.Id;
            item.matrixId = d.AR_Price_Matrix__c;
            item.matrixName = d.AR_Price_Matrix__r.Name;
            item.accountName = d.AR_Price_Matrix__r.AR_Account_Name__c;
            item.positionName = d.AR_Price_Matrix__r.AR_Position_Name__c;
            item.accountCountry = d.AR_Price_Matrix__r.AR_Account_Country__c;
            item.entity = d.AR_Price_Matrix__r.AR_Entity_Ref__r.Name;
            item.currencyCode = d.AR_Price_Matrix__r.AR_Currency__c;
            item.proposedTjm = AR_PricingMatrixService.effectiveTjm(d.AR_Price_Matrix__r);
            item.tjmPeriods = AR_PricingMatrixService.tjmPeriodsOf(d.AR_Price_Matrix__r);
            item.tjmFloor = d.AR_Price_Matrix__r.AR_TJM_Floor__c;
            item.tjmTarget = d.AR_Price_Matrix__r.AR_TJM_Target__c;
            item.tjmIdeal = d.AR_Price_Matrix__r.AR_TJM_Ideal__c;
            item.mc2PercentHuman = d.AR_Price_Matrix__r.AR_MC2_Percent__c;
            item.mc2PerDay = resolveMc2PerDay(
                d.AR_Price_Matrix__r.AR_MC2_Per_Day__c, item.proposedTjm, item.mc2PercentHuman
            );
            item.corridorSegment = d.AR_Price_Matrix__r.AR_Corridor_Segment__c;
            item.gapVsFloor = (item.proposedTjm != null && item.tjmFloor != null) ? item.proposedTjm - item.tjmFloor : null;
            item.rplsrMention = AR_PricingMatrixService.rplsrMention(d.AR_Price_Matrix__r);
            item.matrixRfaPercent = d.AR_Price_Matrix__r.AR_RFA_Percent__c;
            item.accountRfaPercent = rfaPercentOf(rfaByAccount, accountByPosition, d.AR_Price_Matrix__r.AR_Position__c);
            item.decision = d.AR_Decision__c;
            item.requesterReason = d.AR_Requester_Reason__c;
            item.reasonLabels = reasonsByDerogation.containsKey(d.Id) ? reasonsByDerogation.get(d.Id) : new List<String>();
            item.requesterName = d.CreatedBy.Name;
            item.requestedAt = d.AR_Requested_At__c;
            item.selectedValidatorName = d.AR_Selected_Validator__r != null ? d.AR_Selected_Validator__r.Name : null;
            item.effectiveValidatorName = d.AR_Effective_Validator__r != null ? d.AR_Effective_Validator__r.Name : null;
            item.validatorComment = d.AR_Validator_Comment__c;
            item.decidedAt = d.AR_Decided_At__c;
            item.isOwnRequest = isRequesterOrOwner(d);
            item.isAddressedToCurrentUser = isAddressedToCurrentUser(d);
            items.add(item);
        }
        return items;
    }

    /** RFA résolue pour chaque compte distinct (héritage parent → enfant). Les comptes nuls sont ignorés. */
    private static Map<Id, AR_AdminCommercialService.RfaResult> accountRfaByAccount(Set<Id> accountIds) {
        Map<Id, AR_AdminCommercialService.RfaResult> rfaByAccount = new Map<Id, AR_AdminCommercialService.RfaResult>();
        for (Id accountId : accountIds) {
            if (accountId != null) {
                rfaByAccount.put(accountId, AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(accountId));
            }
        }
        return rfaByAccount;
    }

    /** Pourcentage de RFA du compte d'un besoin, ou null si le compte ou sa RFA sont absents. */
    private static Decimal rfaPercentOf(
        Map<Id, AR_AdminCommercialService.RfaResult> rfaByAccount,
        Map<Id, Id> accountByPosition,
        Id positionId
    ) {
        Id accountId = accountByPosition.get(positionId);
        if (accountId == null || !rfaByAccount.containsKey(accountId) || rfaByAccount.get(accountId) == null) {
            return null;
        }
        return rfaByAccount.get(accountId).percent;
    }

    /**
     * Libellés des motifs cochés par le demandeur, par dérogation, dans l'ordre du référentiel (même
     * ordre que la modale de demande). Chaque identifiant demandé a une entrée, même sans motif.
     *
     * `without sharing` (DerogationReasonReader) : les motifs d'une dérogation ont AR_Price_Matrix__c
     * nul (contrôle XOR de AR_ReasonSelectionTriggerHandler), donc aucun partage de matrice ne les
     * couvre et un valideur ne les verrait pas en `with sharing`. Le périmètre est déjà tranché par
     * l'appelant (AR_Approve_Derogation pour la file, lecture de la dérogation pour le contexte). Lecture seule.
     */
    public static Map<Id, List<String>> reasonLabelsByDerogation(Set<Id> derogationIds) {
        Map<Id, List<String>> labels = new Map<Id, List<String>>();
        for (Id derogationId : derogationIds) {
            labels.put(derogationId, new List<String>());
        }
        if (derogationIds.isEmpty()) {
            return labels;
        }
        for (AR_Reason_Selection__c sel : new DerogationReasonReader().read(derogationIds)) {
            labels.get(sel.AR_Derogation__c).add(sel.AR_Reason__r.Name);
        }
        return labels;
    }

    private without sharing class DerogationReasonReader {
        List<AR_Reason_Selection__c> read(Set<Id> derogationIds) {
            return Database.query(
                'SELECT AR_Derogation__c, AR_Reason__r.Name FROM AR_Reason_Selection__c ' +
                'WHERE AR_Derogation__c IN :derogationIds ' +
                'ORDER BY AR_Reason__r.AR_Sort_Order__c ASC NULLS LAST, AR_Reason__r.Name ASC',
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    /**
     * Adressée au valideur sélectionné, seulement (session 40). L'ancienne version élargissait au
     * cercle des valideurs habilités de l'entité (job title, lisible en AccessLevel.SYSTEM_MODE) —
     * ce cercle n'est plus calculable depuis ce contexte utilisateur standard : on ne peut pas savoir
     * si un AUTRE utilisateur détient la Custom Permission AR_Approve_Derogation sans requêter
     * PermissionSetAssignment/SetupEntityAccess, qui lèvent System.SecurityException sans « View
     * Setup and Configuration » (cf. docs/40-habilitation-par-permission.md §4, même contrainte que
     * la combobox de sélection du valideur). « À traiter par moi » signifie donc désormais, au sens
     * strict, « je suis le valideur sélectionné » — plus simple, et compatible avec le modèle.
     */
    private static Boolean isAddressedToCurrentUser(AR_Derogation__c d) {
        return d.AR_Selected_Validator__c == UserInfo.getUserId() && !isRequesterOrOwner(d);
    }

    /** Vrai si l'utilisateur courant a fait la demande (CreatedById) ou possède la matrice : il ne
     * peut alors ni valider ni refuser, quelle que soit sa permission ou sa place dans la chaîne.
     * Nécessite CreatedById et AR_Price_Matrix__r.OwnerId dans la requête de d. */
    private static Boolean isRequesterOrOwner(AR_Derogation__c d) {
        Id me = UserInfo.getUserId();
        return d.CreatedById == me || d.AR_Price_Matrix__r.OwnerId == me;
    }

    /** Compteur léger pour le badge de sidebar (rafraîchi à l'ouverture de l'app). Session 136 :
     * porteurs de la permission seulement, cohérent avec listDerogations().
     * Session 117 : changé en non-cacheable pour que les appels impératifs (refreshDerogationApproverState)
     * voient toujours les données courantes, pas la valeur en cache après une nouvelle demande.
     */
    @AuraEnabled
    public static Integer countPendingDerogations() {
        try {
            // Session 136 : sans la permission, pas de file, donc pas de badge.
            if (!isCurrentUserValidator() || !Schema.sObjectType.AR_Derogation__c.isAccessible()) {
                return 0;
            }
            Id me = UserInfo.getUserId();
            return [
                SELECT COUNT() FROM AR_Derogation__c
                WHERE AR_Decision__c = 'En attente' AND CreatedById != :me AND AR_Price_Matrix__r.OwnerId != :me
            ];
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_DRG_PendingCountAction);
        }
    }

    public class CurrentUserIdentity {
        @AuraEnabled public String name;
        @AuraEnabled public String jobTitle;
    }

    /** En-tête « Connecté : Nom (job title) » de la file d'approbation. */
    @AuraEnabled(cacheable=true)
    public static CurrentUserIdentity getCurrentUserIdentity() {
        User u = [SELECT Name, TP_Job_Title__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        CurrentUserIdentity identity = new CurrentUserIdentity();
        identity.name = u.Name;
        identity.jobTitle = u.TP_Job_Title__c;
        return identity;
    }

    /**
     * Session 143 : MC2/jour affichée au valideur à côté de la MC2 %. Valeur stockée sur la matrice
     * (devise de la matrice) ; repli pour les matrices anciennes sans valeur : TJM × MC2 % / 100,
     * arrondi à 2 décimales (identité de calcMC2). Null si le repli n'a pas ses deux entrées.
     */
    public static Decimal resolveMc2PerDay(Decimal stored, Decimal proposedTjm, Decimal mc2Percent) {
        if (stored != null) {
            return stored;
        }
        if (proposedTjm == null || mc2Percent == null) {
            return null;
        }
        return (proposedTjm * mc2Percent / 100).setScale(2);
    }

    public class DerogationContext {
        @AuraEnabled public Id derogationId;
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String matrixStatus;
        @AuraEnabled public String decision;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal proposedTjm;
        @AuraEnabled public List<AR_PricingResult.TjmPeriod> tjmPeriods;
        @AuraEnabled public Decimal mc2PercentHuman;
        @AuraEnabled public Decimal mc2PerDay;
        @AuraEnabled public String rplsrMention;
        @AuraEnabled public String corridorSegment;
        @AuraEnabled public Decimal tjmFloor;
        @AuraEnabled public Decimal tjmTarget;
        @AuraEnabled public Decimal tjmIdeal;
        @AuraEnabled public Decimal matrixRfaPercent;
        @AuraEnabled public Decimal accountRfaPercent;
        @AuraEnabled public Decimal gapVsFloor;
        @AuraEnabled public Decimal gapVsTarget;
        @AuraEnabled public String requesterReason;
        @AuraEnabled public List<String> reasonLabels;
        @AuraEnabled public Boolean currentUserIsValidator;
        @AuraEnabled public Boolean isOwnRequest;
        // Session 33 §2 : bandeau de verrouillage visuel post-décision (arDerogationPanel) — ces
        // trois informations sont déjà en base, seulement pas exposées jusqu'ici à ce contrôleur.
        @AuraEnabled public String effectiveValidatorName;
        @AuraEnabled public Datetime decidedAt;
        @AuraEnabled public String validatorComment;
    }

    @AuraEnabled(cacheable=true)
    public static DerogationContext getContext(Id matrixId) {
        AR_Price_Matrix__c m = [
            SELECT OwnerId, AR_Status__c, AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_Periods__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_MC2_Percent__c, AR_MC2_Per_Day__c, AR_Corridor_Segment__c,
                   AR_TJM_Floor__c, AR_TJM_Target__c, AR_TJM_Ideal__c, AR_Currency__c,
                   AR_RFA_Percent__c, AR_Position__c, AR_Total_Daily_Cost__c,
                   AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c
            FROM AR_Price_Matrix__c
            WHERE Id = :matrixId
            LIMIT 1
        ];
        List<AR_Derogation__c> derogations = [
            SELECT Id, CreatedById, AR_Requester_Reason__c, AR_Decision__c, AR_Effective_Validator__r.Name,
                   AR_Decided_At__c, AR_Validator_Comment__c
            FROM AR_Derogation__c
            WHERE AR_Price_Matrix__c = :matrixId
            ORDER BY AR_Requested_At__c DESC
            LIMIT 1
        ];

        DerogationContext ctx = new DerogationContext();
        ctx.matrixId = matrixId;
        ctx.matrixStatus = m.AR_Status__c;
        ctx.currencyCode = m.AR_Currency__c;
        // Prix de la mission : le TJM moyen pondéré (docs/254 §1), jamais la seule période 1.
        ctx.proposedTjm = AR_PricingMatrixService.effectiveTjm(m);
        ctx.tjmPeriods = AR_PricingMatrixService.tjmPeriodsOf(m);
        ctx.mc2PercentHuman = m.AR_MC2_Percent__c;
        ctx.mc2PerDay = resolveMc2PerDay(m.AR_MC2_Per_Day__c, ctx.proposedTjm, m.AR_MC2_Percent__c);
        ctx.corridorSegment = m.AR_Corridor_Segment__c;
        ctx.tjmFloor = m.AR_TJM_Floor__c;
        ctx.tjmTarget = m.AR_TJM_Target__c;
        ctx.tjmIdeal = m.AR_TJM_Ideal__c;
        // RFA de la matrice et RFA enregistrée pour le compte (héritage parent → enfant), information seule.
        ctx.matrixRfaPercent = m.AR_RFA_Percent__c;
        ctx.rplsrMention = AR_PricingMatrixService.rplsrMention(m);
        AR_AdminCommercialService.RfaResult accountRfa = AR_AdminCommercialService.getDefaultRfaPercentWithProvenance(
            AR_AccountHierarchy.accountOfPosition(m.AR_Position__c)
        );
        ctx.accountRfaPercent = accountRfa != null ? accountRfa.percent : null;
        ctx.gapVsFloor = (ctx.proposedTjm != null && m.AR_TJM_Floor__c != null) ? ctx.proposedTjm - m.AR_TJM_Floor__c : null;
        ctx.gapVsTarget = (ctx.proposedTjm != null && m.AR_TJM_Target__c != null) ? ctx.proposedTjm - m.AR_TJM_Target__c : null;
        if (!derogations.isEmpty()) {
            ctx.derogationId = derogations[0].Id;
            ctx.requesterReason = derogations[0].AR_Requester_Reason__c;
            ctx.reasonLabels = reasonLabelsByDerogation(new Set<Id>{ derogations[0].Id }).get(derogations[0].Id);
            ctx.decision = derogations[0].AR_Decision__c;
            ctx.effectiveValidatorName = derogations[0].AR_Effective_Validator__r != null ? derogations[0].AR_Effective_Validator__r.Name : null;
            ctx.decidedAt = derogations[0].AR_Decided_At__c;
            ctx.validatorComment = derogations[0].AR_Validator_Comment__c;
        }
        ctx.currentUserIsValidator = isCurrentUserValidator();
        ctx.isOwnRequest = m.OwnerId == UserInfo.getUserId()
            || (!derogations.isEmpty() && derogations[0].CreatedById == UserInfo.getUserId());
        return ctx;
    }

    /**
     * Session 112 : encart dans le simulateur — cherche une dérogation en attente sur la matrice ouverte
     * et vérifie l'habilitation de l'utilisateur courant à la traiter. Retourne null s'il n'y a pas de
     * dérogation, ou si l'utilisateur n'est pas habilité (non-cacheable : état change à chaque décision,
     * un cache afficherait un encart pour une dérogation déjà traitée).
     *
     * Habilitation : exactement celle de decide() (permission AR_Approve_Derogation, session 136).
     */
    @AuraEnabled
    public static PendingDerogationDTO getPendingDerogationForCurrentUser(Id matrixId) {
        try {
            // Session 136 : habilitation = la permission, rien d'autre.
            if (!isCurrentUserValidator()) {
                return null;
            }

            List<AR_Derogation__c> derogations = new AccessControlledDerogationReader()
                .getDerogationsForMatrices(new Set<Id>{ matrixId });

            for (AR_Derogation__c d : derogations) {
                if (d.AR_Decision__c == 'En attente') {
                    if (isRequesterOrOwner(d)) {
                        return null;
                    }
                    PendingDerogationDTO dto = new PendingDerogationDTO();
                    dto.derogationId = d.Id;
                    dto.requesterName = d.CreatedBy.Name;
                    dto.requestedAt = d.AR_Requested_At__c;
                    dto.selectedValidatorName = d.AR_Selected_Validator__r != null ? d.AR_Selected_Validator__r.Name : null;
                    dto.isAddressedToCurrentUser = isAddressedToCurrentUser(d);
                    return dto;
                }
            }

            return null;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_DRG_FindPendingAction);
        }
    }

    /**
     * Accepter → Validée par dérogation + snapshot. Refuser → Refusée + snapshot (pas de réédition,
     * le BM doit créer une nouvelle matrice). Renvoie l'avertissement d'envoi (null si les
     * notifications sont parties). AR_Effective_Validator__c peut différer du valideur
     * sélectionné — les deux sont conservés (cf. CLAUDE.md workflow §4).
     */
    @AuraEnabled
    public static AR_NotificationService.DeliveryWarning decide(Id derogationId, String decision, String comment) {
        if (decision != 'Acceptée' && decision != 'Refusée') {
            throw newAuraException(Label.AR_Msg_DRG_InvalidDecision);
        }
        if (String.isBlank(comment)) {
            throw newAuraException(Label.AR_DRG_CommentMandatory);
        }
        if (!isCurrentUserAuthorizedFor(derogationId)) {
            throw newAuraException(Label.AR_Msg_DRG_NotAuthorized);
        }

        // FOR UPDATE verrouille la ligne pour la transaction : une seconde décision concurrente sur
        // la même dérogation attend puis échoue au contrôle de statut ci-dessous (pas de double traitement).
        AR_Derogation__c derogation = [
            SELECT Id, AR_Decision__c, AR_Price_Matrix__c, CreatedById, AR_Price_Matrix__r.OwnerId
            FROM AR_Derogation__c
            WHERE Id = :derogationId
            LIMIT 1
            FOR UPDATE
        ];
        if (isRequesterOrOwner(derogation)) {
            throw newAuraException(Label.AR_Msg_DRG_OwnRequest);
        }
        if (derogation.AR_Decision__c != 'En attente') {
            throw newAuraException(Label.AR_Msg_DRG_AlreadyProcessed);
        }

        try {
            derogation.AR_Decision__c = decision;
            derogation.AR_Validator_Comment__c = comment;
            derogation.AR_Effective_Validator__c = UserInfo.getUserId();
            derogation.AR_Decided_At__c = System.now();

            String newStatus = decision == 'Acceptée' ? 'Validée par dérogation' : 'Refusée';
            AR_Price_Matrix__c matrixUpdate = new AR_Price_Matrix__c(
                Id = derogation.AR_Price_Matrix__c,
                AR_Status__c = newStatus,
                AR_Effective_Validator__c = UserInfo.getUserId()
            );
            if (decision == 'Acceptée') {
                matrixUpdate.AR_Validated_At__c = System.now();
                matrixUpdate.AR_Perimeter__c = AR_PerimeterSnapshot.perimeterOfMatrix(derogation.AR_Price_Matrix__c);
            }

            // L'habilitation est déjà vérifiée ci-dessus (isCurrentUserValidator) : AccessLevel.SYSTEM_MODE
            // ici évite un faux-négatif FLS observé en contexte de test sur ce champ Master-Detail
            // (AR_Derogation__c est ControlledByParent) — mais AccessLevel.SYSTEM_MODE, posé depuis une
            // classe `with sharing` (celle-ci), ne contourne QUE le CRUD/FLS, jamais le PARTAGE (constaté
            // en session 40, testRunAs_validatorPermissionSetHolder_canDecideAndSeesQueue :
            // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY pour un valideur habilité mais non partagé sur
            // la matrice d'un autre BM — AR_Pricing_Validator/_Admin accordent viewAllRecords, lecture
            // seule org-wide, jamais modifyAllRecords). UnsharedDecisionWriter apporte le second bypass
            // nécessaire (`without sharing`), même motif documenté que l'ancien UnsharedPendingCounter de
            // ce fichier (retiré session 40) — sans risque : l'habilitation est déjà tranchée avant cet
            // appel, jamais l'inverse.
            // AccessLevel.SYSTEM_MODE ne contourne pas AR_DerogationTrigger (qui bloque toute édition
            // hors service) : le bypass doit être positionné explicitement, dans un try/finally.
            AR_TriggerBypass.serviceContext = true;
            try {
                new UnsharedDecisionWriter().apply(derogation, matrixUpdate);
            } finally {
                AR_TriggerBypass.serviceContext = false;
            }

            AR_MatrixVersionService.createSnapshot(derogation.AR_Price_Matrix__c, decision == 'Acceptée' ? 'derogation_acceptee' : 'derogation_refusee');
            AR_NotificationService.sendDerogationResultEmails(derogation.Id);
            return AR_NotificationService.consumeWarning();
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_DRG_DecisionAction);
        }
    }

    /** Écriture de la décision (dérogation + matrice) hors partage — cf. commentaire dans decide().
     * `without sharing` + AccessLevel.SYSTEM_MODE ensemble, jamais un seul des deux : la doc
     * Salesforce est explicite, SYSTEM_MODE seul ignore CRUD/FLS mais pas le partage, qui reste
     * gouverné par le mot-clé de la classe où la requête/DML s'exécute. */
    private without sharing class UnsharedDecisionWriter {
        void apply(AR_Derogation__c derogation, AR_Price_Matrix__c matrixUpdate) {
            Database.update(derogation, AccessLevel.SYSTEM_MODE);
            Database.update(matrixUpdate, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Session 136, décision d'Alexis du 02/10/2026 : traiter une dérogation exige la Custom Permission
     * AR_Approve_Derogation (portée par AR_Pricing_Validator), et rien d'autre. Être DA, DD ou
     * Directeur du propriétaire de la matrice ne suffit PAS, même Directeur : cette chaîne sert à
     * proposer un valideur et à escalader les relances, jamais à autoriser (supprime le chemin
     * relationnel de la session 79). Exposé pour la file d'approbation et pour masquer l'onglet côté
     * arPricingApp.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserValidator() {
        return FeatureManagement.checkPermission('AR_Approve_Derogation');
    }

    /** Vrai si l'utilisateur courant détient la permission de validation ET que la dérogation existe.
     * Utilisé par decide(). */
    public static Boolean isCurrentUserAuthorizedFor(Id derogationId) {
        if (!isCurrentUserValidator()) {
            return false;
        }
        return ![SELECT Id FROM AR_Derogation__c WHERE Id = :derogationId LIMIT 1].isEmpty();
    }

    /** Helper class (without sharing) pour lire les dérogations d'un ensemble de matrices en SYSTEM_MODE.
     * Lecture de la dérogation en attente d'une matrice (getPendingDerogationForCurrentUser).
     */
    private without sharing class AccessControlledDerogationReader {
        List<AR_Derogation__c> getDerogationsForMatrices(Set<Id> matrixIds) {
            return [
                SELECT Id, AR_Decision__c, AR_Requester_Reason__c, AR_Validator_Comment__c,
                       AR_Requested_At__c, AR_Decided_At__c, CreatedBy.Name, CreatedById, AR_Selected_Validator__c,
                       AR_Selected_Validator__r.Name, AR_Effective_Validator__r.Name, AR_Price_Matrix__r.OwnerId,
                       AR_Price_Matrix__c, AR_Price_Matrix__r.Name, AR_Price_Matrix__r.AR_Account_Name__c,
                       AR_Price_Matrix__r.AR_Position_Name__c, AR_Price_Matrix__r.AR_Account_Country__c,
                       AR_Price_Matrix__r.AR_Entity_Ref__r.Name, AR_Price_Matrix__r.AR_Currency__c,
                       AR_Price_Matrix__r.AR_Proposed_TJM__c, AR_Price_Matrix__r.AR_TJM_Weighted__c, AR_Price_Matrix__r.AR_TJM_Periods__c, AR_Price_Matrix__r.AR_Number_Of_Days__c, AR_Price_Matrix__r.AR_Planned_Leave_Days__c, AR_Price_Matrix__r.AR_RPLSR_Enabled__c, AR_Price_Matrix__r.AR_RPLSR_Days_Sold__c, AR_Price_Matrix__r.AR_RPLSR_Days_Produced__c, AR_Price_Matrix__r.AR_TJM_Floor__c,
                       AR_Price_Matrix__r.AR_TJM_Target__c, AR_Price_Matrix__r.AR_TJM_Ideal__c,
                       AR_Price_Matrix__r.AR_MC2_Percent__c, AR_Price_Matrix__r.AR_Corridor_Segment__c
                FROM AR_Derogation__c
                WHERE AR_Price_Matrix__c IN :matrixIds
                ORDER BY AR_Requested_At__c DESC
            ];
        }
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}