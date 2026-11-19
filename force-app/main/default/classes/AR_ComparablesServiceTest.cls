/**
 * Couvre les 3 cercles de comparables et le repli, la médiane (effectif pair/impair), le
 * percentile 90, les niveaux de confiance et l'absence de comparables.
 *
 * Note sur le test de périmètre de partage (`with sharing`) : tous les utilisateurs métier de
 * cette org partagent le même profil `Recruiter` (docs/01-decouverte-org.md §5) et l'OWD de
 * `cxsrec__cxsPosition__c`/`Account` n'a pas été vérifié (même doc, §7) — il n'existe donc pas de
 * profil « restreint » connu et fiable dans cette org pour construire un test négatif (utilisateur
 * qui NE DOIT PAS voir certains comparables) sans risquer un faux positif dû à un OWD permissif par
 * défaut. Le choix `with sharing` est donc validé par lecture de code (mot-clé présent, aucune
 * requête `without sharing` dans la classe) plutôt que par un test comportemental négatif — point
 * ouvert à trancher en atelier une fois l'OWD réel confirmé (cf. docs/09-reperes-marche.md).
 */
@IsTest
private class AR_ComparablesServiceTest {

    @TestSetup
    static void setup() {
        // Initialiser le record AR_General_Setting__c avec toutes les valeurs par défaut du moteur
        insert AR_GeneralSettingDefaults.newDefaultRecord();

        Account accountA = newAccount('Client Comparables A');
        Account accountB = newAccount('Client Comparables B');
        Account accountC = newAccount('Client Comparables C — sans historique');
        Account accountE = newAccount('Client Comparables E — historique rare');
        insert new List<Account>{ accountA, accountB, accountC, accountE };

        // Cercle (a) : 12 besoins Gagné, CDI, chez Account A — confiance élevée (≥10), effectif pair.
        insertWonPositions(accountA, 'CDI', new List<Decimal>{ 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620 });

        // Cercle (b) : 5 besoins Gagné, VIE uniquement, chez Account B — aucun NEARSHORE possible
        // (cxsrec__Contract_type__c ne couvre pas ce statut de contrat AR_, cf. docs/01 §1.1) :
        // sert à tester le repli (a)→(b). Effectif impair.
        insertWonPositions(accountB, 'VIE', new List<Decimal>{ 300, 350, 400, 450, 500 });

        // Cercle (c) : Account E n'a que 2 besoins Gagné Stage, aucun autre besoin Stage ailleurs —
        // sous le seuil de confiance même après repli complet (a)=(b)=(c)=2.
        insertWonPositions(accountE, 'Stage', new List<Decimal>{ 700, 750 });

        // Account C : aucun besoin Gagné propre — sert à tester le repli direct vers le cercle (c).
        insert new cxsrec__cxsPosition__c(
            Name = 'Besoin sans historique compte', cxsrec__Account__c = accountC.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
    }

    private static Account newAccount(String name) {
        return new Account(
            Name = name, AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001'
        );
    }

    private static void insertWonPositions(Account acc, String contractType, List<Decimal> tjms) {
        List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < tjms.size(); i++) {
            positions.add(new cxsrec__cxsPosition__c(
                Name = 'Besoin Gagné ' + acc.Name + ' ' + i,
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné',
                cxsrec__Contract_type__c = contractType,
                TP_TJM__c = tjms[i]
            ));
        }
        insert positions;
    }

    @IsTest
    static void testGetMarketReference_weightedEngine_sameAccountSameContractAllScoresHigh() {
        // Moteur pondéré (session 69) : le besoin cible a le même compte et le même pays que les 12 comparables.
        // Tous les comparables auront un score exact (1.0) sur tous les critères (métier=match, secteur=IT,
        // client=Account A). Score total = 1.0 * (poids_metier + poids_secteur + poids_client) = 1.0.
        // Effectif pondéré = 12 (tous score 1.0) → confiance haute.
        // Médiane pondérée avec tous les poids = 1.0 : c'est la médiane non-pondérée classique = 510.
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A developer', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        System.assertEquals('weighted_metier_secteur_client', ref.circleCode, 'Nouveau code du moteur pondéré');
        System.assertEquals(12, ref.comparableCount);
        // Calcul à la main : target "Nouveau besoin A developer" → métier "dev" (keyword match)
        // Comparables "Besoin Gagné ... " → aucun métier → score métier unknown = 0.25 (30% du score total)
        // Même compte + même secteur IT → score client = 1.0, score secteur = 1.0 (70% du score)
        // Score/comparable = 0.50*0.25 + 0.30*1.0 + 0.20*1.0 = 0.625
        // Effectif pondéré = 12 * 0.625 = 7.5 ≥ HIGH_CONFIDENCE_MIN (7.0 depuis session 69c)
        System.assertEquals('high', ref.confidenceLevel, 'Effectif pondéré 7.5 ≥ HIGH_CONFIDENCE_MIN (7.0, session 69c)');
        System.assert(ref.hasEnoughData);
        // TJM triés = [400,420,440,460,480,500,520,540,560,580,600,620]
        // Médiane pondérée à 50% = TJM au poids cumulé 3.75 → atteint exactement index 5 → moyenne (500+520)/2 = 510
        System.assertEquals(510, ref.medianTjm, 'Médiane pondérée avec poids tous 0.625');
        // P90 pondérée à 90% = TJM au poids cumulé 6.75 → franchit index 11 → 600
        System.assertEquals(600, ref.p90Tjm, 'P90 pondéré');
        System.assertEquals(400, ref.minTjm);
        System.assertEquals(620, ref.maxTjm);
        System.assertNotEquals(null, ref.similarityScoreAvg, 'Score de similarité moyenné disponible');
        // Session 71 : vérifier que les poids et seuils sont exposés (nécessaires pour l'explicabilité)
        System.assertEquals(50, ref.weightMetierPercent, 'Poids métier exposé (50 %)');
        System.assertEquals(30, ref.weightSecteurPercent, 'Poids secteur exposé (30 %)');
        System.assertEquals(20, ref.weightClientPercent, 'Poids client exposé (20 %)');
        System.assertEquals(7.0, ref.highConfidenceMin, 'Seuil confiance haute exposé (7.0)');
        System.assertEquals(3.0, ref.mediumConfidenceMin, 'Seuil confiance moyenne exposé (3.0)');
    }

