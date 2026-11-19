@IsTest
private class AR_DashboardServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Dashboard',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Dashboard', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        // 4 matrices : 2 validées (dont 1 par dérogation), 1 brouillon (sans TJM/MC2/segment), 1 refusée.
        insert new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id, AR_Contract_Type__c = 'NEARSHORE', AR_Status__c = 'Validée',
                AR_Proposed_TJM__c = 400, AR_MC2_Percent__c = 26, AR_Corridor_Segment__c = 'recommended',
                AR_Consultant_Name__c = 'Consultant Dashboard'
            ),
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id, AR_Contract_Type__c = 'NEARSHORE', AR_Status__c = 'Validée par dérogation',
                AR_Proposed_TJM__c = 350, AR_MC2_Percent__c = 22, AR_Corridor_Segment__c = 'low_margin'
            ),
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id, AR_Contract_Type__c = 'NEARSHORE', AR_Status__c = 'Brouillon'
            ),
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id, AR_Contract_Type__c = 'NEARSHORE', AR_Status__c = 'Refusée',
                AR_Proposed_TJM__c = 200, AR_MC2_Percent__c = 10, AR_Corridor_Segment__c = 'below_floor'
            )
        };

        AR_Price_Matrix__c derogMatrix = [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Status__c = 'Refusée' LIMIT 1];
        insert new AR_Derogation__c(
            AR_Price_Matrix__c = derogMatrix.Id,
            AR_Requester_Reason__c = 'Test dashboard',
            AR_Decision__c = 'Refusée',
            AR_Requested_At__c = System.now(),
            AR_Decided_At__c = System.now()
        );
    }

    @IsTest
    static void testGetDashboardData_computesAggregatesAcrossVisibleMatrices() {
        AR_DashboardService.DashboardData data = AR_DashboardService.getDashboardData();

        System.assertEquals(4, data.totalCount);
        System.assertEquals(2, data.validatedCount, 'Validée + Validée par dérogation');
        System.assertEquals(25.0, data.derogationRatePercent, '1 dérogation / 4 matrices = 25 %');
        System.assertEquals(317, data.averageTjm, '(400+350+200)/3 arrondi');
        System.assertEquals(19.3, data.averageMc2Percent, '(26+22+10)/3 arrondi à 1 décimale');

        Map<String, AR_DashboardService.SegmentBreakdown> bySegment = new Map<String, AR_DashboardService.SegmentBreakdown>();
        for (AR_DashboardService.SegmentBreakdown sb : data.segments) {
            bySegment.put(sb.segment, sb);
        }
        System.assertEquals(4, data.segments.size(), 'Les 4 segments doivent toujours être présents, même à 0');
        System.assertEquals(1, bySegment.get('recommended').count);
        System.assertEquals(1, bySegment.get('low_margin').count);
        System.assertEquals(1, bySegment.get('below_floor').count);
        System.assertEquals(0, bySegment.get('superstar').count);
        System.assertEquals(25.0, bySegment.get('recommended').percent, '1/4 = 25 %');

        System.assertEquals(4, data.recentMatrices.size(), 'Les 4 matrices de test, LIMIT 5 non atteint');
        // toItem (AR_MatrixListService) lit le consultant : le SELECT du tableau de bord doit l'interroger.
        Integer withConsultant = 0;
        for (AR_MatrixListService.MatrixListItem item : data.recentMatrices) {
            if (item.consultantName == 'Consultant Dashboard') {
                withConsultant++;
            }
        }
        System.assertEquals(1, withConsultant, 'Le nom du consultant doit être restitué sur les matrices récentes');
    }

    // ------------------------------------------------------------------
    // Socle multi-devises, restitution (session 24b) : devise pivot EUR des agrégats.
    // ------------------------------------------------------------------

    @IsTest
    static void testGetDashboardData_exposesEurPivotCurrency() {
        AR_DashboardService.DashboardData data = AR_DashboardService.getDashboardData();

        System.assertEquals('EUR', data.pivotCurrencyCode);
    }

    /**
     * Le point le plus important de cette partie (prompt session 24b) : l'agrégat consolide les
     * matrices en devise étrangère sur leur ÉQUIVALENT EUR figé, jamais le montant natif brut — sans
     * quoi une matrice à 800 £ pèserait 800 dans la moyenne au lieu de ses ~936 € réels.
     */
    @IsTest
    static void testGetDashboardData_gbpMatrix_usesFrozenEurEquivalent_notNativeAmount() {
        AR_Price_Matrix__c gbpMatrix = validatedGbpMatrix(800, 1.17);

        AR_DashboardService.DashboardData data = AR_DashboardService.getDashboardData();

        AR_Price_Matrix__c reloaded = [
            SELECT AR_Proposed_TJM__c, AR_TJM_EUR_Equivalent__c FROM AR_Price_Matrix__c WHERE Id = :gbpMatrix.Id
        ];
        System.assertEquals(800, reloaded.AR_Proposed_TJM__c, 'Montant natif GBP, jamais converti (moteur, session 24)');
        System.assertEquals(936.00, reloaded.AR_TJM_EUR_Equivalent__c, '800 × 1.17 figé au calcul');

        // 5 matrices au total (les 4 du @TestSetup + celle-ci) : (400+350+200+936)/4 = 471.5 → 472 (arrondi)
        // — la valeur GBP entre dans la moyenne à 936, pas à 800.
        System.assertEquals(472, data.averageTjm);
    }

    /**
     * Le piège explicitement visé par le prompt (même famille que 23b sur les corridors) : modifier
     * le taux de change APRÈS décision ne doit changer aucun agrégat historique — le dashboard doit
     * lire l'équivalent EUR figé sur la matrice, jamais recalculer avec le taux courant.
     */
    @IsTest
    static void testGetDashboardData_rateChangedAfterDecision_neverAffectsHistoricalAggregate() {
        validatedGbpMatrix(800, 1.17);
        AR_DashboardService.DashboardData before = AR_DashboardService.getDashboardData();

        // Le responsable pays met le taux à jour après coup (nouvelle ligne, jamais de réécriture).
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.50,
            AR_Effective_Date__c = Date.today()
        );
        // Témoin : le taux courant a bien changé.
        System.assertEquals(1.50, AR_CurrencyRateService.resolveRate('GBP', Date.today()).rateToEur);

        Test.startTest();
        AR_DashboardService.DashboardData after = AR_DashboardService.getDashboardData();
        Test.stopTest();

        System.assertEquals(before.averageTjm, after.averageTjm, 'Aggrégat historique inchangé malgré le nouveau taux');
    }

    /**
     * Non-régression pour toute matrice antérieure à la session 24 (AR_TJM_EUR_Equivalent__c jamais
     * calculé, champ null) : repli identique au comportement d'avant ce bloc, pas d'exclusion
     * silencieuse de l'historique.
     */
    @IsTest
    static void testGetDashboardData_legacyMatrixWithoutEurEquivalent_fallsBackToNativeTjm() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1];
        insert new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Contract_Type__c = 'NEARSHORE',
            AR_Status__c = 'Validée',
            AR_Proposed_TJM__c = 900,
            AR_MC2_Percent__c = 30,
            AR_Corridor_Segment__c = 'superstar'
            // AR_TJM_EUR_Equivalent__c volontairement non renseigné.
        );

        AR_DashboardService.DashboardData data = AR_DashboardService.getDashboardData();

        // 5 matrices : (400+350+200+900)/4 = 462.5 → 463 (repli sur AR_Proposed_TJM__c pour la 5e).
        System.assertEquals(463, data.averageTjm);
    }

    // ------------------------------------------------------------------
    // Tableau de bord analytique : getDashboardAnalytics(filtersJson).
    // Chaque test isole ses données sur une entité qui lui est propre (filtre entityId ou
    // entityCountry) : les matrices du @TestSetup n'ont pas d'entité et restent hors périmètre.
    // Lecture faite en tant que AR_Pricing_Manager (voit tout), jamais en tant qu'utilisateur courant.
    // ------------------------------------------------------------------

    @IsTest
    static void testAnalytics_keepsLatestVersionPerLineage_andKpisUseIt() {
        AR_PTF_Entity_Referential__c entity = newEntity('Lignée', 'Pays Lignée');
        AR_Price_Matrix__c v1 = validatedMatrix(entity.Id, 'Validée', 12, 'low_margin', Datetime.newInstance(2026, 9, 10, 9, 0, 0), 'Client Lignée');
        insert v1;
        AR_Price_Matrix__c v2 = validatedMatrix(entity.Id, 'Validée par dérogation', 25, 'superstar', Datetime.newInstance(2026, 9, 20, 9, 0, 0), 'Client Lignée');
        v2.AR_Root_Matrix__c = v1.Id;
        v2.AR_TJM_EUR_Equivalent__c = 500;
        insert v2;
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entity.Id, 'Brouillon', null, null, null, 'Client Lignée'),
            validatedMatrix(entity.Id, 'Refusée', 5, 'below_floor', Datetime.newInstance(2026, 9, 21, 9, 0, 0), 'Client Lignée')
        };

        AR_DashboardService.DashboardAnalytics result = analytics(entityFilter(entity.Id));

        System.assertEquals(1, result.kpis.validatedCount, 'V1 remplacée par V2 : une seule affaire ; brouillon et refusée exclus');
        System.assertEquals(1, result.kpis.derogationValidatedCount);
        System.assertEquals(100.0, result.kpis.derogationValidatedPercent);
        System.assertEquals(25.0, result.kpis.averageMc2Percent, 'MC2 de la dernière version, pas la moyenne des deux');
        System.assertEquals(500, result.kpis.averageTjmEur, 'Équivalent EUR de la dernière version (V1 à 400 ignorée)');
        System.assertEquals('EUR', result.kpis.pivotCurrencyCode);
        System.assertEquals(1, result.validationSplit[1].count, 'Répartition : dérogation');
        System.assertEquals(0, result.validationSplit[0].count, 'Répartition : aucune validation directe');
    }

    @IsTest
    static void testAnalytics_periodAppliesAfterDeduplication() {
        AR_PTF_Entity_Referential__c entity = newEntity('Période post-dédoublonnage', 'Pays Période');
        AR_Price_Matrix__c v1 = validatedMatrix(entity.Id, 'Validée', 12, 'low_margin', Datetime.newInstance(2026, 9, 10, 9, 0, 0), 'Client Période');
        insert v1;
        AR_Price_Matrix__c v2 = validatedMatrix(entity.Id, 'Validée', 30, 'superstar', Datetime.newInstance(2026, 11, 3, 9, 0, 0), 'Client Période');
        v2.AR_Root_Matrix__c = v1.Id;
        insert v2;

        // V1 tombe en septembre, mais elle est remplacée par V2 (novembre) : l'affaire sort de la période.
        AR_DashboardService.DashboardAnalytics september = analytics(
            '{"entityId":"' + entity.Id + '","validatedFrom":"2026-09-01","validatedTo":"2026-09-30"}'
        );
        System.assertEquals(0, september.kpis.validatedCount, 'Le filtre de période s’applique après le dédoublonnage');
        System.assertEquals(null, september.kpis.averageMc2Percent);
    }

    @IsTest
    static void testAnalytics_periodBoundsAreWholeDays() {
        AR_PTF_Entity_Referential__c entity = newEntity('Bornes de période', 'Pays Bornes');
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entity.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 10, 31, 23, 0, 0), 'Client Bornes A'),
            validatedMatrix(entity.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 11, 1, 0, 0, 0), 'Client Bornes B'),
            validatedMatrix(entity.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 11, 2, 10, 0, 0), 'Client Bornes C')
        };

        AR_DashboardService.DashboardAnalytics oneDay = analytics(
            '{"entityId":"' + entity.Id + '","validatedFrom":"2026-11-01","validatedTo":"2026-11-01"}'
        );
        AR_DashboardService.DashboardAnalytics all = analytics(entityFilter(entity.Id));

        System.assertEquals(1, oneDay.kpis.validatedCount, 'Seule la matrice du 1er novembre 00:00 est incluse');
        System.assertEquals(3, all.kpis.validatedCount, 'Sans période : tout le périmètre de l’entité');
    }

    @IsTest
    static void testAnalytics_entityAndCountryFilters_andOptions() {
        AR_PTF_Entity_Referential__c entityOne = newEntity('Entité 1', 'Pays Filtre A');
        AR_PTF_Entity_Referential__c entityTwo = newEntity('Entité 2', 'Pays Filtre A');
        AR_PTF_Entity_Referential__c entityThree = newEntity('Entité 3', 'Pays Filtre B');
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entityOne.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client Filtre'),
            validatedMatrix(entityTwo.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 9, 2, 9, 0, 0), 'Client Filtre'),
            validatedMatrix(entityThree.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 9, 3, 9, 0, 0), 'Client Filtre')
        };

        System.assertEquals(1, analytics(entityFilter(entityOne.Id)).kpis.validatedCount, 'Filtre entité');
        System.assertEquals(2, analytics('{"entityCountry":"Pays Filtre A"}').kpis.validatedCount, 'Filtre pays');
        System.assertEquals(1, analytics('{"entityCountry":"Pays Filtre B"}').kpis.validatedCount, 'Filtre pays, autre pays');

        AR_DashboardService.FilterOptions options = analytics('{}').filterOptions;
        List<String> countries = new List<String>{ 'Pays Filtre A', 'Pays Filtre B' };
        System.assertEquals(countries, options.countries, 'Pays distincts, triés');
        System.assertEquals(entityOne.Name, options.entities[0].name, 'Entités triées par nom');
    }

    @IsTest
    static void testAnalytics_mc2BandsAtExactBounds_withDefaultBounds() {
        AR_PTF_Entity_Referential__c entity = newEntity('Tranches défaut', 'Pays Tranches');
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entity.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client Tranche 1'),
            validatedMatrix(entity.Id, 'Validée', 19.99, 'low_margin', Datetime.newInstance(2026, 9, 2, 9, 0, 0), 'Client Tranche 2'),
            validatedMatrix(entity.Id, 'Validée', 15, 'low_margin', Datetime.newInstance(2026, 9, 3, 9, 0, 0), 'Client Tranche 3'),
            validatedMatrix(entity.Id, 'Validée', 10, 'low_margin', Datetime.newInstance(2026, 9, 4, 9, 0, 0), 'Client Tranche 4'),
            validatedMatrix(entity.Id, 'Validée', 9.99, 'below_floor', Datetime.newInstance(2026, 9, 5, 9, 0, 0), 'Client Tranche 5')
        };

        // Aucun enregistrement de paramètres dans le test : repli sur 10;15;20.
        AR_DashboardService.Mc2Bands bands = analytics(entityFilter(entity.Id)).mc2Bands;

        System.assertEquals(new List<Decimal>{ 10, 15, 20 }, bands.bounds);
        System.assertEquals(4, bands.buckets.size());
        System.assertEquals('≥ 20 %', bands.buckets[0].label);
        System.assertEquals(1, bands.buckets[0].count, '20 exactement tombe dans « ≥ 20 % »');
        System.assertEquals(20.0, bands.buckets[0].percent);
        System.assertEquals('15-20 %', bands.buckets[1].label);
        System.assertEquals(2, bands.buckets[1].count, '19,99 et 15 tombent dans « 15-20 % »');
        System.assertEquals('10-15 %', bands.buckets[2].label);
        System.assertEquals(1, bands.buckets[2].count, '10 exactement tombe dans « 10-15 % »');
        System.assertEquals('< 10 %', bands.buckets[3].label);
        System.assertEquals(1, bands.buckets[3].count, '9,99 tombe dans « < 10 % »');
        System.assertEquals(null, bands.buckets[3].min);
        System.assertEquals(10, bands.buckets[3].max);
    }

    @IsTest
    static void testAnalytics_mc2BandsCustomFromSetting() {
        insertGeneralSetting('5;12');
        AR_PTF_Entity_Referential__c entity = newEntity('Tranches personnalisées', 'Pays Perso');
        insert validatedMatrix(entity.Id, 'Validée', 12, 'superstar', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client Perso');

        AR_DashboardService.Mc2Bands bands = analytics(entityFilter(entity.Id)).mc2Bands;

        System.assertEquals(new List<Decimal>{ 5, 12 }, bands.bounds);
        System.assertEquals(3, bands.buckets.size());
        System.assertEquals('≥ 12 %', bands.buckets[0].label);
        System.assertEquals(1, bands.buckets[0].count);
        System.assertEquals('5-12 %', bands.buckets[1].label);
        System.assertEquals('< 5 %', bands.buckets[2].label);
    }

    @IsTest
    static void testAnalytics_mc2BandsFallBackWhenUnreadable() {
        insertGeneralSetting('');
        // Trois valeurs illisibles ou incohérentes : chacune doit retomber sur 10;15;20.
        for (String raw : new List<String>{ '', 'abc', '10;10' }) {
            AR_General_Setting__c setting = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
            setting.AR_Dashboard_MC2_Bands__c = raw;
            update setting;

            AR_DashboardService.Mc2Bands bands = analytics('{}').mc2Bands;

            System.assertEquals(new List<Decimal>{ 10, 15, 20 }, bands.bounds, 'Repli pour « ' + raw + ' »');
        }
    }

    @IsTest
    static void testAnalytics_topFiveReasons_otherReasonsGrouped() {
        AR_PTF_Entity_Referential__c entity = newEntity('Motifs', 'Pays Motifs');
        AR_Price_Matrix__c matrix = validatedMatrix(entity.Id, 'Validée par dérogation', 14, 'low_margin', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client Motifs');
        insert matrix;

        List<AR_Reason__c> reasons = new List<AR_Reason__c>();
        for (String name : new List<String>{ 'Motif A', 'Motif B', 'Motif C', 'Motif D', 'Motif E', 'Motif F' }) {
            reasons.add(new AR_Reason__c(Name = name, AR_Active__c = true));
        }
        insert reasons;

        // Sélections par motif : A 4, B 3, C 2, D 2, E 1, F 1 (13 au total).
        List<List<Integer>> selectionsPerDerogation = new List<List<Integer>>{
            new List<Integer>{ 0, 1, 2, 3, 4, 5 },
            new List<Integer>{ 0, 1, 2, 3 },
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 0 }
        };
        List<AR_Derogation__c> derogations = new List<AR_Derogation__c>();
        for (Integer i = 0; i < selectionsPerDerogation.size(); i++) {
            derogations.add(derogationOn(matrix.Id));
        }
        insert derogations;

        List<AR_Reason_Selection__c> selections = new List<AR_Reason_Selection__c>();
        for (Integer i = 0; i < derogations.size(); i++) {
            for (Integer reasonIndex : selectionsPerDerogation[i]) {
                selections.add(new AR_Reason_Selection__c(
                    AR_Derogation__c = derogations[i].Id,
                    AR_Reason__c = reasons[reasonIndex].Id
                ));
            }
        }
        insert selections;

        AR_DashboardService.Reasons found = analytics(entityFilter(entity.Id)).reasons;

        System.assertEquals(4, found.derogationCount, 'Dérogations demandées, toutes décisions confondues');
        System.assertEquals(13, found.selectionCount);
        System.assertEquals(5, found.top.size());
        System.assertEquals('Motif A', found.top[0].reasonName);
        System.assertEquals(4, found.top[0].count);
        System.assertEquals(30.8, found.top[0].percent, '4 / 13');
        System.assertEquals('Motif D', found.top[3].reasonName, 'Égalité à 2 : départage par nom');
        System.assertEquals('Motif E', found.top[4].reasonName);
        System.assertEquals(1, found.othersCount, 'Motif F seul, regroupé hors du top 5');
        System.assertEquals(7.7, found.othersPercent, '1 / 13');
    }

    @IsTest
    static void testAnalytics_monthlyTrend_sixMonthsWithEmptyOnes() {
        AR_PTF_Entity_Referential__c entity = newEntity('Tendance', 'Pays Tendance');
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entity.Id, 'Validée', 26, 'recommended', Datetime.newInstance(2026, 9, 10, 9, 0, 0), 'Client Tendance'),
            validatedMatrix(entity.Id, 'Validée', 8, 'below_floor', Datetime.newInstance(2026, 11, 3, 9, 0, 0), 'Client Tendance'),
            validatedMatrix(entity.Id, 'Validée', 8, 'below_floor', Datetime.newInstance(2026, 4, 5, 9, 0, 0), 'Client Tendance')
        };

        List<AR_DashboardService.MonthlyCount> monthly = analytics(
            '{"entityId":"' + entity.Id + '","validatedTo":"2026-11-15"}'
        ).monthly;

        System.assertEquals(6, monthly.size());
        System.assertEquals('2026-06', monthly[0].month);
        System.assertEquals('2026-11', monthly[5].month);
        System.assertEquals(0, monthly[2].recommended + monthly[2].below_floor, 'Août : mois vide présent');
        System.assertEquals(1, monthly[3].recommended, 'Septembre');
        System.assertEquals(1, monthly[5].below_floor, 'Novembre');
    }

    @IsTest
    static void testAnalytics_clientRanking_belowTwentyClients_singleRanking() {
        AR_PTF_Entity_Referential__c entity = newEntity('Clients peu nombreux', 'Pays Clients');
        insert new List<AR_Price_Matrix__c>{
            validatedMatrix(entity.Id, 'Validée', 30, 'superstar', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client A'),
            validatedMatrix(entity.Id, 'Validée', 20, 'recommended', Datetime.newInstance(2026, 9, 2, 9, 0, 0), 'Client A'),
            validatedMatrix(entity.Id, 'Validée', 10, 'low_margin', Datetime.newInstance(2026, 9, 3, 9, 0, 0), 'Client C'),
            validatedMatrix(entity.Id, 'Validée', 12, 'low_margin', Datetime.newInstance(2026, 9, 4, 9, 0, 0), 'Client C'),
            validatedMatrix(entity.Id, 'Validée', 40, 'superstar', Datetime.newInstance(2026, 9, 5, 9, 0, 0), 'Client B'),
            validatedMatrix(entity.Id, 'Validée', 40, 'superstar', Datetime.newInstance(2026, 9, 6, 9, 0, 0), null)
        };

        AR_DashboardService.ClientRanking ranking = analytics(entityFilter(entity.Id)).clients;

        System.assertEquals(2, ranking.eligibleCount, 'Client B (une matrice) et matrice sans compte exclus');
        System.assertEquals(true, ranking.singleRanking, 'Moins de 20 comptes : un seul classement');
        System.assertEquals(2, ranking.best.size());
        System.assertEquals('Client A', ranking.best[0].accountName);
        System.assertEquals(25.0, ranking.best[0].averageMc2Percent, 'Moyenne simple : (30 + 20) / 2');
        System.assertEquals(2, ranking.best[0].matrixCount);
        System.assertEquals('Client C', ranking.best[1].accountName);
        System.assertEquals(11.0, ranking.best[1].averageMc2Percent);
        System.assertEquals(0, ranking.worst.size(), 'Pas de liste « moins bonnes » en classement unique');
    }

    @IsTest
    static void testAnalytics_clientRanking_twentyOrMoreClients_topAndFlop() {
        AR_PTF_Entity_Referential__c entity = newEntity('Clients nombreux', 'Pays Nombreux');
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (Integer i = 1; i <= 22; i++) {
            String name = 'Client ' + (i < 10 ? '0' : '') + String.valueOf(i);
            matrices.add(validatedMatrix(entity.Id, 'Validée', i, 'recommended', Datetime.newInstance(2026, 9, 1, 9, 0, 0), name));
            matrices.add(validatedMatrix(entity.Id, 'Validée', i, 'recommended', Datetime.newInstance(2026, 9, 2, 9, 0, 0), name));
        }
        insert matrices;

        AR_DashboardService.ClientRanking ranking = analytics(entityFilter(entity.Id)).clients;

        System.assertEquals(22, ranking.eligibleCount);
        System.assertEquals(false, ranking.singleRanking);
        System.assertEquals(10, ranking.best.size());
        System.assertEquals('Client 22', ranking.best[0].accountName);
        System.assertEquals(22.0, ranking.best[0].averageMc2Percent);
        System.assertEquals(10, ranking.worst.size());
        System.assertEquals('Client 01', ranking.worst[0].accountName);
        System.assertEquals(1.0, ranking.worst[0].averageMc2Percent);
        System.assertEquals('Client 10', ranking.worst[9].accountName, 'Dix moins bons, sans recouvrement avec le top');
    }

    @IsTest
    static void testAnalytics_segmentsByAxis_entity_noEntityAlwaysLast() {
        AR_PTF_Entity_Referential__c entity = newEntity('Segments par entité', 'Pays Segments');
        insert validatedMatrix(entity.Id, 'Validée', 18, 'recommended', Datetime.newInstance(2026, 9, 1, 9, 0, 0), 'Client Segments');

        // Sans filtre : les matrices sans entité du @TestSetup sont présentes et doivent passer en dernier.
        List<AR_DashboardService.AxisSegments> groups = analytics('{}').segmentsByAxis;

        AR_DashboardService.AxisSegments last = groups[groups.size() - 1];
        System.assertEquals(null, last.entityId);
        System.assertEquals('Sans entité', last.entityName);
        System.assertEquals(true, last.noEntity);
        Boolean foundEntity = false;
        for (AR_DashboardService.AxisSegments entry : groups) {
            if (String.valueOf(entity.Id) == entry.entityId) {
                foundEntity = true;
                System.assertEquals(1, entry.total);
                System.assertEquals('Pays Segments', entry.country);
            }
        }
        System.assertEquals(true, foundEntity);
    }

    @IsTest
    static void testAnalytics_invalidFilters_throwReadableMessage() {
        for (String raw : new List<String>{ 'pas du json', '{"validatedFrom":"2026-13-45"}', '{"entityId":"pas un id"}' }) {
            try {
                analytics(raw);
                System.assert(false, 'Filtres invalides : une AuraHandledException est attendue pour « ' + raw + ' »');
            } catch (AuraHandledException ex) {
                System.assert(ex.getMessage().contains('illisibles'), 'Message lisible : ' + ex.getMessage());
            }
        }
    }

    // Session 250 : un utilisateur sans AR_Pricing_Manager (BM) n'a pas d'erreur et ne voit pas plus que le manager.
    @IsTest
    static void testAnalytics_nonManagerUser_noErrorAndNeverMoreThanManager() {
        AR_DashboardService.DashboardAnalytics forManager = analytics('{}');
        String payload;
        System.runAs(AR_TestPersona.bm()) {
            payload = AR_DashboardService.getDashboardAnalytics('{}');
        }
        AR_DashboardService.DashboardAnalytics forBm = (AR_DashboardService.DashboardAnalytics) JSON.deserialize(payload, AR_DashboardService.DashboardAnalytics.class);
        System.assertNotEquals(null, forBm.kpis);
        System.assert(forBm.kpis.validatedCount <= forManager.kpis.validatedCount, 'Le BM ne voit jamais plus de lignées que le manager');
    }

    // ---------- Helpers des tests analytiques ----------

    private static AR_DashboardService.DashboardAnalytics analytics(String filtersJson) {
        String payload;
        System.runAs(AR_TestPersona.manager()) {
            payload = AR_DashboardService.getDashboardAnalytics(filtersJson);
        }
        return (AR_DashboardService.DashboardAnalytics) JSON.deserialize(payload, AR_DashboardService.DashboardAnalytics.class);
    }

    private static String entityFilter(Id entityId) {
        return '{"entityId":"' + entityId + '"}';
    }

    private static AR_PTF_Entity_Referential__c newEntity(String name, String country) {
        AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Name = name, AR_Active__c = true, AR_Country__c = country);
        insert entity;
        return entity;
    }

    /** Matrice non insérée : l'appelant insère (un lot ou une à une, selon le besoin de lignée). */
    private static AR_Price_Matrix__c validatedMatrix(Id entityId, String status, Decimal mc2, String segment, Datetime validatedAt, String accountName) {
        return new AR_Price_Matrix__c(
            AR_Position__c = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1].Id,
            AR_Contract_Type__c = 'NEARSHORE',
            AR_Status__c = status,
            AR_Proposed_TJM__c = 400,
            AR_MC2_Percent__c = mc2,
            AR_Corridor_Segment__c = segment,
            AR_Validated_At__c = validatedAt,
            AR_Entity_Ref__c = entityId,
            AR_Account_Name__c = accountName
        );
    }

    private static AR_Derogation__c derogationOn(Id matrixId) {
        return new AR_Derogation__c(
            AR_Price_Matrix__c = matrixId,
            AR_Requester_Reason__c = 'Test analytique',
            AR_Decision__c = 'Refusée',
            AR_Requested_At__c = System.now(),
            AR_Decided_At__c = System.now()
        );
    }

    private static void insertGeneralSetting(String bands) {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Dashboard_MC2_Bands__c = bands,
            AR_Draft_Purge_Days__c = 30,
            AR_Floor_Percent_Default__c = 20,
            AR_Draft_Purge_Max_Per_Run__c = 50,
            AR_Draft_Purge_Warning_Days__c = 5,
            AR_Markup_Max__c = 60,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 10,
            AR_Target_Percent_Default__c = 25,
            AR_Working_Days_Per_Year__c = 218
        );
    }

    private static AR_Price_Matrix__c validatedGbpMatrix(Decimal proposedTjm, Decimal rateToEur) {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = rateToEur,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Dashboard GBP',
            cxsrec__Account__c = [SELECT Id FROM Account LIMIT 1].Id,
            cxsrec__Country__c = 'Royaume-Uni',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'GBP';
        input.contractType = 'NEARSHORE';
        input.cjmNearshore = 400;
        input.rfaPercent = 0;
        input.proposedTjm = proposedTjm;
        input.entity = String.valueOf(AR_TestPersona.entityRefId('Abylsen GAMMA'));
        input.consultantName = 'Jean DUPONT';
        input.seniorityLevel = 'Senior';
        input.clientSite = 'Site A';
        input.clientGrid = true;
        input.startDate = Date.newInstance(2026, 9, 1);
        input.endDate = Date.newInstance(2026, 9, 30);
        input.numberOfDays = 22;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
        return new AR_Price_Matrix__c(Id = result.matrixId);
    }
}