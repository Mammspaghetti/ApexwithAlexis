/**
 * Repères marché : médiane et percentile 90 des TJM réels observés sur des besoins gagnés
 * comparables, pour étayer la décision de pricing (docs/09-reperes-marche.md et docs/67-cadrage).
 *
 * Source de données (docs/01-decouverte-org.md §4) : `cxsrec__cxsPosition__c.TP_TJM__c` renseigné,
 * `cxsrec__Status__c = 'Gagné'` — la seule source de tarification réelle exploitable dans cette
 * sandbox (les objets missions/placements du package Connexys sont vides).
 *
 * Moteur pondéré (session 69, docs/67-cadrage) : remplace les 3 cercles par un calcul de
 * similarité continu sur métier/secteur/client. Chaque comparable reçoit un score de similarité
 * (0-1), et la médiane/p90 se calculent en pondérant par ce score. La séniorité n'intervient plus
 * au calcul (ancien rôle session 28) ; elle n'intervient qu'à la restitution (segmentation).
 *
 * Source du signal métier (session 69, audit) : les trois champs structurés candidats
 * (Job_position__c, Function__c, LinkedIn_default_title__c) sont à 0% de remplissage sur le pool
 * réel de besoins Gagné. Repli sur analyse textuelle du Name avec table de mots-clés prédéfinis
 * (~60% exploitable, session 67 §5).
 *
 * `with sharing` : un besoin (et son historique de comparables) n'est visible que dans le
 * périmètre de partage de l'utilisateur courant. C'est un choix assumé, pas un oubli — la
 * confidentialité inter-entités (un BM d'une entité ne doit pas voir les TJM pratiqués par une
 * autre entité sur les mêmes comptes) prime sur l'exhaustivité des comparables, conformément à
 * l'atelier du 15/07 (cf. CLAUDE.md, contrainte de partage déjà actée pour les objets AR_).
 * Conséquence assumée : deux BM sur le même besoin peuvent voir des comparables différents selon
 * leur périmètre — comportement voulu, pas un bug.
 */
