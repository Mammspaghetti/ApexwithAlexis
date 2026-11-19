/**
 * Duplication et lecture de la chaîne de négociation (session 22, cf. docs/22-versioning-negociation.md).
 * `with sharing` : le partage normal de l'utilisateur courant gate déjà l'accès à la matrice source.
 *
 * Règle de filiation (tranchée avec Alexis, pas un choix explicite de l'utilisateur dans la
 * modale) : le comportement dépend du STATUT de la matrice source, pas du besoin cible choisi.
 * - Source décidée (Validée / Validée par dérogation / Refusée) → filiation enregistrée + motif
 *   obligatoire. Le refus n'est pas laissé orphelin : la chaîne 480 € refusé → 520 € validé est
 *   la donnée la plus utile du dispositif.
 * - Source Brouillon → duplication libre (cas manager/simulation), sans filiation, sans motif.
 */
public with sharing class AR_MatrixChainService {

    private static final Set<String> DECIDED_STATUSES = new Set<String>{
        'Validée', 'Validée par dérogation', 'Refusée'
    };

    public class DuplicateResult {
        @AuraEnabled
        public Id matrixId;
    }

    /** Prix de négociation 2 et 3 d'une matrice (indicatifs), proposés à la duplication. */
    public class NegotiationPrices {
        @AuraEnabled public Decimal price2;
        @AuraEnabled public Decimal price3;
        @AuraEnabled public String currencyCode;
    }

    public class ChainNode {
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal negotiationVersion;
        // Session 180a : 'Négociation' ou 'Avenant' ; null (matrices antérieures) se lit comme 'Négociation'.
        @AuraEnabled public String versionType;
        @AuraEnabled public String status;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal proposedTjm;
        @AuraEnabled public List<AR_PricingResult.TjmPeriod> tjmPeriods;
        @AuraEnabled public Decimal mc2PercentHuman;
        @AuraEnabled public Decimal mc2PerDay;
        @AuraEnabled public String corridorSegment;
        @AuraEnabled public Datetime decidedAt;
        @AuraEnabled public String changeComment;
        @AuraEnabled public List<String> reasons;
    }

    /** Détection de chaîne partiellement visible (même famille de défaut que le PDF vide
     * silencieux de la session 20) : ne jamais présenter une liste tronquée comme complète. */
    public class ChainResult {
        @AuraEnabled public List<ChainNode> nodes;
        @AuraEnabled public Boolean partiallyVisible;
    }

    /** Lecture de la matrice source d'une copie (liste de champs unique, partagée avec AR_AvenantService). */
    public static AR_Price_Matrix__c loadSource(Id sourceMatrixId) {
        return [
            SELECT
                Id, AR_Position__c, AR_Status__c, AR_Root_Matrix__c,
                AR_Currency__c, AR_Contract_Type__c, AR_Annual_Salary__c, AR_CJM_Before_Markup__c,
                AR_Markup_Applied__c, AR_CJM_VIE__c, AR_CJM_Nearshore__c, AR_VIE_Country__c, AR_Nearshore_Country__c,
                AR_Fee_IK__c, AR_Fee_Meals__c, AR_Fee_Lodging__c, AR_Fee_OM_Other__c, AR_Fee_Periods__c, AR_TJM_Periods__c, AR_Salary_Periods__c, AR_Gratuity_Days__c,
                AR_RPLSR_Enabled__c, AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Plan__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
                AR_Fee_Computer__c, AR_Fee_Phone__c, AR_Fee_Monthly_Other__c, AR_Fee_Training__c, AR_Fee_EPI__c, AR_Fee_OFII_Tax__c, AR_Fee_Other__c,
                AR_RFA_Percent__c, AR_Proposed_TJM__c, AR_Nego_Price_2__c, AR_Nego_Price_3__c, AR_Client_Grid__c,
                AR_Entity_Ref__c, AR_Consultant_Name__c, AR_Consultant__c, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_Seniority__c,
                AR_Version_Type__c, AR_Amended_PTF__c
            FROM AR_Price_Matrix__c
            WHERE Id = :sourceMatrixId
            LIMIT 1
        ];
    }

    public static Boolean isDecided(AR_Price_Matrix__c source) {
        return DECIDED_STATUSES.contains(source.AR_Status__c);
    }

    /**
     * Copie NON insérée de `source` : contexte affaire (Zone 1) + contexte financier (Zone 2) — jamais
     * statut décidé, horodatages de décision, valideurs, ni lien de dérogation. Session 180a : jamais
     * non plus AR_Version_Type__c, AR_Amended_PTF__c, AR_Avenant_Changes__c — dupliquer un avenant donne
     * une version de négociation ordinaire ; c'est AR_AvenantService qui les pose, sur la copie renvoyée
     * ici (session 180b : méthode extraite de duplicateMatrix, pour ne pas dupliquer la liste de champs).
     * `chained` : la copie est une version de la chaîne de `source` (filiation, rang, commentaire).
     */
    public static AR_Price_Matrix__c buildCopy(
        AR_Price_Matrix__c source,
        Id resolvedTargetPositionId,
        Boolean chained,
        String changeComment
    ) {
        AR_Price_Matrix__c copy = new AR_Price_Matrix__c();
        copy.AR_Position__c = resolvedTargetPositionId;
        copy.AR_Status__c = 'Brouillon';
        copy.AR_Currency__c = source.AR_Currency__c;
        copy.AR_Contract_Type__c = source.AR_Contract_Type__c;
        copy.AR_Annual_Salary__c = source.AR_Annual_Salary__c;
        copy.AR_CJM_Before_Markup__c = source.AR_CJM_Before_Markup__c;
        copy.AR_Markup_Applied__c = source.AR_Markup_Applied__c;
        copy.AR_CJM_VIE__c = source.AR_CJM_VIE__c;
        copy.AR_CJM_Nearshore__c = source.AR_CJM_Nearshore__c;
        copy.AR_VIE_Country__c = source.AR_VIE_Country__c;
        copy.AR_Nearshore_Country__c = source.AR_Nearshore_Country__c;
        copy.AR_Fee_IK__c = source.AR_Fee_IK__c;
        copy.AR_Fee_Meals__c = source.AR_Fee_Meals__c;
        copy.AR_Fee_Lodging__c = source.AR_Fee_Lodging__c;
        copy.AR_Fee_OM_Other__c = source.AR_Fee_OM_Other__c;
        copy.AR_Fee_Periods__c = source.AR_Fee_Periods__c;
        copy.AR_TJM_Periods__c = source.AR_TJM_Periods__c;
        copy.AR_Salary_Periods__c = source.AR_Salary_Periods__c;
        copy.AR_RPLSR_Enabled__c = source.AR_RPLSR_Enabled__c;
        copy.AR_RPLSR_Days_Per_Month__c = source.AR_RPLSR_Days_Per_Month__c;
        copy.AR_RPLSR_Plan__c = source.AR_RPLSR_Plan__c;
        copy.AR_RPLSR_Days_Sold__c = source.AR_RPLSR_Days_Sold__c;
        copy.AR_RPLSR_Days_Produced__c = source.AR_RPLSR_Days_Produced__c;
        copy.AR_Gratuity_Days__c = source.AR_Gratuity_Days__c;
        copy.AR_Fee_Computer__c = source.AR_Fee_Computer__c;
        copy.AR_Fee_Phone__c = source.AR_Fee_Phone__c;
        copy.AR_Fee_Monthly_Other__c = source.AR_Fee_Monthly_Other__c;
        copy.AR_Fee_Training__c = source.AR_Fee_Training__c;
        copy.AR_Fee_EPI__c = source.AR_Fee_EPI__c;
        copy.AR_Fee_OFII_Tax__c = source.AR_Fee_OFII_Tax__c;
        copy.AR_Fee_Other__c = source.AR_Fee_Other__c;
        copy.AR_RFA_Percent__c = source.AR_RFA_Percent__c;
        copy.AR_Proposed_TJM__c = source.AR_Proposed_TJM__c;
        copy.AR_Nego_Price_2__c = source.AR_Nego_Price_2__c;
        copy.AR_Nego_Price_3__c = source.AR_Nego_Price_3__c;
        copy.AR_Client_Grid__c = source.AR_Client_Grid__c;
        copy.AR_Entity_Ref__c = source.AR_Entity_Ref__c;
        copy.AR_Consultant_Name__c = source.AR_Consultant_Name__c;
        copy.AR_Consultant__c = source.AR_Consultant__c;
        copy.AR_Client_Site__c = source.AR_Client_Site__c;
        copy.AR_Start_Date__c = source.AR_Start_Date__c;
        copy.AR_End_Date__c = source.AR_End_Date__c;
        copy.AR_Number_Of_Days__c = source.AR_Number_Of_Days__c;
        copy.AR_Planned_Leave_Days__c = source.AR_Planned_Leave_Days__c;
        copy.AR_Seniority__c = source.AR_Seniority__c;

        AR_PricingMatrixService.PositionContext posCtx = AR_PricingMatrixService.requireAccessiblePositionContext(
            resolvedTargetPositionId
        );
        copy.AR_Account_Name__c = posCtx.accountName;
        copy.AR_Account_Country__c = posCtx.accountCountry;
        copy.AR_Manager_Contact__c = posCtx.managerContactId;
        copy.AR_Position_Name__c = posCtx.positionName;

        if (chained) {
            Id rootId = source.AR_Root_Matrix__c != null ? source.AR_Root_Matrix__c : source.Id;
            copy.AR_Previous_Version__c = source.Id;
            copy.AR_Root_Matrix__c = rootId;
            copy.AR_Negotiation_Version__c = AR_MatrixChainVisibility.maxNegotiationVersion(rootId) + 1;
            copy.AR_Version_Change_Comment__c = changeComment;
        }
        return copy;
    }

    public static DuplicateResult duplicateMatrix(
        Id sourceMatrixId,
        Id targetPositionId,
        List<Id> reasonIds,
        String changeComment
    ) {
        return duplicateMatrixWithPrice(sourceMatrixId, targetPositionId, reasonIds, changeComment, null);
    }

    /**
     * Pose sur `copy` le prix de négociation choisi comme TJM proposé (`priceChoice` = 'P2' ou 'P3' ;
     * toute autre valeur, dont null = « garder le TJM actuel », ne change rien). Les prix restants
     * strictement inférieurs au prix choisi sont conservés et remontent d'un rang ; les autres sont
     * vidés. Un prix choisi absent de la source laisse la copie inchangée.
     */
    public static void applyNegotiationPriceChoice(AR_Price_Matrix__c copy, String priceChoice) {
        Decimal chosen;
        Decimal other;
        if (priceChoice == 'P2') {
            chosen = copy.AR_Nego_Price_2__c;
            other = copy.AR_Nego_Price_3__c;
        } else if (priceChoice == 'P3') {
            chosen = copy.AR_Nego_Price_3__c;
            other = null;
        } else {
            return;
        }
        if (chosen == null) {
            return;
        }
        copy.AR_Proposed_TJM__c = chosen;
        // Prix unique : la duplication « pour un nouveau prix » efface les périodes de TJM (docs/254 §5).
        copy.AR_TJM_Periods__c = null;
        copy.AR_Nego_Price_2__c = other != null && other < chosen ? other : null;
        copy.AR_Nego_Price_3__c = null;
    }

    /** Duplication avec choix du prix qui devient le TJM proposé de la copie (cf. applyNegotiationPriceChoice). */
    @AuraEnabled
    public static DuplicateResult duplicateMatrixWithPrice(
        Id sourceMatrixId,
        Id targetPositionId,
        List<Id> reasonIds,
        String changeComment,
        String priceChoice
    ) {
        AR_Price_Matrix__c source = loadSource(sourceMatrixId);

        Boolean isChainDuplication = isDecided(source);
        if (isChainDuplication && (reasonIds == null || reasonIds.isEmpty())) {
            throw newAuraException(
                Label.AR_Msg_MCH_ReasonRequired
            );
        }

        Id resolvedTargetPositionId = targetPositionId != null ? targetPositionId : source.AR_Position__c;

        try {
            AR_Price_Matrix__c copy = buildCopy(source, resolvedTargetPositionId, isChainDuplication, changeComment);
            applyNegotiationPriceChoice(copy, priceChoice);

            // Session 41 : AR_Account_Name__c/AR_Position_Name__c... (Zone 1, dénormalisées depuis le
            // besoin) sont editable=false pour AR_Pricing_User — même motif que
            // AR_PricingMatrixService.saveDraftInput, jamais exercé sous System.runAs avant cette
            // session. Le partage (with sharing, classe entière) reste pleinement appliqué.
            Database.insert(copy, AccessLevel.SYSTEM_MODE);

            if (isChainDuplication) {
                AR_ReasonService.insertSelections(copy.Id, null, reasonIds);
            }

            DuplicateResult result = new DuplicateResult();
            result.matrixId = copy.Id;
            return result;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_MCH_DuplicateAction);
        }
    }

    /** Lecture à l'ouverture de la modale de duplication : jamais cacheable, les prix changent à chaque saisie. */
    @AuraEnabled
    public static NegotiationPrices getNegotiationPrices(Id matrixId) {
        try {
            AR_Price_Matrix__c m = [
                SELECT AR_Nego_Price_2__c, AR_Nego_Price_3__c, AR_Currency__c
                FROM AR_Price_Matrix__c
                WHERE Id = :matrixId
                LIMIT 1
            ];
            NegotiationPrices result = new NegotiationPrices();
            result.price2 = m.AR_Nego_Price_2__c;
            result.price3 = m.AR_Nego_Price_3__c;
            result.currencyCode = m.AR_Currency__c;
            return result;
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, Label.AR_Msg_MCH_DuplicateAction);
        }
    }

    /** Session 279 : documents PTF/avenant générés sur une version précédente de la chaîne. */
    public class PreviousVersionDocument {
        @AuraEnabled public Id ptfDocumentId;
        @AuraEnabled public String reference;
        @AuraEnabled public String documentType;
        @AuraEnabled public Integer versionNumber;
        @AuraEnabled public Integer avenantNumber;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Boolean clientAddressModified;
    }

    /** Session 279 : une version précédente de la chaîne et ses documents visibles. */
    public class PreviousVersionGroup {
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String matrixName;
        @AuraEnabled public Integer negotiationVersion;
        @AuraEnabled public Datetime validatedAt;
        @AuraEnabled public List<PreviousVersionDocument> documents = new List<PreviousVersionDocument>();
    }

    /**
     * Session 279 : une matrice dupliquée (V2) n'affiche plus les PTF de la V1, rattachées à la V1
     * (maître-détail AR_PTF_Document__c.AR_Price_Matrix__c). Renvoie, version la plus récente en
     * premier, les versions de la même chaîne de rang inférieur et leurs documents générés — lecture
     * seule. Classe `with sharing` : une version ou un document que l'utilisateur ne voit pas est
     * simplement absent, sans message. Appel impératif (bouton Actualiser) : jamais cacheable.
     */
    @AuraEnabled
    public static List<PreviousVersionGroup> getPreviousVersionDocuments(Id matrixId) {
        List<PreviousVersionGroup> groups = new List<PreviousVersionGroup>();
        List<AR_Price_Matrix__c> anchors = [
            SELECT Id, AR_Root_Matrix__c, AR_Negotiation_Version__c
            FROM AR_Price_Matrix__c
            WHERE Id = :matrixId
            LIMIT 1
        ];
        if (anchors.isEmpty() || anchors[0].AR_Negotiation_Version__c == null) {
            return groups;
        }
        AR_Price_Matrix__c anchor = anchors[0];
        Id rootId = anchor.AR_Root_Matrix__c != null ? anchor.AR_Root_Matrix__c : anchor.Id;
        Decimal currentVersion = anchor.AR_Negotiation_Version__c;

        Map<Id, PreviousVersionGroup> byMatrix = new Map<Id, PreviousVersionGroup>();
        List<PreviousVersionGroup> ordered = new List<PreviousVersionGroup>();
        for (AR_Price_Matrix__c m : [
            SELECT Id, Name, AR_Negotiation_Version__c, AR_Validated_At__c
            FROM AR_Price_Matrix__c
            WHERE (Id = :rootId OR AR_Root_Matrix__c = :rootId)
              AND Id != :matrixId
              AND (AR_Negotiation_Version__c < :currentVersion OR AR_Negotiation_Version__c = null)
            ORDER BY AR_Negotiation_Version__c DESC NULLS LAST
        ]) {
            PreviousVersionGroup g = new PreviousVersionGroup();
            g.matrixId = m.Id;
            g.matrixName = m.Name;
            // Racine antérieure au versioning (rang vide) : c'est la V1 de la chaîne.
            g.negotiationVersion = m.AR_Negotiation_Version__c == null ? 1 : m.AR_Negotiation_Version__c.intValue();
            g.validatedAt = m.AR_Validated_At__c;
            byMatrix.put(m.Id, g);
            ordered.add(g);
        }
        if (byMatrix.isEmpty()) {
            return groups;
        }
        for (AR_PTF_Document__c doc : [
            SELECT Id, AR_Price_Matrix__c, AR_Reference__c, AR_Document_Type__c, AR_Version_Number__c,
                   AR_Avenant_Number__c, AR_Generated_At__c, AR_Content_Document_Id__c, AR_Snapshot__c
            FROM AR_PTF_Document__c
            WHERE AR_Price_Matrix__c IN :byMatrix.keySet()
              AND AR_Generation_Status__c = 'Généré'
            ORDER BY AR_Generated_At__c DESC
        ]) {
            PreviousVersionDocument d = new PreviousVersionDocument();
            d.ptfDocumentId = doc.Id;
            d.reference = doc.AR_Reference__c;
            d.documentType = String.isNotBlank(doc.AR_Document_Type__c) ? doc.AR_Document_Type__c : 'PTF';
            d.versionNumber = doc.AR_Version_Number__c == null ? null : doc.AR_Version_Number__c.intValue();
            d.avenantNumber = doc.AR_Avenant_Number__c == null ? null : doc.AR_Avenant_Number__c.intValue();
            d.generatedAt = doc.AR_Generated_At__c;
            d.contentDocumentId = String.isNotBlank(doc.AR_Content_Document_Id__c)
                ? Id.valueOf(doc.AR_Content_Document_Id__c)
                : null;
            d.clientAddressModified = AR_PTFHistoryService.isClientAddressModified(doc.AR_Snapshot__c);
            byMatrix.get(doc.AR_Price_Matrix__c).documents.add(d);
        }
        // Ordre de la requête des matrices conservé (version la plus récente en premier) ; une version
        // sans document visible n'apparaît pas.
        for (PreviousVersionGroup g : ordered) {
            if (!g.documents.isEmpty()) {
                groups.add(g);
            }
        }
        return groups;
    }

    @AuraEnabled(cacheable=true)
    public static ChainResult getChain(Id anyMatrixIdInChain) {
        AR_Price_Matrix__c anchor = [
            SELECT Id, AR_Root_Matrix__c
            FROM AR_Price_Matrix__c
            WHERE Id = :anyMatrixIdInChain
            LIMIT 1
        ];
        Id rootId = anchor.AR_Root_Matrix__c != null ? anchor.AR_Root_Matrix__c : anchor.Id;

        List<AR_Price_Matrix__c> visible = [
            SELECT
                Id, Name, AR_Negotiation_Version__c, AR_Status__c, AR_Currency__c, AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_Periods__c, AR_Number_Of_Days__c,
                AR_Planned_Leave_Days__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
                AR_MC2_Percent__c, AR_MC2_Per_Day__c, AR_Corridor_Segment__c, AR_Decided_At__c, AR_Version_Change_Comment__c,
                AR_Version_Type__c
            FROM AR_Price_Matrix__c
            WHERE Id = :rootId OR AR_Root_Matrix__c = :rootId
            ORDER BY AR_Negotiation_Version__c ASC NULLS FIRST
        ];

        Set<Id> visibleIds = new Map<Id, AR_Price_Matrix__c>(visible).keySet();
        Map<Id, List<String>> reasonsByMatrix = new Map<Id, List<String>>();
        for (AR_Reason_Selection__c sel : [
            SELECT AR_Price_Matrix__c, AR_Reason__r.Name
            FROM AR_Reason_Selection__c
            WHERE AR_Price_Matrix__c IN :visibleIds
        ]) {
            if (!reasonsByMatrix.containsKey(sel.AR_Price_Matrix__c)) {
                reasonsByMatrix.put(sel.AR_Price_Matrix__c, new List<String>());
            }
            reasonsByMatrix.get(sel.AR_Price_Matrix__c).add(sel.AR_Reason__r.Name);
        }

        List<ChainNode> nodes = new List<ChainNode>();
        for (AR_Price_Matrix__c m : visible) {
            ChainNode node = new ChainNode();
            node.matrixId = m.Id;
            node.name = m.Name;
            node.negotiationVersion = m.AR_Negotiation_Version__c;
            node.versionType = m.AR_Version_Type__c;
            node.status = m.AR_Status__c;
            node.currencyCode = m.AR_Currency__c;
            node.proposedTjm = AR_PricingMatrixService.effectiveTjm(m);
            node.tjmPeriods = AR_PricingMatrixService.tjmPeriodsOf(m);
            node.mc2PercentHuman = m.AR_MC2_Percent__c;
            node.mc2PerDay = AR_DerogationService.resolveMc2PerDay(
                m.AR_MC2_Per_Day__c, AR_PricingMatrixService.effectiveTjm(m), m.AR_MC2_Percent__c
            );
            node.corridorSegment = m.AR_Corridor_Segment__c;
            node.decidedAt = m.AR_Decided_At__c;
            node.changeComment = m.AR_Version_Change_Comment__c;
            node.reasons = reasonsByMatrix.containsKey(m.Id)
                ? reasonsByMatrix.get(m.Id)
                : new List<String>();
            nodes.add(node);
        }

        ChainResult result = new ChainResult();
        result.nodes = nodes;
        // Le compte réel est obtenu hors partage (AR_MatrixChainVisibility) : un utilisateur ne
        // voyant pas tous les maillons doit être averti, pas recevoir une chaîne tronquée
        // présentée comme complète.
        result.partiallyVisible = visible.size() < AR_MatrixChainVisibility.countChainMembers(rootId);
        return result;
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}