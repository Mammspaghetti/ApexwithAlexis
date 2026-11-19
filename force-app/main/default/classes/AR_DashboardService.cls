/**
 * Agrégats pour la vue « Tableau de bord » de l'app Pricing Tool. `with sharing` : les agrégats
 * portent uniquement sur les matrices visibles de l'utilisateur courant (cohérent avec la vue
 * « Mes matrices », AR_MatrixListService).
 */
public with sharing class AR_DashboardService {

    public class DashboardData {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer validatedCount;
        @AuraEnabled public Decimal derogationRatePercent;
        @AuraEnabled public Decimal averageTjm;
        @AuraEnabled public Decimal averageMc2Percent;
        @AuraEnabled public List<SegmentBreakdown> segments;
        @AuraEnabled public List<AR_MatrixListService.MatrixListItem> recentMatrices;
        // Devise pivot des agrégats (session 24b) : `averageTjm` consolide des matrices
        // potentiellement en devises différentes — jamais sans le dire (un montant agrégé sans
        // devise affichée est un montant faux en puissance, cf. docs/24-multidevise.md). EUR par
        // défaut, décision confirmée le 18/08/2026 — constante volontairement exposée en donnée
        // plutôt qu'en dur côté LWC, pour qu'un futur changement de pivot n'ait qu'un point à changer.
        @AuraEnabled public String pivotCurrencyCode;
    }

    public class SegmentBreakdown {
        @AuraEnabled public String segment;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal percent;
    }

    private static final List<String> SEGMENTS_ORDER = new List<String>{ 'below_floor', 'low_margin', 'recommended', 'superstar' };
    private static final String PIVOT_CURRENCY = 'EUR';

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        Integer totalCount = 0;
        Integer validatedCount = 0;
        Decimal tjmSum = 0;
        Integer tjmCount = 0;
        Decimal mc2Sum = 0;
        Integer mc2Count = 0;
        Map<String, Integer> segmentCounts = new Map<String, Integer>();

        for (AR_Price_Matrix__c m : [
            SELECT AR_Status__c, AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_EUR_Equivalent__c, AR_MC2_Percent__c, AR_Corridor_Segment__c
            FROM AR_Price_Matrix__c
        ]) {
            totalCount++;
            if (m.AR_Status__c == 'Validée' || m.AR_Status__c == 'Validée par dérogation') {
                validatedCount++;
            }
            // Pivot EUR (session 24b) : AR_TJM_EUR_Equivalent__c est le TJM converti et figé au taux
            // gelé de CHAQUE matrice (session 24) — jamais le taux courant, sinon le dashboard d'hier
            // change aujourd'hui parce qu'un responsable pays a mis la table à jour (même piège que
            // 23b sur les corridors). Repli sur AR_Proposed_TJM__c pour une matrice antérieure à la
            // session 24 (champ jamais recalculé depuis, car verrouillée si déjà décidée) : ce repli
            // reproduit EXACTEMENT le comportement d'avant ce bloc pour toute donnée existante — pas
            // une approximation, une garantie de non-régression sur l'historique.
            Decimal tjmInPivotCurrency = m.AR_TJM_EUR_Equivalent__c != null
                ? m.AR_TJM_EUR_Equivalent__c
                : AR_PricingMatrixService.effectiveTjm(m);
            if (tjmInPivotCurrency != null) {
                tjmSum += tjmInPivotCurrency;
                tjmCount++;
            }
            if (m.AR_MC2_Percent__c != null) {
                mc2Sum += m.AR_MC2_Percent__c;
                mc2Count++;
            }
            if (String.isNotBlank(m.AR_Corridor_Segment__c)) {
                Integer current = segmentCounts.containsKey(m.AR_Corridor_Segment__c) ? segmentCounts.get(m.AR_Corridor_Segment__c) : 0;
                segmentCounts.put(m.AR_Corridor_Segment__c, current + 1);
            }
        }

        Integer derogationCount = [SELECT COUNT() FROM AR_Derogation__c];

        DashboardData data = new DashboardData();
        data.totalCount = totalCount;
        data.validatedCount = validatedCount;
        data.derogationRatePercent = totalCount > 0 ? (Decimal.valueOf(derogationCount) / totalCount * 100).setScale(1, RoundingMode.HALF_UP) : 0;
        data.averageTjm = tjmCount > 0 ? (tjmSum / tjmCount).setScale(0, RoundingMode.HALF_UP) : 0;
        data.averageMc2Percent = mc2Count > 0 ? (mc2Sum / mc2Count).setScale(1, RoundingMode.HALF_UP) : 0;
        data.pivotCurrencyCode = PIVOT_CURRENCY;

        data.segments = new List<SegmentBreakdown>();
        for (String segment : SEGMENTS_ORDER) {
            SegmentBreakdown sb = new SegmentBreakdown();
            sb.segment = segment;
            sb.count = segmentCounts.containsKey(segment) ? segmentCounts.get(segment) : 0;
            sb.percent = totalCount > 0 ? (Decimal.valueOf(sb.count) / totalCount * 100).setScale(1, RoundingMode.HALF_UP) : 0;
            data.segments.add(sb);
        }

        data.recentMatrices = new List<AR_MatrixListService.MatrixListItem>();
        // Id DESC en second critère : des enregistrements créés dans la même transaction (import,
        // seed) partagent le même CreatedDate à la milliseconde, l'ordre de tri devient alors
        // indéfini sans départage explicite (observé lors du seed de démo, session 9).
        List<AR_Price_Matrix__c> recent = [
            SELECT Id, Name, AR_Position__c, AR_Position_Name__c, AR_Account_Name__c, AR_Account_Country__c, OwnerId,
                   AR_Contract_Type__c, AR_Currency__c, AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_Periods__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c, AR_MC2_Percent__c, AR_Corridor_Segment__c,
                   AR_Status__c, CreatedDate, AR_Consultant_Name__c, AR_Consultant__r.Name, AR_RPLSR_Enabled__c,
                   AR_Position__r.cxsrec__Status__c, AR_Won__c, AR_Signed_Price_Level__c
            FROM AR_Price_Matrix__c
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 5
        ];
        Map<Id, String> ownerNames = AR_MatrixListService.ownerNamesFor(recent);
        for (AR_Price_Matrix__c m : recent) {
            data.recentMatrices.add(AR_MatrixListService.toItem(m, ownerNames));
        }

        return data;
    }

    // ------------------------------------------------------------------
    // Tableau de bord analytique : agrégats filtrables, restitués en JSON.
    // Règles de calcul : docs/248-plan-tableau-de-bord-1b.md (elles font foi).
    // ------------------------------------------------------------------

    private static final List<String> VALIDATED_STATUSES = new List<String>{ 'Validée', 'Validée par dérogation' };
    private static final String DIRECT_STATUS = 'Validée';
    private static final String DEROGATION_STATUS = 'Validée par dérogation';
    private static final String DEFAULT_MC2_BANDS = '10;15;20';
    private static final Integer TOP_REASONS = 5;
    private static final Integer TREND_MONTHS = 6;
    private static final Integer MIN_MATRICES_PER_CLIENT = 2;
    private static final Integer RANKING_SIZE = 10;
    private static final Integer SINGLE_RANKING_THRESHOLD = 20;
    private static final String AXIS_BM = 'bm';
    private static final String AXIS_ENTITY = 'entity';
    private static final String AXIS_PERIMETER = 'perimeter';
    private static final String AXIS_GROUP = 'group';
    private static final String GROUP_LABEL = 'House of ABY';
    private static final String OTHERS_KEY = '__others';
    private static final Integer MAX_AXIS_ROWS = 10;
    private static final Integer MIN_SAMPLE_SIZE = 3;
    private static final Integer TOP_POSTS = 5;
    private static final Integer TOP_CLIENTS = 5;
    private static final Integer PENDING_WON_LIMIT = 20;
    private static final Integer MAX_MONTHS = 36;

    /** Filtres reçus du LWC (JSON). Tous optionnels ; dates au format ISO yyyy-MM-dd. */
    public class DashboardFilters {
        public String validatedFrom;
        public String validatedTo;
        public String entityId;
        public String entityCountry;
        public String axis;
        public String motifAxisValue;
    }

    /** Filtres parsés et typés. Un champ null signifie « pas de filtre ». */
    private class Scope {
        Date fromDate;
        Date toDate;
        Id entityId;
        String entityCountry;
        String axis = AXIS_ENTITY;
        String motifAxisValue;
    }

    public class DashboardAnalytics {
        public Kpis kpis;
        public List<ValidationShare> validationSplit;
        public Mc2Bands mc2Bands;
        public List<SegmentShare> segments;
        public Reasons reasons;
        public List<MonthlyCount> monthly;
        public ClientRanking clients;
        public FilterOptions filterOptions;
        public List<AxisSegments> segmentsByAxis;
        public Funnel funnel;
        public String axis;
    }

    public class Funnel {
        public Integer simulations;
        public Integer validated;
        public Integer won;
    }

    public class Kpis {
        public Integer validatedCount;
        public Integer derogationValidatedCount;
        public Decimal derogationValidatedPercent;
        public Decimal averageTjmEur;
        public Decimal averageMc2Percent;
        public String pivotCurrencyCode;
        public Integer simulationsCount;
        public Integer wonCount;
    }

    public class ValidationShare {
        public String key;
        public Integer count;
        public Decimal percent;
    }

    public class Mc2Bands {
        public List<Decimal> bounds;
        public List<Bucket> buckets;
    }

    public class Bucket {
        public String key;
        public String label;
        public Decimal min;
        public Decimal max;
        public Integer count;
        public Decimal percent;
    }

    public class SegmentShare {
        public String segment;
        public Integer count;
        public Decimal percent;
    }

    public virtual class EntitySegments implements Comparable {
        public String entityId;
        public String entityName;
        public Boolean noEntity = false;
        public String country;
        public Integer total;
        public List<SegmentShare> segments;

        public Integer compareTo(Object other) {
            EntitySegments o = (EntitySegments) other;
            // « Sans entité » toujours en dernier, puis total décroissant, puis nom.
            if ((entityId == null) != (o.entityId == null)) {
                return entityId == null ? 1 : -1;
            }
            if (total != o.total) {
                return o.total - total;
            }
            return compareNames(entityName, o.entityName);
        }
    }

    /** Ligne de `segmentsByAxis` : la forme historique de « Par entité » plus le drapeau « Autres ». */
    public class AxisSegments extends EntitySegments {
        public Boolean others = false;
    }

    public class Reasons {
        public Integer derogationCount = 0;
        public Integer selectionCount = 0;
        public List<ReasonShare> top;
        public Integer othersCount = 0;
        public Decimal othersPercent;
    }

    public class ReasonShare implements Comparable {
        public String reasonName;
        public Integer count;
        public Decimal percent;

        public Integer compareTo(Object other) {
            ReasonShare o = (ReasonShare) other;
            if (count != o.count) {
                return o.count - count;
            }
            return compareNames(reasonName, o.reasonName);
        }
    }

    public class MonthlyCount {
        public String month;
        public Integer below_floor = 0;
        public Integer low_margin = 0;
        public Integer recommended = 0;
        public Integer superstar = 0;
    }

    public class ClientRanking {
        public List<ClientRow> best;
        public List<ClientRow> worst;
        public Boolean singleRanking;
        public Integer eligibleCount;
    }

    public class ClientRow implements Comparable {
        public String accountName;
        public Integer matrixCount;
        public Decimal averageMc2Percent;
        public Decimal averageTjmEur;

        /** Tri ascendant par MC2 moyenne, puis par nom. */
        public Integer compareTo(Object other) {
            ClientRow o = (ClientRow) other;
            if (averageMc2Percent != o.averageMc2Percent) {
                return averageMc2Percent > o.averageMc2Percent ? 1 : -1;
            }
            return compareNames(accountName, o.accountName);
        }
    }

    public class FilterOptions {
        public List<EntityOption> entities;
        public List<String> countries;
    }

    public class EntityOption implements Comparable {
        public String id;
        public String name;
        public String country;

        public Integer compareTo(Object other) {
            return compareNames(name, ((EntityOption) other).name);
        }
    }

    /**
     * Point d'entrée du tableau de bord analytique. Filtres optionnels (JSON), résultat sérialisé
     * en JSON pour que le LWC consomme la même forme sans conversion côté client.
     * Non cacheable : appelée en impératif à chaque changement de filtre, elle doit toujours revoir le serveur.
     */
    @AuraEnabled
    public static String getDashboardAnalytics(String filtersJson) {
        try {
            Scope scope = parseScope(filtersJson);
            List<Decimal> bounds = readMc2Bounds();

            Base base = loadBase(scope);
            List<AR_Price_Matrix__c> latest = base.latest;
            List<AR_Price_Matrix__c> selected = base.selected;
            List<AR_Price_Matrix__c> trendScope = filterMatrices(latest, scope, false);

            DashboardAnalytics result = new DashboardAnalytics();
            result.kpis = buildKpis(selected);
            result.validationSplit = buildValidationSplit(selected);
            result.mc2Bands = buildMc2Bands(selected, bounds);
            result.segments = buildSegmentShares(selected);
            result.reasons = buildReasons(loadDerogations(), scope);
            result.monthly = buildMonthly(trendScope, scope.toDate);
            result.clients = buildClientRanking(selected);
            result.filterOptions = buildFilterOptions(latest);
            result.axis = scope.axis;
            result.segmentsByAxis = buildSegmentsByAxis(selected, scope.axis);
            List<SimRow> sims = simulationsOf(base);
            List<WonRow> wins = wonRowsOf(base);
            result.kpis.simulationsCount = sims.size();
            result.kpis.wonCount = wins.size();
            result.funnel = new Funnel();
            result.funnel.simulations = sims.size();
            result.funnel.validated = selected.size();
            result.funnel.won = wins.size();
            return JSON.serialize(result);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, 'le chargement du tableau de bord');
        }
    }

    // ---------- Filtres ----------

    private static Scope parseScope(String filtersJson) {
        DashboardFilters raw = new DashboardFilters();
        Scope scope = new Scope();
        try {
            if (String.isNotBlank(filtersJson)) {
                raw = (DashboardFilters) JSON.deserialize(filtersJson, DashboardFilters.class);
            }
            scope.fromDate = parseIsoDate(raw.validatedFrom);
            scope.toDate = parseIsoDate(raw.validatedTo);
            scope.entityId = String.isNotBlank(raw.entityId) ? Id.valueOf(raw.entityId) : null;
            scope.entityCountry = String.isNotBlank(raw.entityCountry) ? raw.entityCountry : null;
            scope.axis = String.isBlank(raw.axis) ? AXIS_ENTITY : raw.axis;
            if (scope.axis != AXIS_BM && scope.axis != AXIS_ENTITY && scope.axis != AXIS_PERIMETER && scope.axis != AXIS_GROUP) {
                throw new JSONException('Axe inconnu : ' + scope.axis);
            }
            scope.motifAxisValue = String.isNotBlank(raw.motifAxisValue) ? raw.motifAxisValue : null;
            if (scope.axis == AXIS_GROUP) {
                // Vue Groupe : les filtres Entité et Pays sont désactivés et ignorés.
                scope.entityId = null;
                scope.entityCountry = null;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Filtres du tableau de bord illisibles : ' + ex.getMessage());
            throw newAuraException('Les filtres du tableau de bord sont illisibles. Rechargez la page et réessayez.');
        }
        return scope;
    }

    private static Date parseIsoDate(String value) {
        return String.isBlank(value) ? null : Date.valueOf(value);
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /** Filtre de période sur la date de validation ; sans borne, tout passe. */
    private static Boolean inPeriod(Datetime at, Scope scope) {
        if (scope.fromDate == null && scope.toDate == null) {
            return true;
        }
        if (at == null) {
            return false;
        }
        if (scope.fromDate != null && at < startOf(scope.fromDate)) {
            return false;
        }
        return scope.toDate == null || at < startOf(scope.toDate.addDays(1));
    }

    private static Boolean matchesEntity(Id entityId, String country, Scope scope) {
        if (scope.entityId != null && entityId != scope.entityId) {
            return false;
        }
        return scope.entityCountry == null || scope.entityCountry == country;
    }

    private static String countryOf(AR_PTF_Entity_Referential__c entity) {
        return entity == null ? null : entity.AR_Country__c;
    }

    private static Datetime startOf(Date day) {
        return Datetime.newInstance(day.year(), day.month(), day.day());
    }

    // ---------- Chargement et dédoublonnage ----------

    /** Toutes les matrices visibles (tous statuts) : le tableau de bord en déduit simulations, validées et gagnées. */
    private static List<AR_Price_Matrix__c> loadAllMatrices() {
        return [
            SELECT Id, AR_Root_Matrix__c, AR_Status__c, AR_Validated_At__c, AR_MC2_Percent__c, CreatedDate,
                   AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_EUR_Equivalent__c, AR_Corridor_Segment__c, AR_Account_Name__c,
                   AR_Entity_Ref__c, AR_Entity_Ref__r.Name, AR_Entity_Ref__r.AR_Country__c,
                   OwnerId, Owner.Name, AR_Perimeter__c, AR_Position__r.TP_P_rim_tre__c,
                   AR_Won__c, AR_Won_Date__c, AR_Signed_TJM__c, AR_Signed_Price_Level__c,
                   AR_Target_Percent_Applied__c, AR_Floor_Percent_Applied__c, AR_Ideal_Percent_Applied__c, AR_Corridor_Source__c
            FROM AR_Price_Matrix__c
        ];
    }

    private class Base {
        Scope scope;
        List<AR_Price_Matrix__c> all;
        List<AR_Price_Matrix__c> latest;
        List<AR_Price_Matrix__c> selected;
    }

    private static Base loadBase(Scope scope) {
        Base base = new Base();
        base.scope = scope;
        base.all = loadAllMatrices();
        List<AR_Price_Matrix__c> validated = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : base.all) {
            if (VALIDATED_STATUSES.contains(m.AR_Status__c)) {
                validated.add(m);
            }
        }
        base.latest = latestByLineage(validated);
        base.selected = filterMatrices(base.latest, scope, true);
        return base;
    }

    private static List<AR_Derogation__c> loadDerogations() {
        return [
            SELECT AR_Requested_At__c, AR_Decided_At__c, AR_Decision__c, AR_Selected_Validator__c, AR_Selected_Validator__r.Name,
                   AR_Effective_Validator__c, AR_Effective_Validator__r.Name,
                   AR_Price_Matrix__r.AR_Entity_Ref__c, AR_Price_Matrix__r.AR_Entity_Ref__r.AR_Country__c,
                   AR_Price_Matrix__r.AR_Entity_Ref__r.Name, AR_Price_Matrix__r.OwnerId, AR_Price_Matrix__r.Owner.Name,
                   AR_Price_Matrix__r.AR_Status__c, AR_Price_Matrix__r.AR_Perimeter__c,
                   AR_Price_Matrix__r.AR_Position__r.TP_P_rim_tre__c, AR_Price_Matrix__r.AR_Account_Name__c,
                   (SELECT AR_Reason__r.Name FROM AR_Reason_Selections__r)
            FROM AR_Derogation__c
        ];
    }

    /** Une affaire = une ligne : seule la dernière version validée de chaque lignée compte. */
    private static List<AR_Price_Matrix__c> latestByLineage(List<AR_Price_Matrix__c> matrices) {
        Map<Id, AR_Price_Matrix__c> latestByLineage = new Map<Id, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : matrices) {
            Id lineage = m.AR_Root_Matrix__c != null ? m.AR_Root_Matrix__c : m.Id;
            AR_Price_Matrix__c current = latestByLineage.get(lineage);
            if (current == null || isMoreRecent(m, current)) {
                latestByLineage.put(lineage, m);
            }
        }
        return latestByLineage.values();
    }

    private static Boolean isMoreRecent(AR_Price_Matrix__c candidate, AR_Price_Matrix__c current) {
        Datetime candidateAt = candidate.AR_Validated_At__c;
        Datetime currentAt = current.AR_Validated_At__c;
        if (candidateAt != currentAt) {
            if (candidateAt == null) {
                return false;
            }
            return currentAt == null || candidateAt > currentAt;
        }
        // Départage à égalité de date de validation : Id, pour un résultat stable.
        return String.valueOf(candidate.Id) > String.valueOf(current.Id);
    }

    private static List<AR_Price_Matrix__c> filterMatrices(List<AR_Price_Matrix__c> matrices, Scope scope, Boolean withPeriod) {
        List<AR_Price_Matrix__c> kept = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : matrices) {
            if (withPeriod && !inPeriod(m.AR_Validated_At__c, scope)) {
                continue;
            }
            if (matchesEntity(m.AR_Entity_Ref__c, countryOf(m.AR_Entity_Ref__r), scope)) {
                kept.add(m);
            }
        }
        return kept;
    }

    private static Decimal pivotTjm(AR_Price_Matrix__c m) {
        // Équivalent EUR figé à la validation ; repli sur le TJM natif pour l'historique d'avant la multi-devise.
        return m.AR_TJM_EUR_Equivalent__c != null ? m.AR_TJM_EUR_Equivalent__c : AR_PricingMatrixService.effectiveTjm(m);
    }

    // ---------- KPI et validation ----------

    private static Kpis buildKpis(List<AR_Price_Matrix__c> selected) {
        Integer derogationCount = 0;
        Decimal tjmSum = 0;
        Integer tjmCount = 0;
        Decimal mc2Sum = 0;
        Integer mc2Count = 0;
        for (AR_Price_Matrix__c m : selected) {
            if (m.AR_Status__c == DEROGATION_STATUS) {
                derogationCount++;
            }
            if (pivotTjm(m) != null) {
                tjmSum += pivotTjm(m);
                tjmCount++;
            }
            if (m.AR_MC2_Percent__c != null) {
                mc2Sum += m.AR_MC2_Percent__c;
                mc2Count++;
            }
        }

        Kpis kpis = new Kpis();
        kpis.validatedCount = selected.size();
        kpis.derogationValidatedCount = derogationCount;
        kpis.derogationValidatedPercent = percentOf(derogationCount, selected.size());
        kpis.averageTjmEur = average(tjmSum, tjmCount, 0);
        kpis.averageMc2Percent = average(mc2Sum, mc2Count, 1);
        kpis.pivotCurrencyCode = PIVOT_CURRENCY;
        return kpis;
    }

    private static List<ValidationShare> buildValidationSplit(List<AR_Price_Matrix__c> selected) {
        Integer direct = 0;
        Integer derogation = 0;
        for (AR_Price_Matrix__c m : selected) {
            if (m.AR_Status__c == DIRECT_STATUS) {
                direct++;
            } else if (m.AR_Status__c == DEROGATION_STATUS) {
                derogation++;
            }
        }
        return new List<ValidationShare>{
            shareOf('direct', direct, selected.size()),
            shareOf('derogation', derogation, selected.size())
        };
    }

    private static ValidationShare shareOf(String key, Integer count, Integer total) {
        ValidationShare share = new ValidationShare();
        share.key = key;
        share.count = count;
        share.percent = percentOf(count, total);
        return share;
    }

    // ---------- Tranches de MC2 ----------

    private static Mc2Bands buildMc2Bands(List<AR_Price_Matrix__c> selected, List<Decimal> bounds) {
        List<Integer> counts = new List<Integer>();
        for (Integer i = 0; i <= bounds.size(); i++) {
            counts.add(0);
        }
        Integer bucketed = 0;
        for (AR_Price_Matrix__c m : selected) {
            if (m.AR_MC2_Percent__c != null) {
                Integer index = bucketFor(m.AR_MC2_Percent__c, bounds);
                counts.set(index, counts.get(index) + 1);
                bucketed++;
            }
        }

        Mc2Bands result = new Mc2Bands();
        result.bounds = bounds;
        result.buckets = new List<Bucket>();
        // Du plus haut au plus bas, comme la maquette.
        for (Integer i = bounds.size(); i >= 0; i--) {
            Bucket b = new Bucket();
            b.key = 'band' + i;
            b.min = i == 0 ? null : bounds[i - 1];
            b.max = i == bounds.size() ? null : bounds[i];
            b.label = bandLabel(b.min, b.max);
            b.count = counts.get(i);
            b.percent = percentOf(b.count, bucketed);
            result.buckets.add(b);
        }
        return result;
    }

    /**
     * Index de la tranche d'un MC2 : nombre de bornes inférieures ou égales (bornes triées, uniques).
     * 0 = sous la plus basse borne, bounds.size() = au-dessus de la plus haute. Seule fonction à
     * modifier pour passer à un calcul « écart à la cible ».
     */
    private static Integer bucketFor(Decimal mc2, List<Decimal> bounds) {
        Integer index = 0;
        for (Decimal bound : bounds) {
            if (mc2 >= bound) {
                index++;
            }
        }
        return index;
    }

    private static String bandLabel(Decimal min, Decimal max) {
        if (min == null) {
            return '< ' + formatBound(max) + ' %';
        }
        if (max == null) {
            return '≥ ' + formatBound(min) + ' %';
        }
        return formatBound(min) + '-' + formatBound(max) + ' %';
    }

    private static String formatBound(Decimal bound) {
        return bound.stripTrailingZeros().toPlainString();
    }

    private static List<Decimal> readMc2Bounds() {
        List<AR_General_Setting__c> settings = [SELECT AR_Dashboard_MC2_Bands__c FROM AR_General_Setting__c LIMIT 1];
        String raw = settings.isEmpty() ? null : settings[0].AR_Dashboard_MC2_Bands__c;
        List<Decimal> bounds = parseBounds(raw);
        if (bounds == null) {
            System.debug(LoggingLevel.WARN, 'Tranches MC2 absentes ou illisibles (« ' + raw + ' ») : repli sur ' + DEFAULT_MC2_BANDS);
            bounds = parseBounds(DEFAULT_MC2_BANDS);
        }
        return bounds;
    }

    /** Bornes « 10;15;20 » → liste triée. Null si vide, non numérique ou en double. */
    private static List<Decimal> parseBounds(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        List<Decimal> bounds = new List<Decimal>();
        try {
            for (String token : raw.split(';')) {
                bounds.add(Decimal.valueOf(token.trim()));
            }
        } catch (Exception ex) {
            return null;
        }
        bounds.sort();
        for (Integer i = 1; i < bounds.size(); i++) {
            if (bounds[i] == bounds[i - 1]) {
                return null;
            }
        }
        return bounds;
    }

    // ---------- Segments de corridor ----------

    private static List<SegmentShare> buildSegmentShares(List<AR_Price_Matrix__c> matrices) {
        Map<String, Integer> counts = new Map<String, Integer>();
        Integer total = 0;
        for (AR_Price_Matrix__c m : matrices) {
            if (String.isNotBlank(m.AR_Corridor_Segment__c)) {
                counts.put(m.AR_Corridor_Segment__c, counts.containsKey(m.AR_Corridor_Segment__c) ? counts.get(m.AR_Corridor_Segment__c) + 1 : 1);
                total++;
            }
        }

        List<SegmentShare> shares = new List<SegmentShare>();
        for (String segment : SEGMENTS_ORDER) {
            SegmentShare share = new SegmentShare();
            share.segment = segment;
            share.count = counts.containsKey(segment) ? counts.get(segment) : 0;
            share.percent = percentOf(share.count, total);
            shares.add(share);
        }
        return shares;
    }

    // ---------- Motifs de dérogation ----------

    private static Reasons buildReasons(List<AR_Derogation__c> derogations, Scope scope) {
        return reasonsOf(derogationsInScope(derogations, scope));
    }

    private static List<AR_Derogation__c> derogationsInScope(List<AR_Derogation__c> derogations, Scope scope) {
        List<AR_Derogation__c> kept = new List<AR_Derogation__c>();
        for (AR_Derogation__c d : derogations) {
            AR_Price_Matrix__c matrix = d.AR_Price_Matrix__r;
            Id entityId = matrix == null ? null : matrix.AR_Entity_Ref__c;
            String country = matrix == null ? null : countryOf(matrix.AR_Entity_Ref__r);
            if (inPeriod(d.AR_Requested_At__c, scope) && matchesEntity(entityId, country, scope)) {
                kept.add(d);
            }
        }
        return kept;
    }

    private static Reasons reasonsOf(List<AR_Derogation__c> derogations) {
        Reasons result = new Reasons();
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AR_Derogation__c d : derogations) {
            result.derogationCount++;
            for (AR_Reason_Selection__c selection : d.AR_Reason_Selections__r) {
                if (selection.AR_Reason__r == null) {
                    continue;
                }
                String name = selection.AR_Reason__r.Name;
                counts.put(name, counts.containsKey(name) ? counts.get(name) + 1 : 1);
                result.selectionCount++;
            }
        }

        List<ReasonShare> ranked = new List<ReasonShare>();
        for (String name : counts.keySet()) {
            ReasonShare share = new ReasonShare();
            share.reasonName = name;
            share.count = counts.get(name);
            share.percent = percentOf(share.count, result.selectionCount);
            ranked.add(share);
        }
        ranked.sort();

        result.top = new List<ReasonShare>();
        Integer topCount = 0;
        for (Integer i = 0; i < ranked.size() && i < TOP_REASONS; i++) {
            result.top.add(ranked[i]);
            topCount += ranked[i].count;
        }
        result.othersCount = result.selectionCount - topCount;
        result.othersPercent = percentOf(result.othersCount, result.selectionCount);
        return result;
    }

    // ---------- Tendance mensuelle ----------

    private static List<MonthlyCount> buildMonthly(List<AR_Price_Matrix__c> matrices, Date endDate) {
        Date lastMonth = (endDate != null ? endDate : Date.today()).toStartOfMonth();
        Date firstMonth = lastMonth.addMonths(1 - TREND_MONTHS);

        Map<String, MonthlyCount> byMonth = new Map<String, MonthlyCount>();
        List<MonthlyCount> months = new List<MonthlyCount>();
        for (Integer i = 0; i < TREND_MONTHS; i++) {
            MonthlyCount entry = new MonthlyCount();
            entry.month = monthKey(startOf(firstMonth.addMonths(i)));
            byMonth.put(entry.month, entry);
            months.add(entry);
        }

        for (AR_Price_Matrix__c m : matrices) {
            if (m.AR_Validated_At__c == null || String.isBlank(m.AR_Corridor_Segment__c)) {
                continue;
            }
            MonthlyCount entry = byMonth.get(monthKey(m.AR_Validated_At__c));
            if (entry == null) {
                continue;
            }
            if (m.AR_Corridor_Segment__c == 'below_floor') {
                entry.below_floor++;
            } else if (m.AR_Corridor_Segment__c == 'low_margin') {
                entry.low_margin++;
            } else if (m.AR_Corridor_Segment__c == 'recommended') {
                entry.recommended++;
            } else if (m.AR_Corridor_Segment__c == 'superstar') {
                entry.superstar++;
            }
        }
        return months;
    }

    private static String monthKey(Datetime at) {
        return at.format('yyyy-MM');
    }

    // ---------- Lecture client ----------

    private static ClientRanking buildClientRanking(List<AR_Price_Matrix__c> matrices) {
        Map<String, List<AR_Price_Matrix__c>> byClient = new Map<String, List<AR_Price_Matrix__c>>();
        for (AR_Price_Matrix__c m : matrices) {
            if (String.isBlank(m.AR_Account_Name__c)) {
                continue;
            }
            if (!byClient.containsKey(m.AR_Account_Name__c)) {
                byClient.put(m.AR_Account_Name__c, new List<AR_Price_Matrix__c>());
            }
            byClient.get(m.AR_Account_Name__c).add(m);
        }

        List<ClientRow> eligible = new List<ClientRow>();
        for (String accountName : byClient.keySet()) {
            List<AR_Price_Matrix__c> members = byClient.get(accountName);
            if (members.size() < MIN_MATRICES_PER_CLIENT) {
                continue;
            }
            Decimal mc2Sum = 0;
            Integer mc2Count = 0;
            Decimal tjmSum = 0;
            Integer tjmCount = 0;
            for (AR_Price_Matrix__c m : members) {
                if (m.AR_MC2_Percent__c != null) {
                    mc2Sum += m.AR_MC2_Percent__c;
                    mc2Count++;
                }
                if (pivotTjm(m) != null) {
                    tjmSum += pivotTjm(m);
                    tjmCount++;
                }
            }
            if (mc2Count == 0) {
                continue;
            }
            ClientRow row = new ClientRow();
            row.accountName = accountName;
            row.matrixCount = members.size();
            row.averageMc2Percent = average(mc2Sum, mc2Count, 1);
            row.averageTjmEur = average(tjmSum, tjmCount, 0);
            eligible.add(row);
        }
        eligible.sort();

        ClientRanking ranking = new ClientRanking();
        ranking.eligibleCount = eligible.size();
        ranking.singleRanking = eligible.size() < SINGLE_RANKING_THRESHOLD;
        ranking.best = new List<ClientRow>();
        ranking.worst = new List<ClientRow>();
        Integer bestLimit = ranking.singleRanking ? eligible.size() : RANKING_SIZE;
        for (Integer i = eligible.size() - 1; i >= 0 && ranking.best.size() < bestLimit; i--) {
            ranking.best.add(eligible[i]);
        }
        // Un seul classement complet quand il y a peu de comptes : pas de deux listes qui se recouvrent.
        for (Integer i = 0; !ranking.singleRanking && i < RANKING_SIZE; i++) {
            ranking.worst.add(eligible[i]);
        }
        return ranking;
    }

    // ---------- Options de filtre ----------

    private static FilterOptions buildFilterOptions(List<AR_Price_Matrix__c> latest) {
        Map<String, EntityOption> entities = new Map<String, EntityOption>();
        Set<String> countries = new Set<String>();
        for (AR_Price_Matrix__c m : latest) {
            if (m.AR_Entity_Ref__c == null) {
                continue;
            }
            EntityOption option = new EntityOption();
            option.id = String.valueOf(m.AR_Entity_Ref__c);
            option.name = m.AR_Entity_Ref__r.Name;
            option.country = countryOf(m.AR_Entity_Ref__r);
            entities.put(option.id, option);
            if (String.isNotBlank(option.country)) {
                countries.add(option.country);
            }
        }

        List<EntityOption> entityList = new List<EntityOption>(entities.values());
        entityList.sort();
        List<String> countryList = new List<String>(countries);
        countryList.sort();

        FilterOptions options = new FilterOptions();
        options.entities = entityList;
        options.countries = countryList;
        return options;
    }

    // ------------------------------------------------------------------
    // Session 285 — axe d'analyse, simulations, affaires gagnées et onglets à la demande.
    // Règles : docs/283-plan-tableau-de-bord-enrichi.md. Postes de coût : AR_DashboardCosts.
    // Échantillon inférieur à MIN_SAMPLE_SIZE : ratio, moyenne ou médiane renvoyé à null (le LWC affiche « — »).
    // ------------------------------------------------------------------

    public virtual class AxisRef {
        public String key;
        public String label;
        public Boolean noValue = false;
        public Boolean others = false;
    }

    private class AxisItem {
        String key;
        String label;
        Boolean noValue = false;
    }

    private static AxisItem newItem(String key, String label, Boolean noValue) {
        AxisItem item = new AxisItem();
        item.key = key;
        item.label = label;
        item.noValue = noValue;
        return item;
    }

    /** Valeur d'axe d'une matrice (BM = propriétaire ; périmètre figé si validée, sinon celui du besoin). */
    private static AxisItem axisOf(AR_Price_Matrix__c m, String axis) {
        if (axis == AXIS_GROUP) {
            return newItem(AXIS_GROUP, GROUP_LABEL, false);
        }
        if (axis == AXIS_BM) {
            return m.OwnerId == null ? newItem('', 'Sans BM', true) : newItem(String.valueOf(m.OwnerId), m.Owner.Name, false);
        }
        if (axis == AXIS_PERIMETER) {
            String perimeter = VALIDATED_STATUSES.contains(m.AR_Status__c)
                ? m.AR_Perimeter__c
                : (m.AR_Position__r == null ? null : m.AR_Position__r.TP_P_rim_tre__c);
            return String.isBlank(perimeter) ? newItem('', 'Sans périmètre', true) : newItem(perimeter, perimeter, false);
        }
        return m.AR_Entity_Ref__c == null
            ? newItem('', 'Sans entité', true)
            : newItem(String.valueOf(m.AR_Entity_Ref__c), m.AR_Entity_Ref__r.Name, false);
    }

    private static AxisItem axisOfLog(AR_Purge_Log__c log, String axis) {
        if (axis == AXIS_GROUP) {
            return newItem(AXIS_GROUP, GROUP_LABEL, false);
        }
        if (axis == AXIS_BM) {
            return String.isBlank(log.AR_Owner_Id__c) ? newItem('', 'Sans BM', true) : newItem(log.AR_Owner_Id__c, log.AR_Owner_Name__c, false);
        }
        if (axis == AXIS_PERIMETER) {
            return String.isBlank(log.AR_Perimeter__c) ? newItem('', 'Sans périmètre', true) : newItem(log.AR_Perimeter__c, log.AR_Perimeter__c, false);
        }
        return String.isBlank(log.AR_Entity_Id__c) ? newItem('', 'Sans entité', true) : newItem(log.AR_Entity_Id__c, log.AR_Entity_Name__c, false);
    }

    private class KeyCount implements Comparable {
        String key;
        String label;
        Integer count;

        public Integer compareTo(Object other) {
            KeyCount o = (KeyCount) other;
            if (count != o.count) {
                return o.count - count;
            }
            return compareNames(label, o.label);
        }
    }

    /** Valeurs d'axe d'une population : au plus MAX_AXIS_ROWS lignes triées par volume, le reste regroupé en « Autres ». */
    private class AxisBuckets {
        Map<String, Integer> counts = new Map<String, Integer>();
        Map<String, AxisItem> items = new Map<String, AxisItem>();
        Map<String, String> finalKey = new Map<String, String>();
        List<String> ordered = new List<String>();
        Boolean hasOthers = false;

        void add(AxisItem item) {
            counts.put(item.key, (counts.containsKey(item.key) ? counts.get(item.key) : 0) + 1);
            items.put(item.key, item);
        }

        AxisBuckets done() {
            List<KeyCount> ranked = new List<KeyCount>();
            for (String key : counts.keySet()) {
                KeyCount kc = new KeyCount();
                kc.key = key;
                kc.label = items.get(key).label == null ? '' : items.get(key).label;
                kc.count = counts.get(key);
                ranked.add(kc);
            }
            ranked.sort();
            for (Integer i = 0; i < ranked.size(); i++) {
                if (i < MAX_AXIS_ROWS) {
                    ordered.add(ranked[i].key);
                    finalKey.put(ranked[i].key, ranked[i].key);
                } else {
                    finalKey.put(ranked[i].key, OTHERS_KEY);
                    hasOthers = true;
                }
            }
            return this;
        }

        String keyOf(AxisItem item) {
            return finalKey.containsKey(item.key) ? finalKey.get(item.key) : item.key;
        }

        List<String> keys() {
            List<String> all = new List<String>(ordered);
            if (hasOthers) {
                all.add(OTHERS_KEY);
            }
            return all;
        }

        void fill(AxisRef ref, String key) {
            ref.key = key;
            if (key == OTHERS_KEY) {
                ref.label = 'Autres';
                ref.others = true;
            } else {
                ref.label = items.get(key).label;
                ref.noValue = items.get(key).noValue;
            }
        }
    }

    private static Integer count(Map<String, Integer> counts, String key) {
        return counts.containsKey(key) ? counts.get(key) : 0;
    }

    private static void increment(Map<String, Integer> counts, String key) {
        counts.put(key, count(counts, key) + 1);
    }

    private static Decimal sampledPercent(Integer part, Integer total) {
        return total < MIN_SAMPLE_SIZE ? null : percentOf(part, total);
    }

    private static Decimal median(List<Decimal> values) {
        if (values.size() < MIN_SAMPLE_SIZE) {
            return null;
        }
        List<Decimal> sorted = new List<Decimal>(values);
        sorted.sort();
        Integer n = sorted.size();
        Decimal mid = Math.mod(n, 2) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
        return mid.setScale(1, RoundingMode.HALF_UP);
    }

    private static Decimal delayInDays(AR_Derogation__c d) {
        if (d.AR_Requested_At__c == null || d.AR_Decided_At__c == null) {
            return null;
        }
        Decimal ms = Decimal.valueOf(d.AR_Decided_At__c.getTime() - d.AR_Requested_At__c.getTime());
        return ms / 86400000;
    }

    private static String decisionOf(AR_Derogation__c d) {
        return d.AR_Decision__c == 'Acceptée' || d.AR_Decision__c == 'Refusée' ? d.AR_Decision__c : 'En attente';
    }

    // ---------- Simulations et affaires gagnées ----------

    private class SimRow {
        AxisItem item;
        Datetime createdAt;
    }

    private class WonRow {
        AxisItem item;
        AR_Price_Matrix__c matrix;
        String level;
    }

    /**
     * Simulations de la période : lignées dont la matrice racine a été créée dans la période (tous statuts),
     * plus les racines purgées (journal de purge). Une lignée est caractérisée par sa dernière version validée,
     * à défaut par sa racine. Une racine non visible de l'utilisateur n'est pas comptée.
     */
    private static List<SimRow> simulationsOf(Base base) {
        Scope scope = base.scope;
        Map<Id, AR_Price_Matrix__c> latestByRoot = new Map<Id, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : base.latest) {
            latestByRoot.put(m.AR_Root_Matrix__c != null ? m.AR_Root_Matrix__c : m.Id, m);
        }
        List<SimRow> rows = new List<SimRow>();
        for (AR_Price_Matrix__c m : base.all) {
            if (m.AR_Root_Matrix__c != null || !inPeriod(m.CreatedDate, scope)) {
                continue;
            }
            AR_Price_Matrix__c rep = latestByRoot.containsKey(m.Id) ? latestByRoot.get(m.Id) : m;
            if (!matchesEntity(rep.AR_Entity_Ref__c, countryOf(rep.AR_Entity_Ref__r), scope)) {
                continue;
            }
            SimRow row = new SimRow();
            row.item = axisOf(rep, scope.axis);
            row.createdAt = m.CreatedDate;
            rows.add(row);
        }
        rows.addAll(purgedRoots(scope));
        return rows;
    }

    private static List<SimRow> purgedRoots(Scope scope) {
        Map<String, String> countryByEntity = new Map<String, String>();
        if (scope.entityCountry != null) {
            for (AR_PTF_Entity_Referential__c entity : [SELECT Id, AR_Country__c FROM AR_PTF_Entity_Referential__c]) {
                countryByEntity.put(String.valueOf(entity.Id).left(15), entity.AR_Country__c);
            }
        }
        String scopeEntity = scope.entityId == null ? null : String.valueOf(scope.entityId).left(15);
        List<SimRow> rows = new List<SimRow>();
        // Journal de purge : lecture hors partage, filtrée côté serveur par AR_DashboardPurgeReader.
        for (AR_Purge_Log__c log : AR_DashboardPurgeReader.readableRootLogs()) {
            if (!inPeriod(log.AR_Matrix_Created_Date__c, scope)) {
                continue;
            }
            String logEntity = String.isBlank(log.AR_Entity_Id__c) ? null : log.AR_Entity_Id__c.left(15);
            if (scopeEntity != null && scopeEntity != logEntity) {
                continue;
            }
            if (scope.entityCountry != null && (logEntity == null || countryByEntity.get(logEntity) != scope.entityCountry)) {
                continue;
            }
            SimRow row = new SimRow();
            row.item = axisOfLog(log, scope.axis);
            row.createdAt = log.AR_Matrix_Created_Date__c;
            rows.add(row);
        }
        return rows;
    }

    /** Affaires gagnées de la période (date de signature) : une version gagnante par lignée. */
    private static List<WonRow> wonRowsOf(Base base) {
        Scope scope = base.scope;
        Map<Id, AR_Price_Matrix__c> wonByLineage = new Map<Id, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : base.all) {
            if (m.AR_Won__c != true) {
                continue;
            }
            Id lineage = m.AR_Root_Matrix__c != null ? m.AR_Root_Matrix__c : m.Id;
            AR_Price_Matrix__c current = wonByLineage.get(lineage);
            if (current == null || (m.AR_Won_Date__c != null && (current.AR_Won_Date__c == null || m.AR_Won_Date__c > current.AR_Won_Date__c))) {
                wonByLineage.put(lineage, m);
            }
        }
        List<WonRow> rows = new List<WonRow>();
        for (AR_Price_Matrix__c m : wonByLineage.values()) {
            Datetime wonAt = m.AR_Won_Date__c == null ? null : startOf(m.AR_Won_Date__c);
            if (!inPeriod(wonAt, scope) || !matchesEntity(m.AR_Entity_Ref__c, countryOf(m.AR_Entity_Ref__r), scope)) {
                continue;
            }
            WonRow row = new WonRow();
            row.item = axisOf(m, scope.axis);
            row.matrix = m;
            row.level = m.AR_Signed_Price_Level__c;
            rows.add(row);
        }
        return rows;
    }

    // ---------- Segments par axe (Vue d'ensemble) ----------

    private static List<AxisSegments> buildSegmentsByAxis(List<AR_Price_Matrix__c> matrices, String axis) {
        AxisBuckets buckets = new AxisBuckets();
        List<AR_Price_Matrix__c> withSegment = new List<AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : matrices) {
            if (String.isNotBlank(m.AR_Corridor_Segment__c)) {
                withSegment.add(m);
                buckets.add(axisOf(m, axis));
            }
        }
        buckets.done();
        Map<String, List<AR_Price_Matrix__c>> byKey = new Map<String, List<AR_Price_Matrix__c>>();
        for (AR_Price_Matrix__c m : withSegment) {
            String key = buckets.keyOf(axisOf(m, axis));
            if (!byKey.containsKey(key)) {
                byKey.put(key, new List<AR_Price_Matrix__c>());
            }
            byKey.get(key).add(m);
        }
        List<AxisSegments> rows = new List<AxisSegments>();
        AxisSegments othersRow = null;
        for (String key : byKey.keySet()) {
            List<AR_Price_Matrix__c> members = byKey.get(key);
            AxisRef ref = new AxisRef();
            buckets.fill(ref, key);
            AxisSegments entry = new AxisSegments();
            entry.segments = buildSegmentShares(members);
            entry.total = 0;
            for (SegmentShare share : entry.segments) {
                entry.total += share.count;
            }
            for (SegmentShare share : entry.segments) {
                share.percent = sampledPercent(share.count, entry.total);
            }
            entry.entityName = ref.label;
            entry.noEntity = ref.noValue;
            entry.others = ref.others;
            entry.entityId = ref.noValue ? null : key;
            if (axis == AXIS_ENTITY && !ref.noValue && !ref.others) {
                entry.country = countryOf(members[0].AR_Entity_Ref__r);
            }
            if (ref.others) {
                othersRow = entry;
            } else {
                rows.add(entry);
            }
        }
        rows.sort();
        if (othersRow != null) {
            rows.add(othersRow);
        }
        return rows;
    }

    // ---------- Mois de la période ----------

    private static List<Date> monthRange(Scope scope, List<Datetime> dates) {
        Date endMonth = (scope.toDate != null ? scope.toDate : Date.today()).toStartOfMonth();
        Date startMonth = null;
        if (scope.fromDate != null) {
            startMonth = scope.fromDate.toStartOfMonth();
        } else {
            for (Datetime at : dates) {
                if (at != null && (startMonth == null || at.date().toStartOfMonth() < startMonth)) {
                    startMonth = at.date().toStartOfMonth();
                }
            }
        }
        if (startMonth == null || startMonth > endMonth) {
            startMonth = endMonth;
        }
        if (startMonth.monthsBetween(endMonth) + 1 > MAX_MONTHS) {
            startMonth = endMonth.addMonths(1 - MAX_MONTHS);
        }
        List<Date> months = new List<Date>();
        for (Date month = startMonth; month <= endMonth; month = month.addMonths(1)) {
            months.add(month);
        }
        return months;
    }

    private static List<String> monthKeys(List<Date> months) {
        List<String> keys = new List<String>();
        for (Date month : months) {
            keys.add(monthKey(startOf(month)));
        }
        return keys;
    }

    // ---------- Point d'entrée des onglets ----------

    /**
     * Onglets chargés à la demande : `derogations`, `profitability` ou `won`. Mêmes filtres JSON que la Vue
     * d'ensemble (axis, période, entité, pays) plus `motifAxisValue` pour le top des motifs.
     */
    @AuraEnabled
    public static String getDashboardTab(String tab, String filtersJson) {
        try {
            Scope scope = parseScope(filtersJson);
            Base base = loadBase(scope);
            if (tab == 'derogations') {
                return JSON.serialize(buildDerogationsTab(base));
            }
            if (tab == 'profitability') {
                return JSON.serialize(buildProfitabilityTab(base));
            }
            if (tab == 'won') {
                return JSON.serialize(buildWonTab(base));
            }
            throw newAuraException('Onglet du tableau de bord inconnu : ' + tab);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, 'le chargement du tableau de bord');
        }
    }

    // ---------- Onglet Dérogations ----------

    public class DerogationsTab {
        public String axis;
        public DerogationKpis kpis;
        public List<String> months;
        public List<DerogationMonth> monthly;
        public List<DerogationAxisRate> rateByAxis;
        public String motifAxisValue;
        public List<AxisRef> motifAxisOptions;
        public Reasons reasons;
        public List<ValidatorStats> validators;
        public List<DerogationClient> topClients;
    }

    public class DerogationKpis {
        public Integer requestedCount;
        public Decimal derogationRatePercent;
        public Integer acceptedCount;
        public Integer refusedCount;
        public Integer pendingCount;
        public Decimal acceptedPercent;
        public Decimal medianDelayDays;
    }

    public class DerogationMonth {
        public String month;
        public Integer accepted = 0;
        public Integer refused = 0;
        public Integer pending = 0;
    }

    public class DerogationAxisRate extends AxisRef {
        public Integer validatedCount;
        public Integer derogationValidatedCount;
        public Decimal ratePercent;
    }

    public class ValidatorStats {
        public String validatorId;
        public String name;
        public Integer received = 0;
        public Integer accepted = 0;
        public Integer refused = 0;
        public Integer pending = 0;
        public Decimal refusalPercent;
        public Decimal medianDelayDays;
        transient List<Decimal> delays = new List<Decimal>();
    }

    public class DerogationClient {
        public String accountName;
        public Integer derogationCount;
        public Integer validatedCount;
        public Decimal ratePercent;
        public String mainReason;
    }

    private static DerogationsTab buildDerogationsTab(Base base) {
        Scope scope = base.scope;
        List<AR_Derogation__c> derogations = derogationsInScope(loadDerogations(), scope);
        DerogationsTab tab = new DerogationsTab();
        tab.axis = scope.axis;

        Integer accepted = 0;
        Integer refused = 0;
        Integer pending = 0;
        List<Decimal> delays = new List<Decimal>();
        List<Datetime> requestDates = new List<Datetime>();
        for (AR_Derogation__c d : derogations) {
            String decision = decisionOf(d);
            requestDates.add(d.AR_Requested_At__c);
            if (decision == 'Acceptée') {
                accepted++;
            } else if (decision == 'Refusée') {
                refused++;
            } else {
                pending++;
            }
            if (decision != 'En attente' && delayInDays(d) != null) {
                delays.add(delayInDays(d));
            }
        }
        tab.kpis = new DerogationKpis();
        tab.kpis.requestedCount = derogations.size();
        tab.kpis.derogationRatePercent = buildKpis(base.selected).derogationValidatedPercent;
        tab.kpis.acceptedCount = accepted;
        tab.kpis.refusedCount = refused;
        tab.kpis.pendingCount = pending;
        tab.kpis.acceptedPercent = sampledPercent(accepted, accepted + refused);
        tab.kpis.medianDelayDays = median(delays);

        // Série mensuelle par décision.
        List<Date> months = monthRange(scope, requestDates);
        tab.months = monthKeys(months);
        Map<String, DerogationMonth> byMonth = new Map<String, DerogationMonth>();
        tab.monthly = new List<DerogationMonth>();
        for (String key : tab.months) {
            DerogationMonth entry = new DerogationMonth();
            entry.month = key;
            byMonth.put(key, entry);
            tab.monthly.add(entry);
        }
        for (AR_Derogation__c d : derogations) {
            DerogationMonth entry = d.AR_Requested_At__c == null ? null : byMonth.get(monthKey(d.AR_Requested_At__c));
            if (entry == null) {
                continue;
            }
            String decision = decisionOf(d);
            if (decision == 'Acceptée') {
                entry.accepted++;
            } else if (decision == 'Refusée') {
                entry.refused++;
            } else {
                entry.pending++;
            }
        }

        // Taux de dérogation par valeur d'axe (validées par dérogation ÷ validées).
        AxisBuckets rateBuckets = new AxisBuckets();
        for (AR_Price_Matrix__c m : base.selected) {
            rateBuckets.add(axisOf(m, scope.axis));
        }
        rateBuckets.done();
        Map<String, Integer> validatedByKey = new Map<String, Integer>();
        Map<String, Integer> derogationByKey = new Map<String, Integer>();
        for (AR_Price_Matrix__c m : base.selected) {
            String key = rateBuckets.keyOf(axisOf(m, scope.axis));
            increment(validatedByKey, key);
            if (m.AR_Status__c == DEROGATION_STATUS) {
                increment(derogationByKey, key);
            }
        }
        tab.rateByAxis = new List<DerogationAxisRate>();
        for (String key : rateBuckets.keys()) {
            DerogationAxisRate row = new DerogationAxisRate();
            rateBuckets.fill(row, key);
            row.validatedCount = count(validatedByKey, key);
            row.derogationValidatedCount = count(derogationByKey, key);
            row.ratePercent = sampledPercent(row.derogationValidatedCount, row.validatedCount);
            tab.rateByAxis.add(row);
        }

        // Top des motifs, filtrable par valeur d'axe.
        AxisBuckets motifBuckets = new AxisBuckets();
        for (AR_Derogation__c d : derogations) {
            motifBuckets.add(axisOf(d.AR_Price_Matrix__r, scope.axis));
        }
        motifBuckets.done();
        tab.motifAxisValue = scope.motifAxisValue;
        tab.motifAxisOptions = new List<AxisRef>();
        for (String key : motifBuckets.keys()) {
            AxisRef option = new AxisRef();
            motifBuckets.fill(option, key);
            tab.motifAxisOptions.add(option);
        }
        List<AR_Derogation__c> motifScope = new List<AR_Derogation__c>();
        for (AR_Derogation__c d : derogations) {
            if (scope.motifAxisValue == null || motifBuckets.keyOf(axisOf(d.AR_Price_Matrix__r, scope.axis)) == scope.motifAxisValue) {
                motifScope.add(d);
            }
        }
        tab.reasons = reasonsOf(motifScope);

        tab.validators = buildValidatorStats(derogations);
        tab.topClients = buildDerogationClients(derogations, base.selected);
        return tab;
    }

    private class ValidatorOrder implements Comparable {
        ValidatorStats stats;

        public Integer compareTo(Object other) {
            ValidatorOrder o = (ValidatorOrder) other;
            if (stats.received != o.stats.received) {
                return o.stats.received - stats.received;
            }
            return compareNames(stats.name, o.stats.name);
        }
    }

    /** Valideur = valideur effectif ; une dérogation en attente est attribuée au valideur sélectionné. */
    private static List<ValidatorStats> buildValidatorStats(List<AR_Derogation__c> derogations) {
        Map<String, ValidatorStats> byValidator = new Map<String, ValidatorStats>();
        for (AR_Derogation__c d : derogations) {
            Boolean effective = d.AR_Effective_Validator__c != null;
            Id validatorId = effective ? d.AR_Effective_Validator__c : d.AR_Selected_Validator__c;
            String key = validatorId == null ? '' : String.valueOf(validatorId);
            ValidatorStats stats = byValidator.get(key);
            if (stats == null) {
                stats = new ValidatorStats();
                stats.validatorId = validatorId == null ? null : key;
                stats.name = validatorId == null ? 'Sans valideur' : (effective ? d.AR_Effective_Validator__r.Name : d.AR_Selected_Validator__r.Name);
                byValidator.put(key, stats);
            }
            stats.received++;
            String decision = decisionOf(d);
            if (decision == 'Acceptée') {
                stats.accepted++;
            } else if (decision == 'Refusée') {
                stats.refused++;
            } else {
                stats.pending++;
            }
            if (decision != 'En attente' && delayInDays(d) != null) {
                stats.delays.add(delayInDays(d));
            }
        }
        List<ValidatorOrder> ordered = new List<ValidatorOrder>();
        for (ValidatorStats stats : byValidator.values()) {
            stats.refusalPercent = sampledPercent(stats.refused, stats.accepted + stats.refused);
            stats.medianDelayDays = median(stats.delays);
            ValidatorOrder order = new ValidatorOrder();
            order.stats = stats;
            ordered.add(order);
        }
        ordered.sort();
        List<ValidatorStats> result = new List<ValidatorStats>();
        for (ValidatorOrder order : ordered) {
            result.add(order.stats);
        }
        return result;
    }

    private class ClientOrder implements Comparable {
        DerogationClient row;

        public Integer compareTo(Object other) {
            ClientOrder o = (ClientOrder) other;
            if (row.derogationCount != o.row.derogationCount) {
                return o.row.derogationCount - row.derogationCount;
            }
            return compareNames(row.accountName, o.row.accountName);
        }
    }

    private static List<DerogationClient> buildDerogationClients(List<AR_Derogation__c> derogations, List<AR_Price_Matrix__c> selected) {
        Map<String, Integer> validatedByAccount = new Map<String, Integer>();
        Map<String, Integer> derogationValidatedByAccount = new Map<String, Integer>();
        for (AR_Price_Matrix__c m : selected) {
            if (String.isBlank(m.AR_Account_Name__c)) {
                continue;
            }
            increment(validatedByAccount, m.AR_Account_Name__c);
            if (m.AR_Status__c == DEROGATION_STATUS) {
                increment(derogationValidatedByAccount, m.AR_Account_Name__c);
            }
        }
        Map<String, Integer> countByAccount = new Map<String, Integer>();
        Map<String, Map<String, Integer>> reasonsByAccount = new Map<String, Map<String, Integer>>();
        for (AR_Derogation__c d : derogations) {
            String account = d.AR_Price_Matrix__r == null ? null : d.AR_Price_Matrix__r.AR_Account_Name__c;
            if (String.isBlank(account)) {
                continue;
            }
            increment(countByAccount, account);
            if (!reasonsByAccount.containsKey(account)) {
                reasonsByAccount.put(account, new Map<String, Integer>());
            }
            for (AR_Reason_Selection__c selection : d.AR_Reason_Selections__r) {
                if (selection.AR_Reason__r != null) {
                    increment(reasonsByAccount.get(account), selection.AR_Reason__r.Name);
                }
            }
        }
        List<ClientOrder> ordered = new List<ClientOrder>();
        for (String account : countByAccount.keySet()) {
            DerogationClient row = new DerogationClient();
            row.accountName = account;
            row.derogationCount = countByAccount.get(account);
            row.validatedCount = count(validatedByAccount, account);
            row.ratePercent = row.validatedCount < MIN_MATRICES_PER_CLIENT ? null : percentOf(count(derogationValidatedByAccount, account), row.validatedCount);
            row.mainReason = mostFrequent(reasonsByAccount.get(account));
            ClientOrder order = new ClientOrder();
            order.row = row;
            ordered.add(order);
        }
        ordered.sort();
        List<DerogationClient> result = new List<DerogationClient>();
        for (Integer i = 0; i < ordered.size() && i < TOP_CLIENTS; i++) {
            result.add(ordered[i].row);
        }
        return result;
    }

    /** Valeur la plus fréquente ; à égalité, la première par ordre alphabétique. Null si aucune. */
    private static String mostFrequent(Map<String, Integer> counts) {
        String best = null;
        for (String key : counts.keySet()) {
            if (best == null || counts.get(key) > counts.get(best) || (counts.get(key) == counts.get(best) && compareNames(key, best) < 0)) {
                best = key;
            }
        }
        return best;
    }

    // ---------- Onglet Rentabilité & coûts ----------

    public class ProfitabilityTab {
        public String axis;
        public ProfitabilityKpis kpis;
        public List<String> posts;
        public CostRow groupRow;
        public List<CostRow> costRows;
        public List<PostPoints> mc2PointsByPost;
        public Decimal groupAverageMc2Percent;
        public String groupSegment;
        public List<Mc2AxisRow> mc2ByAxis;
        public List<LowMarginClient> lowestMarginClients;
        public List<ThresholdAccount> highestThresholdAccounts;
        public Integer costSampleSize;
        public Integer excludedWithoutDays;
    }

    public class ProfitabilityKpis {
        public Decimal averageMc2Percent;
        public Decimal costsOfSalesPerDay;
        public String topPost;
        public Decimal topPostSharePercent;
        public Integer belowFloorCount;
        public String pivotCurrencyCode;
    }

    public class PostValue {
        public String post;
        public Decimal perDay;
        public Decimal percent;
    }

    public class CostRow extends AxisRef {
        public Integer matrixCount;
        public Decimal totalPerDay;
        public List<PostValue> parts;
    }

    public class PostPoints {
        public String post;
        public Decimal points;
    }

    public class Mc2AxisRow extends AxisRef {
        public Integer matrixCount;
        public Decimal averageMc2Percent;
        public String segment;
    }

    public class LowMarginClient {
        public String accountName;
        public String axisLabel;
        public Integer matrixCount;
        public Decimal averageMc2Percent;
        public Decimal averageTargetPercent;
        public Decimal gapPoints;
    }

    public class ThresholdAccount {
        public String accountName;
        public Decimal floorPercent;
        public Decimal targetPercent;
        public Decimal idealPercent;
        public String source;
    }

    private class CostAgg {
        Integer matrices = 0;
        Decimal days = 0;
        Map<String, Decimal> postDays = new Map<String, Decimal>();
        Decimal tjmDays = 0;
        Map<String, Decimal> pointsNumerator = new Map<String, Decimal>();

        CostAgg() {
            for (String post : AR_DashboardCosts.POSTS) {
                postDays.put(post, 0);
                pointsNumerator.put(post, 0);
            }
        }

        void add(Map<String, Decimal> eurPerDay, Decimal weight, Decimal tjmEur) {
            matrices++;
            days += weight;
            for (String post : AR_DashboardCosts.POSTS) {
                postDays.put(post, postDays.get(post) + eurPerDay.get(post) * weight);
                if (tjmEur != null) {
                    pointsNumerator.put(post, pointsNumerator.get(post) + eurPerDay.get(post) * weight);
                }
            }
            if (tjmEur != null) {
                tjmDays += tjmEur * weight;
            }
        }

        Decimal perDay(String post) {
            return days > 0 ? postDays.get(post) / days : null;
        }
    }

    private static CostRow costRowOf(CostAgg agg) {
        CostRow row = new CostRow();
        row.matrixCount = agg.matrices;
        row.parts = new List<PostValue>();
        Boolean sampled = agg.matrices >= MIN_SAMPLE_SIZE && agg.days > 0;
        Decimal total = 0;
        for (String post : AR_DashboardCosts.POSTS) {
            total += sampled ? agg.perDay(post) : 0;
        }
        row.totalPerDay = sampled ? total.setScale(2, RoundingMode.HALF_UP) : null;
        for (String post : AR_DashboardCosts.POSTS) {
            PostValue part = new PostValue();
            part.post = post;
            if (sampled) {
                part.perDay = agg.perDay(post).setScale(2, RoundingMode.HALF_UP);
                part.percent = total > 0 ? (agg.perDay(post) * 100 / total).setScale(1, RoundingMode.HALF_UP) : 0;
            }
            row.parts.add(part);
        }
        return row;
    }

    private class PointsOrder implements Comparable {
        PostPoints entry;

        public Integer compareTo(Object other) {
            PointsOrder o = (PointsOrder) other;
            if (entry.points != o.entry.points) {
                return entry.points > o.entry.points ? -1 : 1;
            }
            return compareNames(entry.post, o.entry.post);
        }
    }

    private static ProfitabilityTab buildProfitabilityTab(Base base) {
        Scope scope = base.scope;
        List<AR_Price_Matrix__c> selected = base.selected;
        ProfitabilityTab tab = new ProfitabilityTab();
        tab.axis = scope.axis;
        tab.posts = AR_DashboardCosts.POSTS;

        // Frais par poste : fonctions du moteur, pivot EUR (taux figé de la matrice), pondération par jours facturables.
        Set<Id> ids = new Set<Id>();
        for (AR_Price_Matrix__c m : selected) {
            ids.add(m.Id);
        }
        Map<Id, AR_Price_Matrix__c> costMatrices = AR_DashboardCosts.loadForCosts(ids);
        AxisBuckets buckets = new AxisBuckets();
        for (AR_Price_Matrix__c m : selected) {
            buckets.add(axisOf(m, scope.axis));
        }
        buckets.done();

        CostAgg groupAgg = new CostAgg();
        Map<String, CostAgg> aggByKey = new Map<String, CostAgg>();
        tab.excludedWithoutDays = 0;
        for (AR_Price_Matrix__c m : selected) {
            AR_Price_Matrix__c costMatrix = costMatrices.get(m.Id);
            Decimal weight = AR_DashboardCosts.weightDays(costMatrix);
            if (weight <= 0) {
                tab.excludedWithoutDays++;
                continue;
            }
            Decimal rate = AR_DashboardCosts.rateToEur(costMatrix);
            Map<String, Decimal> eur = new Map<String, Decimal>();
            Map<String, Decimal> perDay = AR_DashboardCosts.postsPerDay(costMatrix);
            for (String post : perDay.keySet()) {
                eur.put(post, perDay.get(post) * rate);
            }
            Decimal tjmEur = pivotTjm(m);
            groupAgg.add(eur, weight, tjmEur);
            String key = buckets.keyOf(axisOf(m, scope.axis));
            if (!aggByKey.containsKey(key)) {
                aggByKey.put(key, new CostAgg());
            }
            aggByKey.get(key).add(eur, weight, tjmEur);
        }
        tab.costSampleSize = groupAgg.matrices;

        tab.groupRow = costRowOf(groupAgg);
        tab.groupRow.key = AXIS_GROUP;
        tab.groupRow.label = GROUP_LABEL;
        tab.costRows = new List<CostRow>();
        for (String key : buckets.keys()) {
            CostRow row = costRowOf(aggByKey.containsKey(key) ? aggByKey.get(key) : new CostAgg());
            buckets.fill(row, key);
            tab.costRows.add(row);
        }

        // KPI.
        tab.kpis = new ProfitabilityKpis();
        tab.kpis.averageMc2Percent = buildKpis(selected).averageMc2Percent;
        tab.kpis.pivotCurrencyCode = PIVOT_CURRENCY;
        tab.kpis.costsOfSalesPerDay = tab.groupRow.totalPerDay;
        tab.kpis.belowFloorCount = 0;
        for (AR_Price_Matrix__c m : selected) {
            if (m.AR_Corridor_Segment__c == 'below_floor') {
                tab.kpis.belowFloorCount++;
            }
        }
        if (tab.groupRow.totalPerDay != null && tab.groupRow.totalPerDay > 0) {
            PostValue top = null;
            for (PostValue part : tab.groupRow.parts) {
                if (top == null || part.perDay > top.perDay) {
                    top = part;
                }
            }
            tab.kpis.topPost = top.post;
            tab.kpis.topPostSharePercent = top.percent;
        }

        // Points de MC2 consommés par poste : Σ(frais × jours) ÷ Σ(TJM × jours) × 100.
        tab.mc2PointsByPost = new List<PostPoints>();
        if (groupAgg.matrices >= MIN_SAMPLE_SIZE && groupAgg.tjmDays > 0) {
            List<PointsOrder> ordered = new List<PointsOrder>();
            for (String post : AR_DashboardCosts.POSTS) {
                PointsOrder order = new PointsOrder();
                order.entry = new PostPoints();
                order.entry.post = post;
                order.entry.points = (groupAgg.pointsNumerator.get(post) * 100 / groupAgg.tjmDays).setScale(1, RoundingMode.HALF_UP);
                ordered.add(order);
            }
            ordered.sort();
            for (Integer i = 0; i < ordered.size() && i < TOP_POSTS; i++) {
                tab.mc2PointsByPost.add(ordered[i].entry);
            }
        }

        // MC2 moyenne par valeur d'axe, avec son segment (seuils par défaut du moteur).
        tab.groupAverageMc2Percent = tab.kpis.averageMc2Percent;
        tab.groupSegment = segmentOfAverage(tab.groupAverageMc2Percent);
        Map<String, Decimal> mc2Sum = new Map<String, Decimal>();
        Map<String, Integer> mc2Count = new Map<String, Integer>();
        for (AR_Price_Matrix__c m : selected) {
            if (m.AR_MC2_Percent__c == null) {
                continue;
            }
            String key = buckets.keyOf(axisOf(m, scope.axis));
            mc2Sum.put(key, (mc2Sum.containsKey(key) ? mc2Sum.get(key) : 0) + m.AR_MC2_Percent__c);
            increment(mc2Count, key);
        }
        tab.mc2ByAxis = new List<Mc2AxisRow>();
        for (String key : buckets.keys()) {
            Mc2AxisRow row = new Mc2AxisRow();
            buckets.fill(row, key);
            row.matrixCount = count(mc2Count, key);
            row.averageMc2Percent = row.matrixCount < MIN_SAMPLE_SIZE ? null : average(mc2Sum.get(key), row.matrixCount, 1);
            row.segment = segmentOfAverage(row.averageMc2Percent);
            tab.mc2ByAxis.add(row);
        }

        tab.lowestMarginClients = buildLowMarginClients(selected, scope.axis);
        tab.highestThresholdAccounts = buildThresholdAccounts(selected);
        return tab;
    }

    private static String segmentOfAverage(Decimal averageMc2Percent) {
        return averageMc2Percent == null ? null : AR_PricingCalculator.getCorridorSegment(averageMc2Percent / 100, null);
    }

    private class LowMarginOrder implements Comparable {
        LowMarginClient row;

        public Integer compareTo(Object other) {
            LowMarginOrder o = (LowMarginOrder) other;
            if (row.averageMc2Percent != o.row.averageMc2Percent) {
                return row.averageMc2Percent > o.row.averageMc2Percent ? 1 : -1;
            }
            return compareNames(row.accountName, o.row.accountName);
        }
    }

    private static List<LowMarginClient> buildLowMarginClients(List<AR_Price_Matrix__c> selected, String axis) {
        Map<String, List<AR_Price_Matrix__c>> byAccount = new Map<String, List<AR_Price_Matrix__c>>();
        for (AR_Price_Matrix__c m : selected) {
            if (String.isBlank(m.AR_Account_Name__c) || m.AR_MC2_Percent__c == null) {
                continue;
            }
            if (!byAccount.containsKey(m.AR_Account_Name__c)) {
                byAccount.put(m.AR_Account_Name__c, new List<AR_Price_Matrix__c>());
            }
            byAccount.get(m.AR_Account_Name__c).add(m);
        }
        List<LowMarginOrder> ordered = new List<LowMarginOrder>();
        for (String account : byAccount.keySet()) {
            List<AR_Price_Matrix__c> members = byAccount.get(account);
            if (members.size() < MIN_MATRICES_PER_CLIENT) {
                continue;
            }
            Decimal mc2Sum = 0;
            Decimal targetSum = 0;
            Integer targetCount = 0;
            Map<String, Integer> labels = new Map<String, Integer>();
            for (AR_Price_Matrix__c m : members) {
                mc2Sum += m.AR_MC2_Percent__c;
                if (m.AR_Target_Percent_Applied__c != null) {
                    targetSum += m.AR_Target_Percent_Applied__c;
                    targetCount++;
                }
                increment(labels, axisOf(m, axis).label);
            }
            LowMarginClient row = new LowMarginClient();
            row.accountName = account;
            row.matrixCount = members.size();
            row.averageMc2Percent = average(mc2Sum, members.size(), 1);
            row.averageTargetPercent = average(targetSum, targetCount, 1);
            row.gapPoints = row.averageTargetPercent == null ? null : (row.averageMc2Percent - row.averageTargetPercent).setScale(1, RoundingMode.HALF_UP);
            row.axisLabel = mostFrequentByCount(labels);
            LowMarginOrder order = new LowMarginOrder();
            order.row = row;
            ordered.add(order);
        }
        ordered.sort();
        List<LowMarginClient> result = new List<LowMarginClient>();
        for (Integer i = 0; i < ordered.size() && i < TOP_CLIENTS; i++) {
            result.add(ordered[i].row);
        }
        return result;
    }

    /** Libellé le plus fréquent (plus grand effectif ; à égalité, ordre alphabétique). */
    private static String mostFrequentByCount(Map<String, Integer> counts) {
        return mostFrequent(counts);
    }

    private class ThresholdOrder implements Comparable {
        ThresholdAccount row;

        public Integer compareTo(Object other) {
            ThresholdOrder o = (ThresholdOrder) other;
            if (row.targetPercent != o.row.targetPercent) {
                return row.targetPercent > o.row.targetPercent ? -1 : 1;
            }
            if (row.idealPercent != o.row.idealPercent) {
                return (row.idealPercent == null ? -1 : row.idealPercent) > (o.row.idealPercent == null ? -1 : o.row.idealPercent) ? -1 : 1;
            }
            return compareNames(row.accountName, o.row.accountName);
        }
    }

    /** Par compte, la matrice validée aux seuils cibles les plus hauts ; les cinq comptes les plus hauts. */
    private static List<ThresholdAccount> buildThresholdAccounts(List<AR_Price_Matrix__c> selected) {
        Map<String, AR_Price_Matrix__c> best = new Map<String, AR_Price_Matrix__c>();
        for (AR_Price_Matrix__c m : selected) {
            if (String.isBlank(m.AR_Account_Name__c) || m.AR_Target_Percent_Applied__c == null) {
                continue;
            }
            AR_Price_Matrix__c current = best.get(m.AR_Account_Name__c);
            if (current == null || m.AR_Target_Percent_Applied__c > current.AR_Target_Percent_Applied__c) {
                best.put(m.AR_Account_Name__c, m);
            }
        }
        List<ThresholdOrder> ordered = new List<ThresholdOrder>();
        for (String account : best.keySet()) {
            AR_Price_Matrix__c m = best.get(account);
            ThresholdAccount row = new ThresholdAccount();
            row.accountName = account;
            row.floorPercent = m.AR_Floor_Percent_Applied__c;
            row.targetPercent = m.AR_Target_Percent_Applied__c;
            row.idealPercent = m.AR_Ideal_Percent_Applied__c;
            row.source = m.AR_Corridor_Source__c;
            ThresholdOrder order = new ThresholdOrder();
            order.row = row;
            ordered.add(order);
        }
        ordered.sort();
        List<ThresholdAccount> result = new List<ThresholdAccount>();
        for (Integer i = 0; i < ordered.size() && i < TOP_CLIENTS; i++) {
            result.add(ordered[i].row);
        }
        return result;
    }

    // ---------- Onglet Simulations & affaires gagnées ----------

    public class WonTab {
        public String axis;
        public WonKpis kpis;
        public List<LevelShare> levels;
        public List<String> months;
        public List<MonthlyAxisRow> simulationsByMonth;
        public List<TransformRow> transformation;
        public TransformRow total;
        public Integer pendingTotal;
        public List<AR_WonDealService.WonDealDTO> pending;
    }

    public class WonKpis {
        public Integer simulationsCount;
        public Integer validatedCount;
        public Integer wonCount;
        public Decimal simulatedToWonPercent;
        public Decimal validatedToWonPercent;
        public Decimal priceOnePercent;
        public Integer pendingCount;
    }

    public class LevelShare {
        public String level;
        public Integer count;
        public Decimal percent;
    }

    public class MonthlyAxisRow extends AxisRef {
        public List<Integer> counts;
        public Integer total;
        public Decimal monthlyAverage;
    }

    public class TransformRow extends AxisRef {
        public Integer simulated = 0;
        public Integer validated = 0;
        public Integer won = 0;
        public Decimal simulatedToWonPercent;
        public Decimal validatedToWonPercent;
        public Integer priceOne = 0;
        public Integer priceTwo = 0;
        public Integer priceThree = 0;
        public Integer offGrid = 0;
    }

    private static final List<String> LEVELS_ORDER = new List<String>{
        AR_SignedPriceLevel.P1, AR_SignedPriceLevel.P2, AR_SignedPriceLevel.P3, AR_SignedPriceLevel.OFF_GRID
    };

    private static void addLevel(TransformRow row, String level) {
        if (level == AR_SignedPriceLevel.P1) {
            row.priceOne++;
        } else if (level == AR_SignedPriceLevel.P2) {
            row.priceTwo++;
        } else if (level == AR_SignedPriceLevel.P3) {
            row.priceThree++;
        } else if (level == AR_SignedPriceLevel.OFF_GRID) {
            row.offGrid++;
        }
    }

    private static WonTab buildWonTab(Base base) {
        Scope scope = base.scope;
        List<SimRow> sims = simulationsOf(base);
        List<WonRow> wins = wonRowsOf(base);
        List<AR_Price_Matrix__c> validated = base.selected;
        WonTab tab = new WonTab();
        tab.axis = scope.axis;

        List<AR_WonDealService.WonDealDTO> pendingAll = AR_WonDealService.getPendingWonDeals();
        tab.pendingTotal = pendingAll.size();
        tab.pending = new List<AR_WonDealService.WonDealDTO>();
        for (Integer i = 0; i < pendingAll.size() && i < PENDING_WON_LIMIT; i++) {
            tab.pending.add(pendingAll[i]);
        }

        tab.total = new TransformRow();
        tab.total.key = AXIS_GROUP;
        tab.total.label = GROUP_LABEL;
        tab.total.simulated = sims.size();
        tab.total.validated = validated.size();
        tab.total.won = wins.size();
        Map<String, Integer> levelCounts = new Map<String, Integer>();
        for (WonRow w : wins) {
            addLevel(tab.total, w.level);
            increment(levelCounts, w.level == null ? '' : w.level);
        }
        tab.total.simulatedToWonPercent = sampledPercent(wins.size(), sims.size());
        tab.total.validatedToWonPercent = sampledPercent(wins.size(), validated.size());

        tab.kpis = new WonKpis();
        tab.kpis.simulationsCount = sims.size();
        tab.kpis.validatedCount = validated.size();
        tab.kpis.wonCount = wins.size();
        tab.kpis.simulatedToWonPercent = tab.total.simulatedToWonPercent;
        tab.kpis.validatedToWonPercent = tab.total.validatedToWonPercent;
        tab.kpis.priceOnePercent = sampledPercent(tab.total.priceOne, wins.size());
        tab.kpis.pendingCount = pendingAll.size();

        tab.levels = new List<LevelShare>();
        for (String level : LEVELS_ORDER) {
            LevelShare share = new LevelShare();
            share.level = level;
            share.count = count(levelCounts, level);
            share.percent = sampledPercent(share.count, wins.size());
            tab.levels.add(share);
        }

        // Valeurs d'axe communes aux trois populations.
        AxisBuckets buckets = new AxisBuckets();
        for (SimRow s : sims) {
            buckets.add(s.item);
        }
        for (AR_Price_Matrix__c m : validated) {
            buckets.add(axisOf(m, scope.axis));
        }
        for (WonRow w : wins) {
            buckets.add(w.item);
        }
        buckets.done();

        Map<String, TransformRow> rowsByKey = new Map<String, TransformRow>();
        for (String key : buckets.keys()) {
            TransformRow row = new TransformRow();
            buckets.fill(row, key);
            rowsByKey.put(key, row);
        }
        for (SimRow s : sims) {
            rowsByKey.get(buckets.keyOf(s.item)).simulated++;
        }
        for (AR_Price_Matrix__c m : validated) {
            rowsByKey.get(buckets.keyOf(axisOf(m, scope.axis))).validated++;
        }
        for (WonRow w : wins) {
            TransformRow row = rowsByKey.get(buckets.keyOf(w.item));
            row.won++;
            addLevel(row, w.level);
        }
        tab.transformation = new List<TransformRow>();
        for (String key : buckets.keys()) {
            TransformRow row = rowsByKey.get(key);
            row.simulatedToWonPercent = sampledPercent(row.won, row.simulated);
            row.validatedToWonPercent = sampledPercent(row.won, row.validated);
            tab.transformation.add(row);
        }

        // Simulations par mois et par valeur d'axe (moyenne mensuelle sur la période).
        List<Datetime> simDates = new List<Datetime>();
        for (SimRow s : sims) {
            simDates.add(s.createdAt);
        }
        List<Date> months = monthRange(scope, simDates);
        tab.months = monthKeys(months);
        Map<String, Integer> monthIndex = new Map<String, Integer>();
        for (Integer i = 0; i < tab.months.size(); i++) {
            monthIndex.put(tab.months[i], i);
        }
        Map<String, MonthlyAxisRow> monthlyByKey = new Map<String, MonthlyAxisRow>();
        tab.simulationsByMonth = new List<MonthlyAxisRow>();
        for (String key : buckets.keys()) {
            MonthlyAxisRow row = new MonthlyAxisRow();
            buckets.fill(row, key);
            row.counts = new List<Integer>();
            for (Integer i = 0; i < tab.months.size(); i++) {
                row.counts.add(0);
            }
            row.total = 0;
            monthlyByKey.put(key, row);
            tab.simulationsByMonth.add(row);
        }
        for (SimRow s : sims) {
            Integer index = s.createdAt == null ? null : monthIndex.get(monthKey(s.createdAt));
            if (index == null) {
                continue;
            }
            MonthlyAxisRow row = monthlyByKey.get(buckets.keyOf(s.item));
            row.counts.set(index, row.counts.get(index) + 1);
            row.total++;
        }
        for (MonthlyAxisRow row : tab.simulationsByMonth) {
            row.monthlyAverage = (Decimal.valueOf(row.total) / tab.months.size()).setScale(1, RoundingMode.HALF_UP);
        }
        return tab;
    }

    // ---------- Utilitaires ----------

    private static Decimal percentOf(Integer part, Integer total) {
        return total == 0 ? null : (Decimal.valueOf(part) * 100 / total).setScale(1, RoundingMode.HALF_UP);
    }

    private static Decimal average(Decimal sum, Integer count, Integer scale) {
        return count == 0 ? null : (sum / count).setScale(scale, RoundingMode.HALF_UP);
    }

    private static Integer compareNames(String left, String right) {
        if (left == right) {
            return 0;
        }
        return left > right ? 1 : -1;
    }
}