public with sharing class AR_ComparablesService {

    private static final Integer QUERY_LIMIT = 2000;
    private static final Integer MONTHS_WIDE = 12;
    // Moteur pondéré (session 69) : effectif pondéré = somme des scores de similarité (max 1.0/comparable).
    // Score métier tombe à 0.25 si keyword absent (cas quasi-universel). Score max réaliste =
    // 0.625 (métier unknown 0.25 + secteur exact 1.0 + client exact 1.0, poids 50/30/20).
    // Session 69c : recalibré de 10.0 (inatteignable) à 7.0 (score réaliste de 12 comparables).
    // À confirmer avec usage réel — peut être ajusté par AR_General_Setting__c.
    private static final Decimal HIGH_CONFIDENCE_MIN = 7.0;   // effectif pondéré, pas brut
    private static final Decimal MEDIUM_CONFIDENCE_MIN = 3.0;  // à confirmer aussi
    private static final String WON_STATUS = 'Gagné';

    // --- Moteur pondéré (session 69) ---
    // Scores de correspondance par critère : exact, unknown (données manquantes), different.
    private static final Decimal MATCH_SCORE_EXACT = 1.00;
    private static final Decimal MATCH_SCORE_UNKNOWN = 0.25;
    private static final Decimal MATCH_SCORE_DIFFERENT = 0.00;

    // Table de mots-clés métier pour le repli textuel (aucun champ structuré n'est rempli en production).
    // ~60% exploitable d'après l'audit de session 67 §5.
    // Session 69c : ordre de résolution rendu déterministe en itérant une liste ordonnée plutôt que
    // Map.keySet() (ordre non garanti). Les mots-clés les plus longs sont testés en premier pour
    // éviter des matches partiels (ex. "lead" avant "lea*"). Ajout de niveaux de séniorité (utilisés
    // dans les tests pour différencier des profils).
    private static final List<String> METIER_KEYWORDS_ORDERED = new List<String>{
        'architect', 'infrastructure', 'devops', 'engineer', 'manager', 'analyst',
        'support', 'senior', 'confirmed', 'junior', 'lead', 'pmo', 'dev',
        'data', 'chef', 'qa', 'sys', 'tech'
    };

    private static final Map<String, String> METIER_KEYWORDS = new Map<String, String>{
        'dev' => 'développeur',
        'engineer' => 'ingénieur',
        'architect' => 'architecte',
        'manager' => 'manager',
        'lead' => 'lead',
        'pmo' => 'pmo',
        'chef' => 'chef de projet',
        'data' => 'data',
        'analyst' => 'analyst',
        'qa' => 'qa',
        'devops' => 'devops',
        'sys' => 'système',
        'infrastr' => 'infrastructure',
        'infrastructure' => 'infrastructure',
        'support' => 'support',
        'tech' => 'technique',
        'senior' => 'senior',
        'junior' => 'junior',
        'confirmed' => 'confirmé',
        'mid' => 'intermédiaire'
    };

    // Table de correspondance séniorité mots-clés → paliers (session 70, docs/67).
    // Mapping validé le 11/09/2026 : 4 paliers exactement (Junior, Confirmé, Senior, Expert).
    // Extraction approximative par LIKE sur Name (même méthode que métier) — utile quand
    // cxsCandidate.TP_Seniority__c n'est pas disponible (historique des besoins).
    private static final List<String> SENIORITY_KEYWORDS_ORDERED = new List<String>{
        'technical leader', 'project leader',  // Expert (2 mots, à tester avant les variantes single)
        'leader', 'expert',                     // Expert
        'specialist', 'technical manager', 'project manager',  // Senior
        'confirmed',                            // Confirmé
        'starter', 'junior'                     // Junior
    };

    // Mapping keyword → palier (docs/67, validation Alexis 11/09)
    private static final Map<String, String> SENIORITY_TIER_MAP = new Map<String, String>{
        'starter' => 'Junior',
        'junior' => 'Junior',
        'confirmed' => 'Confirmé',
        'specialist' => 'Senior',
        'project manager' => 'Senior',
        'technical manager' => 'Senior',
        'leader' => 'Expert',
        'project leader' => 'Expert',
        'technical leader' => 'Expert',
        'expert' => 'Expert'
    };

    public class MarketReference {
        @AuraEnabled public Integer comparableCount;
        @AuraEnabled public String circleCode;
        @AuraEnabled public String circleLabel;
        @AuraEnabled public Decimal medianTjm;
        @AuraEnabled public Decimal p90Tjm;
        @AuraEnabled public Decimal minTjm;
        @AuraEnabled public Decimal maxTjm;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public String confidenceLevel; // high / medium / low
        @AuraEnabled public Boolean hasEnoughData;
        // Socle multi-devises, restitution (session 24b) : l'historique de comparables
        // (cxsPosition.TP_TJM__c) est intégralement en euros, l'org étant mono-devise avant le lot 1.
        // medianTjm/p90Tjm/minTjm/maxTjm ci-dessus sont exprimés dans `currencyCode` — EUR par défaut
        // (non convertis), ou la devise de l'affaire si un taux a été fourni à getMarketReference.
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Boolean isConverted;
        @AuraEnabled public Decimal conversionRateApplied;
        // Valeurs EUR natives avant conversion — pour la mention "converti depuis X €" côté UI/PTF.
        // Null si isConverted = false (déjà nul besoin de les distinguer des valeurs ci-dessus).
        @AuraEnabled public Decimal medianTjmEurSource;
        @AuraEnabled public Decimal p90TjmEurSource;
        // Moteur pondéré (session 69) : score de similarité moyen du pool retenu, pour restitution
        // future (affichage de la qualité de la correspondance). Plage [0,1].
        @AuraEnabled public Decimal similarityScoreAvg;
        // Session 71 : poids et seuils exposés au front pour éviter la duplication et la divergence
        // à chaque recalibration. Valeurs effectives utilisées pour le calcul de ce pool (pas de
        // recalcul côté front).
        @AuraEnabled public Decimal weightMetierPercent;    // 50 par défaut
        @AuraEnabled public Decimal weightSecteurPercent;   // 30 par défaut
        @AuraEnabled public Decimal weightClientPercent;    // 20 par défaut
        @AuraEnabled public Decimal highConfidenceMin;      // effectif pondéré min pour "haute"
        @AuraEnabled public Decimal mediumConfidenceMin;    // effectif pondéré min pour "moyenne"
        // Resserrement par séniorité (session 28) : OBSOLÈTE en session 69. La séniorité n'intervient
        // plus au calcul ; elle n'intervient qu'à la restitution (segmentation). Conservé ici pour
        // non-régression des API existantes, toujours false.
        @AuraEnabled public Boolean seniorityNarrowed;
        // Session 73 : résultats réels du moteur (pas seulement ses réglages)
        @AuraEnabled public String resolvedCountry;
        @AuraEnabled public String resolvedMetierLabel;   // null si aucun mot-clé détecté
        @AuraEnabled public String resolvedSecteurLabel;  // null si Business_Line__c vide
        @AuraEnabled public Decimal avgMetierMatchPercent;
        @AuraEnabled public Decimal avgSecteurMatchPercent;
        @AuraEnabled public Decimal avgClientMatchPercent;
        @AuraEnabled public Decimal weightedEffectiveCount;
    }

    public class SeniorityTierReference {
        @AuraEnabled public String tierLabel;      // "Junior", "Confirmé", "Senior", "Expert"
        @AuraEnabled public Integer comparableCount;
        @AuraEnabled public Decimal q1Tjm;        // quartile bas
        @AuraEnabled public Decimal medianTjm;
        @AuraEnabled public Decimal q3Tjm;        // quartile haut
        @AuraEnabled public Boolean hasEnoughData;
    }

    /** Wrapper interne pour queryAndScoreComparables : retourne les listes pondérées
     * + les valeurs résolues du moteur (pays, métier, secteur) pour exposition au front (session 73). */
    private class ScoredComparablesResult {
        List<Decimal> tjms;
        List<Decimal> scores;
        List<Decimal> metierMatches;
        List<Decimal> secteurMatches;
        List<Decimal> clientMatches;
        String resolvedMetierKeyword;
        String resolvedBusinessLine;

        ScoredComparablesResult(
            List<Decimal> tjms,
            List<Decimal> scores,
            List<Decimal> metierMatches,
            List<Decimal> secteurMatches,
            List<Decimal> clientMatches,
            String resolvedMetierKeyword,
            String resolvedBusinessLine
        ) {
            this.tjms = tjms;
            this.scores = scores;
            this.metierMatches = metierMatches;
            this.secteurMatches = secteurMatches;
            this.clientMatches = clientMatches;
            this.resolvedMetierKeyword = resolvedMetierKeyword;
            this.resolvedBusinessLine = resolvedBusinessLine;
        }
    }

    // Devise native de l'historique de comparables (docs/01-decouverte-org.md §4 : org mono-devise
    // avant le lot 1, TP_TJM__c toujours en euros, sans que rien ne le dise explicitement côté donnée).
    private static final String SOURCE_CURRENCY = 'EUR';

    /**
     * Moteur pondéré (session 69, docs/67-cadrage) : remplace les 3 cercles par un calcul continu
     * de similarité sur métier/secteur/client. Chaque comparable dans le pool (filtré par pays et
     * optionnellement contractType) reçoit un score de similarité (0-1), et la médiane/p90 se
     * calculent en pondérant par ce score plutôt qu'en excluant les moins similaires.
     *
     * Historiquement, `seniorityLevelName` resserrait la requête (session 28). Ce rôle est obsolète
     * en session 69 — la séniorité n'intervient plus au calcul, seulement à la restitution
     * (segmentation). Le paramètre est conservé pour non-régression de l'API, mais rendu inerte ici.
     */
    /**
     * Rétrocompatible : pas de conversion, repères natifs EUR (comportement d'avant la session 24b).
     * Volontairement PAS `@AuraEnabled` : deux méthodes surchargées exposées à la frontière Aura
     * prêtent à ambiguïté de résolution côté plateforme (non documenté comme fiable pour LWC) — un
     * seul point d'entrée web (la surcharge à 4 arguments ci-dessous), les appelants Apex internes
     * historiques (tests notamment) gardent cette surcharge en appel Apex-à-Apex classique.
     */
    public static MarketReference getMarketReference(Id positionId, String contractType) {
        return getMarketReference(positionId, contractType, SOURCE_CURRENCY, null, null);
    }

    /** Apex-à-Apex uniquement (pas @AuraEnabled, cf. commentaire ci-dessus sur le point d'entrée
     * web unique) : conservée pour les appelants antérieurs à la séniorité (session 28). */
    public static MarketReference getMarketReference(
        Id positionId,
        String contractType,
        String targetCurrencyCode,
        Decimal rateToEur
    ) {
        return getMarketReference(positionId, contractType, targetCurrencyCode, rateToEur, null);
    }

    /**
     * targetCurrencyCode/rateToEur (session 24b) : le taux doit être celui déjà résolu par l'appelant
     * (AR_CurrencyRateService, ou le taux gelé AR_Currency_Rate_Applied__c pour un snapshot) — jamais
     * recalculé ici, cette classe reste une requête pure. Décision produit du 18/08/2026 (à confirmer
     * avec Matthieu, cf. docs/24-multidevise.md) : convertir plutôt qu'afficher en EUR avec mention —
     * lecture immédiate pour l'utilisateur, au prix d'une précision apparente que le taux du jour ne
     * porte pas vraiment ; compensé par `isConverted`/`medianTjmEurSource` (mention explicite de la
     * source) et par le déclassement de `confidenceLevel` ci-dessous.
     *
     * seniorityLevelName (session 28, obsolète en session 69) : conservé pour non-régression de l'API,
     * mais rendu inerte — la séniorité n'intervient plus au calcul de similarité. Elle n'intervient
     * qu'à la restitution (segmentation future, session 70). `null` reproduit exactement le
     * comportement d'avant cette session.
     */
    @AuraEnabled(cacheable=true)
    public static MarketReference getMarketReference(
        Id positionId,
        String contractType,
        String targetCurrencyCode,
        Decimal rateToEur,
        String seniorityLevelName
    ) {
        Id accountId = resolveAccountId(positionId);
        String targetCountry = resolveTargetCountry(positionId);
        cxsrec__cxsPosition__c targetPosition = resolveTargetPosition(positionId);
        Datetime wideSince = Datetime.now().addMonths(-MONTHS_WIDE);

        // Charger les poids une seule fois (réutilisés si pays absent + dans buildWeightedReference)
        AR_General_Setting__c settings = getSettings();
        Decimal weightMetier = settings.AR_Weight_Metier__c != null ? settings.AR_Weight_Metier__c : AR_GeneralSettingDefaults.WEIGHT_METIER;
        Decimal weightSecteur = settings.AR_Weight_Secteur__c != null ? settings.AR_Weight_Secteur__c : AR_GeneralSettingDefaults.WEIGHT_SECTEUR;
        Decimal weightClient = settings.AR_Weight_Client__c != null ? settings.AR_Weight_Client__c : AR_GeneralSettingDefaults.WEIGHT_CLIENT;

        // Filtre pays obligatoire (session 68) : pas de pays = pas de comparables.
        if (String.isBlank(targetCountry)) {
            return buildWeightedReference(
                new List<Decimal>(), new List<Decimal>(), new List<Decimal>(), new List<Decimal>(), new List<Decimal>(),
                'no_country_specified', Label.AR_Msg_CMP_NoCountry, wideSince, weightMetier, weightSecteur, weightClient);
        }

        // Moteur pondéré (session 69) : requête unique filtrée par pays + contractType (filtre dur),
        // puis calcul de similarité continu pour chaque comparable.
        ScoredComparablesResult scoredResult = queryAndScoreComparables(
            targetPosition, accountId, contractType, wideSince, targetCountry, settings);

        MarketReference ref = buildWeightedReference(
            scoredResult.tjms,
            scoredResult.scores,
            scoredResult.metierMatches,
            scoredResult.secteurMatches,
            scoredResult.clientMatches,
            'weighted_metier_secteur_client',
            Label.AR_Msg_CMP_WeightedCircle, wideSince,
            weightMetier, weightSecteur, weightClient);

        // Session 73 : exposer les résultats réels du moteur
        ref.resolvedCountry = targetCountry;
        ref.resolvedMetierLabel = scoredResult.resolvedMetierKeyword != null
            ? METIER_KEYWORDS.get(scoredResult.resolvedMetierKeyword)
            : null;
        ref.resolvedSecteurLabel = scoredResult.resolvedBusinessLine;

        return applyCurrencyConversion(ref, targetCurrencyCode, rateToEur);
    }

    /**
     * Restitution segmentée par séniorité (session 70) : retourne le même pool pondéré que
     * getMarketReference(), mais segmenté en 4 paliers (Junior/Confirmé/Senior/Expert) avec
     * quartiles indépendants par palier.
     *
     * Le pool n'est pas repondéré — c'est le même pool filtré par pays + contractType (+ poids
     * similarité identiques). La segmentation porte sur l'affichage, pas sur le calcul.
     *
     * Un comparable dont le Name ne contient aucun mot-clé reconnu n'entre dans aucun palier
     * (comportement cohérent avec « pas de fausse précision »). Le résultat contient toujours les
     * 4 paliers, même ceux sous le seuil de confiance (pour affichage « Expert — 1 affaire
     * seulement, repère indicatif »).
     */
    @AuraEnabled(cacheable=true)
    public static List<SeniorityTierReference> getMarketReferenceBySeniority(
        Id positionId,
        String contractType,
        String targetCurrencyCode,
        Decimal rateToEur
    ) {
        String targetCountry = resolveTargetCountry(positionId);

        // Filtre pays obligatoire (même que getMarketReference)
        if (String.isBlank(targetCountry)) {
            return new List<SeniorityTierReference>();
        }

        Id accountId = resolveAccountId(positionId);
        cxsrec__cxsPosition__c targetPosition = resolveTargetPosition(positionId);
        Datetime wideSince = Datetime.now().addMonths(-MONTHS_WIDE);

        // Récupérer le pool pondéré (identique à getMarketReference)
        ScoredComparablesResult scoredResult = queryAndScoreComparables(
            targetPosition, accountId, contractType, wideSince, targetCountry, getSettings());

        List<Decimal> tjms = scoredResult.tjms;
        List<Decimal> scores = scoredResult.scores;

        // Requête du pool pour accès aux Names (nécessaire pour extraction séniorité)
        List<cxsrec__cxsPosition__c> comparables = queryComparablesForSeniority(
            targetPosition, accountId, contractType, wideSince, targetCountry);

        // Grouper les TJM par palier de séniorité
        Map<String, List<Decimal>> tierToTjms = new Map<String, List<Decimal>>();
        Map<String, Integer> tierToComparableCount = new Map<String, Integer>();

        // Initialiser les 4 paliers
        for (String tier : new List<String>{ 'Junior', 'Confirmé', 'Senior', 'Expert' }) {
            tierToTjms.put(tier, new List<Decimal>());
            tierToComparableCount.put(tier, 0);
        }

        // Remplir les paliers (en parallèle avec le pool pondéré)
        for (Integer i = 0; i < comparables.size(); i++) {
            String tier = extractSeniorityTier(comparables[i].Name);
            if (tier != null) {
                tierToTjms.get(tier).add(tjms[i]);
                tierToComparableCount.put(tier, tierToComparableCount.get(tier) + 1);
            }
        }

        // Construire les 4 résultats (toujours présents)
        List<SeniorityTierReference> results = new List<SeniorityTierReference>();
        for (String tier : new List<String>{ 'Junior', 'Confirmé', 'Senior', 'Expert' }) {
            List<Decimal> tierTjms = tierToTjms.get(tier);
            SeniorityTierReference tierRef = new SeniorityTierReference();
            tierRef.tierLabel = tier;
            tierRef.comparableCount = tierToComparableCount.get(tier);
            tierRef.hasEnoughData = tierTjms.size() >= MEDIUM_CONFIDENCE_MIN;

            if (tierRef.hasEnoughData) {
                // Poids uniformes (1.0 pour chaque comparable du palier)
                List<Decimal> uniformWeights = new List<Decimal>();
                for (Integer i = 0; i < tierTjms.size(); i++) {
                    uniformWeights.add(1.0);
                }

                // Trier les TJM du palier pour les quartiles
                List<Decimal> sortedTierTjms = new List<Decimal>(tierTjms);
                sortedTierTjms.sort();

                tierRef.q1Tjm = weightedPercentile(sortedTierTjms, uniformWeights, 25);
                tierRef.medianTjm = weightedPercentile(sortedTierTjms, uniformWeights, 50);
                tierRef.q3Tjm = weightedPercentile(sortedTierTjms, uniformWeights, 75);
            }

            results.add(tierRef);
        }

        return results;
    }

    /**
     * Requête du pool complet pour extraction séniorité. Retourne les mêmes comparables que
     * queryAndScoreComparables() mais avec le champ Name (nécessaire pour la classification
     * des paliers).
     */
    private static List<cxsrec__cxsPosition__c> queryComparablesForSeniority(
        cxsrec__cxsPosition__c targetPosition,
        Id targetAccountId,
        String contractType,
        Datetime since,
        String targetCountry
    ) {
        String query = 'SELECT Id, TP_TJM__c, Name FROM cxsrec__cxsPosition__c' +
            ' WHERE cxsrec__Status__c = :WON_STATUS AND TP_TJM__c != null' +
            ' AND Id != :excludePositionId AND CreatedDate >= :since' +
            ' AND cxsrec__Country__c = :targetCountry';
        if (String.isNotBlank(contractType)) {
            query += ' AND cxsrec__Contract_type__c = :contractType';
        }
        query += ' ORDER BY TP_TJM__c ASC LIMIT :QUERY_LIMIT';

        Id excludePositionId = targetPosition != null ? targetPosition.Id : null;
        return Database.query(query);
    }

    /**
     * Extraire le palier de séniorité (Junior/Confirmé/Senior/Expert) depuis le Name du besoin,
     * par analyse textuelle (LIKE sur mots-clés prédéfinis). Retourne null si aucun mot-clé
     * de séniorité n'est trouvé — le comparable n'entre alors dans aucun palier.
     *
     * Session 70 : même approche approximative que extractMetierKeyword().
     */
    private static String extractSeniorityTier(String positionName) {
        if (String.isBlank(positionName)) {
            return null;
        }
        String nameLower = positionName.toLowerCase();

        // Tester les mots-clés en ordre de priorité (les plus longs en premier)
        for (String keyword : SENIORITY_KEYWORDS_ORDERED) {
            if (nameLower.contains(keyword)) {
                return SENIORITY_TIER_MAP.get(keyword);
            }
        }
        return null;
    }

    private static MarketReference applyCurrencyConversion(MarketReference ref, String targetCurrencyCode, Decimal rateToEur) {
        String effectiveTarget = String.isNotBlank(targetCurrencyCode) ? targetCurrencyCode : SOURCE_CURRENCY;
        Boolean shouldConvert = effectiveTarget != SOURCE_CURRENCY && rateToEur != null && rateToEur > 0;
        ref.currencyCode = shouldConvert ? effectiveTarget : SOURCE_CURRENCY;
        ref.isConverted = shouldConvert;
        ref.conversionRateApplied = shouldConvert ? rateToEur : null;
        if (!shouldConvert) {
            return ref;
        }
        ref.medianTjmEurSource = ref.medianTjm;
        ref.p90TjmEurSource = ref.p90Tjm;
        // AR_Currency_Rate__c.AR_Rate_To_EUR__c : "1 unité de la devise = ce montant en EUR" — donc
        // montant devise = montant EUR / taux (cf. docs/24-multidevise.md).
        ref.medianTjm = convertFromEur(ref.medianTjm, rateToEur);
        ref.p90Tjm = convertFromEur(ref.p90Tjm, rateToEur);
        ref.minTjm = convertFromEur(ref.minTjm, rateToEur);
        ref.maxTjm = convertFromEur(ref.maxTjm, rateToEur);
        // Un comparable converti est moins fiable qu'un comparable natif (le taux ajoute une
        // incertitude propre, en plus d'un historique GBP/MAD aujourd'hui inexistant) — l'indice de
        // confiance ne doit jamais annoncer une fiabilité qu'il n'a pas (atelier du 10/08/2026,
        // transparence des résultats). Seul le libellé de confiance est déclassé : la présence même
        // de la médiane/p90 reste gouvernée par l'effectif (hasEnoughData), inchangée par la devise.
        ref.confidenceLevel = downgradeConfidence(ref.confidenceLevel);
        return ref;
    }

    private static Decimal convertFromEur(Decimal eurValue, Decimal rateToEur) {
        return eurValue == null ? null : (eurValue / rateToEur).setScale(0, RoundingMode.HALF_UP);
    }

    private static String downgradeConfidence(String level) {
        if (level == 'high') {
            return 'medium';
        }
        return 'low';
    }

    /** Besoins déjà lus dans la transaction, par utilisateur (le partage `with sharing` dépend de l'utilisateur courant).
     * Une seule requête par besoin pour le compte, le pays et le besoin cible (291c : limite SOQL des chemins qui
     * recalculent plusieurs fois la même matrice). Seuls les besoins trouvés sont mémorisés. */
    private static Map<String, cxsrec__cxsPosition__c> positionCache = new Map<String, cxsrec__cxsPosition__c>();
    /** Secteur (Business Line) des comptes déjà lus dans la transaction. */
    private static Map<Id, String> businessLineCache = new Map<Id, String>();

    private static cxsrec__cxsPosition__c loadPosition(Id positionId) {
        if (positionId == null) {
            return null;
        }
        String key = UserInfo.getUserId() + '|' + positionId;
        if (positionCache.containsKey(key)) {
            return positionCache.get(key);
        }
        List<cxsrec__cxsPosition__c> positions = [
            SELECT Id, Name, cxsrec__Account__c, cxsrec__Country__c, AB_Need_details__r.AB_Account__c
            FROM cxsrec__cxsPosition__c
            WHERE Id = :positionId
            LIMIT 1
        ];
        if (positions.isEmpty()) {
            return null;
        }
        positionCache.put(key, positions[0]);
        return positions[0];
    }

    private static Id resolveAccountId(Id positionId) {
        cxsrec__cxsPosition__c position = loadPosition(positionId);
        if (position == null) {
            return null;
        }
        // Prefer the new chain (AB_Need_details__c → AB_Account__c), fall back to legacy field
        Id accountIdFromNewChain = position.AB_Need_details__r?.AB_Account__c;
        return accountIdFromNewChain != null ? accountIdFromNewChain : position.cxsrec__Account__c;
    }

    private static String resolveTargetCountry(Id positionId) {
        cxsrec__cxsPosition__c position = loadPosition(positionId);
        return position == null ? null : position.cxsrec__Country__c;
    }

    private static cxsrec__cxsPosition__c resolveTargetPosition(Id positionId) {
        return loadPosition(positionId);
    }

    /** Moteur pondéré (session 69) : requête unique filtrée par pays + contractType, puis calcul
     * de similarité continu pour chaque comparable basé sur métier/secteur/client.
     * Session 73 : retourne aussi les pourcentages de correspondance par critère et métadonnées résolues.
     * Session 81 : utilise le chaînage AB_Need_details__c.AB_Account__c comme source fiable de compte,
     * avec fallback au champ legacy cxsrec__Account__c pour couverture des 32% de besoins non liés.
     */
    private static ScoredComparablesResult queryAndScoreComparables(
        cxsrec__cxsPosition__c targetPosition,
        Id targetAccountId,
        String contractType,
        Datetime since,
        String targetCountry,
        AR_General_Setting__c settings
    ) {
        // Requête : tous les comparables filtrés par pays + contractType, triés par TJM pour
        // faciliter les calculs de médiane/percentile.
        // Session 81 : inclure le nouveau chaînage (AB_Need_details__r.AB_Account__c) pour relever le compte
        // avec la Business Line via la relation correcte. Garder le champ legacy cxsrec__Account__c comme fallback.
        String query = 'SELECT Id, TP_TJM__c, Name, cxsrec__Account__c, cxsrec__Account__r.TP_Business_Line__c,' +
            ' AB_Need_details__r.AB_Account__c, AB_Need_details__r.AB_Account__r.TP_Business_Line__c' +
            ' FROM cxsrec__cxsPosition__c' +
            ' WHERE cxsrec__Status__c = :WON_STATUS AND TP_TJM__c != null' +
            ' AND Id != :excludePositionId AND CreatedDate >= :since' +
            ' AND cxsrec__Country__c = :targetCountry';
        if (String.isNotBlank(contractType)) {
            query += ' AND cxsrec__Contract_type__c = :contractType';
        }
        query += ' ORDER BY TP_TJM__c ASC LIMIT :QUERY_LIMIT';

        Id excludePositionId = targetPosition != null ? targetPosition.Id : null;
        List<cxsrec__cxsPosition__c> comparables = Database.query(query);

        Decimal weightMetier = settings.AR_Weight_Metier__c != null ? settings.AR_Weight_Metier__c / 100 : (AR_GeneralSettingDefaults.WEIGHT_METIER / 100);
        Decimal weightSecteur = settings.AR_Weight_Secteur__c != null ? settings.AR_Weight_Secteur__c / 100 : (AR_GeneralSettingDefaults.WEIGHT_SECTEUR / 100);
        Decimal weightClient = settings.AR_Weight_Client__c != null ? settings.AR_Weight_Client__c / 100 : (AR_GeneralSettingDefaults.WEIGHT_CLIENT / 100);

        // Extraire le secteur cible (Business Line du compte du besoin cible) — utiliser le nouveau chaînage
        String targetBusinessLine = null;
        if (targetAccountId != null) {
            if (businessLineCache.containsKey(targetAccountId)) {
                targetBusinessLine = businessLineCache.get(targetAccountId);
            } else {
                List<Account> targetAccounts = [SELECT TP_Business_Line__c FROM Account WHERE Id = :targetAccountId LIMIT 1];
                if (!targetAccounts.isEmpty()) {
                    targetBusinessLine = targetAccounts[0].TP_Business_Line__c;
                    businessLineCache.put(targetAccountId, targetBusinessLine);
                }
            }
        }

        // Extraire le métier cible (keyword matching depuis le Name du besoin)
        String targetMetier = extractMetierKeyword(targetPosition != null ? targetPosition.Name : '');

        // Calculer un score de similarité pour chaque comparable + accumuler les pourcentages de correspondance
        List<Decimal> tjms = new List<Decimal>();
        List<Decimal> scores = new List<Decimal>();
        List<Decimal> metierMatches = new List<Decimal>();
        List<Decimal> secteurMatches = new List<Decimal>();
        List<Decimal> clientMatches = new List<Decimal>();

        for (cxsrec__cxsPosition__c comparable : comparables) {
            Decimal metierMatch = scoreMetierMatch(extractMetierKeyword(comparable.Name), targetMetier);

            // Session 81 : pour le secteur, préférer le compte résolu via le nouveau chaînage
            Id comparableAccountId = comparable.AB_Need_details__r?.AB_Account__c != null
                ? comparable.AB_Need_details__r.AB_Account__c
                : comparable.cxsrec__Account__c;
            String comparableBusinessLine = comparable.AB_Need_details__r?.AB_Account__r?.TP_Business_Line__c != null
                ? comparable.AB_Need_details__r.AB_Account__r.TP_Business_Line__c
                : comparable.cxsrec__Account__r?.TP_Business_Line__c;

            Decimal secteurMatch = scoreSecteurMatch(comparableBusinessLine, targetBusinessLine);
            Decimal clientMatch = scoreClientMatch(comparableAccountId, targetAccountId);

            Decimal score = (weightMetier * metierMatch) + (weightSecteur * secteurMatch) + (weightClient * clientMatch);

            tjms.add(comparable.TP_TJM__c);
            scores.add(score);
            metierMatches.add(metierMatch);
            secteurMatches.add(secteurMatch);
            clientMatches.add(clientMatch);
        }

        return new ScoredComparablesResult(
            tjms,
            scores,
            metierMatches,
            secteurMatches,
            clientMatches,
            targetMetier,
            targetBusinessLine
        );
    }

    private static AR_General_Setting__c getSettings() {
        List<AR_General_Setting__c> settings = [SELECT
            AR_Weight_Metier__c, AR_Weight_Secteur__c, AR_Weight_Client__c
            FROM AR_General_Setting__c WHERE Name = 'Default' LIMIT 1];
        if (settings.isEmpty()) {
            return AR_GeneralSettingDefaults.newDefaultRecord();
        }
        return settings[0];
    }

    /** Extraire un mot-clé métier depuis le Name du besoin (keyword matching, déterministe).
     * Retourne le mot-clé trouvé, ou null si aucun ne correspond.
     *
     * Session 69c : résolution déterministe en itérant METIER_KEYWORDS_ORDERED (ordre explicite)
     * plutôt que Map.keySet() (ordre non garanti). Les mots-clés les plus longs sont testés en
     * premier pour éviter des matches partiels (ex. tester "architect" avant "lead").
     */
    private static String extractMetierKeyword(String positionName) {
        if (String.isBlank(positionName)) {
            return null;
        }
        String nameLower = positionName.toLowerCase();
        for (String keyword : METIER_KEYWORDS_ORDERED) {
            if (nameLower.contains(keyword)) {
                return keyword;
            }
        }
        return null;
    }

    private static Decimal scoreMetierMatch(String comparableMetier, String targetMetier) {
        if (targetMetier == null && comparableMetier == null) return MATCH_SCORE_UNKNOWN;
        if (targetMetier == null || comparableMetier == null) return MATCH_SCORE_UNKNOWN;
        if (targetMetier.equalsIgnoreCase(comparableMetier)) return MATCH_SCORE_EXACT;
        return MATCH_SCORE_DIFFERENT;
    }

    private static Decimal scoreSecteurMatch(String comparableSecteur, String targetSecteur) {
        if (targetSecteur == null && comparableSecteur == null) return MATCH_SCORE_UNKNOWN;
        if (targetSecteur == null || comparableSecteur == null) return MATCH_SCORE_UNKNOWN;
        if (targetSecteur.equalsIgnoreCase(comparableSecteur)) return MATCH_SCORE_EXACT;
        return MATCH_SCORE_DIFFERENT;
    }

    private static Decimal scoreClientMatch(Id comparableAccountId, Id targetAccountId) {
        if (targetAccountId == null) return 0.00;
        if (comparableAccountId == null) return 0.00;
        if (targetAccountId == comparableAccountId) return MATCH_SCORE_EXACT;
        return MATCH_SCORE_DIFFERENT;
    }

    private static MarketReference buildWeightedReference(
        List<Decimal> tjms,
        List<Decimal> scores,
        List<Decimal> metierMatches,
        List<Decimal> secteurMatches,
        List<Decimal> clientMatches,
        String circleCode,
        String circleLabel,
        Datetime periodStart,
        Decimal weightMetierPercent,
        Decimal weightSecteurPercent,
        Decimal weightClientPercent
    ) {
        MarketReference ref = new MarketReference();
        ref.comparableCount = tjms.size();
        ref.circleCode = circleCode;
        ref.circleLabel = circleLabel;
        ref.periodStart = periodStart.date();
        ref.periodEnd = Date.today();
        ref.seniorityNarrowed = false;
        ref.weightMetierPercent = weightMetierPercent;
        ref.weightSecteurPercent = weightSecteurPercent;
        ref.weightClientPercent = weightClientPercent;
        ref.highConfidenceMin = HIGH_CONFIDENCE_MIN;
        ref.mediumConfidenceMin = MEDIUM_CONFIDENCE_MIN;

        // Effectif pondéré : somme des scores de similarité (un comparable avec score 1.0
        // pèse pour 1, un avec score 0.25 pèse pour 0.25, etc.)
        Decimal effectiveCount = 0;
        Decimal scoreSum = 0;
        Decimal metierMatchSum = 0;
        Decimal secteurMatchSum = 0;
        Decimal clientMatchSum = 0;
        List<Decimal> sortedTjms = new List<Decimal>();
        List<Decimal> sortedWeights = new List<Decimal>();
        Decimal minTjm = null;
        Decimal maxTjm = null;
        Integer scoredComparableCount = 0;

        for (Integer i = 0; i < tjms.size(); i++) {
            Decimal tjm = tjms[i];
            Decimal score = scores[i];
            if (score > 0) { // ne compter que les comparables avec un score > 0
                effectiveCount += score;
                scoreSum += score;
                metierMatchSum += metierMatches[i];
                secteurMatchSum += secteurMatches[i];
                clientMatchSum += clientMatches[i];
                scoredComparableCount++;
                sortedTjms.add(tjm);
                sortedWeights.add(score);
                if (minTjm == null || tjm < minTjm) minTjm = tjm;
                if (maxTjm == null || tjm > maxTjm) maxTjm = tjm;
            }
        }

        ref.hasEnoughData = effectiveCount >= MEDIUM_CONFIDENCE_MIN;
        ref.confidenceLevel = effectiveCount >= HIGH_CONFIDENCE_MIN ? 'high' : (ref.hasEnoughData ? 'medium' : 'low');
        ref.similarityScoreAvg = scoreSum > 0 ? (scoreSum / tjms.size()).setScale(2, RoundingMode.HALF_UP) : null;

        // Session 73 : pourcentages moyens de correspondance par critère (sur les comparables scorés)
        if (scoredComparableCount > 0) {
            ref.avgMetierMatchPercent = (metierMatchSum / scoredComparableCount * 100).setScale(0, RoundingMode.HALF_UP);
            ref.avgSecteurMatchPercent = (secteurMatchSum / scoredComparableCount * 100).setScale(0, RoundingMode.HALF_UP);
            ref.avgClientMatchPercent = (clientMatchSum / scoredComparableCount * 100).setScale(0, RoundingMode.HALF_UP);
        }

        // Session 73 : effectif pondéré exposé au front
        ref.weightedEffectiveCount = effectiveCount.setScale(1, RoundingMode.HALF_UP);

        if (ref.hasEnoughData) {
            ref.medianTjm = weightedPercentile(sortedTjms, sortedWeights, 50);
            ref.p90Tjm = weightedPercentile(sortedTjms, sortedWeights, 90);
            ref.minTjm = minTjm;
            ref.maxTjm = maxTjm;
        }
        return ref;
    }

    /**
     * Médiane/percentile pondérés sur des valeurs triées. Cumule les poids et retourne la valeur
     * au premier index où le poids cumulé atteint pct % du poids total.
     *
     * Session 69d : restaure le comportement de moyenne pour la médiane. Quand le poids cumulé
     * atteint **exactement** la cible (cas équivalent d'un effectif pair dans l'ancienne médiane()),
     * retourne la moyenne de cette valeur et de la suivante. Sinon, comportement plus-proche-rang.
     *
     * @param sortedValues Liste triée en ordre croissant
     * @param weights Poids associés (même longueur que sortedValues)
     * @param pct Percentile demandé (ex. 50 pour médiane, 90 pour p90)
     * @return La valeur au percentile demandé (moyenne si cumul atteint exactement la cible)
     */
    private static Decimal weightedPercentile(List<Decimal> sortedValues, List<Decimal> weights, Decimal pct) {
        if (sortedValues.isEmpty()) return null;
        if (sortedValues.size() != weights.size()) return null;

        Decimal totalWeight = 0;
        for (Decimal w : weights) {
            totalWeight += w;
        }

        if (totalWeight <= 0) return null;

        Decimal targetWeight = (totalWeight * pct) / 100;
        Decimal cumulativeWeight = 0;

        for (Integer i = 0; i < sortedValues.size(); i++) {
            cumulativeWeight += weights[i];
            if (cumulativeWeight >= targetWeight) {
                // Cas de moyenne : le poids cumulé atteint exactement la cible
                if (Math.abs(cumulativeWeight - targetWeight) < 0.0001 && i + 1 < sortedValues.size()) {
                    return (sortedValues[i] + sortedValues[i + 1]) / 2;
                }
                // Comportement normal : plus-proche-rang
                return sortedValues[i];
            }
        }

        // Fallback : retourner la dernière valeur
        return sortedValues[sortedValues.size() - 1];
    }
}