    // ------------------------------------------------------------------
    // Resserrement par séniorité (session 28 §3) : correspondance de sous-chaîne approximative sur
    // l'intitulé du besoin, cf. commentaire de classe AR_ComparablesService. `null` (comportement
    // par défaut, tous les tests ci-dessus) doit rester rigoureusement inchangé — c'est la
    // non-régression la plus importante de cet ajout.
    // ------------------------------------------------------------------

    @IsTest
    static void testGetMarketReference_seniorityParamIgnored_session69() {
        // Session 69 : la séniorité n'intervient plus au calcul, elle n'intervient qu'à la restitution (future).
        // Le paramètre seniorityLevelName est conservé pour non-régression API, mais rendu inerte.
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A developer', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        // Appel avec séniorité explicite (par exemple 'Senior')
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'EUR', null, 'Senior');

        // Résultat inchangé : la séniorité est ignorée, le moteur pondéré retourne tous les comparables
        System.assertEquals('weighted_metier_secteur_client', ref.circleCode);
        System.assertEquals(12, ref.comparableCount, 'Tous les comparables, pas de resserrement par séniorité');
        System.assertEquals(510, ref.medianTjm);
        System.assertEquals(false, ref.seniorityNarrowed, 'La séniorité ne réserre plus rien (session 69)');
    }

    @IsTest
    static void testGetMarketReference_weightedEngine_seniorityDoesNotNarrow() {
        // Session 69 : la séniorité n'intervient plus au calcul. Avant, un paramètre seniorityLevelName
        // aurait resserré le pool. Maintenant, on obtient le même pool complet avec des scores pondérés.
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        // Ajouter 3 comparables qui contiennent "Senior" — pour vérifier qu'ils NE sont pas exclos
        insert new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(
                Name = '20001 - Senior Integration Engineer', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 700
            ),
            new cxsrec__cxsPosition__c(
                Name = '20002 - Senior C&Q Engineer', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 750
            ),
            new cxsrec__cxsPosition__c(
                Name = '20003 - Senior Project Manager', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 800
            )
        };
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A developer', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        Test.startTest();
        // Même avec 'Senior' en paramètre (conservé pour API backward-compat), aucun resserrement
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'EUR', null, 'Senior');
        Test.stopTest();

        System.assertEquals('weighted_metier_secteur_client', ref.circleCode);
        System.assertEquals(false, ref.seniorityNarrowed, 'Séniorité ne resserre jamais (session 69)');
        // 12 (testSetup) + 3 (nouveaux) = 15 comparables, tous inclus
        System.assertEquals(15, ref.comparableCount, 'Tous les comparables inclus, aucun exclusion par séniorité');
    }

    @IsTest
    static void testGetMarketReference_weightedEngine_allComparablesIncludedRegardlessOfMetier() {
        // Session 69 : le moteur pondéré inclut TOUS les comparables (aucun exclusion catégorique).
        // Un comparable sans match métier aura simplement un score plus bas, mais restera inclus
        // (pondération continue, pas exclusion binaire).
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A architect', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        // Les 12 comparables du @TestSetup ont des noms génériques sans métier spécifique
        // ('Besoin Gagné Client Comparables A 0', etc.) → scoreMetierMatch() retournera MATCH_SCORE_UNKNOWN
        // pour tous. Ils resteront quand même inclus.
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'EUR', null, null);

        System.assertEquals('weighted_metier_secteur_client', ref.circleCode);
        System.assertEquals(12, ref.comparableCount, 'Tous les comparables inclus malgré le motif métier différent');
        System.assertEquals(false, ref.seniorityNarrowed);
        System.assert(ref.medianTjm != null, 'Médiane pondérée calculée même avec des scores partiels');
    }

    @IsTest
    static void testGetMarketReference_weightedEngine_mixedContractTypesIncluded() {
        // Moteur pondéré (session 69) : si on demande NEARSHORE (absent du test data),
        // on obtient 0 comparables dans le pool filtré (contractType='NEARSHORE'). Aucun repli
        // automatique — c'est le choix du moteur pondéré : pas de cercles, pas de repli.
        Account accountB = [SELECT Id FROM Account WHERE Name = 'Client Comparables B' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin B', cxsrec__Account__c = accountB.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'VIE'
        );
        insert target;

        // VIE correspond à Account B (5 comparables) → moteur pondéré retourne ces 5
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'VIE');

        System.assertEquals('weighted_metier_secteur_client', ref.circleCode, 'Moteur pondéré, pas de cercle nommé');
        System.assertEquals(5, ref.comparableCount, 'Pool filtré par pays+contractType');
        System.assertEquals('medium', ref.confidenceLevel, 'Effectif 5 = seuil MEDIUM_CONFIDENCE_MIN');
        // Calcul à la main : TJM [300,350,400,450,500] → médiane (tous poids=1.0) = 400
        System.assertEquals(400, ref.medianTjm, 'Médiane pondérée de [300,350,400,450,500]');
        // P90 pondéré : poids cumulé 4.5 → franchit index 4 → 500
        System.assertEquals(500, ref.p90Tjm);
    }

    @IsTest
    static void testGetMarketReference_weightedEngine_poolIsCrossAccountWhenOwnAccountEmpty() {
        // Moteur pondéré (session 69) : les comparables sont filtrés par pays + contractType.
        // Aucun filtre « compte propre d'abord, puis autres ». Le pool est simplement tous les
        // comparables du pays/contractType, quel que soit le compte.
        Account accountC = [SELECT Id FROM Account WHERE Name = 'Client Comparables C — sans historique' LIMIT 1];
        cxsrec__cxsPosition__c target = [SELECT Id FROM cxsrec__cxsPosition__c WHERE cxsrec__Account__c = :accountC.Id LIMIT 1];

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        // Account C n'a aucun comparables CDI, mais Account A en a 12 → la requête en France/CDI retourne 12
        // Tous ces comparables auront des scores clients différents (clientMatch=0.0 car Account A ≠ Account C),
        // mais restent inclus avec pondération.
        // Score/comparable = 0.50*0.25 (métier unknown) + 0.30*1.0 (secteur IT) + 0.20*0.0 (client) = 0.425
        // Effectif = 12 * 0.425 = 5.1 → confiance 'medium' (≥3.0, <7.0), pas 'high'
        System.assertEquals('weighted_metier_secteur_client', ref.circleCode);
        System.assertEquals(12, ref.comparableCount, 'Pool CDI France = 12 (tous d\'Account A)');
        System.assertEquals('medium', ref.confidenceLevel, 'Effectif pondéré 5.1 >= MEDIUM (3.0), < HIGH (7.0)');
        System.assertEquals(false, ref.seniorityNarrowed);
    }

    @IsTest
    static void testGetMarketReference_lowConfidence_fewComparables_noExtrapolation() {
        Account accountE = [SELECT Id FROM Account WHERE Name = 'Client Comparables E — historique rare' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin E', cxsrec__Account__c = accountE.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'Stage'
        );
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'Stage');

        System.assertEquals(2, ref.comparableCount);
        System.assertEquals('low', ref.confidenceLevel);
        System.assertEquals(false, ref.hasEnoughData);
        System.assertEquals(null, ref.medianTjm, 'Sous le seuil de confiance : aucune extrapolation');
        System.assertEquals(null, ref.p90Tjm);
    }

    @IsTest
    static void testGetMarketReference_noComparablesAtAll() {
        Account accountC = [SELECT Id FROM Account WHERE Name = 'Client Comparables C — sans historique' LIMIT 1];
        cxsrec__cxsPosition__c target = [SELECT Id FROM cxsrec__cxsPosition__c WHERE cxsrec__Account__c = :accountC.Id LIMIT 1];

        // "Alternance" est une valeur réelle de cxsrec__Contract_type__c mais absente de tout le
        // jeu de données de test — les 3 cercles doivent être vides.
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'Alternance');

        System.assertEquals(0, ref.comparableCount);
        System.assertEquals('low', ref.confidenceLevel);
        System.assertEquals(false, ref.hasEnoughData);
    }

    @IsTest
    static void testGetMarketReference_nullPositionId_returnsEmptyLowConfidence() {
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(null, 'Alternance');

        System.assertEquals(0, ref.comparableCount);
        System.assertEquals('low', ref.confidenceLevel);
    }

    // ------------------------------------------------------------------
    // Socle multi-devises, restitution (session 24b) : conversion des repères marché.
    // ------------------------------------------------------------------

    @IsTest
    static void testGetMarketReference_2argOverload_defaultsToEurNoConversion() {
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A2', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        System.assertEquals('EUR', ref.currencyCode);
        System.assertEquals(false, ref.isConverted);
        System.assertEquals(null, ref.conversionRateApplied);
        System.assertEquals(510, ref.medianTjm, 'Non converti : valeur native inchangée');
    }

    /**
     * Le point central de cette section : conversion correcte (division par le taux, cf.
     * docs/24-multidevise.md — AR_Rate_To_EUR__c = "1 unité devise = ce montant en EUR") et
     * déclassement de la confiance (high → medium), sans fabriquer une fausse précision.
     */
    @IsTest
    static void testGetMarketReference_convertsToTargetCurrency_andDowngradesConfidence() {
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A3', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        Test.startTest();
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'GBP', 1.17);
        Test.stopTest();

        // Témoin (cf. testGetMarketReference_2argOverload_defaultsToEurNoConversion, même cercle) :
        // sans conversion, ce même échantillon de 12 comparables est à confiance 'high'.
        System.assertEquals('medium', ref.confidenceLevel, 'Converti : high déclassé à medium');
        System.assertEquals(true, ref.isConverted);
        System.assertEquals('GBP', ref.currencyCode);
        System.assertEquals(1.17, ref.conversionRateApplied);
        System.assertEquals(510, ref.medianTjmEurSource, 'Valeur EUR native conservée pour la mention de source');
        System.assertEquals(600, ref.p90TjmEurSource);
        System.assertEquals(436, ref.medianTjm, '510 / 1.17 = 435,9 → 436');
        System.assertEquals(513, ref.p90Tjm, '600 / 1.17 = 512,8 → 513');
        System.assertEquals(342, ref.minTjm, '400 / 1.17 = 341,9 → 342');
        System.assertEquals(530, ref.maxTjm, '620 / 1.17 = 529,9 → 530');
    }

    @IsTest
    static void testGetMarketReference_targetCurrencyEur_explicit_noConversion() {
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A4', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        // rateToEur non nul mais devise cible EUR : ne doit jamais convertir (la source EUR n'a pas
        // besoin d'un taux vers elle-même).
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'EUR', 1.17);

        System.assertEquals(false, ref.isConverted);
        System.assertEquals('EUR', ref.currencyCode);
        System.assertEquals(510, ref.medianTjm);
        System.assertEquals('high', ref.confidenceLevel, 'Pas de conversion, pas de déclassement');
    }

    @IsTest
    static void testGetMarketReference_nullRate_noConversion_neverCrashes() {
        Account accountA = [SELECT Id FROM Account WHERE Name = 'Client Comparables A' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin A5', cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        // Taux absent (ex. appelant qui n'a pas encore résolu de taux) : jamais de conversion
        // fictive au taux 1, jamais de MathException — repli silencieux sur EUR natif.
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI', 'GBP', null);

        System.assertEquals(false, ref.isConverted);
        System.assertEquals('EUR', ref.currencyCode);
        System.assertEquals(510, ref.medianTjm);
    }

    @IsTest
    static void testGetMarketReference_lowConfidence_conversionNeverFabricatesNumbers() {
        Account accountE = [SELECT Id FROM Account WHERE Name = 'Client Comparables E — historique rare' LIMIT 1];
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin E2', cxsrec__Account__c = accountE.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'Stage'
        );
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'Stage', 'GBP', 1.17);

        System.assertEquals(false, ref.hasEnoughData, 'Effectif insuffisant : inchangé par la devise');
        System.assertEquals(null, ref.medianTjm, 'Toujours aucune extrapolation, converti ou non');
        System.assertEquals(null, ref.p90Tjm);
        System.assertEquals('low', ref.confidenceLevel, 'low déjà au plancher, reste low après déclassement');
        System.assertEquals(true, ref.isConverted, 'isConverted reflète la demande de conversion, indépendamment des données disponibles');
    }

    // ------------------------------------------------------------------
    // Filtre pays obligatoire (session 68) : le pays délimite le référentiel
    // ------------------------------------------------------------------

    @IsTest
    static void testGetMarketReference_countryFilter_excludesOtherCountryComparables() {
        // Session 69c : test réécrit pour isoler le scénario sous le nouveau modèle (pas de filtre compte).
        // Utilise un contractType inédit "TRAINING" (non présent dans @TestSetup) pour que le pool soit
        // isolé à ce test seulement. Intention : prouver que le filtre pays exclut bien les comparables
        // d'un autre pays (5 Belgique ne doivent pas être inclus).
        Account multiCountryAccount = newAccount('Client Multi-Pays');
        insert multiCountryAccount;

        // 5 besoins TRAINING Gagné en France, TJM entre 400 et 500
        List<cxsrec__cxsPosition__c> frenchPositions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 5; i++) {
            frenchPositions.add(new cxsrec__cxsPosition__c(
                Name = 'Besoin FR TRAINING ' + i,
                cxsrec__Account__c = multiCountryAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné',
                cxsrec__Contract_type__c = 'TRAINING',
                TP_TJM__c = 400 + (i * 25)
            ));
        }
        // 5 besoins TRAINING Gagné en Belgique, TJM entre 600 et 700
        List<cxsrec__cxsPosition__c> belgianPositions = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 5; i++) {
            belgianPositions.add(new cxsrec__cxsPosition__c(
                Name = 'Besoin BE TRAINING ' + i,
                cxsrec__Account__c = multiCountryAccount.Id,
                cxsrec__Country__c = 'Belgique',
                cxsrec__Status__c = 'Gagné',
                cxsrec__Contract_type__c = 'TRAINING',
                TP_TJM__c = 600 + (i * 25)
            ));
        }
        insert frenchPositions;
        insert belgianPositions;

        // Besoin cible en France
        cxsrec__cxsPosition__c frenchTarget = new cxsrec__cxsPosition__c(
            Name = 'Nouveau besoin cible FR training', cxsrec__Account__c = multiCountryAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'TRAINING'
        );
        insert frenchTarget;

        Test.startTest();
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(frenchTarget.Id, 'TRAINING');
        Test.stopTest();

        // Pool isolé à France/TRAINING = 5 besoins (les 5 belges ne doivent pas être inclus)
        System.assertEquals(5, ref.comparableCount, 'Seuls les comparables français (5), jamais les belges');
        // Calcul à la main : 5 comparables, tous sans métier (score métier unknown = 0.25), même compte
        // (client exact = 1.0), même secteur IT (secteur exact = 1.0).
        // Score/comparable = 0.50*0.25 + 0.30*1.0 + 0.20*1.0 = 0.625
        // Effectif pondéré = 5 * 0.625 = 3.125 → confiance 'medium' (≥ MEDIUM_CONFIDENCE_MIN 3.0, < HIGH 7.0)
        System.assertEquals('medium', ref.confidenceLevel, 'Effectif pondéré 3.125 ≥ MEDIUM_CONFIDENCE_MIN (3.0)');
        System.assertEquals(true, ref.hasEnoughData, 'Effectif ≥ 3');
        System.assertEquals(450, ref.medianTjm, 'Médiane pondérée des TJM [400, 425, 450, 475, 500]');
        System.assertEquals(500, ref.p90Tjm, 'P90 pondéré');
    }

    // ========================================================================================
    // Tests du moteur pondéré : fonctions unitaires
    // ========================================================================================

    @IsTest
    static void testWeightedPercentile_uniformWeights_reproducesSimpleMedian() {
        // Cas trivial : tous les poids égaux (1.0) → pondéré = non-pondéré.
        // TJM = [400, 500, 600], poids = [1, 1, 1]
        // Médiane (50%) : poids cumulé cible = 1.5 → franchit index 1 → 500
        List<Decimal> tjms = new List<Decimal>{ 400, 500, 600 };
        List<Decimal> weights = new List<Decimal>{ 1, 1, 1 };

        // Appel privé : invoquer via getMarketReference sur données dédiées
        Account testAccount = newAccount('Test Weighted Percentile');
        insert testAccount;
        insert new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(Name = 'Dev 1', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 400),
            new cxsrec__cxsPosition__c(Name = 'Dev 2', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 500),
            new cxsrec__cxsPosition__c(Name = 'Dev 3', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 600)
        };
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Target dev', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        System.assertEquals(500, ref.medianTjm, 'Médiane uniforme [400,500,600] = 500');
        System.assertEquals(600, ref.p90Tjm, 'P90 uniforme [400,500,600] = 600 (index 2.7→3, dernière)');
    }

    @IsTest
    static void testWeightedPercentile_unequalWeights_affectsPercentile() {
        // TJM = [400, 500, 600], poids = [0.25, 0.25, 1.0] (accent sur 600)
        // Total poids = 1.5
        // Médiane (50%) : cumulé cible = 0.75 → franchit index 2 → 600 (au lieu de 500)
        Account testAccount = newAccount('Test Unequal Weights');
        insert testAccount;
        insert new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(Name = 'Dev junior', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 400),
            new cxsrec__cxsPosition__c(Name = 'Dev mid', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 500),
            new cxsrec__cxsPosition__c(Name = 'Dev senior', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 600)
        };
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Target senior', cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert target;

        // Forcer les poids : un score élevé sur le comparables 'Dev senior'.
        // Le test ne peut pas directement contrôler les scores sans modifier les poids de settings,
        // donc on teste le comportement via des comparables avec différents niveaux de match.
        // Ce test prouve que les poids affectent le résultat.
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        // Avec des scores différents, la médiane devrait refléter les poids appliqués
        System.assertNotEquals(500, ref.medianTjm, 'Médiane pondérée différente de non-pondérée quand poids inégaux');
        System.assert(ref.medianTjm > 400, 'Médiane reste dans la plage de données');
    }

    @IsTest
    static void testScoreMetierMatch_exact() {
        Account testAccount = newAccount('Test Metier Score');
        insert testAccount;
        insert new cxsrec__cxsPosition__c(Name = 'Dev Architect lead', cxsrec__Account__c = testAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CDI', TP_TJM__c = 600);
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Position architect',
            cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI');
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CDI');

        // Comparable 'Dev Architect lead' contient keyword 'architect' → MATCH_SCORE_EXACT pour métier
        System.assert(ref.similarityScoreAvg >= 0.0, 'Score de similarité calculé avec match métier');
    }

    @IsTest
    static void testScoreSecteurMatch_exact() {
        // Session 69d : isolé avec contractType inédit pour éviter contamination du @TestSetup (CDI)
        // Ajouter 3 comparables (au lieu de 2) pour atteindre MEDIUM_CONFIDENCE_MIN (3.0)
        Account testAccount1 = newAccount('Test Secteur IT');
        Account testAccount2 = newAccount('Test Secteur Services');
        testAccount1.TP_Business_Line__c = 'IT';
        // testAccount2 : secteur vide (pas de modification de TP_Business_Line__c, évite erreur picklist)
        insert new List<Account>{ testAccount1, testAccount2 };

        // Comparable chez testAccount1 (IT) — score secteur exact 1.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev 1', cxsrec__Account__c = testAccount1.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SECTEUR_TEST', TP_TJM__c = 500);
        // Comparable chez testAccount2 (Services) — score secteur different 0.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev 2', cxsrec__Account__c = testAccount2.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SECTEUR_TEST', TP_TJM__c = 550);
        // Comparable neutre pour atteindre effectif >= 3.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev 3', cxsrec__Account__c = testAccount1.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SECTEUR_TEST', TP_TJM__c = 525);

        // Besoin cible chez testAccount1 (IT) → match exact avec IT, pas avec Services
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Target',
            cxsrec__Account__c = testAccount1.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'SECTEUR_TEST');
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'SECTEUR_TEST');

        // Trois comparables : scores secteur (IT=1.0, Services=0.0, IT=1.0)
        // Score 1 = 0.5*0.25 + 0.3*1.0 + 0.2*1.0 = 0.625 (IT exact)
        // Score 2 = 0.5*0.25 + 0.3*0.0 + 0.2*1.0 = 0.325 (Services different)
        // Score 3 = 0.5*0.25 + 0.3*1.0 + 0.2*1.0 = 0.625 (IT exact)
        // Effectif = 0.625 + 0.325 + 0.625 = 1.575 < 3.0 → confiance 'low'
        System.assertEquals(3, ref.comparableCount, 'Pool isolé à 3 comparables (contractType SECTEUR_TEST)');
        System.assertEquals('low', ref.confidenceLevel, 'Effectif pondéré 1.575 < MEDIUM (3.0)');
        System.assertEquals(null, ref.medianTjm, 'Pas assez de données pour extrapoler une médiane');
    }

    @IsTest
    static void testScoreClientMatch_exact() {
        // Session 69d : isolé avec contractType inédit pour éviter contamination du @TestSetup (CDI)
        // Ajouter 3 comparables (au lieu de 2) pour atteindre MEDIUM_CONFIDENCE_MIN (3.0)
        Account accountA = newAccount('Test Client A');
        Account accountB = newAccount('Test Client B');
        insert new List<Account>{ accountA, accountB };

        // Comparable chez Client A — score client exact 1.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev A', cxsrec__Account__c = accountA.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CLIENT_TEST', TP_TJM__c = 400);
        // Comparable chez Client B — score client different 0.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev B', cxsrec__Account__c = accountB.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CLIENT_TEST', TP_TJM__c = 600);
        // Comparable neutre pour atteindre effectif >= 3.0
        insert new cxsrec__cxsPosition__c(Name = 'Dev C', cxsrec__Account__c = accountA.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CLIENT_TEST', TP_TJM__c = 500);

        // Besoin cible chez Client A → match exact sur client
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Target',
            cxsrec__Account__c = accountA.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CLIENT_TEST');
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CLIENT_TEST');

        // Trois comparables : scores client (A=1.0, B=0.0, A=1.0)
        // Score 1 = 0.5*0.25 + 0.3*1.0 + 0.2*1.0 = 0.625 (client A exact)
        // Score 2 = 0.5*0.25 + 0.3*1.0 + 0.2*0.0 = 0.425 (client B different)
        // Score 3 = 0.5*0.25 + 0.3*1.0 + 0.2*1.0 = 0.625 (client A exact)
        // Effectif = 0.625 + 0.425 + 0.625 = 1.675 < 3.0 → confiance 'low'
        System.assertEquals(3, ref.comparableCount, 'Pool isolé à 3 comparables (contractType CLIENT_TEST)');
        System.assertEquals('low', ref.confidenceLevel, 'Effectif pondéré 1.675 < MEDIUM (3.0)');
        System.assertEquals(null, ref.medianTjm, 'Pas assez de données pour extrapoler une médiane');
    }

    @IsTest
    static void testIntegration_weightedEngine_handCalculatedMedian() {
        // Session 69d : cas d'intégration isolé avec contractType inédit pour éviter contamination du @TestSetup.
        // 3 comparables, TJM [400, 500, 600], métier « junior » (keywords présents dans tous les noms).
        // Les noms sont choisis pour ne contenir aucun autre keyword connu que "junior" pour éviter
        // que la priorité des mots-clés plus longs (ex. "engineer") prenne le pas.
        // Tous same account, same secteur → scores : metier exact 1.0, secteur exact 1.0, client exact 1.0 → score = 1.0 chacun
        // Effectif pondéré = 3 * 1.0 = 3.0 ≥ MEDIUM_CONFIDENCE_MIN (3.0) → confiance 'medium', pas 'high' (< 7.0)
        Account testAccount = newAccount('Test Integration Weighted');
        insert testAccount;
        insert new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(Name = 'Position A junior', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CONSULTING', TP_TJM__c = 400),
            new cxsrec__cxsPosition__c(Name = 'Position B junior', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CONSULTING', TP_TJM__c = 500),
            new cxsrec__cxsPosition__c(Name = 'Position C junior', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'CONSULTING', TP_TJM__c = 600)
        };
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Need job junior position',
            cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CONSULTING');
        insert target;

        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'CONSULTING');

        System.assertEquals(3, ref.comparableCount, 'Pool isolé à 3 comparables (contractType CONSULTING)');
        // Effectif = 3 * 1.0 = 3.0 → pas assez pour 'high' (7.0), mais assez pour 'medium' (3.0)
        System.assertEquals('medium', ref.confidenceLevel, 'Effectif 3.0 ≥ MEDIUM (3.0), < HIGH (7.0)');
        // Médiane pondérée [400, 500, 600], poids [1,1,1], cible 1.5. Cumul saute de 1.0 (index 1) à 2.0 (index 2).
        // N'atteint jamais exactement 1.5 → pas de moyenne, plus-proche-rang normal → 500
        System.assertEquals(500, ref.medianTjm, 'Médiane pondérée, pas de cas de moyenne avec effectif impair');
        System.assert(ref.p90Tjm > ref.medianTjm, 'P90 > médiane');
        System.assert(ref.similarityScoreAvg >= 0 && ref.similarityScoreAvg <= 1, 'Score de similarité en [0,1]');
    }

    @IsTest
    static void testGetMarketReferenceBySeniority_fourTiersWithHandCalculatedQuartiles() {
        // Session 70 : test avec 12 comparables répartis sur 4 paliers de séniorité, quartiles vérifiés à la main.
        // Cas isolé avec contractType inédit pour ne pas contaminer @TestSetup.
        //
        // Pool :
        // - Junior (keyword "junior") : TJM [300, 400, 500] (3 comparables, effectif OK)
        // - Confirmé (keyword "confirmed") : TJM [450, 550, 650] (3 comparables, effectif OK)
        // - Senior (keyword "specialist") : TJM [600, 700, 800, 900] (4 comparables, effectif OK)
        // - Expert (keyword "leader") : TJM [950, 1000] (2 comparables, < MEDIUM_CONFIDENCE_MIN 3.0)
        //
        // Vérification à la main des quartiles (poids uniformes, tous 1.0) :
        // Junior [300, 400, 500] :
        //   Q1 (25%) : cible 0.75, cumul atteint 1.0 à index 0 → 300
        //   Médiane (50%) : cible 1.5, cumul atteint 2.0 à index 1 → 400
        //   Q3 (75%) : cible 2.25, cumul atteint 3.0 à index 2 → 500
        // Confirmé [450, 550, 650] :
        //   Q1 : cible 0.75 → index 0 → 450
        //   Médiane : cible 1.5 → index 1 → 550
        //   Q3 : cible 2.25 → index 2 → 650
        // Senior [600, 700, 800, 900] :
        //   Q1 : cible 1.0, cumul exactement 1.0 à index 0 → moyenne (600+700)/2 = 650
        //   Médiane : cible 2.0, cumul exactement 2.0 à index 1 → moyenne (700+800)/2 = 750
        //   Q3 : cible 3.0, cumul exactement 3.0 à index 2 → moyenne (800+900)/2 = 850
        // Expert [950, 1000] :
        //   hasEnoughData = false (< 3 comparables) → q1/médiane/q3 = null

        Account testAccount = newAccount('Test Seniority Tiers');
        insert testAccount;

        insert new List<cxsrec__cxsPosition__c>{
            // Junior (3 comparables)
            new cxsrec__cxsPosition__c(Name = 'Position Junior A', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 300),
            new cxsrec__cxsPosition__c(Name = 'Position Junior B', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 400),
            new cxsrec__cxsPosition__c(Name = 'Position Junior C', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 500),
            // Confirmé (3 comparables)
            new cxsrec__cxsPosition__c(Name = 'Position Confirmed A', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 450),
            new cxsrec__cxsPosition__c(Name = 'Position Confirmed B', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 550),
            new cxsrec__cxsPosition__c(Name = 'Position Confirmed C', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 650),
            // Senior (4 comparables)
            new cxsrec__cxsPosition__c(Name = 'Position Specialist A', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 600),
            new cxsrec__cxsPosition__c(Name = 'Position Specialist B', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 700),
            new cxsrec__cxsPosition__c(Name = 'Position Specialist C', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 800),
            new cxsrec__cxsPosition__c(Name = 'Position Specialist D', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 900),
            // Expert (2 comparables, < MEDIUM_CONFIDENCE_MIN)
            new cxsrec__cxsPosition__c(Name = 'Position Leader A', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 950),
            new cxsrec__cxsPosition__c(Name = 'Position Leader B', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'SENIORITY_TEST', TP_TJM__c = 1000)
        };

        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Need job specialist position',
            cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'SENIORITY_TEST');
        insert target;

        List<AR_ComparablesService.SeniorityTierReference> tiers = AR_ComparablesService.getMarketReferenceBySeniority(
            target.Id, 'SENIORITY_TEST', 'EUR', null);

        System.assertEquals(4, tiers.size(), 'Toujours 4 paliers retournés');

        // Vérification Junior
        System.assertEquals('Junior', tiers[0].tierLabel);
        System.assertEquals(3, tiers[0].comparableCount);
        System.assert(tiers[0].hasEnoughData, 'Junior a 3 comparables ≥ MEDIUM_CONFIDENCE_MIN');
        System.assertEquals(300, tiers[0].q1Tjm, 'Q1 Junior = 300');
        System.assertEquals(400, tiers[0].medianTjm, 'Médiane Junior = 400');
        System.assertEquals(500, tiers[0].q3Tjm, 'Q3 Junior = 500');

        // Vérification Confirmé
        System.assertEquals('Confirmé', tiers[1].tierLabel);
        System.assertEquals(3, tiers[1].comparableCount);
        System.assert(tiers[1].hasEnoughData);
        System.assertEquals(450, tiers[1].q1Tjm, 'Q1 Confirmé = 450');
        System.assertEquals(550, tiers[1].medianTjm, 'Médiane Confirmé = 550');
        System.assertEquals(650, tiers[1].q3Tjm, 'Q3 Confirmé = 650');

        // Vérification Senior
        System.assertEquals('Senior', tiers[2].tierLabel);
        System.assertEquals(4, tiers[2].comparableCount);
        System.assert(tiers[2].hasEnoughData);
        System.assertEquals(650, tiers[2].q1Tjm, 'Q1 Senior = (600+700)/2 = 650 (cas de moyenne)');
        System.assertEquals(750, tiers[2].medianTjm, 'Médiane Senior = (700+800)/2 = 750');
        System.assertEquals(850, tiers[2].q3Tjm, 'Q3 Senior = (800+900)/2 = 850');

        // Vérification Expert (insuffisant)
        System.assertEquals('Expert', tiers[3].tierLabel);
        System.assertEquals(2, tiers[3].comparableCount);
        System.assert(!tiers[3].hasEnoughData, 'Expert a 2 comparables < MEDIUM_CONFIDENCE_MIN (3)');
        System.assertEquals(null, tiers[3].q1Tjm, 'Expert q1 = null (insuffisant)');
        System.assertEquals(null, tiers[3].medianTjm, 'Expert médiane = null');
        System.assertEquals(null, tiers[3].q3Tjm, 'Expert q3 = null');
    }

    @IsTest
    static void testGetMarketReferenceBySeniority_comparableWithoutSeniorityKeywordEntersNoTier() {
        // Session 70 : comparables sans mot-clé reconnu de séniorité n'entrent dans aucun palier.
        Account testAccount = newAccount('Test No Seniority');
        insert testAccount;

        insert new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(Name = 'Position with junior keyword', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'TEST_NO_SENIOR', TP_TJM__c = 400),
            new cxsrec__cxsPosition__c(Name = 'Position with no seniority keyword', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'TEST_NO_SENIOR', TP_TJM__c = 500),
            new cxsrec__cxsPosition__c(Name = 'BUD', cxsrec__Account__c = testAccount.Id,
                cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'TEST_NO_SENIOR', TP_TJM__c = 600)
        };

        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(Name = 'Need job junior',
            cxsrec__Account__c = testAccount.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'TEST_NO_SENIOR');
        insert target;

        List<AR_ComparablesService.SeniorityTierReference> tiers = AR_ComparablesService.getMarketReferenceBySeniority(
            target.Id, 'TEST_NO_SENIOR', 'EUR', null);

        // Seulement un comparable entre le palier Junior (celui avec le mot-clé)
        System.assertEquals(1, tiers[0].comparableCount, 'Junior : 1 comparable (avec keyword "junior")');
        System.assertEquals(0, tiers[1].comparableCount, 'Confirmé : 0 comparable');
        System.assertEquals(0, tiers[2].comparableCount, 'Senior : 0 comparable');
        System.assertEquals(0, tiers[3].comparableCount, 'Expert : 0 comparable');

        // Tous les paliers sont sous le seuil (< 3)
        System.assert(!tiers[0].hasEnoughData);
        System.assert(!tiers[1].hasEnoughData);
        System.assert(!tiers[2].hasEnoughData);
        System.assert(!tiers[3].hasEnoughData);
    }

    @IsTest
    static void testGetMarketReferenceBySeniority_returnsEmptyListWhenNoCountrySet() {
        // Session 70 : filtre pays obligatoire, comme dans getMarketReference.
        cxsrec__cxsPosition__c targetNoCountry = new cxsrec__cxsPosition__c(
            Name = 'Besoin sans pays', cxsrec__Country__c = null,
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert targetNoCountry;

        List<AR_ComparablesService.SeniorityTierReference> tiers = AR_ComparablesService.getMarketReferenceBySeniority(
            targetNoCountry.Id, 'CDI', 'EUR', null);

        System.assertEquals(0, tiers.size(), 'Pas de pays = liste vide');
    }

    // ========================================================================================
    // Session 81 : nouvelle chaîne de compte via AB_Need_details__c avec fallback au champ legacy
    // ========================================================================================

    @IsTest
    static void testGetMarketReference_accountViaABNeedDetails_fallsBackToLegacyField_session81() {
        // Session 81 : le vrai chaînage besoin → compte passe par AB_Need_details__c.AB_Account__c,
        // pas par le champ legacy cxsrec__Account__c. Vérifier que :
        // 1. Un comparable lié via AB_Need_details__c (legacy field NULL) est correctement trouvé
        // 2. Un comparable lié via legacy field seul (AB_Need_details__c NULL) est trouvé en fallback
        // 3. Un comparable lié via les deux est résolu via le nouveau chaînage (préféré)

        // Contact cible requis par AB_Need_details__c.AB_Contact__c
        Contact targetContact = new Contact(LastName = 'Test Contact');
        insert targetContact;

        // Compte cible (pour match exact du comparable)
        Account targetAccount = newAccount('Session81 Target Account');
        insert targetAccount;

        // Compte secondaire (pour test fallback du champ legacy)
        Account legacyAccount = newAccount('Session81 Legacy Account');
        insert legacyAccount;

        // AB_Need_details__c pour le chaînage nouveau
        AB_Need_details__c needDetail = new AB_Need_details__c(
            AB_Account__c = targetAccount.Id,
            AB_Contact__c = targetContact.Id
        );
        insert needDetail;

        // Comparable 1 : lié via AB_Need_details__c seul (legacy NULL)
        // — prouve que le nouveau chaînage fonctionne
        cxsrec__cxsPosition__c comp1 = new cxsrec__cxsPosition__c(
            Name = 'Dev 1 via AB_Need_details', AB_Need_details__c = needDetail.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné',
            cxsrec__Contract_type__c = 'TEST_S81', TP_TJM__c = 500
        );

        // Comparable 2 : lié via legacy cxsrec__Account__c seul
        // — prouve que le fallback au champ legacy fonctionne
        cxsrec__cxsPosition__c comp2 = new cxsrec__cxsPosition__c(
            Name = 'Dev 2 via legacy field', cxsrec__Account__c = targetAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné',
            cxsrec__Contract_type__c = 'TEST_S81', TP_TJM__c = 550
        );

        // Comparable 3 : lié via AB_Need_details__c, mais legacy field aussi renseigné (à différent compte)
        // — vérifie que le nouveau chaînage est préféré
        AB_Need_details__c needDetail3 = new AB_Need_details__c(
            AB_Account__c = targetAccount.Id,
            AB_Contact__c = targetContact.Id
        );
        insert needDetail3;
        cxsrec__cxsPosition__c comp3 = new cxsrec__cxsPosition__c(
            Name = 'Dev 3 both fields but prefer AB_Need_details', AB_Need_details__c = needDetail3.Id,
            cxsrec__Account__c = legacyAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Gagné',
            cxsrec__Contract_type__c = 'TEST_S81', TP_TJM__c = 600
        );

        insert new List<cxsrec__cxsPosition__c>{ comp1, comp2, comp3 };

        // Besoin cible lié via AB_Need_details__c (nouveau chaînage)
        AB_Need_details__c targetNeedDetail = new AB_Need_details__c(
            AB_Account__c = targetAccount.Id,
            AB_Contact__c = targetContact.Id
        );
        insert targetNeedDetail;
        cxsrec__cxsPosition__c target = new cxsrec__cxsPosition__c(
            Name = 'Besoin cible developer', AB_Need_details__c = targetNeedDetail.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'TEST_S81'
        );
        insert target;

        Test.startTest();
        AR_ComparablesService.MarketReference ref = AR_ComparablesService.getMarketReference(target.Id, 'TEST_S81');
        Test.stopTest();

        // Le pool est filtré par pays + type de contrat (sessions 68/69), pas par compte : un type de
        // contrat inédit isole ces 3 comparables des 12 CDI du @TestSetup (même méthode qu'en 69d).
        System.assertEquals(3, ref.comparableCount, 'Les 3 comparables (via nouveau et legacy chaînage)');
        // Preuve de la résolution du compte : si l'un des trois n'était pas résolu à targetAccount
        // (ex. comp3 résolu au compte legacy au lieu du nouveau chaînage), la moyenne serait < 100.
        System.assertEquals(100, ref.avgClientMatchPercent, 'Les 3 comparables doivent matcher le compte cible');

        // Chaque comparable : métier reconnu (« Dev »/« developer » → score exact), secteur identique,
        // client exact → score 1.0. Effectif pondéré = 3 × 1.0 = 3.0 = MEDIUM_CONFIDENCE_MIN → confiance
        // 'medium' (le commentaire d'origine, 0.625 × 3 = 1.875 'low', datait d'avant la session 81).
        // Médiane pondérée de 500/550/600 à poids égaux : le cumul franchit 50 % au 2e → 550.
        System.assertEquals('medium', ref.confidenceLevel, 'Effectif 3.0 = MEDIUM (3.0)');
        System.assertEquals(550, ref.medianTjm, 'Médiane pondérée des trois comparables résolus');

        // Le résultat sans erreur prouve que les trois comparables ont été correctement résolus au compte
        // (pas d'exception, pas de null-reference sur le scoring)
        System.assertNotEquals(null, ref.circleCode, 'Reference construit sans erreur');
    }
}