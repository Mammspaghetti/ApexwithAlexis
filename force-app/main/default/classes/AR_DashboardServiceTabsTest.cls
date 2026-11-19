/**
 * Session 285 : axe d'analyse, Vue d'ensemble enrichie et onglets Dérogations, Rentabilité, Affaires gagnées.
 * Chaque test construit son jeu et calcule les valeurs attendues ; les valeurs d'axe sont des libellés de
 * périmètre propres au test (aucune dépendance aux données de la sandbox).
 */
@IsTest
private class AR_DashboardServiceTabsTest {
    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Tabs', AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001'
        );
        insert acc;
        insert new cxsrec__cxsPosition__c(
            Name = 'Besoin Tabs', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
    }

    // ---------- Vue d'ensemble : non-régression et ajouts ----------

    @IsTest
    static void testOverview_existingKeysUnchanged_andNewKeysAdded() {
        Id entityA = AR_TestPersona.entityRefId('Tabs Entité A');
        insert new List<AR_Price_Matrix__c>{
            matrix('Validée', entityA, 'PER-X', 30, 'superstar', 400, 'Client 1'),
            matrix('Validée par dérogation', entityA, 'PER-X', 22, 'low_margin', 350, 'Client 1'),
            matrix('Brouillon', entityA, null, null, null, null, 'Client 2')
        };
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(runAsManagerOverview('{}'));
        // Clés historiques : toujours présentes, mêmes valeurs.
        for (String key : new List<String>{ 'kpis', 'validationSplit', 'mc2Bands', 'segments', 'segmentsByAxis', 'reasons', 'monthly', 'clients', 'filterOptions' }) {
            System.assert(raw.containsKey(key), 'Clé historique conservée : ' + key);
        }
        AR_DashboardService.DashboardAnalytics a = analytics('{}');
        System.assertEquals(2, a.kpis.validatedCount);
        System.assertEquals(1, a.kpis.derogationValidatedCount);
        System.assertEquals(50.0, a.kpis.derogationValidatedPercent);
        System.assertEquals(375, a.kpis.averageTjmEur);
        System.assertEquals(26.0, a.kpis.averageMc2Percent);
        System.assertEquals(6, a.monthly.size());
        // Ajouts.
        System.assertEquals(3, a.kpis.simulationsCount, 'Trois lignées racines créées maintenant');
        System.assertEquals(0, a.kpis.wonCount);
        System.assertEquals(3, a.funnel.simulations);
        System.assertEquals(2, a.funnel.validated);
        System.assertEquals('entity', a.axis);
        // À axe entité, segmentsByAxis porte un total par agence ; la somme couvre les matrices à segment.
        Integer axisTotal = 0;
        for (AR_DashboardService.AxisSegments e : a.segmentsByAxis) {
            axisTotal += e.total;
        }
        System.assertEquals(2, axisTotal, 'Deux matrices validées ont un segment');
    }

    @IsTest
    static void testOverview_groupAxisIgnoresEntityAndCountryFilters() {
        AR_PTF_Entity_Referential__c a = new AR_PTF_Entity_Referential__c(Name = 'Tabs Agence 1', AR_Active__c = true, AR_Country__c = 'France');
        AR_PTF_Entity_Referential__c b = new AR_PTF_Entity_Referential__c(Name = 'Tabs Agence 2', AR_Active__c = true, AR_Country__c = 'Maroc');
        insert new List<AR_PTF_Entity_Referential__c>{ a, b };
        insert new List<AR_Price_Matrix__c>{
            matrix('Validée', a.Id, 'PER-X', 30, 'superstar', 400, 'Client 1'),
            matrix('Validée', b.Id, 'PER-X', 26, 'recommended', 400, 'Client 2')
        };
        System.assertEquals(1, analytics('{"entityId":"' + a.Id + '","axis":"entity"}').kpis.validatedCount);
        AR_DashboardService.DashboardAnalytics group1 = analytics('{"entityId":"' + a.Id + '","entityCountry":"France","axis":"group"}');
        System.assertEquals(2, group1.kpis.validatedCount, 'La vue Groupe ignore Entité et Pays');
        System.assertEquals(1, group1.segmentsByAxis.size());
        System.assertEquals('House of ABY', group1.segmentsByAxis[0].entityName);
        System.assertEquals(2, group1.segmentsByAxis[0].total);
    }

    @IsTest
    static void testOverview_unknownAxis_throwsReadableMessage() {
        try {
            System.runAs(AR_TestPersona.manager()) {
                AR_DashboardService.getDashboardAnalytics('{"axis":"inconnu"}');
            }
            System.assert(false, 'Un axe inconnu doit être refusé');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('illisibles'), e.getMessage());
        }
    }

    @IsTest
    static void testOverview_axisValuesCappedAtTenPlusOthers() {
        List<AR_Price_Matrix__c> rows = new List<AR_Price_Matrix__c>();
        for (Integer i = 0; i < 12; i++) {
            // 12 périmètres ; PER-00 compte le plus de matrices pour fixer l'ordre.
            rows.add(matrix('Validée', null, 'PER-' + String.valueOf(100 + i).right(2), 30, 'superstar', 400, 'C' + i));
        }
        rows.add(matrix('Validée', null, 'PER-00', 30, 'superstar', 400, 'C-extra'));
        insert rows;
        AR_DashboardService.DashboardAnalytics a = analytics('{"axis":"perimeter"}');
        System.assertEquals(11, a.segmentsByAxis.size(), 'Dix valeurs + « Autres »');
        System.assert(a.segmentsByAxis[10].others, 'La dernière ligne regroupe le reste');
        System.assertEquals('Autres', a.segmentsByAxis[10].entityName);
        System.assertEquals(0, a.segmentsByAxis[0].entityName.compareTo('PER-00'), 'Tri par volume');
    }

    // ---------- Simulations, gagnées, onglet Affaires gagnées ----------

    @IsTest
    static void testWonTab_lineageCountedOnce_purgedRootsCounted_levelsAndRates() {
        // Lignée A : V1 gagnée au Prix 2, V2 validée plus tard — une simulation, une validée, une gagnée.
        AR_Price_Matrix__c v1 = matrix('Validée', null, 'PER-A', 30, 'superstar', 400, 'Client A');
        v1.AR_Nego_Price_2__c = 380;
        v1.AR_Nego_Price_3__c = 360;
        v1.AR_Won__c = true;
        v1.AR_Won_Date__c = Date.today();
        v1.AR_Signed_TJM__c = 380;
        v1.AR_Signed_Price_Level__c = 'P2';
        v1.AR_Validated_At__c = System.now().addDays(-2);
        insert v1;
        AR_Price_Matrix__c v2 = matrix('Validée', null, 'PER-A', 28, 'recommended', 410, 'Client A');
        v2.AR_Root_Matrix__c = v1.Id;
        v2.AR_Validated_At__c = System.now().addDays(-1);
        insert v2;
        // Lignée B : racine validée par dérogation, gagnée au Prix 1.
        AR_Price_Matrix__c b = matrix('Validée par dérogation', null, 'PER-B', 22, 'low_margin', 300, 'Client B');
        b.AR_Won__c = true;
        b.AR_Won_Date__c = Date.today();
        b.AR_Signed_TJM__c = 300;
        b.AR_Signed_Price_Level__c = 'P1';
        insert b;
        // Journal de purge : deux racines purgées de PER-A comptent, une non racine non.
        insert new List<AR_Purge_Log__c>{
            purgeLog('PER-A', true), purgeLog('PER-A', true), purgeLog('PER-A', false), purgeLog('PER-B', true)
        };

        AR_DashboardService.WonTab tab = (AR_DashboardService.WonTab) JSON.deserialize(tab('won', '{"axis":"perimeter"}'), AR_DashboardService.WonTab.class);
        AR_DashboardService.TransformRow rowA = transformRow(tab, 'PER-A');
        AR_DashboardService.TransformRow rowB = transformRow(tab, 'PER-B');
        System.assertEquals(3, rowA.simulated, 'Racine A + 2 purgées racine ; V2 et la purgée non racine ne comptent pas');
        System.assertEquals(1, rowA.validated, 'La lignée A est comptée une fois (dernière version)');
        System.assertEquals(1, rowA.won);
        System.assertEquals(33.3, rowA.simulatedToWonPercent, '1 gagnée / 3 simulées');
        System.assertEquals(null, rowA.validatedToWonPercent, 'Moins de 3 validées : valeur nulle');
        System.assertEquals(1, rowA.priceTwo);
        System.assertEquals(2, rowB.simulated, 'Racine B + 1 purgée');
        System.assertEquals(1, rowB.priceOne);
        System.assertEquals(null, rowB.simulatedToWonPercent, 'Moins de 3 simulées : valeur nulle');
        System.assertEquals(2, tab.kpis.wonCount);
        System.assertEquals(2, tab.kpis.validatedCount);
        System.assertEquals(null, tab.kpis.priceOnePercent, 'Moins de 3 gagnées : valeur nulle');
        System.assertEquals(2, tab.total.won);
        // Mois : tous les relevés tombent dans le mois courant, moyenne = total / nombre de mois.
        System.assert(tab.months.size() >= 1);
        AR_DashboardService.MonthlyAxisRow monthA;
        for (AR_DashboardService.MonthlyAxisRow r : tab.simulationsByMonth) {
            if (r.label == 'PER-A') {
                monthA = r;
            }
        }
        System.assertNotEquals(null, monthA);
        System.assertEquals(3, monthA.total);
        System.assertEquals((Decimal.valueOf(3) / tab.months.size()).setScale(1, RoundingMode.HALF_UP), monthA.monthlyAverage);
        System.assert(tab.pending.size() <= 20);
    }

    @IsTest
    static void testWonTab_levelsDistribution_withThreeWonDeals() {
        List<AR_Price_Matrix__c> rows = new List<AR_Price_Matrix__c>();
        for (String level : new List<String>{ 'P1', 'P1', 'Hors grille' }) {
            AR_Price_Matrix__c m = matrix('Validée', null, 'PER-L', 30, 'superstar', 400, 'Client ' + rows.size());
            m.AR_Won__c = true;
            m.AR_Won_Date__c = Date.today();
            m.AR_Signed_Price_Level__c = level;
            rows.add(m);
        }
        insert rows;
        AR_DashboardService.WonTab tab = (AR_DashboardService.WonTab) JSON.deserialize(tab('won', '{"axis":"perimeter"}'), AR_DashboardService.WonTab.class);
        System.assertEquals(66.7, tab.kpis.priceOnePercent, '2 prix 1 sur 3 gagnées');
        Map<String, Integer> byLevel = new Map<String, Integer>();
        for (AR_DashboardService.LevelShare s : tab.levels) {
            byLevel.put(s.level, s.count);
        }
        System.assertEquals(2, byLevel.get('P1'));
        System.assertEquals(1, byLevel.get('Hors grille'));
        System.assertEquals(0, byLevel.get('P2'));
    }

    // ---------- Onglet Dérogations ----------

    @IsTest
    static void testDerogationsTab_kpisMonthlyValidatorsClientsReasons() {
        User v1 = AR_TestPersona.valideur();
        User v2 = AR_TestPersona.valideur();
        AR_Price_Matrix__c ma = matrix('Validée par dérogation', null, 'PER-A', 22, 'low_margin', 300, 'Client D');
        AR_Price_Matrix__c mb = matrix('Validée', null, 'PER-B', 30, 'superstar', 300, 'Client E');
        insert new List<AR_Price_Matrix__c>{ ma, mb };
        Datetime requested = System.now().addDays(-7);
        List<AR_Derogation__c> derogations = new List<AR_Derogation__c>{
            derogation(ma.Id, 'Acceptée', requested, requested.addDays(2), v1.Id),
            derogation(ma.Id, 'Acceptée', requested, requested.addDays(4), v1.Id),
            derogation(ma.Id, 'Refusée', requested, requested.addDays(6), v1.Id),
            derogation(mb.Id, 'En attente', requested, null, null)
        };
        derogations[3].AR_Selected_Validator__c = v2.Id;
        insert derogations;
        AR_Reason__c r1 = new AR_Reason__c(Name = 'Motif Tabs 1', AR_Active__c = true);
        AR_Reason__c r2 = new AR_Reason__c(Name = 'Motif Tabs 2', AR_Active__c = true);
        insert new List<AR_Reason__c>{ r1, r2 };
        insert new List<AR_Reason_Selection__c>{
            new AR_Reason_Selection__c(AR_Derogation__c = derogations[0].Id, AR_Reason__c = r1.Id),
            new AR_Reason_Selection__c(AR_Derogation__c = derogations[1].Id, AR_Reason__c = r1.Id),
            new AR_Reason_Selection__c(AR_Derogation__c = derogations[2].Id, AR_Reason__c = r2.Id),
            new AR_Reason_Selection__c(AR_Derogation__c = derogations[3].Id, AR_Reason__c = r2.Id)
        };

        AR_DashboardService.DerogationsTab t = (AR_DashboardService.DerogationsTab) JSON.deserialize(tab('derogations', '{"axis":"perimeter"}'), AR_DashboardService.DerogationsTab.class);
        System.assertEquals(4, t.kpis.requestedCount);
        System.assertEquals(2, t.kpis.acceptedCount);
        System.assertEquals(1, t.kpis.refusedCount);
        System.assertEquals(1, t.kpis.pendingCount);
        System.assertEquals(66.7, t.kpis.acceptedPercent, 'Acceptées ÷ décidées : 2/3');
        System.assertEquals(4.0, t.kpis.medianDelayDays, 'Médiane de 2, 4 et 6 jours');
        System.assertEquals(50.0, t.kpis.derogationRatePercent, '1 validée par dérogation sur 2 validées');
        // Série mensuelle : les quatre demandes tombent dans un seul mois (ou deux à cheval) ; le total y est.
        Integer inSeries = 0;
        for (AR_DashboardService.DerogationMonth m : t.monthly) {
            inSeries += m.accepted + m.refused + m.pending;
        }
        System.assertEquals(4, inSeries);
        // Taux par axe : PER-A 1/1 validée par dérogation (échantillon < 3 → nul), PER-B 0/1.
        for (AR_DashboardService.DerogationAxisRate r : t.rateByAxis) {
            System.assertEquals(null, r.ratePercent, 'Échantillon < 3 pour ' + r.label);
        }
        // Valideurs : v1 a 3 reçues dont 3 décidées (taux de refus 33.3, délai médian 4.0), v2 une en attente.
        System.assertEquals(v1.Id, t.validators[0].validatorId, 'Triés par volume');
        System.assertEquals(3, t.validators[0].received);
        System.assertEquals(33.3, t.validators[0].refusalPercent);
        System.assertEquals(4.0, t.validators[0].medianDelayDays);
        System.assertEquals(1, t.validators[1].received);
        System.assertEquals(1, t.validators[1].pending);
        System.assertEquals(null, t.validators[1].refusalPercent);
        // Clients : Client D 3 dérogations (1 validée → taux nul sous 2 matrices), motif principal « Motif Tabs 1 ».
        System.assertEquals('Client D', t.topClients[0].accountName);
        System.assertEquals(3, t.topClients[0].derogationCount);
        System.assertEquals(1, t.topClients[0].validatedCount);
        System.assertEquals(null, t.topClients[0].ratePercent);
        System.assertEquals('Motif Tabs 1', t.topClients[0].mainReason);
        // Motifs : sans filtre r1 et r2 ont 2 occurrences chacun ; filtré sur PER-A, r1 devient premier.
        System.assertEquals(4, t.reasons.selectionCount);
        AR_DashboardService.DerogationsTab filtered = (AR_DashboardService.DerogationsTab) JSON.deserialize(
            tab('derogations', '{"axis":"perimeter","motifAxisValue":"PER-A"}'), AR_DashboardService.DerogationsTab.class
        );
        System.assertEquals(3, filtered.reasons.derogationCount);
        System.assertEquals('Motif Tabs 1', filtered.reasons.top[0].reasonName);
        System.assertEquals(2, filtered.reasons.top[0].count);
        System.assert(filtered.motifAxisOptions.size() >= 2, 'Les pastilles proposent les valeurs d\'axe');
    }

    // ---------- Onglet Rentabilité : postes de coût ----------

    @IsTest
    static void testCosts_postsSumToEngineTotalMinusCjm_andExplicitValues() {
        AR_Price_Matrix__c m = costMatrix('CDI');
        insert m;
        AR_Price_Matrix__c loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ m.Id }).get(m.Id);
        Map<String, Decimal> posts = AR_DashboardCosts.postsPerDay(loaded);
        AR_PricingCalculator.Context ctx = AR_PricingMatrixService.costContextOf(loaded);
        Decimal expected = AR_PricingCalculator.calcTotalDailyCost(ctx) - AR_PricingCalculator.calcCJM(ctx);
        Decimal sum = 0;
        for (String post : AR_DashboardCosts.POSTS) {
            sum += posts.get(post);
        }
        System.assertEquals(expected.setScale(8, RoundingMode.HALF_UP), sum.setScale(8, RoundingMode.HALF_UP), 'La somme des 9 postes boucle sur le moteur');
        System.assertEquals(20, posts.get('lodging'));
        System.assertEquals(10, posts.get('fuel'));
        System.assertEquals(15, posts.get('meals'));
        System.assertEquals(6, posts.get('training'), '600 € par mission ÷ 100 jours');
        System.assertEquals(2, posts.get('ofii'), '436 € par an ÷ 218 jours');
        System.assertEquals((Decimal.valueOf(2) + Decimal.valueOf(30 * 12) / 218).setScale(8, RoundingMode.HALF_UP), posts.get('it_phone').setScale(8, RoundingMode.HALF_UP), 'PC 2 €/jour + téléphone 30 €/mois');
        System.assertEquals((Decimal.valueOf(2) * AR_PricingCalculator.calcCJM(ctx) / 100).setScale(8, RoundingMode.HALF_UP), posts.get('gratuity').setScale(8, RoundingMode.HALF_UP), 'Jours offerts : 2 jours × CJM ÷ 100 jours, calculés explicitement');
        System.assertEquals((Decimal.valueOf(5) + Decimal.valueOf(20 * 12) / 218 + Decimal.valueOf(109) / 100).setScale(8, RoundingMode.HALF_UP), posts.get('other').setScale(8, RoundingMode.HALF_UP), 'Autres : OM autre 5 + mensuel autre 20 × 12 ÷ 218 + mission autre 109 ÷ 100');
        System.assertEquals(2.18, posts.get('epi').setScale(2, RoundingMode.HALF_UP), '218 € par mission ÷ 100 jours');
    }

    @IsTest
    static void testCosts_feePeriodsSmoothingPerComponent_andIndependantOnlyGratuity() {
        AR_Price_Matrix__c m = costMatrix('CDI');
        // Période 1 : 100 jours − 40 = 60 jours aux frais de base ; 40 jours à IK 20 / repas 25 / logement 0 / autre 0.
        m.AR_Fee_Periods__c = '[{"days":40,"feeIk":20,"feeMeals":25,"feeLodging":0,"feeOmOther":0}]';
        AR_Price_Matrix__c indep = costMatrix('INDEP');
        indep.AR_CJM_Before_Markup__c = 400;
        indep.AR_Markup_Applied__c = 50;
        insert new List<AR_Price_Matrix__c>{ m, indep };
        Map<Id, AR_Price_Matrix__c> loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ m.Id, indep.Id });
        Map<String, Decimal> posts = AR_DashboardCosts.postsPerDay(loaded.get(m.Id));
        System.assertEquals((Decimal.valueOf(10 * 60 + 20 * 40) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('fuel').setScale(6, RoundingMode.HALF_UP), 'IK lissées : (60×10 + 40×20) ÷ 100');
        System.assertEquals((Decimal.valueOf(15 * 60 + 25 * 40) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('meals').setScale(6, RoundingMode.HALF_UP));
        System.assertEquals((Decimal.valueOf(20 * 60) / 100).setScale(6, RoundingMode.HALF_UP), posts.get('lodging').setScale(6, RoundingMode.HALF_UP));
        // INDEP : le moteur ignore les frais, seule la gratuité (2 jours × CJM ÷ 100 jours) compte, classée en « Jours offerts ».
        Map<String, Decimal> indepPosts = AR_DashboardCosts.postsPerDay(loaded.get(indep.Id));
        System.assertEquals(0, indepPosts.get('fuel'));
        System.assertEquals(0, indepPosts.get('lodging'));
        System.assertEquals((Decimal.valueOf(2) * 450 / 100).setScale(6, RoundingMode.HALF_UP), indepPosts.get('gratuity').setScale(6, RoundingMode.HALF_UP));
    }

    @IsTest
    static void testProfitabilityTab_breakdownPointsAxisRowsAndClients() {
        List<AR_Price_Matrix__c> rows = new List<AR_Price_Matrix__c>();
        for (Integer i = 0; i < 3; i++) {
            AR_Price_Matrix__c m = costMatrix('CDI');
            m.AR_Status__c = 'Validée';
            m.AR_Perimeter__c = 'PER-P';
            m.AR_Account_Name__c = 'Client P' + Math.mod(i, 2); // P0 (2 matrices), P1 (1)
            m.AR_Proposed_TJM__c = 500;
            m.AR_TJM_EUR_Equivalent__c = 500;
            m.AR_MC2_Percent__c = 18 + i * 2; // 18, 20, 22
            m.AR_Corridor_Segment__c = i == 0 ? 'below_floor' : 'low_margin';
            m.AR_Target_Percent_Applied__c = 25 + i; // 25, 26, 27
            m.AR_Floor_Percent_Applied__c = 20;
            m.AR_Ideal_Percent_Applied__c = 30;
            m.AR_Corridor_Source__c = i == 2 ? 'ACCOUNT' : 'DEFAULT';
            m.AR_Validated_At__c = System.now();
            rows.add(m);
        }
        insert rows;
        AR_DashboardService.ProfitabilityTab t = (AR_DashboardService.ProfitabilityTab) JSON.deserialize(tab('profitability', '{"axis":"perimeter"}'), AR_DashboardService.ProfitabilityTab.class);
        // Les 3 matrices ont les mêmes frais : la décomposition du groupe est celle d'une matrice.
        AR_Price_Matrix__c loaded = AR_DashboardCosts.loadForCosts(new Set<Id>{ rows[0].Id }).get(rows[0].Id);
        Map<String, Decimal> one = AR_DashboardCosts.postsPerDay(loaded);
        Decimal total = 0;
        for (String post : AR_DashboardCosts.POSTS) {
            total += one.get(post);
        }
        System.assertEquals(3, t.costSampleSize);
        System.assertEquals(total.setScale(2, RoundingMode.HALF_UP), t.groupRow.totalPerDay);
        System.assertEquals(total.setScale(2, RoundingMode.HALF_UP), t.kpis.costsOfSalesPerDay);
        System.assertEquals(1, t.kpis.belowFloorCount);
        System.assertEquals(20.0, t.kpis.averageMc2Percent, '(18+20+22)/3');
        // Premier poste : celui dont le montant par jour est le plus grand.
        String expectedTop;
        Decimal expectedMax = -1;
        for (String post : AR_DashboardCosts.POSTS) {
            if (one.get(post) > expectedMax) {
                expectedMax = one.get(post);
                expectedTop = post;
            }
        }
        System.assertEquals(expectedTop, t.kpis.topPost);
        // Points de MC2 : Σ(frais × jours) ÷ Σ(TJM × jours) × 100 = frais/jour ÷ 500 × 100 pour des matrices identiques.
        Decimal topPoints = (one.get(t.mc2PointsByPost[0].post) * 100 / 500).setScale(1, RoundingMode.HALF_UP);
        System.assertEquals(topPoints, t.mc2PointsByPost[0].points);
        System.assert(t.mc2PointsByPost.size() <= 5);
        // MC2 par axe : PER-P a 3 matrices, moyenne 20.0 → segment « low_margin » (20 ≤ x < 25).
        Boolean found = false;
        for (AR_DashboardService.Mc2AxisRow r : t.mc2ByAxis) {
            if (r.label == 'PER-P') {
                found = true;
                System.assertEquals(20.0, r.averageMc2Percent);
                System.assertEquals('low_margin', r.segment);
            }
        }
        System.assert(found);
        // Clients à la marge la plus basse : P0 (matrices 0 et 2 : MC2 18 et 22 → 20.0), cible moyenne 26.0, écart −6.0.
        System.assertEquals(1, t.lowestMarginClients.size(), 'Seul Client P0 a deux matrices');
        System.assertEquals('Client P0', t.lowestMarginClients[0].accountName);
        System.assertEquals(20.0, t.lowestMarginClients[0].averageMc2Percent);
        System.assertEquals(26.0, t.lowestMarginClients[0].averageTargetPercent);
        System.assertEquals(-6.0, t.lowestMarginClients[0].gapPoints);
        System.assertEquals('PER-P', t.lowestMarginClients[0].axisLabel);
        // Seuils les plus hauts : P0 (cible max 27, origine ACCOUNT) devant P1 (cible 26).
        System.assertEquals('Client P0', t.highestThresholdAccounts[0].accountName);
        System.assertEquals(27, t.highestThresholdAccounts[0].targetPercent);
        System.assertEquals('ACCOUNT', t.highestThresholdAccounts[0].source);
    }

    @IsTest
    static void testTab_unknownTab_throws() {
        try {
            System.runAs(AR_TestPersona.manager()) {
                AR_DashboardService.getDashboardTab('inconnu', '{}');
            }
            System.assert(false, 'Un onglet inconnu doit être refusé');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('inconnu'), e.getMessage());
        }
    }

    // ---------- Visibilité ----------

    @IsTest
    static void testTabs_bmWithoutManagerSeesOnlyOwnPerimeter() {
        User bm = AR_TestPersona.bm();
        AR_Price_Matrix__c own = matrix('Validée', null, 'PER-BM', 30, 'superstar', 400, 'Client BM');
        own.OwnerId = bm.Id;
        AR_Price_Matrix__c other = matrix('Validée', null, 'PER-AUTRE', 30, 'superstar', 400, 'Client Autre');
        insert new List<AR_Price_Matrix__c>{ own, other };
        String payload;
        String won;
        System.runAs(bm) {
            payload = AR_DashboardService.getDashboardAnalytics('{"axis":"perimeter"}');
            won = AR_DashboardService.getDashboardTab('won', '{"axis":"perimeter"}');
        }
        AR_DashboardService.DashboardAnalytics forBm = (AR_DashboardService.DashboardAnalytics) JSON.deserialize(payload, AR_DashboardService.DashboardAnalytics.class);
        for (AR_DashboardService.AxisSegments e : forBm.segmentsByAxis) {
            System.assertNotEquals('PER-AUTRE', e.entityName, 'Le BM ne voit pas la matrice d\'un autre');
        }
        AR_DashboardService.DashboardAnalytics forManager = analytics('{"axis":"perimeter"}');
        System.assert(forBm.kpis.simulationsCount <= forManager.kpis.simulationsCount);
        System.assertNotEquals(null, won);
    }

    // ---------- Helpers ----------

    private static AR_Price_Matrix__c matrix(String status, Id entityId, String perimeter, Decimal mc2, String segment, Decimal tjm, String account) {
        return new AR_Price_Matrix__c(
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1].Id,
            AR_Contract_Type__c = 'NEARSHORE',
            AR_Status__c = status,
            AR_Proposed_TJM__c = tjm,
            AR_MC2_Percent__c = mc2,
            AR_Corridor_Segment__c = segment,
            AR_Validated_At__c = status == 'Brouillon' ? null : System.now(),
            AR_Entity_Ref__c = entityId,
            AR_Perimeter__c = perimeter,
            AR_Account_Name__c = account
        );
    }

    /** Matrice aux frais renseignés (chaque poste a une valeur distincte), 100 jours de mission. */
    private static AR_Price_Matrix__c costMatrix(String contractType) {
        return new AR_Price_Matrix__c(
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1].Id,
            AR_Contract_Type__c = contractType,
            AR_Status__c = 'Brouillon',
            AR_Annual_Salary__c = 50000,
            AR_Fee_IK__c = 10, AR_Fee_Meals__c = 15, AR_Fee_Lodging__c = 20, AR_Fee_OM_Other__c = 5,
            AR_Fee_Computer__c = 2, AR_Fee_Phone__c = 30, AR_Fee_Monthly_Other__c = 20,
            AR_Fee_Training__c = 600, AR_Fee_EPI__c = 218, AR_Fee_OFII_Tax__c = 436, AR_Fee_Other__c = 109,
            AR_Gratuity_Days__c = 2,
            AR_Number_Of_Days__c = 100,
            AR_Planned_Leave_Days__c = 0
        );
    }

    private static AR_Purge_Log__c purgeLog(String perimeter, Boolean wasRoot) {
        return new AR_Purge_Log__c(
            AR_Perimeter__c = perimeter, AR_Was_Root__c = wasRoot, AR_Matrix_Created_Date__c = System.now(),
            AR_Purged_At__c = System.now(), AR_Matrix_Name__c = 'PURGE-TEST'
        );
    }

    private static AR_Derogation__c derogation(Id matrixId, String decision, Datetime requestedAt, Datetime decidedAt, Id effectiveValidator) {
        return new AR_Derogation__c(
            AR_Price_Matrix__c = matrixId, AR_Requester_Reason__c = 'Test onglets', AR_Decision__c = decision,
            AR_Requested_At__c = requestedAt, AR_Decided_At__c = decidedAt, AR_Effective_Validator__c = effectiveValidator
        );
    }

    private static String tab(String name, String filtersJson) {
        String payload;
        System.runAs(AR_TestPersona.manager()) {
            payload = AR_DashboardService.getDashboardTab(name, filtersJson);
        }
        return payload;
    }

    private static String runAsManagerOverview(String filtersJson) {
        String payload;
        System.runAs(AR_TestPersona.manager()) {
            payload = AR_DashboardService.getDashboardAnalytics(filtersJson);
        }
        return payload;
    }

    private static AR_DashboardService.DashboardAnalytics analytics(String filtersJson) {
        return (AR_DashboardService.DashboardAnalytics) JSON.deserialize(runAsManagerOverview(filtersJson), AR_DashboardService.DashboardAnalytics.class);
    }

    private static AR_DashboardService.TransformRow transformRow(AR_DashboardService.WonTab tab, String label) {
        for (AR_DashboardService.TransformRow row : tab.transformation) {
            if (row.label == label) {
                return row;
            }
        }
        System.assert(false, 'Ligne d\'axe absente : ' + label);
        return null;
    }

    // ---------- Journal de purge : visibilité d'un BM (session 286) ----------

    @IsTest
    static void testPurgeReader_bmOwnDaOtherBmAndManager() {
        User bm = AR_TestPersona.bmWithDa();
        Id daId = [SELECT TP_DA__c FROM User WHERE Id = :bm.Id].TP_DA__c;
        User otherBm = AR_TestPersona.bm();
        AR_Purge_Log__c mine = purgeLog('PER-MINE', true);
        mine.AR_Owner_Id__c = String.valueOf(bm.Id);
        AR_Purge_Log__c other = purgeLog('PER-OTHER', true);
        other.AR_Owner_Id__c = String.valueOf(otherBm.Id);
        AR_Purge_Log__c notRoot = purgeLog('PER-MINE', false);
        notRoot.AR_Owner_Id__c = String.valueOf(bm.Id);
        insert new List<AR_Purge_Log__c>{ mine, other, notRoot };

        System.runAs(bm) {
            System.assertEquals(new Set<String>{ 'PER-MINE' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'Le BM ne voit que les siens (racines), sans droit objet sur le journal');
        }
        System.runAs(new User(Id = daId)) {
            System.assertEquals(new Set<String>{ 'PER-MINE' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'Le DA voit ceux de son BM');
        }
        System.runAs(otherBm) {
            Set<String> seen = perimetersOf(AR_DashboardPurgeReader.readableRootLogs());
            System.assert(!seen.contains('PER-MINE'), 'Un autre BM ne voit rien de ce BM');
            System.assertEquals(new Set<String>{ 'PER-OTHER' }, seen);
        }
        System.runAs(AR_TestPersona.manager()) {
            System.assertEquals(new Set<String>{ 'PER-MINE', 'PER-OTHER' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'Le Manager voit tout');
        }
    }

    private static Set<String> perimetersOf(List<AR_Purge_Log__c> logs) {
        Set<String> out = new Set<String>();
        for (AR_Purge_Log__c l : logs) {
            out.add(l.AR_Perimeter__c);
        }
        return out;
    }
}