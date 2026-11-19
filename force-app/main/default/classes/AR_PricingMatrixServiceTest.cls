/**
 * Tests d'intégration AR_PricingMatrixService : chargement des référentiels (VIE, Nearshore,
 * corridor grand compte), écriture des champs calculés sur AR_Price_Matrix__c, et simulate()
 * sans DML. Données créées en @TestSetup, sans SeeAllData.
 */
@IsTest
private class AR_PricingMatrixServiceTest {
    @TestSetup
    static void setup() {
        Account standardAccount = newTestAccount('Client Standard');
        Account corridorAccount = newTestAccount('Grand Compte Corridor');
        insert new List<Account>{ standardAccount, corridorAccount };

        insert new AR_Account_Corridor__c(
            AR_Account__c = corridorAccount.Id,
            AR_Floor_Percent__c = 5,
            AR_Target_Percent__c = 8,
            AR_Ideal_Percent__c = 12
        );

        insert new AR_VIE_Referential__c(
            Name = 'France',
            AR_Daily_Allowance__c = 180
        );
        insert new AR_Nearshore_Referential__c(
            Name = 'Maroc',
            AR_Seniority__c = AR_PricingMatrixService.NEARSHORE_DEFAULT_SENIORITY,
            AR_Daily_Rate__c = 200
        );

        insert new AR_Reason__c(
            Name = 'Motif Test A',
            AR_Applies_To_Derogation__c = true,
            AR_Applies_To_Version__c = true,
            AR_Active__c = true
        );

        // Session 46 : AR_PTF_Entity__mdt migré vers AR_PTF_Entity_Referential__c (objet custom, même
        // principe que AR_Settings__mdt ci-dessus) — insertion explicite nécessaire pour
        // testGetEntityOptions_activeAdminFichesOnly_valueIsFicheId_noPicklistFilter.
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
        // Session 48 : entité porteuse d'un coefficient/jours travaillés propres, pour les tests de
        // cascade — 'Abylsen GAMMA' ci-dessus reste la fixture "sans surcharge" (aucun changement).
        insert new AR_PTF_Entity_Referential__c(
            Name = 'Abylsen STRA',
            AR_Active__c = true,
            AR_Coefficient__c = 1.90,
            AR_Working_Days__c = 200
        );

        // Session 23 : AR_Settings__mdt migré vers AR_General_Setting__c (objet custom, pas de
        // données "seedées" automatiquement en test comme un __mdt déployé — insertion explicite
        // nécessaire pour que testGetPricingSettings_returnsSeededDefaults exerce réellement la
        // lecture de l'objet plutôt que la seule valeur de repli codée en dur).
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Working_Days_Per_Year__c = 218,
            AR_Markup_Percent__c = 18,
            AR_Markup_Max__c = 60,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Draft_Purge_Enabled__c = false,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Warning_Days__c = 5,
            AR_Draft_Purge_Max_Per_Run__c = 200
        );
        List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(
                Name = 'Besoin CDI',
                cxsrec__Account__c = standardAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Open',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'Besoin VIE',
                cxsrec__Account__c = standardAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Open',
                cxsrec__Contract_type__c = 'VIE'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Nearshore',
                cxsrec__Account__c = standardAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Open',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Corridor',
                cxsrec__Account__c = corridorAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Open',
                cxsrec__Contract_type__c = 'CDI'
            ),
            // Session 54 : besoin dédié au lookup consultant, pour ne pas exposer les tests existants
            // (CDI/VIE/Nearshore/Corridor ci-dessus) à un candidat pressenti qu'ils n'attendent pas.
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Consultant',
                cxsrec__Account__c = standardAccount.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Open',
                cxsrec__Contract_type__c = 'CDI'
            )
        };
        insert positions;

        // Session 54 : consultants de test, record type Consultant (seul filtré par searchConsultants
        // et par le pré-remplissage de séniorité) — distinct du record type External_candidate utilisé
        // ailleurs dans l'org (cf. AR_QualificationGatingHandlerTest).
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName()
            .get('Consultant')
            .getRecordTypeId();
        insert new List<cxsrec__cxsCandidate__c>{
            new cxsrec__cxsCandidate__c(
                RecordTypeId = consultantRecordTypeId,
                cxsrec__First_name__c = 'Alice',
                cxsrec__Last_name__c = 'MARTIN',
                TP_Seniority__c = 'Confirmed Consultant',
                // Fiche complète (session 65) : contrat, séniorité — sinon le pré-remplissage n'a rien à
                // lire. L'entité n'est jamais pré-remplie (session 132), cf.
                // testGetConsultantContext_neverPrefillsEntity_evenWhenConsultantHasACompany. Le salaire reste posé À DESSEIN (session 136, décision du 02/10/2026) : il
                // prouve que getConsultantContext ne le reprend ni ne le mentionne, même quand la source existe.
                AB_Annual_base_salary__c = 45000,
                TP_Type_de_contrat__c = 'CDI',
                // Dates périmées POSÉES À DESSEIN (session 146c, décision du 06/10/2026) : la source existe,
                // et testGetConsultantContext_neverReadsDates prouve qu'elle n'est ni reprise ni mentionnée.
                TP_Date_de_demarrage__c = Date.newInstance(2012, 10, 29),
                TP_Date_de_fin_de_missions_previsionnel__c = Date.newInstance(2017, 9, 30)
            ),
            new cxsrec__cxsCandidate__c(
                RecordTypeId = consultantRecordTypeId,
                cxsrec__First_name__c = 'Bruno',
                cxsrec__Last_name__c = 'PETIT',
                // Contrat et rémunération actuelle connus, mais pas de salaire de base : la source du
                // salaire existe sans valeur exploitable → `sourceEmpty` (session 65 §6).
                TP_Type_de_contrat__c = 'CDI',
                TP_Remuneration_actuelle__c = 40000
            )
        };

        // Candidature pressentie (AR_Job_Application__c) pointant vers Alice MARTIN — source de la
        // suggestion de pré-remplissage (session 54, jamais automatique), cf.
        // testGetMatrixInput_suggestsConsultantFromJobApplication_whenNoConsultantSelected.
        cxsrec__cxsPosition__c consultantPosition = [
            SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Consultant' LIMIT 1
        ];
        Id aliceId = [
            SELECT Id FROM cxsrec__cxsCandidate__c WHERE cxsrec__Last_name__c = 'MARTIN' LIMIT 1
        ].Id;
        cxsrec__cxsJob_application__c jobApp = new cxsrec__cxsJob_application__c(
            Name = 'JA Consultant Test',
            cxsrec__Position__c = consultantPosition.Id,
            cxsrec__Candidate__c = aliceId
        );
        insert jobApp;

        insert new AR_Price_Matrix__c(
            AR_Position__c = consultantPosition.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Annual_Salary__c = 43600,
            AR_RFA_Percent__c = 0,
            // TJM délibérément distinct de 700 : la matrice CDI de référence ci-dessous est retrouvée
            // ailleurs dans ce fichier par WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            // LIMIT 1 (testResolveRecordContext_fromPosition_and_fromMatrix) — une collision sur ce
            // couple rendrait cette requête non déterministe entre les deux matrices.
            AR_Proposed_TJM__c = 650,
            AR_Job_Application__c = jobApp.Id
        );

        // Matrice CDI de référence : coût total = 447 (cf. AR_PricingCalculatorTest), TJM proposé 700 → superstar
        insert new AR_Price_Matrix__c(
            AR_Position__c = positions[0].Id,
            AR_Contract_Type__c = 'CDI',
            AR_Annual_Salary__c = 43600,
            AR_Fee_IK__c = 8,
            AR_Fee_Meals__c = 12,
            AR_Fee_Lodging__c = 15,
            AR_Fee_OM_Other__c = 5,
            AR_Gratuity_Days__c = 1,
            AR_Fee_Computer__c = 0,
            AR_Fee_Phone__c = 0,
            AR_Fee_Training__c = 200,
            AR_Fee_EPI__c = 50,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 700
        );

        // Matrice VIE : pas de CJM saisi → doit être résolu via AR_VIE_Referential__c (France = 180)
        insert new AR_Price_Matrix__c(
            AR_Position__c = positions[1].Id,
            AR_Contract_Type__c = 'VIE',
            AR_Account_Country__c = 'France',
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 300
        );

        // Matrice sur le grand compte à corridor personnalisé (floor 5 / target 8 / ideal 12), même coût que la CDI de référence
        insert new AR_Price_Matrix__c(
            AR_Position__c = positions[3].Id,
            AR_Contract_Type__c = 'CDI',
            AR_Annual_Salary__c = 43600,
            AR_Fee_IK__c = 8,
            AR_Fee_Meals__c = 12,
            AR_Fee_Lodging__c = 15,
            AR_Fee_OM_Other__c = 5,
            AR_Gratuity_Days__c = 1,
            AR_Fee_Computer__c = 0,
            AR_Fee_Phone__c = 0,
            AR_Fee_Training__c = 200,
            AR_Fee_EPI__c = 50,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 500
        );
    }

    @IsTest
    static void testSearchPositions_matchesByPositionOrAccountName() {
        List<AR_PricingMatrixService.PositionOption> byPosition = AR_PricingMatrixService.searchPositions('Besoin VIE');
        System.assertEquals(1, byPosition.size());
        System.assert(byPosition[0].label.startsWith('Besoin VIE — Client Standard'));

        List<AR_PricingMatrixService.PositionOption> byAccount = AR_PricingMatrixService.searchPositions('Grand Compte');
        System.assertEquals(1, byAccount.size());
        System.assertEquals('Besoin Corridor — Grand Compte Corridor', byAccount[0].label);
    }

    @IsTest
    static void testSearchPositions_belowMinLength_returnsEmpty() {
        // Session 83 : seuil abaissé à 1 caractère — 'B' devrait maintenant retourner des résultats
        System.assertNotEquals(0, AR_PricingMatrixService.searchPositions('B').size(), 'Un caractère devrait déclencher la recherche');
        System.assertEquals(0, AR_PricingMatrixService.searchPositions('').size(), 'Chaîne vide devrait rester vide');
        System.assertEquals(0, AR_PricingMatrixService.searchPositions(null).size(), 'null devrait rester vide');
    }

    @IsTest
    static void testSearchPositions_oneCharacter_returnsResults() {
        // Session 83 : vérifier que le seuil 1 caractère fonctionne côté serveur
        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('B');
        System.assertNotEquals(0, results.size(), 'La recherche "B" devrait retourner au moins "Besoin CDI", "Besoin VIE", "Besoin Nearshore", "Besoin Corridor"');
        System.assert(results.size() >= 4, 'Au moins 4 besoins commencent par "B"');
    }

    @IsTest
    static void testSearchPositions_excludesClosedNeeds_won_lost_deleted() {
        // Session 88 : créer des besoins clos à exclure de la recherche
        Account acc = newTestAccount('Account Pour Besoins Clos');
        insert acc;
        List<cxsrec__cxsPosition__c> closedNeeds = new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Gagné',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Perdu',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Perdu',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'Besoin Supprimé',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Supprimé',
                cxsrec__Contract_type__c = 'CDI'
            )
        };
        insert closedNeeds;

        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('Besoin');

        for (AR_PricingMatrixService.PositionOption opt : results) {
            System.assert(
                !opt.label.contains('Besoin Gagné') && !opt.label.contains('Besoin Perdu') && !opt.label.contains('Besoin Supprimé'),
                'Besoins clos ne doivent pas apparaître dans les résultats de recherche'
            );
        }
    }

    @IsTest
    static void testSearchPositions_includesOpenNeeds() {
        // Session 88 : vérifier que les besoins Open apparaissent dans la recherche
        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('Besoin CDI');
        System.assert(
            results.size() > 0 && results[0].label.contains('Besoin CDI'),
            'Besoin Open doit apparaître dans la recherche'
        );
    }

    @IsTest
    static void testSearchPositions_includesNullStatusNeeds() {
        // Session 88 : besoins avec statut null ne doivent pas être exclus (traités comme non-clos)
        Account acc = newTestAccount('Account Pour Besoin Null Status');
        insert acc;
        cxsrec__cxsPosition__c nullStatusPosition = new cxsrec__cxsPosition__c(
            Name = 'Besoin Sans Statut',
            cxsrec__Account__c = acc.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = null,
            cxsrec__Contract_type__c = 'CDI'
        );
        insert nullStatusPosition;

        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('Sans Statut');

        System.assertEquals(1, results.size(), 'Besoin avec statut null doit être inclus dans la recherche');
        System.assert(results[0].label.contains('Besoin Sans Statut'));
    }

    @IsTest
    static void testSearchPositions_sortsByCreatedDateNewest() {
        // Session 117 : tri par date de création (plus récent en premier)
        Account acc = newTestAccount('Account Session 117 Sort Test');
        insert acc;
        List<cxsrec__cxsPosition__c> needs = new List<cxsrec__cxsPosition__c>{
            new cxsrec__cxsPosition__c(
                Name = 'A Besoin Session 117',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'B Besoin Session 117',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Contract_type__c = 'CDI'
            ),
            new cxsrec__cxsPosition__c(
                Name = 'C Besoin Session 117',
                cxsrec__Account__c = acc.Id,
                cxsrec__Country__c = 'France',
                cxsrec__Contract_type__c = 'CDI'
            )
        };
        insert needs;

        Test.setCreatedDate(needs[0].Id, System.now().addHours(-2));
        Test.setCreatedDate(needs[1].Id, System.now().addHours(-1));
        Test.setCreatedDate(needs[2].Id, System.now());

        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('Besoin Session 117');

        System.assertEquals(3, results.size(), 'Tous les 3 besoins doivent être retournés');
        System.assertEquals(needs[2].Id, results[0].positionId, 'C (plus récent) doit être premier');
        System.assertEquals(needs[1].Id, results[1].positionId, 'B doit être deuxième');
        System.assertEquals(needs[0].Id, results[2].positionId, 'A (plus ancien) doit être dernier');

        System.assertNotEquals(null, results[0].createdDate, 'CreatedDate de C doit être mappée et non null');
        System.assertNotEquals(null, results[1].createdDate, 'CreatedDate de B doit être mappée et non null');
        System.assertNotEquals(null, results[2].createdDate, 'CreatedDate de A doit être mappée et non null');
    }

    /** Session 54 : lookup consultant — filtré au record type Consultant, porte la séniorité pour
     * le pré-remplissage à la sélection côté LWC. */
    @IsTest
    static void testSearchConsultants_matchesConsultantRecordTypeOnly() {
        List<AR_PricingMatrixService.ConsultantOption> results = AR_PricingMatrixService.searchConsultants('MARTIN');
        System.assertEquals(1, results.size());
        System.assertEquals(consultantId('MARTIN'), results[0].consultantId);
        System.assertEquals(consultantName('MARTIN'), results[0].label);
        System.assertEquals('Confirmed Consultant', results[0].seniority);
    }

    @IsTest
    static void testSearchConsultants_includesExternalCandidate_excludesOtherRecordTypes() {
        Map<String, Schema.RecordTypeInfo> rts = Schema.SObjectType.cxsrec__cxsCandidate__c.getRecordTypeInfosByDeveloperName();
        List<cxsrec__cxsCandidate__c> toInsert = new List<cxsrec__cxsCandidate__c>{
            new cxsrec__cxsCandidate__c(
                RecordTypeId = rts.get('External_candidate').getRecordTypeId(),
                cxsrec__First_name__c = 'Zoe',
                cxsrec__Last_name__c = 'ZEXTERNE',
                TP_Seniority__c = 'Starter Consultant'
            )
        };
        // Une fiche d'un autre record type, si l'utilisateur de test en a un d'assignable (selon le
        // profil, Candidat_BM_BP / Candidat_BP ne le sont pas toujours) : elle doit rester exclue.
        for (Schema.RecordTypeInfo info : rts.values()) {
            if (
                info.isAvailable() &&
                info.isActive() &&
                !info.isMaster() &&
                info.getDeveloperName() != 'Consultant' &&
                info.getDeveloperName() != 'External_candidate' &&
                info.isDefaultRecordTypeMapping() == false
            ) {
                toInsert.add(
                    new cxsrec__cxsCandidate__c(
                        RecordTypeId = info.getRecordTypeId(),
                        cxsrec__First_name__c = 'Zack',
                        cxsrec__Last_name__c = 'ZEXTERNE'
                    )
                );
                break;
            }
        }
        insert toInsert;
        List<AR_PricingMatrixService.ConsultantOption> results = AR_PricingMatrixService.searchConsultants('ZEXTERNE');
        System.assertEquals(1, results.size(), 'External_candidate trouvé, autre record type exclu');
        System.assertEquals('Zoe ZEXTERNE', results[0].label);
        System.assertEquals('Starter Consultant', results[0].seniority);
    }

    @IsTest
    static void testSearchConsultants_candidateWithoutSeniority_returnsNullSeniority() {
        List<AR_PricingMatrixService.ConsultantOption> results = AR_PricingMatrixService.searchConsultants('PETIT');
        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].seniority, 'Bruno PETIT ne porte aucune séniorité dans le jeu de test');
    }

    @IsTest
    static void testSearchConsultants_withOneCharacter_returnsMatchingResults() {
        // Session 99 : seuil abaissé à 1 caractère pour alignment sur searchPositions (session 83).
        List<AR_PricingMatrixService.ConsultantOption> results = AR_PricingMatrixService.searchConsultants('M');
        System.assertEquals(1, results.size(), 'M devrait matcher MARTIN');
        System.assertEquals(consultantId('MARTIN'), results[0].consultantId);
    }

    @IsTest
    static void testSearchConsultants_belowMinLength_returnsEmpty() {
        System.assertEquals(0, AR_PricingMatrixService.searchConsultants('').size());
        System.assertEquals(0, AR_PricingMatrixService.searchConsultants(null).size());
    }

    /**
     * Session 65 : pré-remplissage à la sélection du consultant — contexte complet avec toutes les
     * propriétés renseignées et `filled` cohérent.
     */
    @IsTest
    static void testGetConsultantContext_complete_fillsAllPropertiesAndPopulatesFilled() {
        Id consultantId = consultantId('MARTIN');
        AR_PricingMatrixService.ConsultantContext ctx = AR_PricingMatrixService.getConsultantContext(
            consultantId
        );

        System.assertNotEquals(null, ctx.contractType, 'Contrat doit être rempli');
        System.assertNotEquals(null, ctx.seniorityLevel, 'Séniorité doit être remplie');
        System.assertEquals(2, ctx.filled.size(), 'Contrat et séniorité : tous les champs repris doivent être dans `filled`');
        System.assert(!ctx.filled.contains('entity'), 'L\'entité n\'est jamais pré-remplie');
        System.assertEquals(0, ctx.sourceEmpty.size(), 'Aucun source vide attendu');
        System.assertEquals(0, ctx.unreadable.size(), 'Aucun champ non lisible attendu');
        assertNoSalaryMention(ctx);
    }

    /**
     * Session 146c (06/10/2026) : les dates de la fiche consultant sont périmées (MARTIN : 2012 → 2017,
     * posées en fixture) et ne sont jamais reprises. Le contexte ne porte aucune propriété de date, et
     * ni `filled`, ni `sourceEmpty`, ni `unreadable` ne les mentionnent.
     */
    @IsTest
    static void testGetConsultantContext_neverReadsDates() {
        AR_PricingMatrixService.ConsultantContext ctx = AR_PricingMatrixService.getConsultantContext(
            consultantId('MARTIN')
        );
        String serialized = JSON.serialize(ctx);
        System.assert(!serialized.containsIgnoreCase('startDate'), 'Aucune date de début dans le contexte : ' + serialized);
        System.assert(!serialized.containsIgnoreCase('endDate'), 'Aucune date de fin dans le contexte : ' + serialized);
        System.assert(!serialized.contains('2012') && !serialized.contains('2017'), 'Aucune valeur de date de la fiche : ' + serialized);
        for (String key : new List<String>{ 'startDate', 'endDate' }) {
            System.assert(!ctx.filled.contains(key), key + ' ne doit pas être dans filled');
            System.assert(!ctx.sourceEmpty.contains(key), key + ' ne doit pas être dans sourceEmpty');
            System.assert(!ctx.unreadable.contains(key), key + ' ne doit pas être dans unreadable');
        }
        System.assertEquals(2, ctx.filled.size(), 'Seuls contrat et séniorité sont repris');
    }

    /**
     * Session 136, décision 2 (02/10/2026) : le salaire du consultant n'est pas repris. MARTIN porte
     * AB_Annual_base_salary__c = 45000 (fixture), PETIT n'a aucun salaire : dans les deux cas le salaire
     * n'apparaît ni dans `filled`, ni dans `sourceEmpty`, ni dans `unreadable`.
     */
    @IsTest
    static void testGetConsultantContext_salaryNeverReadNorMentioned() {
        assertNoSalaryMention(AR_PricingMatrixService.getConsultantContext(consultantId('MARTIN')));
        assertNoSalaryMention(AR_PricingMatrixService.getConsultantContext(consultantId('PETIT')));
    }

    private static void assertNoSalaryMention(AR_PricingMatrixService.ConsultantContext ctx) {
        System.assertEquals(false, ctx.filled.contains('annualSalary'), 'Salaire absent de `filled`');
        System.assertEquals(false, ctx.sourceEmpty.contains('annualSalary'), 'Salaire absent de `sourceEmpty`');
        System.assertEquals(false, ctx.unreadable.contains('annualSalary'), 'Salaire absent de `unreadable` (pas de mention « non lisible »)');
    }

    /**
     * Session 65 §4 : contrat non traduisible → champ non rempli, motif rapporté dans `sourceEmpty`.
     */
    @IsTest
    static void testGetConsultantContext_untranslatableContractType_notFilledAndReported() {
        // Créer un consultant avec un contrat non traduisible (Sous-traitant)
        cxsrec__cxsCandidate__c c = new cxsrec__cxsCandidate__c(
            cxsrec__First_name__c = 'Test',
            cxsrec__Last_name__c = 'Untranslatable',
            RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
                .getRecordTypeInfosByDeveloperName()
                .get('Consultant')
                .getRecordTypeId(),
            TP_Type_de_contrat__c = 'Sous-traitant'
        );
        insert c;

        AR_PricingMatrixService.ConsultantContext ctx = AR_PricingMatrixService.getConsultantContext(c.Id);

        System.assertEquals(null, ctx.contractType, 'Contrat non traduisible doit rester null');
        System.assertEquals(
            true,
            ctx.sourceEmpty.contains('contractType'),
            'Doit lister le contrat en sourceEmpty avec motif'
        );
    }

    /**
     * Session 65 §6 : consultant inexistant → erreur explicite, pas un contexte vide silencieux.
     */
    @IsTest
    static void testGetConsultantContext_consultantNotFound_throwsException() {
        try {
            AR_PricingMatrixService.getConsultantContext(
                Id.valueOf(cxsrec__cxsCandidate__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
            );
            System.assert(false, 'Doit lever une exception');
        } catch (AuraHandledException e) {
            System.assertEquals(Label.AR_Msg_PM_ConsultantNotFound, e.getMessage());
        }
    }

    /**
     * Session 65 §6 : USER_MODE SOQL — champ non lisible (FLS) → dans `unreadable`, jamais dans
     * `filled`. Testé en runAs d'un persona porteur d'`AR_Pricing_User` seul.
     */
    @IsTest
    static void testGetConsultantContext_fieldNotReadableByUser_inUnreadableNotFilled() {
        User userWithoutAccess = queryOrCreatePricingUser();
        Id consultantId = consultantId('MARTIN');

        System.runAs(userWithoutAccess) {
            AR_PricingMatrixService.ConsultantContext ctx = AR_PricingMatrixService.getConsultantContext(
                consultantId
            );
            // MARTIN a un contrat CDI : soit le persona le lit (rempli), soit non (unreadable) —
            // jamais les deux, jamais ni l'un ni l'autre (muet). Le résultat dépend de la config
            // réelle des permissions : ce test prouve que l'appel ne tombe pas en bloc et que chaque
            // cas est étiqueté. (Le salaire n'est plus lu, session 136.)
            Boolean filled = ctx.filled.contains('contractType');
            Boolean unreadable = ctx.unreadable.contains('contractType');
            System.assertEquals(true, filled != unreadable, 'Contrat : rempli XOR non lisible, jamais muet');
            if (filled) {
                System.assertEquals('CDI', ctx.contractType);
            } else {
                System.assertEquals(null, ctx.contractType);
                System.assertEquals(false, ctx.sourceEmpty.contains('contractType'));
            }
            assertNoSalaryMention(ctx);
        }
    }

    /**
     * Session 65 : Session 64 translation table — Indépendant → INDEP.
     */
    @IsTest
    static void testGetConsultantContext_contractTypeIndependant_translatesTo_INDEP() {
        // « Indépendant » existe sur 28 fiches Consultant de l'org mais n'est plus une valeur ACTIVE de la
        // picklist restreinte TP_Type_de_contrat__c (7 valeurs actives, relevé session 135) : un insert
        // de test est refusé (INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST). La table de traduction, elle,
        // doit rester juste pour ces fiches historiques — on la teste donc directement.
        System.assertEquals('INDEP', AR_PricingMatrixService.translateContractType('Indépendant'));
        System.assertEquals('CDI', AR_PricingMatrixService.translateContractType('CDI'));
        System.assertEquals('CDD', AR_PricingMatrixService.translateContractType('CDD'));
        System.assertEquals('VIE', AR_PricingMatrixService.translateContractType('VIE'));
        System.assertEquals(null, AR_PricingMatrixService.translateContractType('Sous-traitant'));
        System.assertEquals(null, AR_PricingMatrixService.translateContractType(null));
    }

    /**
     * Session 54 §0bis : la suggestion depuis AR_Job_Application__c (candidature pressentie) n'est
     * jamais automatique — seulement une donnée de sortie, quand AR_Consultant__c est encore vide.
     */
    @IsTest
    static void testGetMatrixInput_suggestsConsultantFromJobApplication_whenNoConsultantSelected() {
        AR_Price_Matrix__c matrix = [
            SELECT Id FROM AR_Price_Matrix__c WHERE AR_Job_Application__c != null LIMIT 1
        ];

        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(matrix.Id);

        System.assertEquals(null, input.consultantId, 'La suggestion ne doit jamais présélectionner AR_Consultant__c');
        System.assertEquals(consultantId('MARTIN'), input.suggestedConsultantId);
        System.assertEquals(consultantName('MARTIN'), input.suggestedConsultantLabel);
    }

    @IsTest
    static void testGetMatrixInput_noSuggestion_onceConsultantAlreadySelected() {
        AR_Price_Matrix__c matrix = [
            SELECT Id FROM AR_Price_Matrix__c WHERE AR_Job_Application__c != null LIMIT 1
        ];
        update new AR_Price_Matrix__c(Id = matrix.Id, AR_Consultant__c = consultantId('PETIT'));

        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(matrix.Id);

        System.assertEquals(consultantId('PETIT'), input.consultantId);
        System.assertEquals(
            null,
            input.suggestedConsultantId,
            'Un consultant déjà sélectionné ne doit plus afficher la suggestion depuis la candidature'
        );
    }

    // Session 9 : AR_TJM_Top10__c doit refléter le p90 des comparables réels quand il dépasse
    // idéal×1.10 (639×1.10 = 703 pour la base CDI, cf. testRecalculate_cdiBaseCase ci-dessous), et
    // retomber sur ce fallback dans le cas inverse — cf. AR_PricingCalculator.calcThresholds.
    @IsTest
    static void testRecalculate_realTop10Comparables_beatsIdealFallback() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];
        insertWonComparables(acc.Id, 'CDI', new List<Decimal>{ 700, 720, 740, 760, 780, 800, 820, 840, 860, 880 });
        AR_Price_Matrix__c matrix = [
            SELECT Id
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];

        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);

        // Moteur pondéré (session 69, docs/69d) : 10 comparables de poids égaux → le cumul atteint
        // EXACTEMENT 90 % au 9e (860) : weightedPercentile renvoie alors la moyenne avec le 10e (880) = 870.
        System.assertEquals(870, result.tjmTop10, 'p90 réel (870 = moyenne 860/880, cf. 69d) dépasse idéal×1.10 (703) : le réel doit gagner');
    }

    @IsTest
    static void testRecalculate_lowTop10Comparables_fallsBackToIdealTimes110() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];
        insertWonComparables(acc.Id, 'CDI', new List<Decimal>{ 200, 210, 220, 230 });
        AR_Price_Matrix__c matrix = [
            SELECT Id
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];

        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);

        System.assertEquals(703, result.tjmTop10, 'p90 réel (230) sous idéal×1.10 (703) : le fallback doit gagner');
    }

    private static void insertWonComparables(Id accountId, String contractType, List<Decimal> tjms) {
        List<cxsrec__cxsPosition__c> won = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < tjms.size(); i++) {
            won.add(new cxsrec__cxsPosition__c(
                Name = 'Comparable Gagné ' + i,
                cxsrec__Account__c = accountId,
                cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné',
                cxsrec__Contract_type__c = contractType,
                TP_TJM__c = tjms[i]
            ));
        }
        insert won;
    }

    @IsTest
    static void testRecalculate_cdiBaseCase_writesCalculatedFields() {
        AR_Price_Matrix__c matrix = [
            SELECT Id
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];

        Test.startTest();
        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);
        Test.stopTest();

        System.assertEquals(447, result.totalDailyCost);
        System.assertEquals('superstar', result.corridorSegment);

        AR_Price_Matrix__c reloaded = [
            SELECT AR_Total_Daily_Cost__c, AR_Corridor_Segment__c, AR_MC2_Per_Day__c
            FROM AR_Price_Matrix__c
            WHERE Id = :matrix.Id
        ];
        System.assertEquals(447, reloaded.AR_Total_Daily_Cost__c);
        System.assertEquals('superstar', reloaded.AR_Corridor_Segment__c);
        System.assertEquals(253.0, reloaded.AR_MC2_Per_Day__c);
    }

    @IsTest
    static void testRecalculate_vieContractType_resolvesReferential() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Contract_Type__c = 'VIE' LIMIT 1];

        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);

        System.assertEquals(180, result.cjm, 'CJM VIE doit provenir du référentiel pays (France = 180)');
        System.assertEquals(180, result.totalDailyCost, 'Pas de frais saisis → coût total = CJM seul');
    }

    @IsTest
    static void testRecalculate_accountCorridorOverride_changesSegment() {
        // Même coût (447) et un TJM proposé de 500 qu'en base CDI (MC2 % = 10.6 %) :
        // avec les seuils par défaut (20/25/30) ce serait below_floor, mais le corridor du
        // grand compte (5/8/12) le classe en recommended.
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Proposed_TJM__c = 500 LIMIT 1];

        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);

        System.assertEquals('recommended', result.corridorSegment);
    }

    @IsTest
    static void testSimulate_noDmlAndMatchesCalculator() {
        AR_PricingMatrixService.SimulateRequest req = new AR_PricingMatrixService.SimulateRequest();
        req.contractType = 'NEARSHORE';
        req.cjmNearshore = 200;
        req.rfaPercent = 0;
        req.proposedTjm = 400;
        req.top10Comparables = 0;

        Integer matrixCountBefore = [SELECT COUNT() FROM AR_Price_Matrix__c];

        Test.startTest();
        AR_PricingResult result = AR_PricingMatrixService.simulate(req);
        Test.stopTest();

        Integer matrixCountAfter = [SELECT COUNT() FROM AR_Price_Matrix__c];
        System.assertEquals(matrixCountBefore, matrixCountAfter, 'simulate() ne doit faire aucun DML');
        System.assertEquals(200, result.cjm);
        System.assertEquals(200, result.totalDailyCost);
    }

    @IsTest
    static void testGetPositionContext_returnsZone1Fields() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals('Besoin CDI', ctx.positionName);
        System.assertEquals('France', ctx.accountCountry);
        System.assertEquals('Client Standard', ctx.accountName);
        System.assertNotEquals(null, ctx.accountId);
        System.assertEquals(true, ctx.accessible, 'Cas nominal : le besoin est accessible');
    }

    /** Session 167 : besoin invisible (ici supprimé — même effet qu'un besoin hors partage : 0 ligne
     * en SOQL with sharing) → contexte vide `accessible = false`, jamais « List has no rows ». */
    private static Id invisiblePositionId() {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin invisible',
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        Id positionId = position.Id;
        delete position;
        return positionId;
    }

    @IsTest
    static void testGetPositionContext_positionNotVisible_returnsEmptyInaccessibleContext() {
        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(
            invisiblePositionId()
        );

        System.assertEquals(false, ctx.accessible);
        System.assertEquals(null, ctx.positionName);
        System.assertEquals(null, ctx.accountId);
        System.assertEquals(null, ctx.managerContactId);
    }

    @IsTest
    static void testRequireAccessiblePositionContext_positionNotVisible_throwsClearMessage() {
        String message;
        try {
            AR_PricingMatrixService.requireAccessiblePositionContext(invisiblePositionId());
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(System.Label.AR_PMS_PositionAccessDeniedSaveError, message);
        System.assert(!message.contains('List has no rows'), 'Jamais l\'erreur Apex brute');
    }

    @IsTest
    static void testSaveDraftInput_positionNotVisible_throwsClearMessage_andWritesNothing() {
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__c];
        String message;
        try {
            AR_PricingMatrixService.saveDraftInput(cdiInput(invisiblePositionId(), 60000, 'Abylsen GAMMA', 600));
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(System.Label.AR_PMS_PositionAccessDeniedSaveError, message);
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__c], 'Aucune matrice écrite');
    }

    /** Persona réel (AR_Pricing_User seul) : le besoin n'est pas forcément masqué dans cette org
     * (partage Connexys), donc on n'asserte que l'invariant — jamais d'exception brute en lecture,
     * et `accessible` reflète exactement la visibilité de la ligne pour cet utilisateur. */
    @IsTest
    static void testGetPositionContext_persona_neverRawException_accessibleMatchesVisibility() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        User persona = AR_TestPersona.sansHabilitation();
        System.runAs(persona) {
            Boolean visible = ![SELECT Id FROM cxsrec__cxsPosition__c WHERE Id = :position.Id].isEmpty();
            AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);
            System.assertEquals(visible, ctx.accessible);
        }
    }

    /** Bandeau récapitulatif Zone 1 (session 17) : Périmètre/Business Line du besoin, choisis à la
     * place de TP_Secteur_d_activit__c (vide sur 100% de l'org, cf. docs/17-contexte-affaire.md). */
    @IsTest
    static void testGetPositionContext_returnsPerimetreAndBusinessLine() {
        Account acc = newTestAccount('Client Perimetre');
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Perimetre',
            cxsrec__Account__c = acc.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI',
            TP_P_rim_tre__c = 'Gamma',
            TP_Business_Line__c = 'IT'
        );
        insert position;

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals('Gamma', ctx.perimetre);
        System.assertEquals('IT', ctx.businessLine);
    }

    @IsTest
    static void testGetPositionContext_returnsEstimatedEndDate() {
        // Session 184b : « Estimated End Date » du besoin exposée ; vide → null (l'écran retombe sur le 31/12).
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        System.assertEquals(
            null,
            AR_PricingMatrixService.getPositionContext(position.Id).estimatedEndDate,
            'Champ vide : aucune date estimée'
        );

        position.AB_Estimated_End_Date__c = Date.newInstance(2027, 3, 31);
        update position;

        System.assertEquals(
            Date.newInstance(2027, 3, 31),
            AR_PricingMatrixService.getPositionContext(position.Id).estimatedEndDate,
            'Champ rempli : date estimée du besoin'
        );
    }

    @IsTest
    static void testGetPositionContext_returnsStatus() {
        // Session 88 : vérifier que le statut du besoin est exposé dans le contexte
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals('Open', ctx.status, 'Le statut du besoin doit être exposé');
    }

    @IsTest
    static void testResolveRecordContext_fromPosition_and_fromMatrix() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_Price_Matrix__c matrix = [
            SELECT Id
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];

        AR_PricingMatrixService.RecordContext fromPosition = AR_PricingMatrixService.resolveRecordContext(position.Id);
        System.assertEquals(position.Id, fromPosition.positionId);
        System.assertEquals(null, fromPosition.matrixId);

        AR_PricingMatrixService.RecordContext fromMatrix = AR_PricingMatrixService.resolveRecordContext(matrix.Id);
        System.assertEquals(matrix.Id, fromMatrix.matrixId);
        System.assertEquals(position.Id, fromMatrix.positionId);
    }

    @IsTest
    static void testCountMatricesForPosition_countsExistingMatrices() {
        AR_Price_Matrix__c matrix = [
            SELECT AR_Position__c
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];
        Integer expected = [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c = :matrix.AR_Position__c];

        Integer actual = AR_PricingMatrixService.countMatricesForPosition(matrix.AR_Position__c);

        System.assert(actual >= 1, 'Le besoin porte au moins la matrice de test');
        System.assertEquals(expected, actual, 'Le compte doit refléter les matrices réelles du besoin');
    }

    @IsTest
    static void testGetMatrixInput_reloadsEditableFields() {
        AR_Price_Matrix__c matrix = [
            SELECT Id
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];

        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(matrix.Id);

        System.assertEquals(matrix.Id, input.matrixId);
        System.assertEquals('CDI', input.contractType);
        System.assertEquals(43600, input.annualSalary);
        System.assertEquals(700, input.proposedTjm);
        System.assertEquals('Brouillon', input.status);
        System.assertEquals(UserInfo.getName(), input.creatorName, 'Zone 1 "Propriétaire" = créateur de la matrice, pas le owner du besoin');
    }

    /** Zone 1 (session 17) : les champs mission doivent faire l'aller-retour saveDraft → getMatrixInput,
     * pas seulement être écrits en base (cf. testSaveDraft_persistsMissionFields). */
    @IsTest
    static void testGetMatrixInput_reloadsMissionFields() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixSaveResult saved = AR_PricingMatrixService.saveDraftInput(nearshoreInput(position.Id, 400));

        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(saved.matrixId);

        System.assertEquals(AR_TestPersona.entityRefId('Abylsen GAMMA'), input.entity);
        System.assertEquals('Abylsen GAMMA', input.entityName);
        // Session 54 : la persistance passe désormais par consultantId (Lookup), pas consultantName
        // (texte libre, devenu un champ de sortie pur — cf. testGetMatrixInput_reloadsMissionFields
        // ne l'exerce plus, testGetMatrixInput_neverPersistsLegacyConsultantText couvre son immutabilité).
        System.assertEquals(consultantId('MARTIN'), input.consultantId);
        System.assertEquals(consultantName('MARTIN'), input.consultantLabel);
        System.assertEquals('Paris La Défense', input.clientSite);
        System.assertEquals(Date.newInstance(2026, 9, 1), input.startDate);
        System.assertEquals(Date.newInstance(2026, 9, 30), input.endDate);
        System.assertEquals(22, input.numberOfDays);
    }

    @IsTest
    static void testValidateInput_freezesPerimeter_notRecomputedWhenPositionChanges() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Corridor' LIMIT 1];
        position.TP_P_rim_tre__c = 'NEO';
        update position;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(nearshoreInput(position.Id, 400));
        System.assertEquals('Validée', result.status);

        position.TP_P_rim_tre__c = 'NEO/NORD';
        update position;
        System.assertEquals('NEO', [SELECT AR_Perimeter__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId].AR_Perimeter__c, 'Périmètre figé à la validation');
    }

    /**
     * Non-régression session 23b — le défaut du contrôle navigateur du 18/08 : les seuils/segment
     * affichés par le simulateur sur une matrice DÉCIDÉE ne doivent jamais dériver rétroactivement
     * si le corridor du grand compte change après coup (prompts/session-23b-derive-retroactive-seuils.md
     * §1). getMatrixInput() est le service qui alimente le simulateur (MatrixInput.storedResult,
     * cf. arPriceMatrixSimulator.applyFrozenCalculationIfDecided) : c'est lui qui doit continuer à
     * renvoyer les valeurs d'origine, pas seulement les champs bruts de l'enregistrement (déjà
     * couverts, et déjà corrects, par les tests existants — c'est la lecture qui manquait).
     */
    @IsTest
    static void testGetMatrixInput_decidedMatrix_ignoresLaterCorridorChange() {
        Account corridorAccount = [SELECT Id FROM Account WHERE Name = 'Grand Compte Corridor' LIMIT 1];
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Corridor' LIMIT 1];
        // coût 200 (CJM nearshore seul) ; TJM 400 → MC2 200/jour, MC2 % 50 % ; corridor d'origine
        // 5/8/12 (cf. @TestSetup) ⇒ floor 211 / target 218 / ideal 228, segment superstar.
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(
            nearshoreInput(position.Id, 400)
        );
        System.assertEquals('Validée', result.status);

        update new AR_Account_Corridor__c(
            Id = [SELECT Id FROM AR_Account_Corridor__c WHERE AR_Account__c = :corridorAccount.Id LIMIT 1].Id,
            AR_Floor_Percent__c = 1,
            AR_Target_Percent__c = 2,
            AR_Ideal_Percent__c = 3
        );
        // Le corridor a bien changé : sert de témoin pour prouver que storedResult ci-dessous n'est
        // pas juste "resté correct par coïncidence".
        System.assertEquals(
            1,
            AR_PricingMatrixService.getAccountCorridorPercents(corridorAccount.Id, null).floorPercent
        );

        Test.startTest();
        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        Test.stopTest();

        System.assertEquals(211, input.storedResult.tjmFloor, 'Seuil plancher figé au calcul d\'origine');
        System.assertEquals(218, input.storedResult.tjmTarget, 'Seuil cible figé au calcul d\'origine');
        System.assertEquals(228, input.storedResult.tjmIdeal, 'Seuil idéal figé au calcul d\'origine');
        System.assertEquals(50.00, input.storedResult.mc2PercentHuman);
        System.assertEquals('superstar', input.storedResult.corridorSegment);
        System.assertEquals(5, input.storedResult.floorPercentApplied, 'Corridor appliqué à l\'origine, pas le corridor courant');
        System.assertEquals(8, input.storedResult.targetPercentApplied);
        System.assertEquals(12, input.storedResult.idealPercentApplied);
    }

    // ------------------------------------------------------------------
    // CDD et coefficient administrable (session 28 §1).
    // ------------------------------------------------------------------

    @IsTest
    static void testSaveDraftInput_cdd_defaultCoefficient_computesLikeCdiBaseCase() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cddInput(position.Id, 43600, 700);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // Même chiffre que la matrice CDI de référence (@TestSetup, coût 447) : le CDD sans
        // coefficient administré applique le même défaut moteur (2,02) que le CDI.
        System.assertEquals(447, result.calculation.totalDailyCost);
        System.assertEquals('superstar', result.calculation.corridorSegment);
        System.assertEquals(2.02, result.calculation.contractCoefficientApplied);

        AR_Price_Matrix__c saved = [SELECT AR_Contract_Coefficient_Applied__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        System.assertEquals(2.02, saved.AR_Contract_Coefficient_Applied__c, 'Coefficient appliqué figé sur la matrice, comme AR_Floor_Percent_Applied__c');
    }

    @IsTest
    static void testSaveDraftInput_negotiationPrices_roundTripWithoutChangingCalculation() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cddInput(position.Id, 43600, 700);
        input.clientGrid = false;
        input.negoPrice2 = 650;
        input.negoPrice3 = 610;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);

        System.assertEquals(447, result.calculation.totalDailyCost);
        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        System.assertEquals(650, reloaded.negoPrice2);
        System.assertEquals(610, reloaded.negoPrice3);
        System.assertEquals(700, reloaded.proposedTjm, 'le TJM proposé reste le prix 1');
    }

    // ------------------------------------------------------------------
    // Cascade coefficient/jours travaillés par entité (session 48, réunion client du 03/09/2026).
    // ------------------------------------------------------------------

    @IsTest
    static void testSaveDraftInput_entityWithCoefficientAndWorkingDays_overridesEngineDefaults() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, 'Abylsen STRA', 900);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // round(45000 * 1,90 / 200) = round(427.5) = 428. Aucun frais dans cdiInput ci-dessous
        // (gratuityDays=0) ⇒ coût total = CJM seul.
        System.assertEquals(428, result.calculation.cjm);
        System.assertEquals(428, result.calculation.totalDailyCost);
        System.assertEquals(1.90, result.calculation.contractCoefficientApplied);
        System.assertEquals(200, result.calculation.workingDaysPerYearApplied);

        AR_Price_Matrix__c saved = [
            SELECT AR_Contract_Coefficient_Applied__c, AR_Working_Days_Applied__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(1.90, saved.AR_Contract_Coefficient_Applied__c, 'Coefficient d\'entité figé sur la matrice');
        System.assertEquals(200, saved.AR_Working_Days_Applied__c, 'Jours travaillés d\'entité figés sur la matrice');
    }

    @IsTest
    static void testSaveDraftInput_entityWithoutOverride_fallsBackToGlobalWorkingDaysAndEngineCoefficient() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        // 'Abylsen GAMMA' (@TestSetup) n'a ni coefficient ni jours travaillés propres.
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, 'Abylsen GAMMA', 900);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // round(45000 * 2,02 / 218) = 417 (même cas que la matrice CDI de référence) : coefficient
        // global toujours découplé (session 28) ⇒ constante moteur ; jours travaillés = paramètre
        // général (218, @TestSetup).
        System.assertEquals(417, result.calculation.cjm);
        System.assertEquals(2.02, result.calculation.contractCoefficientApplied);
        System.assertEquals(218, result.calculation.workingDaysPerYearApplied);
    }

    @IsTest
    static void testSaveDraftInput_noEntitySelected_stillAppliesGlobalWorkingDaysWithoutError() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 900);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertEquals(417, result.calculation.cjm, 'Aucune entité sélectionnée : ne doit ni bloquer ni changer le résultat par défaut');
        System.assertEquals(218, result.calculation.workingDaysPerYearApplied);
    }

    /**
     * Non-régression rétroactive (session 48, même parade que testGetMatrixInput_decidedMatrix_
     * ignoresLaterCorridorChange ci-dessus et bloc 23b) : une matrice déjà décidée garde le
     * coefficient/jours travaillés — et donc le coût/MC2 — appliqués au moment de la décision, même
     * si l'entité change de paramétrage ensuite.
     */
    @IsTest
    static void testGetMatrixInput_decidedMatrix_ignoresLaterEntityCoefficientChange() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, 'Abylsen STRA', 900);
        input.startDate = Date.newInstance(2026, 10, 1); // session 108 : dates de matrice exigées
        input.endDate = Date.newInstance(2027, 3, 31);
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
        System.assertEquals('Validée', result.status);
        System.assertEquals(428, result.calculation.totalDailyCost);

        update new AR_PTF_Entity_Referential__c(
            Id = [SELECT Id FROM AR_PTF_Entity_Referential__c WHERE Name = 'Abylsen STRA' LIMIT 1].Id,
            AR_Coefficient__c = 1.50,
            AR_Working_Days__c = 190
        );
        // Le référentiel a bien changé : témoin, sur le même principe que le corridor dans
        // testGetMatrixInput_decidedMatrix_ignoresLaterCorridorChange ci-dessus.
        AR_PTF_Entity_Referential__c changed = [
            SELECT AR_Coefficient__c FROM AR_PTF_Entity_Referential__c WHERE Name = 'Abylsen STRA'
        ];
        System.assertEquals(1.50, changed.AR_Coefficient__c);

        Test.startTest();
        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        Test.stopTest();

        System.assertEquals(
            1.90,
            reloaded.storedResult.contractCoefficientApplied,
            'Coefficient figé au calcul d\'origine, pas le coefficient d\'entité courant'
        );
        System.assertEquals(
            200,
            reloaded.storedResult.workingDaysPerYearApplied,
            'Jours travaillés figés au calcul d\'origine, pas la valeur d\'entité courante'
        );
        System.assertEquals(428, reloaded.storedResult.totalDailyCost);
    }

    private static AR_PricingMatrixService.MatrixInput cdiInput(
        Id positionId,
        Decimal annualSalary,
        String entity,
        Decimal proposedTjm
    ) {
        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = positionId;
        input.currencyCode = 'EUR';
        input.contractType = 'CDI';
        input.annualSalary = annualSalary;
        input.entity = entity == null ? null : String.valueOf(AR_TestPersona.entityRefId(entity));
        input.feeIk = 0;
        input.feeMeals = 0;
        input.feeLodging = 0;
        input.feeOmOther = 0;
        input.gratuityDays = 0;
        input.feeComputer = 0;
        input.feeTraining = 0;
        input.feeEpi = 0;
        input.feeOfiiTax = 0;
        input.feeOther = 0;
        input.rfaPercent = 0;
        input.proposedTjm = proposedTjm;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;
        return input;
    }

    // testSaveDraftInput_cdd_administeredCoefficient_overridesDefault et
    // testGetMatrixInput_decidedCddMatrix_ignoresLaterCoefficientChange RETIRÉS (session 28,
    // incident post-livraison) : les deux testaient la surcharge du coefficient CDD par
    // AR_General_Setting__c.AR_CDD_Coefficient__c, capacité découplée tant que ce champ reste
    // inaccessible en SOQL/DML malgré suppression/redéploiement — cf.
    // docs/28-ecarts-contractuels.md. À réécrire une fois l'org débloquée et la capacité rebranchée
    // (AR_PricingMatrixService.applySettingsDefaults).

    private static AR_PricingMatrixService.MatrixInput cddInput(Id positionId, Decimal annualSalary, Decimal proposedTjm) {
        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = positionId;
        input.currencyCode = 'EUR';
        input.contractType = 'CDD';
        input.annualSalary = annualSalary;
        input.feeIk = 8;
        input.feeMeals = 12;
        input.feeLodging = 15;
        input.feeOmOther = 5;
        input.gratuityDays = 1;
        input.feeComputer = 0;
        input.feeTraining = 200;
        input.feeEpi = 50;
        input.rfaPercent = 0;
        input.proposedTjm = proposedTjm;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;
        return input;
    }

    // ------------------------------------------------------------------
    // Référentiel VIE/Nearshore incomplet : blocage explicite (session 28 §2, remplace la
    // NullPointerException technique documentée comme divergence de parité, cf. AR_PricingParityTest).
    // ------------------------------------------------------------------

    @IsTest
    static void testSaveDraftInput_vieCountryWithoutReferentialRow_throwsNamedException() {
        Account standardAccount = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin VIE Allemagne', cxsrec__Account__c = standardAccount.Id, cxsrec__Country__c = 'Allemagne',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'VIE'
        );
        insert position;

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'EUR';
        input.contractType = 'VIE';
        // cjmVie volontairement non renseigné : seul le référentiel pourrait le résoudre, et
        // "Allemagne" n'a aucune ligne dans AR_VIE_Referential__c (seule "France" existe, @TestSetup).
        input.rfaPercent = 0;
        input.proposedTjm = 300;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;

        Boolean threw = false;
        try {
            AR_PricingMatrixService.saveDraftInput(input);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Allemagne'), 'Le message doit nommer le pays en cause, pas une trace technique : ' + e.getMessage());
            System.assert(e.getMessage().contains('VIE'), e.getMessage());
        }
        System.assertEquals(true, threw, 'Un référentiel VIE manquant doit bloquer explicitement, jamais produire un coût à 0 ni planter avec une NullPointerException');
    }

    @IsTest
    static void testSaveDraftInput_nearshoreCountryWithoutReferentialRow_throwsNamedException() {
        Account standardAccount = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Nearshore Sénégal', cxsrec__Account__c = standardAccount.Id, cxsrec__Country__c = 'Sénégal',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'NEARSHORE'
        );
        insert position;

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'EUR';
        input.contractType = 'NEARSHORE';
        // "Sénégal" absent de AR_Nearshore_Referential__c (seul "Maroc" existe, @TestSetup).
        input.rfaPercent = 0;
        input.proposedTjm = 300;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;

        Boolean threw = false;
        try {
            AR_PricingMatrixService.saveDraftInput(input);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Sénégal'), e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    // testSaveDraftInput_vieNoCountryKnownAtAll_throwsGenericBlockingException RETIRÉ (session 28,
    // trouvé faux positif au premier vrai passage vert de la suite après l'incident
    // AR_General_Setting__c) : le scénario "aucun pays connu du tout" n'est pas constructible via un
    // besoin réel — cxsrec__cxsPosition__c.cxsrec__Country__c a une valeur par défaut de picklist
    // ("France", confirmé par describe) qui s'applique dès que le champ est laissé vide à l'insert,
    // et "France" a justement une ligne dans AR_VIE_Referential__c (@TestSetup) : le calcul aboutit
    // normalement, aucune exception ne peut être observée. Le garde-fou défensif
    // (calculateAndPopulate, "aucun pays connu du tout") reste dans le code pour un appelant Apex/API
    // direct qui passerait explicitement un AR_Account_Country__c vide sur un objet en mémoire — ce
    // chemin n'est simplement pas atteignable depuis saveDraftInput tant que Connexys impose ce
    // défaut. Couverture réelle de la garde "référentiel incomplet" : cf.
    // testSaveDraftInput_vieCountryWithoutReferentialRow_throwsNamedException ci-dessus.

    // ------------------------------------------------------------------
    // Séniorité (session 28 §3) : champ optionnel, persisté et transmis aux repères marché.
    // ------------------------------------------------------------------

    @IsTest
    static void testSaveDraftInput_seniorityLevel_persistedOnMatrix() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'EUR';
        input.contractType = 'CDI';
        input.annualSalary = 43600;
        input.rfaPercent = 0;
        input.proposedTjm = 500;
        input.seniorityLevel = 'Confirmed Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        AR_Price_Matrix__c saved = [SELECT AR_Seniority__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        System.assertEquals('Confirmed Consultant', saved.AR_Seniority__c);

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        System.assertEquals('Confirmed Consultant', reloaded.seniorityLevel, 'getMatrixInput doit restituer le palier pour la réédition du Brouillon');
    }

    @IsTest
    static void testGetVieReferentialOptions_returnsSeededCountries() {
        List<AR_PricingMatrixService.ReferentialCountryOption> options = AR_PricingMatrixService.getVieReferentialOptions();

        System.assertEquals(1, options.size());
        System.assertEquals('France', options[0].country);
        System.assertEquals(180, options[0].cjm);
    }

    @IsTest
    static void testGetNearshoreReferentialOptions_returnsSeededCountries() {
        List<AR_PricingMatrixService.ReferentialCountryOption> options = AR_PricingMatrixService.getNearshoreReferentialOptions();

        System.assertEquals(1, options.size());
        System.assertEquals('Maroc', options[0].country);
        System.assertEquals(200, options[0].cjm);
    }

    /** Session 18 : les 2 lookups pays doivent survivre à saveDraft et faire l'aller-retour getMatrixInput,
     * même chose que les champs mission de la session 17 (testSaveDraft_persistsMissionFields). */
    @IsTest
    static void testSaveDraft_persistsAndReloadsReferentialCountryLookups() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_Nearshore_Referential__c maroc = [SELECT Id FROM AR_Nearshore_Referential__c WHERE Name = 'Maroc' AND AR_Seniority__c = 'DEFAULT' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        input.nearshoreCountryId = maroc.Id;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        AR_Price_Matrix__c saved = [
            SELECT AR_Nearshore_Country__c, AR_VIE_Country__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(maroc.Id, saved.AR_Nearshore_Country__c);
        System.assertEquals(null, saved.AR_VIE_Country__c);

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        System.assertEquals(maroc.Id, reloaded.nearshoreCountryId);
    }

    /** Comportement attendu (session 18, prompt §3) : une surcharge manuelle du CJM après avoir
     * choisi un pays conserve le lookup — la traçabilité du pays ne doit pas se perdre. */
    @IsTest
    static void testSaveDraft_overridingCjmAfterCountrySelection_keepsLookup() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_Nearshore_Referential__c maroc = [SELECT Id FROM AR_Nearshore_Referential__c WHERE Name = 'Maroc' AND AR_Seniority__c = 'DEFAULT' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        input.nearshoreCountryId = maroc.Id;
        input.cjmNearshore = 350; // écart volontaire au référentiel (200)

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);

        AR_Price_Matrix__c saved = [
            SELECT AR_Nearshore_Country__c, AR_CJM_Nearshore__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(maroc.Id, saved.AR_Nearshore_Country__c, 'Le lookup pays doit être conservé même quand le CJM est surchargé');
        System.assertEquals(350, saved.AR_CJM_Nearshore__c);
    }

    @IsTest
    static void testGetEntityOptions_activeAdminFichesOnly_valueIsFicheId_noPicklistFilter() {
        // Session 132 : la liste d'administration est l'unique référence — une fiche dont le Nom
        // n'a jamais figuré dans l'ancien picklist est proposée, une fiche désactivée ne l'est pas.
        AR_PTF_Entity_Referential__c metz = new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN EST – Metz', AR_Active__c = true);
        AR_PTF_Entity_Referential__c inactive = new AR_PTF_Entity_Referential__c(Name = 'Fiche désactivée', AR_Active__c = false);
        insert new List<AR_PTF_Entity_Referential__c>{ metz, inactive };

        List<AR_PricingMatrixService.PicklistOption> options = AR_PricingMatrixService.getEntityOptions();

        Map<String, String> labelByValue = new Map<String, String>();
        for (AR_PricingMatrixService.PicklistOption opt : options) {
            labelByValue.put(opt.value, opt.label);
        }
        System.assertEquals('ABYLSEN EST – Metz', labelByValue.get(metz.Id), 'Une fiche absente de l\'ancien picklist doit être proposée, sous son Nom');
        System.assertEquals('Abylsen GAMMA', labelByValue.get(AR_TestPersona.entityRefId('Abylsen GAMMA')));
        System.assert(!labelByValue.containsKey(inactive.Id), 'Une fiche désactivée ne doit plus être proposable');
    }

    @IsTest
    static void testGetEntityOptions_neverCarriesPtfReadinessMarker_nonRegression() {
        // Session 47 : getEntityOptions() est aussi consommée par arAdminGeneralSettings (exceptions
        // de jours travaillés par entité), un écran SANS rapport avec la PTF — le libellé ne doit
        // jamais y porter la marque de préparation PTF, réservée à getEntityOptionsWithPtfReadiness
        // (arPriceMatrixSimulator). 'Abylsen GAMMA' (fixture, aucune coordonnée) est pourtant
        // incomplète pour tous les gabarits qui en réclament : la preuve que ce n'est pas un hasard.
        List<AR_PricingMatrixService.PicklistOption> options = AR_PricingMatrixService.getEntityOptions();
        System.assert(!options.isEmpty(), 'Le référentiel AR_PTF_Entity_Referential__c doit alimenter au moins une option');
        for (AR_PricingMatrixService.PicklistOption opt : options) {
            System.assert(
                !opt.label.contains('préparation PTF'),
                'getEntityOptions() ne doit jamais marquer un libellé : ' + opt.label
            );
        }
    }

    @IsTest
    static void testGetEntityOptionsWithPtfReadiness_labelIsEntityNameOnly() {
        // Complète ou non pour son gabarit, une entité s'affiche sous son seul Name.
        AR_PTF_Entity_Referential__c abmi = new AR_PTF_Entity_Referential__c(
            Name = 'ABMI Groupe', AR_Active__c = true, AR_Template_Code__c = 'ABMI_DQ012',
            AR_Address__c = '28 Allée d\'Aquitaine', AR_Postal_Code__c = '92000', AR_City__c = 'NANTERRE',
            AR_Phone__c = '+33 (0)1 30 79 12 79', AR_Fax__c = '+33 (0)1 30 55 82 85', AR_Website__c = 'www.abmi-groupe.com'
        );
        AR_PTF_Entity_Referential__c abylsenSansRib = new AR_PTF_Entity_Referential__c(
            Name = 'Abylsen sans RIB', AR_Active__c = true, AR_Template_Code__c = 'ABYLSEN_AT_V11'
        );
        AR_PTF_Entity_Referential__c abmiSansCoordonnees = new AR_PTF_Entity_Referential__c(
            Name = 'ABMI sans coordonnées', AR_Active__c = true, AR_Template_Code__c = 'ABMI_DQ012'
        );
        insert new List<AR_PTF_Entity_Referential__c>{ abmi, abylsenSansRib, abmiSansCoordonnees };

        Map<String, String> labelByValue = new Map<String, String>();
        for (AR_PricingMatrixService.PicklistOption opt : AR_PricingMatrixService.getEntityOptionsWithPtfReadiness()) {
            labelByValue.put(opt.value, opt.label);
            System.assert(!opt.label.contains('préparation'), 'Aucune mention de préparation : ' + opt.label);
        }
        System.assertEquals('Abylsen GAMMA', labelByValue.get(AR_TestPersona.entityRefId('Abylsen GAMMA')));
        System.assertEquals('ABMI Groupe', labelByValue.get(abmi.Id));
        System.assertEquals('Abylsen sans RIB', labelByValue.get(abylsenSansRib.Id));
        System.assertEquals('ABMI sans coordonnées', labelByValue.get(abmiSansCoordonnees.Id));
    }

    @IsTest
    static void testGetEntityOptionsWithPtfReadiness_exposesEntityCountry_blankAsNull() {
        // Session 141 : le pays de la fiche voyage avec les options (aucun appel supplémentaire) ;
        // un pays non saisi reste null — c'est l'écran qui affiche « Non renseigné », jamais un repli.
        AR_PTF_Entity_Referential__c withCountry = new AR_PTF_Entity_Referential__c(
            Name = 'S141 Belgique', AR_Active__c = true, AR_Country__c = 'Belgique'
        );
        AR_PTF_Entity_Referential__c withoutCountry = new AR_PTF_Entity_Referential__c(
            Name = 'S141 Sans pays', AR_Active__c = true, AR_Country__c = '   '
        );
        insert new List<AR_PTF_Entity_Referential__c>{ withCountry, withoutCountry };

        Map<String, String> countryByValue = new Map<String, String>();
        for (AR_PricingMatrixService.PicklistOption opt : AR_PricingMatrixService.getEntityOptionsWithPtfReadiness()) {
            countryByValue.put(opt.value, opt.country);
        }
        System.assertEquals('Belgique', countryByValue.get(withCountry.Id));
        System.assert(countryByValue.containsKey(withoutCountry.Id), 'L\'entité sans pays reste proposée');
        System.assertEquals(null, countryByValue.get(withoutCountry.Id), 'Un pays vide est exposé null, pas une chaîne d\'espaces');
    }

    @IsTest
    static void testGetEntityPricingDefaults_carriesCountry_evenForInactiveEntity_session141() {
        AR_PTF_Entity_Referential__c inactive = new AR_PTF_Entity_Referential__c(
            Name = 'S141 Inactive Italie', AR_Active__c = false, AR_Country__c = 'Italie'
        );
        insert inactive;

        AR_PricingMatrixService.EntityPricingDefaultDto found;
        for (AR_PricingMatrixService.EntityPricingDefaultDto dto : AR_PricingMatrixService.getEntityPricingDefaults()) {
            if (dto.entityId == inactive.Id) {
                found = dto;
            }
        }
        System.assertNotEquals(null, found, 'Une entité désactivée reste servie (recalcul d\'une matrice existante)');
        System.assertEquals('Italie', found.country);
    }

    @IsTest
    static void testGetEntityPricingDefaults_keyedByFicheId() {
        Id straId = AR_TestPersona.entityRefId('Abylsen STRA');
        AR_PricingMatrixService.EntityPricingDefaultDto found;
        for (AR_PricingMatrixService.EntityPricingDefaultDto dto : AR_PricingMatrixService.getEntityPricingDefaults()) {
            if (dto.entityId == straId) {
                found = dto;
            }
        }
        System.assertNotEquals(null, found, 'Le coefficient d\'entité doit être servi par Id de fiche');
        System.assertEquals('Abylsen STRA', found.entityName);
        System.assertEquals(1.90, found.coefficient);
        System.assertEquals(200, found.workingDays);
    }

    /**
     * Session 132 : l'entité n'est JAMAIS pré-remplie, même quand la fiche consultant porte une
     * société. Le champ source n'est écrit que dynamiquement (le garde-fou
     * scripts/check-no-picklist-entity.js interdit sa mention directe dans classes/).
     */
    @IsTest
    static void testGetConsultantContext_neverPrefillsEntity_evenWhenConsultantHasACompany() {
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName()
            .get('Consultant')
            .getRecordTypeId();
        cxsrec__cxsCandidate__c withCompany = new cxsrec__cxsCandidate__c(
            RecordTypeId = consultantRecordTypeId,
            cxsrec__First_name__c = 'Clara',
            cxsrec__Last_name__c = 'ENTITE',
            TP_Seniority__c = 'Confirmed Consultant',
            TP_Type_de_contrat__c = 'CDI'
        );
        withCompany.put('TP_Abylsen_' + 'Company__c', 'Abylsen SIGMA');
        insert withCompany;

        AR_PricingMatrixService.ConsultantContext ctx = AR_PricingMatrixService.getConsultantContext(withCompany.Id);

        System.assert(!ctx.filled.contains('entity'), 'L\'entité ne doit jamais figurer parmi les champs pré-remplis');
        System.assert(!ctx.unreadable.contains('entity'), 'Plus aucune mention de l\'entité dans le contexte consultant');
        System.assert(!ctx.sourceEmpty.contains('entity'));
        System.assertEquals(2, ctx.filled.size(), 'Seuls le contrat et la séniorité restent pré-remplis');
    }

    @IsTest
    static void testSaveDraftInput_ficheAbsentFromOldPicklist_savesReloadsAndUsesItsOwnCoefficient() {
        // « ABYLSEN EST – Metz » : Nom absent de l'ancienne liste d'entités à choix.
        AR_PTF_Entity_Referential__c metz = new AR_PTF_Entity_Referential__c(
            Name = 'ABYLSEN EST – Metz', AR_Active__c = true, AR_Coefficient__c = 1.80, AR_Working_Days__c = 210
        );
        insert metz;
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, 'ABYLSEN EST – Metz', 900);

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);

        System.assertEquals(1.80, result.calculation.contractCoefficientApplied, 'Coefficient de CETTE fiche');
        System.assertEquals(210, result.calculation.workingDaysPerYearApplied);
        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(result.matrixId);
        System.assertEquals(String.valueOf(metz.Id), reloaded.entity);
        System.assertEquals('ABYLSEN EST – Metz', reloaded.entityName);
    }

    @IsTest
    static void testSaveDraftInput_twoFichesDifferingOnlyByCase_eachMatrixKeepsItsOwn() {
        // SOQL compare sans tenir compte de la casse : « Abylsen GAMMA » (fixture) et
        // « ABYLSEN GAMMA » ne doivent jamais se confondre (piège N2 du suivi client).
        AR_PTF_Entity_Referential__c upper = new AR_PTF_Entity_Referential__c(
            Name = 'ABYLSEN GAMMA', AR_Active__c = true, AR_Coefficient__c = 1.70, AR_Working_Days__c = 190
        );
        insert upper;
        Id lowerId = AR_TestPersona.entityRefId('Abylsen GAMMA');
        System.assertNotEquals(upper.Id, lowerId, 'Deux fiches distinctes');
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        AR_PricingMatrixService.MatrixInput inputUpper = cdiInput(position.Id, 45000, 'Abylsen GAMMA', 900);
        inputUpper.entity = String.valueOf(upper.Id);
        AR_PricingMatrixService.MatrixSaveResult resultUpper = AR_PricingMatrixService.saveDraftInput(inputUpper);
        AR_PricingMatrixService.MatrixSaveResult resultLower = AR_PricingMatrixService.saveDraftInput(
            cdiInput(position.Id, 45000, 'Abylsen GAMMA', 900)
        );

        System.assertEquals(1.70, resultUpper.calculation.contractCoefficientApplied);
        System.assertEquals(190, resultUpper.calculation.workingDaysPerYearApplied);
        System.assertEquals(2.02, resultLower.calculation.contractCoefficientApplied, 'La fiche sans surcharge garde le coefficient moteur');
        System.assertEquals(218, resultLower.calculation.workingDaysPerYearApplied);
        System.assertEquals('ABYLSEN GAMMA', AR_PricingMatrixService.getMatrixInput(resultUpper.matrixId).entityName);
        System.assertEquals('Abylsen GAMMA', AR_PricingMatrixService.getMatrixInput(resultLower.matrixId).entityName);
    }

    @IsTest
    static void testGetCurrentUserName_returnsRunningUserName() {
        System.assertEquals(UserInfo.getName(), AR_PricingMatrixService.getCurrentUserName());
    }

    @IsTest
    static void testGetRecentDraftForCurrentUser_returnsMostRecentBrouillon() {
        // Les Brouillons du @TestSetup partagent potentiellement le même LastModifiedDate (résolution de
        // l'horloge de test) que celui créé ici : un ORDER BY LastModifiedDate DESC LIMIT 1 serait alors
        // non déterministe entre eux. On les bascule hors "Brouillon" pour isoler un candidat unique.
        List<AR_Price_Matrix__c> existingDrafts = [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c WHERE AR_Status__c = 'Brouillon'];
        for (AR_Price_Matrix__c m : existingDrafts) {
            m.AR_Status__c = 'Refusée';
        }
        update existingDrafts;

        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_Price_Matrix__c freshDraft = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Account_Name__c = 'Client Standard',
            AR_Contract_Type__c = 'CDI',
            AR_Annual_Salary__c = 40000
        );
        insert freshDraft; // AR_Status__c défaut du picklist = Brouillon

        AR_PricingMatrixService.DraftResumeInfo info = AR_PricingMatrixService.getRecentDraftForCurrentUser();

        System.assertNotEquals(null, info);
        System.assertEquals(freshDraft.Id, info.matrixId);
        System.assertEquals('Client Standard', info.accountName);
    }

    @IsTest
    static void testGetRecentDraftForCurrentUser_noBrouillonForUser_returnsNull() {
        List<AR_Price_Matrix__c> allDrafts = [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c WHERE AR_Status__c = 'Brouillon'];
        for (AR_Price_Matrix__c m : allDrafts) {
            m.AR_Status__c = 'Refusée';
        }
        update allDrafts;

        System.assertEquals(null, AR_PricingMatrixService.getRecentDraftForCurrentUser());
    }

    @IsTest
    static void testGetAccountCorridorPercents_returnsOverrideOrNull() {
        Account corridorAccount = [SELECT Id FROM Account WHERE Name = 'Grand Compte Corridor' LIMIT 1];
        Account standardAccount = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];

        AR_PricingMatrixService.ThresholdPercentsDto corridorDto = AR_PricingMatrixService.getAccountCorridorPercents(corridorAccount.Id, null);
        System.assertEquals(5, corridorDto.floorPercent);

        System.assertEquals(null, AR_PricingMatrixService.getAccountCorridorPercents(standardAccount.Id, null));
    }

    @IsTest
    static void testGetPricingSettings_returnsSeededDefaults() {
        AR_PricingMatrixService.PricingSettingsDto settings = AR_PricingMatrixService.getPricingSettings();

        System.assertEquals(218, settings.workingDaysPerYear);
        System.assertEquals(18, settings.markupPercent);
        System.assertEquals(60, settings.markupMax);
        System.assertEquals(20, settings.floorPercentDefault);
    }

    @IsTest
    static void testSaveDraft_createsNewDraft_denormalizesZone1() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertNotEquals(null, result.matrixId);
        System.assertEquals('Brouillon', result.status);
        System.assertEquals(200, result.calculation.cjm);

        AR_Price_Matrix__c saved = [
            SELECT AR_Status__c, AR_Position_Name__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals('Brouillon', saved.AR_Status__c);
        System.assertEquals('Besoin Nearshore', saved.AR_Position_Name__c);
    }

    /** Zone 1 (session 17) : les 6 nouveaux champs mission doivent survivre à saveDraft, pas seulement
     * les champs financiers déjà couverts par testSaveDraft_createsNewDraft_denormalizesZone1. */
    @IsTest
    static void testSaveDraft_persistsMissionFields() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        AR_Price_Matrix__c saved = [
            SELECT AR_Entity_Ref__c, AR_Consultant_Name__c, AR_Consultant__c, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c, AR_Number_Of_Days__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(AR_TestPersona.entityRefId('Abylsen GAMMA'), saved.AR_Entity_Ref__c);
        // Session 54 : consultantId (Lookup) est désormais le champ persisté ; AR_Consultant_Name__c
        // (texte libre) n'est plus écrit du tout par une nouvelle matrice, cf.
        // testSaveDraft_neverWritesLegacyConsultantText pour la garantie sur une matrice qui le portait déjà.
        System.assertEquals(consultantId('MARTIN'), saved.AR_Consultant__c);
        System.assertEquals(null, saved.AR_Consultant_Name__c);
        System.assertEquals('Paris La Défense', saved.AR_Client_Site__c);
        System.assertEquals(Date.newInstance(2026, 9, 1), saved.AR_Start_Date__c);
        System.assertEquals(Date.newInstance(2026, 9, 30), saved.AR_End_Date__c);
        System.assertEquals(22, saved.AR_Number_Of_Days__c);
    }

    @IsTest
    static void testSaveDraft_secondCallOnSameMatrix_updatesInPlace() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        AR_PricingMatrixService.MatrixSaveResult first = AR_PricingMatrixService.saveDraftInput(input);

        input.matrixId = first.matrixId;
        input.proposedTjm = 450;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult second = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertEquals(first.matrixId, second.matrixId);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :first.matrixId]);
    }

    /**
     * Régression session 28b §1 : `buildMatrixFromInput` ne réassigne jamais AR_Status__c pour un
     * enregistrement existant (seul un champ saisi), donc `m.AR_Status__c` valait null sur cette
     * resauvegarde avant le correctif — le composant recevait alors un statut `undefined` et se
     * verrouillait. Ce test aurait échoué sur le code d'avant cette session (`second.status` était
     * null) ; il reste vert après le correctif qui requête AR_Status__c pour tout enregistrement
     * existant.
     */
    @IsTest
    static void testSaveDraftInput_existingDraftResaved_returnsRealStatusNotNull() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        AR_PricingMatrixService.MatrixSaveResult first = AR_PricingMatrixService.saveDraftInput(input);

        input.matrixId = first.matrixId;
        input.proposedTjm = 450;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult second = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertEquals('Brouillon', second.status, 'Le DTO de resauvegarde d\'un Brouillon existant doit porter le statut réel, jamais null');
    }

    @IsTest
    static void testValidate_aboveFloor_setsValidatedAndSnapshots() {
        // coût 200 (CJM nearshore seul, pas de frais) ; TJM 400 → MC2 200/jour, MC2 % 50 % ⇒ superstar (≥ plancher)
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);
        Test.stopTest();

        System.assertEquals('Validée', result.status);
        AR_Price_Matrix__c saved = [
            SELECT AR_Status__c, AR_Validated_At__c, AR_Version_Number__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals('Validée', saved.AR_Status__c);
        System.assertNotEquals(null, saved.AR_Validated_At__c);
        System.assertEquals(1, saved.AR_Version_Number__c);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :result.matrixId]);
    }

    @IsTest
    static void testValidate_thenDirectEdit_isBlockedByTrigger() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(input);

        Boolean threw = false;
        try {
            update new AR_Price_Matrix__c(Id = result.matrixId, AR_Proposed_TJM__c = 999);
        } catch (DmlException e) {
            threw = true;
        }
        System.assert(threw, 'AR_PriceMatrixTrigger doit bloquer toute édition directe d\'une matrice Validée');
    }

    @IsTest
    static void testValidate_aboveFloor_sendsAutoValidationEmail() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);

        // Test.startTest() réinitialise les limites de gouverneur : la baseline doit être mesurée
        // à l'intérieur du bloc startTest/stopTest, jamais avant, sous peine de comparer deux contextes distincts.
        Test.startTest();
        AR_PricingMatrixService.validateInput(input);
        System.assert(Limits.getEmailInvocations() > 0, 'La validation automatique doit envoyer un email au propriétaire');
        Test.stopTest();
    }

    @IsTest
    static void testValidate_belowFloor_throwsAndLeavesMatrixUnvalidated() {
        // coût 200 ; TJM 205 → MC2 5/jour, MC2 % 2.44 % ⇒ below_floor
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 205);

        Test.startTest();
        Boolean threw = false;
        try {
            AR_PricingMatrixService.validateInput(input);
        } catch (AuraHandledException e) {
            threw = true;
            System.assertEquals(Label.AR_Msg_PM_BelowFloorNeedsDerogation, e.getMessage(), 'Le message doit orienter vers la dérogation');
        }
        Test.stopTest();

        System.assert(threw, 'validate() doit rejeter une matrice sous le plancher');
    }

    @IsTest
    static void testValidate_missingSeniority_throwsAndNamesSeniorityField() {
        System.runAs(AR_TestPersona.francais()) {
            cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
            AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 60000, null, 800);
            input.startDate = Date.newInstance(2026, 10, 1);
            input.endDate = Date.newInstance(2027, 10, 1);
            input.clientSite = 'Paris';
            input.clientGrid = true;
            input.seniorityLevel = null;

            Test.startTest();
            Boolean threw = false;
            String message = '';
            try {
                AR_PricingMatrixService.validateInput(input);
            } catch (AuraHandledException e) {
                threw = true;
                message = e.getMessage();
            }
            Test.stopTest();

            System.assert(threw, 'validate() doit rejeter une matrice sans séniorité');
            System.assert(message.contains('Séniorité'), 'Le message doit nommer le champ « Séniorité »');
        }
    }

    @IsTest
    static void testValidate_missingClientSite_throwsAndNamesClientSiteField() {
        System.runAs(AR_TestPersona.francais()) {
            cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
            AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 60000, null, 800);
            input.startDate = Date.newInstance(2026, 10, 1);
            input.endDate = Date.newInstance(2027, 10, 1);
            input.seniorityLevel = 'Senior Consultant';
            input.clientSite = null;

            Test.startTest();
            Boolean threw = false;
            String message = '';
            try {
                AR_PricingMatrixService.validateInput(input);
            } catch (AuraHandledException e) {
                threw = true;
                message = e.getMessage();
            }
            Test.stopTest();

            System.assert(threw, 'validate() doit rejeter une matrice sans site client');
            System.assert(message.contains('Site client'), 'Le message doit nommer le champ « Site client »');
        }
    }

    @IsTest
    static void testSaveDraft_missingSeniority_acceptsAndSavesDraft() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 60000, null, 800);
        input.startDate = Date.newInstance(2026, 10, 1);
        input.endDate = Date.newInstance(2027, 10, 1);
        input.clientSite = 'Paris';
        input.clientGrid = true;
        // seniorityLevel left null intentionally

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertNotEquals(null, result.matrixId, 'saveDraft() doit accepter et sauvegarder un brouillon sans séniorité');
        System.assertEquals('Brouillon', result.status, 'Le statut doit être Brouillon');
    }

    @IsTest
    static void testSaveDraft_missingClientSite_acceptsAndSavesDraft() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 60000, null, 800);
        input.startDate = Date.newInstance(2026, 10, 1);
        input.endDate = Date.newInstance(2027, 10, 1);
        input.seniorityLevel = 'Senior Consultant';
        // clientSite left null intentionally

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        System.assertNotEquals(null, result.matrixId, 'saveDraft() doit accepter et sauvegarder un brouillon sans site client');
        System.assertEquals('Brouillon', result.status, 'Le statut doit être Brouillon');
    }

    @IsTest
    static void testRequestDerogation_success_setsStatusAndCreatesRecord() {
        // Session 119h : pas de persona ici (licence, partage et FLS Connexys masquaient chacun le
        // suivant). On garde l'utilisateur exécutant, comme avant la 119d, et on lui donne un DA :
        // c'est tout ce qu'exige verifyCreatorHasValidatorChain. runAs(self) isole le DML sur User.
        Id currentUserId = UserInfo.getUserId();
        User daUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :currentUserId LIMIT 1];
        System.runAs(new User(Id = currentUserId)) {
            update new User(Id = currentUserId, TP_DA__c = daUser.Id);
        }
        cxsrec__cxsPosition__c position = [SELECT Id, cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;

        Id validatorId = daUser.Id;

        Test.startTest();
        // Input construit hors du bloc de test.
        AR_PricingMatrixService.MatrixInput successInput = nearshoreInput(position.Id, 205);
        {
            AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
            req.matrixInput = successInput;
            req.reason = 'Contexte concurrentiel tendu';
            req.derogationReasonIds = new List<Id>{ reasonId };
            req.selectedValidatorId = validatorId;

            AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.requestDerogationInput(req);
            System.assert(Limits.getEmailInvocations() > 0, 'La demande de dérogation doit envoyer un email au valideur sélectionné');

            System.assertEquals('En dérogation', result.status);
            AR_Price_Matrix__c saved = [
                SELECT AR_Status__c, AR_Derogation_Reason__c
                FROM AR_Price_Matrix__c
                WHERE Id = :result.matrixId
            ];
            System.assertEquals('En dérogation', saved.AR_Status__c);
            System.assertEquals('Contexte concurrentiel tendu', saved.AR_Derogation_Reason__c, 'Le texte libre reste un complément persisté');

            AR_Derogation__c derogation = [
                SELECT AR_Decision__c
                FROM AR_Derogation__c
                WHERE AR_Price_Matrix__c = :result.matrixId
            ];
            System.assertEquals('En attente', derogation.AR_Decision__c);

            List<AR_Reason_Selection__c> selections = [
                SELECT AR_Reason__c, AR_Derogation__c, AR_Price_Matrix__c
                FROM AR_Reason_Selection__c
                WHERE AR_Derogation__c = :derogation.Id
            ];
            System.assertEquals(1, selections.size(), 'Le motif standardisé sélectionné doit être enregistré');
            System.assertEquals(reasonId, selections[0].AR_Reason__c);
            System.assertEquals(null, selections[0].AR_Price_Matrix__c, 'XOR : jamais les deux lookups parent renseignés');
        }
        Test.stopTest();
    }

    /**
     * Session 132, scénario Matthieu : une matrice sur « ABYLSEN EST – Metz » (Nom absent de l'ancien
     * picklist, jusque-là insauvegardable) se sauvegarde puis demande une dérogation ; l'entité
     * stockée est bien le lookup vers cette fiche.
     */
    @IsTest
    static void testRequestDerogation_ficheAbsentFromOldPicklist_savesThenRequestsDerogation() {
        Id currentUserId = UserInfo.getUserId();
        User daUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :currentUserId LIMIT 1];
        System.runAs(new User(Id = currentUserId)) {
            update new User(Id = currentUserId, TP_DA__c = daUser.Id);
        }
        AR_PTF_Entity_Referential__c metz = new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN EST – Metz', AR_Active__c = true);
        insert metz;
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;

        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 205);
        input.entity = String.valueOf(metz.Id);
        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(input);
        System.assertEquals('Brouillon', draft.status);

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(draft.matrixId);
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = reloaded;
        req.reason = 'Contexte concurrentiel tendu';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = daUser.Id;
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.requestDerogationInput(req);

        System.assertEquals('En dérogation', result.status);
        AR_Price_Matrix__c saved = [SELECT AR_Entity_Ref__c, AR_Entity_Ref__r.Name FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        System.assertEquals(metz.Id, saved.AR_Entity_Ref__c);
        System.assertEquals('ABYLSEN EST – Metz', saved.AR_Entity_Ref__r.Name);
    }

    /**
     * Décision client du 10/08/2026 : fin de la saisie libre comme SEUL motif. Un texte libre
     * rempli ne suffit plus — la sélection de motif(s) standardisés est désormais ce qui gate la
     * demande, le texte libre n'étant qu'un complément (commentaire obligatoire depuis la session 220).
     */
    @IsTest
    static void testRequestDerogation_noStandardizedReasonSelected_throwsEvenWithFreeText() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = nearshoreInput(position.Id, 205);
        req.reason = 'Un texte libre bien rempli, mais aucun motif standardisé sélectionné';
        req.derogationReasonIds = new List<Id>();
        req.selectedValidatorId = UserInfo.getUserId();

        Boolean threw = false;
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Au moins un motif standardisé est obligatoire, le texte libre seul ne suffit plus');
    }

    /**
     * Session 220 : le commentaire est obligatoire, même pour un motif standardisé valide. Persona
     * BM (AR_Pricing_User seul), comme l'utilisateur réel : le rejet a lieu avant tout DML.
     */
    @IsTest
    static void testRequestDerogation_emptyComment_throwsNamedLabelForNonAdmin() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = nearshoreInput(position.Id, 205);
        req.reason = '';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = UserInfo.getUserId();

        User persona = AR_TestPersona.bm();
        Boolean threw = false;
        System.runAs(persona) {
            try {
                AR_PricingMatrixService.requestDerogationInput(req);
            } catch (AuraHandledException e) {
                threw = true;
                System.assertEquals(Label.AR_Msg_PM_DerogationCommentRequired, e.getMessage());
            }
        }
        System.assert(threw, 'Une demande de dérogation sans commentaire doit être rejetée');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c = :position.Id],
            'Aucune matrice ne doit être écrite quand le rejet a lieu'
        );
    }

    /** Session 220 : des espaces seuls sont un commentaire vide. */
    @IsTest
    static void testRequestDerogation_whitespaceOnlyComment_throws() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = nearshoreInput(position.Id, 205);
        req.reason = '   \n\t ';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = UserInfo.getUserId();

        Boolean threw = false;
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            threw = true;
            System.assertEquals(Label.AR_Msg_PM_DerogationCommentRequired, e.getMessage());
        }
        System.assert(threw, 'Un commentaire fait d\'espaces seuls doit être rejeté');
    }

    /**
     * Session 29c §2 : confirme que le champ AR_Derogation__c.AR_Selected_Validator__c null n'est
     * pas atteignable depuis l'interface — la garde existe déjà (requestDerogationInput), ce test la
     * couvre explicitement pour qu'une régression future soit détectée. La branche « valideur
     * absent » d'AR_DerogationReminderBatch doit servir au vrai cas (le valideur a quitté
     * l'entreprise), jamais à rattraper une saisie incomplète.
     */
    @IsTest
    static void testRequestDerogation_noValidatorSelected_throws() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = nearshoreInput(position.Id, 205);
        req.reason = 'Motif';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = null;

        Boolean threw = false;
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            threw = true;
            System.assertEquals(Label.AR_Msg_PM_ValidatorRequired, e.getMessage());
        }
        System.assert(threw, 'Une demande de dérogation sans valideur sélectionné doit être rejetée');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Derogation__c WHERE AR_Price_Matrix__r.AR_Position__c = :position.Id],
            'Aucune dérogation ne doit être créée quand le rejet a lieu'
        );
    }

    @IsTest
    static void testRequestDerogation_duplicatePending_throws() {
        // Session 119h : pas de persona ici (licence, partage et FLS Connexys masquaient chacun le
        // suivant). On garde l'utilisateur exécutant, comme avant la 119d, et on lui donne un DA :
        // c'est tout ce qu'exige verifyCreatorHasValidatorChain. runAs(self) isole le DML sur User.
        Id currentUserId = UserInfo.getUserId();
        User daUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :currentUserId LIMIT 1];
        System.runAs(new User(Id = currentUserId)) {
            update new User(Id = currentUserId, TP_DA__c = daUser.Id);
        }
        cxsrec__cxsPosition__c position = [SELECT Id, cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;

        Id validatorId = daUser.Id;

        Test.startTest();
        // Inputs construits hors du bloc de test.
        AR_PricingMatrixService.MatrixInput firstInput = nearshoreInput(position.Id, 205);
        AR_PricingMatrixService.MatrixInput secondInput = nearshoreInput(position.Id, 205);
        {
            AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
            req.matrixInput = firstInput;
            req.reason = 'Premier motif';
            req.derogationReasonIds = new List<Id>{ reasonId };
            req.selectedValidatorId = validatorId;
            AR_PricingMatrixService.MatrixSaveResult first = AR_PricingMatrixService.requestDerogationInput(req);

            AR_PricingMatrixService.DerogationRequest secondReq = new AR_PricingMatrixService.DerogationRequest();
            secondInput.matrixId = first.matrixId;
            secondReq.matrixInput = secondInput;
            secondReq.reason = 'Second motif';
            secondReq.derogationReasonIds = new List<Id>{ reasonId };
            secondReq.selectedValidatorId = validatorId;

            Boolean threw = false;
            try {
                AR_PricingMatrixService.requestDerogationInput(secondReq);
            } catch (AuraHandledException e) {
                threw = true;
            }

            System.assert(threw, 'Une seule dérogation En attente autorisée par matrice');
        }
        Test.stopTest();
    }

    /**
     * Façade JSON (10/08/2026) : c'est le seul chemin réellement emprunté par le LWC depuis que les
     * paramètres de type classe wrapper arrivent vides côté Aura. Ce test garde l'aller-retour
     * JSON.serialize → JSON.deserialize sous contrôle, en particulier les types non triviaux
     * (Id, Date, Decimal) qui sont ceux qui cassent silencieusement en cas de régression.
     */
    @IsTest
    static void testSaveDraft_jsonFacade_deserializesAllFieldTypes() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraft(JSON.serialize(input));
        Test.stopTest();

        System.assertNotEquals(null, result.matrixId, 'La façade JSON doit créer la matrice');

        AR_Price_Matrix__c saved = [
            SELECT AR_Position__c, AR_Contract_Type__c, AR_Proposed_TJM__c, AR_Start_Date__c, AR_Client_Site__c, AR_Consultant__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(position.Id, saved.AR_Position__c, 'Id : le besoin doit survivre à la sérialisation');
        System.assertEquals('NEARSHORE', saved.AR_Contract_Type__c);
        System.assertEquals(400, saved.AR_Proposed_TJM__c, 'Decimal');
        System.assertEquals(Date.newInstance(2026, 9, 1), saved.AR_Start_Date__c, 'Date');
        System.assertEquals('Paris La Défense', saved.AR_Client_Site__c, 'String');
        // Session 54 : consultantId (Id, via MatrixInput) doit lui aussi survivre à la sérialisation JSON.
        System.assertEquals(consultantId('MARTIN'), saved.AR_Consultant__c, 'Id (lookup consultant)');
    }

    @IsTest
    static void testSaveDraft_jsonFacade_rejectsBlankPayload() {
        Boolean threw = false;
        try {
            AR_PricingMatrixService.saveDraft('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Un payload vide doit produire un message actionnable, pas une erreur Apex interne');
    }

    // ------------------------------------------------------------------
    // Socle multi-devises (session 24). "Besoin Nearshore" (positions[2] du @TestSetup) n'a aucune
    // matrice en base : terrain neutre pour ces tests, sans perturber les autres.
    // ------------------------------------------------------------------

    @IsTest
    static void testSaveDraftInput_gbpMatrix_freezesRateAndComputesEurEquivalents() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(position.Id, 400, 'GBP')
        );
        Test.stopTest();

        // Calcul natif intégralement en GBP (CLAUDE.md) : coût 200, MC2/jour 200, MC2% 50 — jamais convertis.
        System.assertEquals(200, result.calculation.totalDailyCost, 'Le calcul natif reste en GBP, jamais converti');
        System.assertEquals(1.17, result.calculation.currencyRateApplied);
        System.assertEquals(468.00, result.calculation.tjmEurEquivalent, '400 × 1.17');
        System.assertEquals(234.00, result.calculation.totalDailyCostEurEquivalent, '200 × 1.17');
        System.assertEquals(234.00, result.calculation.mc2PerDayEurEquivalent, '200.0 × 1.17');

        AR_Price_Matrix__c reloaded = [
            SELECT AR_Currency_Rate_Applied__c, AR_Currency_Rate_Effective_Date__c, AR_TJM_EUR_Equivalent__c,
                   AR_Total_Daily_Cost_EUR_Equivalent__c, AR_MC2_Per_Day_EUR_Equivalent__c, AR_Total_Daily_Cost__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(200, reloaded.AR_Total_Daily_Cost__c, 'Champ natif intact');
        System.assertEquals(1.17, reloaded.AR_Currency_Rate_Applied__c);
        System.assertEquals(Date.today().addDays(-1), reloaded.AR_Currency_Rate_Effective_Date__c);
        System.assertEquals(468.00, reloaded.AR_TJM_EUR_Equivalent__c);
        System.assertEquals(234.00, reloaded.AR_Total_Daily_Cost_EUR_Equivalent__c);
        System.assertEquals(234.00, reloaded.AR_MC2_Per_Day_EUR_Equivalent__c);
    }

    /**
     * Le test qui manquait sur les corridors, transposé au taux de change (prompt session 24) :
     * modifier le taux après décision ne doit rien changer à la matrice déjà validée — même
     * garantie, même mécanisme (verrou post-décision) que testGetMatrixInput_decidedMatrix_ignoresLaterCorridorChange.
     */
    @IsTest
    static void testValidateInput_gbpMatrix_rateFrozenAfterAdminChangesRateLater() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(
            nearshoreInput(position.Id, 400, 'GBP')
        );
        System.assertEquals('Validée', validated.status);

        // L'administrateur met le taux à jour APRÈS la décision (nouvelle ligne, jamais de réécriture).
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.30,
            AR_Effective_Date__c = Date.today()
        );
        // Témoin : le taux courant a bien changé (sinon le test ne prouverait rien).
        System.assertEquals(
            1.30,
            AR_CurrencyRateService.resolveRate('GBP', Date.today()).rateToEur
        );

        Test.startTest();
        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(validated.matrixId);
        Test.stopTest();

        System.assertEquals(1.17, input.storedResult.currencyRateApplied, 'Taux figé à la décision, pas le taux courant');
        System.assertEquals(Date.today().addDays(-1), input.currencyRateEffectiveDate);
        System.assertEquals(468.00, input.storedResult.tjmEurEquivalent, 'Équivalent EUR figé lui aussi (400 × 1.17, pas × 1.30)');
    }

    /**
     * Session 50 : preuve de non-rétroactivité symétrique à celle ci-dessus, mais pour le geste
     * introduit cette session — une CORRECTION en place (AR_AdminCommercialService.updateCurrencyRate,
     * même ligne, même devise, même date d'effet), pas un ajout de ligne. La garantie tient pour la
     * même raison que ci-dessus : le taux gelé sur la matrice (AR_Currency_Rate_Applied__c) ne
     * dépend jamais de l'état ultérieur de la table AR_Currency_Rate__c, que cet état change par un
     * ajout ou par une réécriture en place.
     */
    @IsTest
    static void testValidateInput_gbpMatrix_rateFrozenAfterAdminCorrectsRateInPlace() {
        User adminDevises = AR_TestPersona.adminDevises();
        Id rateId;
        System.runAs(adminDevises) {
            rateId = AR_AdminCommercialService.addCurrencyRate('GBP', 1.17, Date.today().addDays(-1));
        }
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(
            nearshoreInput(position.Id, 400, 'GBP')
        );
        System.assertEquals('Validée', validated.status);

        // L'administrateur CORRIGE la ligne existante (même devise, même date d'effet) après la
        // décision — pas un ajout : c'est précisément le geste que ce test doit distinguer du
        // précédent.
        System.runAs(adminDevises) {
            AR_AdminCommercialService.updateCurrencyRate(rateId, 1.30);
        }
        // Témoin : le taux courant a bien changé (sinon le test ne prouverait rien).
        System.assertEquals(
            1.30,
            AR_CurrencyRateService.resolveRate('GBP', Date.today()).rateToEur
        );
        System.assertEquals(1, [SELECT COUNT() FROM AR_Currency_Rate__c WHERE AR_Currency_Code__c = 'GBP'], 'Une correction ne crée jamais de nouvelle ligne');

        Test.startTest();
        AR_PricingMatrixService.MatrixInput input = AR_PricingMatrixService.getMatrixInput(validated.matrixId);
        Test.stopTest();

        System.assertEquals(
            1.17,
            input.storedResult.currencyRateApplied,
            'Taux figé à la décision : une correction en place de la ligne d\'origine ne doit pas l\'altérer rétroactivement'
        );
        System.assertEquals(Date.today().addDays(-1), input.currencyRateEffectiveDate);
        System.assertEquals(468.00, input.storedResult.tjmEurEquivalent, 'Équivalent EUR figé lui aussi (400 × 1.17, pas × 1.30)');
    }

    /**
     * Session 50, comportement inverse — VOULU, pas une régression (docs/50-taux-modifiables.md) :
     * tant que la matrice reste en Brouillon, calculateAndPopulate rappelle resolveRate à chaque
     * sauvegarde (AR_CurrencyRateService, en-tête). Une correction de taux doit donc bien se
     * répercuter sur un Brouillon existant à la sauvegarde suivante — seule une matrice déjà
     * décidée est protégée par le gel.
     */
    @IsTest
    static void testSaveDraftInput_gbpDraftMatrix_picksUpCorrectedRateAtNextSave() {
        User adminDevises = AR_TestPersona.adminDevises();
        Id rateId;
        System.runAs(adminDevises) {
            rateId = AR_AdminCommercialService.addCurrencyRate('GBP', 1.17, Date.today().addDays(-1));
        }
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixInput draftInput = nearshoreInput(position.Id, 400, 'GBP');
        AR_PricingMatrixService.MatrixSaveResult firstSave = AR_PricingMatrixService.saveDraftInput(draftInput);
        System.assertEquals('Brouillon', firstSave.status);
        System.assertEquals(1.17, firstSave.calculation.currencyRateApplied);

        // Correction du taux pendant que la matrice reste en Brouillon (aucune décision prise).
        System.runAs(adminDevises) {
            AR_AdminCommercialService.updateCurrencyRate(rateId, 1.30);
        }

        Test.startTest();
        draftInput.matrixId = firstSave.matrixId;
        AR_PricingMatrixService.MatrixSaveResult secondSave = AR_PricingMatrixService.saveDraftInput(draftInput);
        Test.stopTest();

        System.assertEquals(
            1.30,
            secondSave.calculation.currencyRateApplied,
            'Comportement voulu, pas une régression : un Brouillon reprend la valeur corrigée à la sauvegarde suivante'
        );
        System.assertEquals(520.00, secondSave.calculation.tjmEurEquivalent, '400 × 1.30');
    }

    @IsTest
    static void testSaveDraftInput_madMatrix_fullPipelineWithEurEquivalents() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'MAD',
            AR_Rate_To_EUR__c = 0.09,
            AR_Effective_Date__c = Date.today().addDays(-30)
        );
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(position.Id, 400, 'MAD')
        );

        System.assertEquals(200, result.calculation.totalDailyCost, 'Calcul natif en MAD, chiffre identique à EUR/GBP (même CJM)');
        System.assertEquals(0.09, result.calculation.currencyRateApplied);
        System.assertEquals(36.00, result.calculation.tjmEurEquivalent, '400 × 0.09');
        System.assertEquals(18.00, result.calculation.totalDailyCostEurEquivalent, '200 × 0.09');
        System.assertEquals(18.00, result.calculation.mc2PerDayEurEquivalent, '200.0 × 0.09');
    }

    /**
     * Le point critique de la session (prompt §"Et s'il n'y a pas de taux") : bloque le calcul,
     * n'écrit jamais la matrice avec un taux fictif de 1 — un facteur 1 à 12 sur le dirham resterait
     * invisible à l'écran sinon.
     */
    @IsTest
    static void testSaveDraftInput_currencyWithoutAnyRate_throwsAndNeverPersistsSilentDefault() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        // Aucun AR_Currency_Rate__c pour MAD n'est inséré dans ce test.

        Boolean threw = false;
        Test.startTest();
        try {
            AR_PricingMatrixService.saveDraftInput(nearshoreInput(position.Id, 400, 'MAD'));
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('MAD'), 'Message actionnable nommant la devise en cause');
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Une devise sans taux doit bloquer le calcul, jamais retomber sur 1');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c = :position.Id],
            'Aucune matrice ne doit être créée avec un taux fictif'
        );
    }

    /**
     * Référentiel VIE dans une devise différente de celle de la matrice : le moteur ne convertit
     * jamais (CLAUDE.md), donc ce cas doit bloquer bruyamment plutôt que de mélanger silencieusement
     * une indemnité EUR dans un calcul GBP.
     */
    @IsTest
    static void testSaveDraftInput_vieReferentialCurrencyMismatch_throwsExplicitException() {
        // AR_VIE_Referential__c "France" du @TestSetup n'a pas de devise explicite → traité comme EUR.
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin VIE' LIMIT 1];

        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = position.Id;
        input.currencyCode = 'GBP';
        input.contractType = 'VIE';
        // cjmVie volontairement non renseigné : doit se résoudre via le référentiel EUR "France".
        input.rfaPercent = 0;
        input.proposedTjm = 300;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;

        Boolean threw = false;
        try {
            AR_PricingMatrixService.saveDraftInput(input);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('VIE'), 'Message doit nommer le référentiel en cause');
            System.assert(e.getMessage().contains('EUR') && e.getMessage().contains('GBP'), 'Message doit nommer les deux devises en conflit');
        }
        System.assertEquals(true, threw, 'Un référentiel dans une autre devise que la matrice doit bloquer, jamais être mélangé silencieusement');
    }

    /**
     * Non-régression EUR — le test le plus important de la session (prompt) : une matrice sans
     * devise explicite (comme toutes celles créées avant ce bloc) se comporte exactement comme
     * avant, taux 1, équivalents EUR égaux aux montants natifs.
     */
    @IsTest
    static void testRecalculate_matrixWithoutCurrencySet_behavesExactlyAsEurNonRegression() {
        AR_Price_Matrix__c matrix = [
            SELECT Id, AR_Currency__c
            FROM AR_Price_Matrix__c
            WHERE AR_Contract_Type__c = 'CDI' AND AR_Proposed_TJM__c = 700
            LIMIT 1
        ];
        // Témoin : le @TestSetup insère cette matrice sans jamais toucher AR_Currency__c — la
        // plateforme applique elle-même la valeur <default>true</default> de la picklist restreinte
        // à l'insertion (comportement serveur, pas seulement un défaut d'affichage UI), donc une
        // matrice historique se retrouve bien en 'EUR' plutôt qu'à null. Le test vaut pour ce cas
        // (le seul qui existe réellement dans l'org) autant que pour un null explicite : les deux
        // sont traités identiquement par AR_CurrencyRateService.resolveRate (cf. String.isBlank).
        System.assertEquals('EUR', matrix.AR_Currency__c, 'Témoin : matrice historique, devise jamais saisie explicitement');

        Test.startTest();
        AR_PricingResult result = AR_PricingMatrixService.recalculate(matrix.Id);
        Test.stopTest();

        System.assertEquals(447, result.totalDailyCost, 'Chiffre identique à testRecalculate_cdiBaseCase_writesCalculatedFields');
        System.assertEquals('superstar', result.corridorSegment);
        System.assertEquals(1, result.currencyRateApplied, 'EUR : taux 1');
        System.assertEquals(result.totalDailyCost, result.totalDailyCostEurEquivalent, 'EUR : équivalent = montant natif');
        System.assertEquals(700, result.tjmEurEquivalent);
    }

    /**
     * Session 24b — bug latent corrigé : top10Comparables (AR_ComparablesService.p90Tjm, source
     * TOUJOURS en EUR) était injecté tel quel dans AR_PricingCalculator.compute pour une matrice
     * GBP/MAD, contaminant le seuil Top 10 % avec un montant EUR non converti. Preuve : 3 comparables
     * EUR à 1000/1050/1100 (p90 = 1100) sur le même compte qu'une matrice GBP dont l'idéal×1.10 vaut
     * 315 £. Sans conversion, tjmTop10 = max(1100, 315) = 1100 (nombre EUR aberrant en contexte GBP).
     * Avec conversion (1100 / 1.17 = 940), tjmTop10 = max(940, 315) = 940 (cohérent en GBP).
     */
    @IsTest
    static void testRecalculate_gbpMatrix_top10ComparablesConvertedBeforeThreshold_notRawEur() {
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        Account standardAccount = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];
        // Moteur pondéré (session 69, docs/69) : p90 absent tant que l'effectif pondéré (Σ scores) < 3 ;
        // 3 comparables ne peuvent donc suffire (score max 1.0 chacun, jamais atteint ici). 15 comparables
        // de poids égaux : le cumul franchit 90 % (13,5) au 14e → p90 = 14e valeur triée = 1100.
        // Type de contrat NEARSHORE = celui de la matrice : filtre dur du pool depuis la session 69.
        List<cxsrec__cxsPosition__c> comparables = new List<cxsrec__cxsPosition__c>();
        for (Integer i = 0; i < 15; i++) {
            comparables.add(new cxsrec__cxsPosition__c(
                Name = 'Comparable EUR ' + (i + 1), cxsrec__Account__c = standardAccount.Id, cxsrec__Country__c = 'France',
                cxsrec__Status__c = 'Gagné', cxsrec__Contract_type__c = 'NEARSHORE', TP_TJM__c = i < 12 ? 1000 + i * 5 : 1100
            ));
        }
        insert comparables;
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(position.Id, 400, 'GBP')
        );
        Test.stopTest();

        System.assertEquals(
            940,
            result.calculation.tjmTop10,
            'p90 EUR (1100) converti au taux GBP (1.17) = 940 — pas 1100 (contamination EUR non convertie)'
        );
    }

    private static AR_PricingMatrixService.MatrixInput nearshoreInput(Id positionId, Decimal proposedTjm) {
        return nearshoreInput(positionId, proposedTjm, 'EUR');
    }

    // Session 24 : surcharge avec devise explicite, pour les tests multi-devises ci-dessous — ne
    // duplique pas la construction, se contente d'ajouter le paramètre manquant au helper existant.
    private static AR_PricingMatrixService.MatrixInput nearshoreInput(Id positionId, Decimal proposedTjm, String currencyCode) {
        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = positionId;
        input.currencyCode = currencyCode;
        input.contractType = 'NEARSHORE';
        input.cjmNearshore = 200;
        input.rfaPercent = 0;
        input.proposedTjm = proposedTjm;
        // Champs mission Zone 1 (session 17) : valeurs par défaut sur tous les tests qui passent par ce
        // helper, pour que la persistance soit couverte par le cycle de vie complet (brouillon/validation/
        // dérogation) sans dupliquer un jeu de tests entier — cf. testSaveDraft_persistsMissionFields
        // pour les assertions explicites.
        input.entity = String.valueOf(AR_TestPersona.entityRefId('Abylsen GAMMA'));
        // Session 54 : AR_Consultant_Name__c (texte libre) est remplacé par le lookup — ce helper
        // envoie désormais consultantId, cf. testGetMatrixInput_reloadsMissionFields pour le round-trip.
        input.consultantId = consultantId('MARTIN');
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris La Défense';
        input.clientGrid = true;
        input.startDate = Date.newInstance(2026, 9, 1);
        input.endDate = Date.newInstance(2026, 9, 30);
        input.numberOfDays = 22;
        return input;
    }

    private static Id consultantId(String lastName) {
        return [
            SELECT Id FROM cxsrec__cxsCandidate__c WHERE cxsrec__Last_name__c = :lastName LIMIT 1
        ].Id;
    }

    // Name est un champ système du package Connexys (concaténation prénom/nom non documentée côté
    // AR_) : jamais supposer son format exact dans une assertion, toujours le relire.
    private static String consultantName(String lastName) {
        return [
            SELECT Name FROM cxsrec__cxsCandidate__c WHERE cxsrec__Last_name__c = :lastName LIMIT 1
        ].Name;
    }

    // Satisfait les règles de validation existantes de l'org (AB_BL_and_Industry, AB_Industry_And_SubIndustry,
    // TP_Address_Validation) qui ne concernent pas le Pricing Tool mais bloquent tout insert Account en test.
    // AB_Account_industry__c = 'IT / Telecoms' est dans la liste exemptée de sous-secteur obligatoire.
    private static Account newTestAccount(String name) {
        return new Account(
            Name = name,
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
    }

    // Session 65 : user porteur d'AR_Pricing_User seul (persona réel), pour tester le FLS en runAs.
    private static User queryOrCreatePricingUser() {
        List<User> existing = [
            SELECT Id
            FROM User
            WHERE
                Username = 'pricing-test-user@example.com'
                AND IsActive = TRUE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        // En création, il faudrait de vrais profils/permissions — en test, ce getter sert surtout à
        // prouver le chemin USER_MODE. Si le compte n'existe pas, on retourne l'admin système (par
        // défaut du test), et le test documente que le vrai cas dépend de cette création.
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return admin;
    }

    // ========================================================================================
    // Session 81 : nouvelle chaîne de compte via AB_Need_details__c avec fallback au champ legacy
    // ========================================================================================

    @IsTest
    static void testSearchPositions_accountViaABNeedDetails_session81() {
        // Session 81 : le vrai chaînage besoin → compte passe par AB_Need_details__c.AB_Account__c.
        // Vérifier que searchPositions trouve les résultats via cette chaîne avec fallback au champ legacy.

        Account targetAccount = newTestAccount('Session81 Search Account');
        insert targetAccount;

        // Contact requis pour AB_Need_details__c
        Contact contact = new Contact(
            LastName = 'Test Contact',
            AccountId = targetAccount.Id
        );
        insert contact;

        // AB_Need_details__c pour le nouveau chaînage
        AB_Need_details__c needDetail = new AB_Need_details__c(
            AB_Account__c = targetAccount.Id,
            AB_Contact__c = contact.Id
        );
        insert needDetail;

        // Position lié via AB_Need_details__c (legacy NULL) — prouve que le nouveau chaînage fonctionne
        cxsrec__cxsPosition__c pos1 = new cxsrec__cxsPosition__c(
            Name = 'Session81 Search Test Position', AB_Need_details__c = needDetail.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert pos1;

        // Rechercher par le nom du besoin
        List<AR_PricingMatrixService.PositionOption> byPosition = AR_PricingMatrixService.searchPositions('Session81 Search Test');
        System.assertEquals(1, byPosition.size(), 'Trouvé par le nom du besoin');
        System.assert(byPosition[0].label.contains('Session81 Search Account'), 'Compte correctement résolu via AB_Need_details__c');

        // Rechercher par le nom du compte (via la nouvelle chaîne)
        List<AR_PricingMatrixService.PositionOption> byAccount = AR_PricingMatrixService.searchPositions('Session81 Search Account');
        System.assertEquals(1, byAccount.size(), 'Trouvé par le nom du compte via AB_Need_details__c');
        System.assert(byAccount[0].label.contains('Session81 Search Account'), 'Compte trouvé dans les résultats');
    }

    @IsTest
    static void testGetPositionContext_accountViaABNeedDetails_session81() {
        // Session 81 : getPositionContext utilise aussi le nouveau chaînage avec fallback au legacy.

        Account targetAccount = newTestAccount('Session81 Context Account');
        insert targetAccount;

        // Contact requis pour AB_Need_details__c
        Contact contact = new Contact(
            LastName = 'Test Contact',
            AccountId = targetAccount.Id
        );
        insert contact;

        // AB_Need_details__c pour le nouveau chaînage
        AB_Need_details__c needDetail = new AB_Need_details__c(
            AB_Account__c = targetAccount.Id,
            AB_Contact__c = contact.Id
        );
        insert needDetail;

        // Position lié via AB_Need_details__c seul
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Session81 Context Position', AB_Need_details__c = needDetail.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals('Session81 Context Position', ctx.positionName);
        System.assertEquals(targetAccount.Id, ctx.accountId, 'Account resolved via AB_Need_details__c chain');
        System.assertEquals('Session81 Context Account', ctx.accountName, 'Account name resolved via AB_Need_details__c chain');
        System.assertNotEquals(null, ctx.createdDate, 'CreatedDate added for two-step selection panel');
    }

    @IsTest
    static void testGetPositionContext_accountCity_viaNeedDetailsChain_session141() {
        // Session 141 : accountCity = BillingCity du compte résolu par la même chaîne que accountId.
        // Le compte legacy (cxsrec__Account__c) porte une AUTRE ville : elle ne doit pas être prise.
        Account chainAccount = newTestAccount('S141 Chain Account');
        chainAccount.BillingCity = 'Lyon';
        Account legacyAccount = newTestAccount('S141 Legacy Account');
        legacyAccount.BillingCity = 'Marseille';
        insert new List<Account>{ chainAccount, legacyAccount };
        Contact contact = new Contact(LastName = 'S141 Contact', AccountId = chainAccount.Id);
        insert contact;
        AB_Need_details__c needDetail = new AB_Need_details__c(AB_Account__c = chainAccount.Id, AB_Contact__c = contact.Id);
        insert needDetail;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'S141 Position chaîne', AB_Need_details__c = needDetail.Id, cxsrec__Account__c = legacyAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals(chainAccount.Id, ctx.accountId);
        System.assertEquals('Lyon', ctx.accountCity, 'Ville du compte de la chaîne need-details, pas celle du compte legacy');
    }

    @IsTest
    static void testGetPositionContext_accountCity_legacyFallbackAndBlank_session141() {
        // Repli : aucun need-details → compte legacy. Ville vide → null (rien ne sera pré-rempli).
        Account legacyAccount = newTestAccount('S141 Legacy Only');
        legacyAccount.BillingCity = 'Nantes';
        Account noCityAccount = newTestAccount('S141 No City');
        insert new List<Account>{ legacyAccount, noCityAccount };
        // Une règle de validation exige une adresse à la création (newTestAccount pose ShippingCity) :
        // la ville est vidée par mise à jour pour obtenir un compte réellement sans ville, ni de
        // facturation ni de livraison (session 142c — avec le repli ShippingCity de la 142b, le compte
        // « sans ville » du test de la session 141 renvoyait la ville de livraison du helper).
        noCityAccount.ShippingCity = null;
        update noCityAccount;
        cxsrec__cxsPosition__c legacyPosition = new cxsrec__cxsPosition__c(
            Name = 'S141 Position legacy', cxsrec__Account__c = legacyAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c noCityPosition = new cxsrec__cxsPosition__c(
            Name = 'S141 Position sans ville', cxsrec__Account__c = noCityAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert new List<cxsrec__cxsPosition__c>{ legacyPosition, noCityPosition };

        System.assertEquals('Nantes', AR_PricingMatrixService.getPositionContext(legacyPosition.Id).accountCity);
        System.assertEquals(null, AR_PricingMatrixService.getPositionContext(noCityPosition.Id).accountCity);
    }

    @IsTest
    static void testGetPositionContext_accountCity_shippingCityFallback_session142b() {
        // Session 142b : si BillingCity est vide, utiliser ShippingCity. Mesure 142 : 13 matrices
        // sur 16 n'ont que l'adresse de livraison.
        Account billingOnlyAccount = newTestAccount('S142b Billing Only');
        billingOnlyAccount.BillingCity = 'Colombes';
        Account shippingOnlyAccount = newTestAccount('S142b Shipping Only');
        shippingOnlyAccount.ShippingCity = 'Paris';
        Account bothCitiesAccount = newTestAccount('S142b Both Cities');
        bothCitiesAccount.BillingCity = 'Lyon';
        bothCitiesAccount.ShippingCity = 'Marseille';
        Account noCitiesAccount = newTestAccount('S142b No Cities');
        insert new List<Account>{ billingOnlyAccount, shippingOnlyAccount, bothCitiesAccount, noCitiesAccount };
        // Adresse exigée à la création (cf. newTestAccount) : vidée par mise à jour pour le cas « aucune ville ».
        noCitiesAccount.ShippingCity = null;
        update noCitiesAccount;

        cxsrec__cxsPosition__c billingOnlyPos = new cxsrec__cxsPosition__c(
            Name = 'S142b Position Billing', cxsrec__Account__c = billingOnlyAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c shippingOnlyPos = new cxsrec__cxsPosition__c(
            Name = 'S142b Position Shipping', cxsrec__Account__c = shippingOnlyAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c bothPos = new cxsrec__cxsPosition__c(
            Name = 'S142b Position Both', cxsrec__Account__c = bothCitiesAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        cxsrec__cxsPosition__c noCitiesPos = new cxsrec__cxsPosition__c(
            Name = 'S142b Position No Cities', cxsrec__Account__c = noCitiesAccount.Id,
            cxsrec__Country__c = 'France', cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert new List<cxsrec__cxsPosition__c>{ billingOnlyPos, shippingOnlyPos, bothPos, noCitiesPos };

        // BillingCity seul
        System.assertEquals('Colombes', AR_PricingMatrixService.getPositionContext(billingOnlyPos.Id).accountCity);

        // ShippingCity seul, BillingCity vide → repli sur ShippingCity
        System.assertEquals('Paris', AR_PricingMatrixService.getPositionContext(shippingOnlyPos.Id).accountCity);

        // Les deux : BillingCity gagne
        System.assertEquals('Lyon', AR_PricingMatrixService.getPositionContext(bothPos.Id).accountCity);

        // Aucune : null
        System.assertEquals(null, AR_PricingMatrixService.getPositionContext(noCitiesPos.Id).accountCity);
    }

    @IsTest
    static void testSearchPositions_byAccountNameOnly_session85() {
        // Session 85 : la recherche par nom de compte doit fonctionner même quand le nom du besoin
        // ne contient pas le terme recherché (non-régression).

        Account account = newTestAccount('Session85 Test Client');
        insert account;

        // Position dont le nom ne contient PAS le terme de recherche
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Senior Developer XYZ',
            cxsrec__Account__c = account.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        // Rechercher par le nom du compte uniquement
        List<AR_PricingMatrixService.PositionOption> results = AR_PricingMatrixService.searchPositions('Session85 Test Client');

        System.assertEquals(1, results.size(), 'Le besoin doit être trouvé par le nom du compte');
        System.assertEquals(position.Id, results[0].positionId, 'Le bon besoin est retourné');
        System.assert(results[0].label.contains('Session85 Test Client'), 'Le compte doit être affiché dans le libellé');
    }

    @IsTest
    static void testGetPositionContext_contractType_session85() {
        // Session 85 : vérifier que contractType est peuplé dans PositionContext.

        Account account = newTestAccount('Session85 Context Account');
        insert account;

        Contact contact = new Contact(
            LastName = 'Test Contact',
            AccountId = account.Id
        );
        insert contact;

        AB_Need_details__c needDetail = new AB_Need_details__c(
            AB_Account__c = account.Id,
            AB_Contact__c = contact.Id
        );
        insert needDetail;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Session85 Context Position',
            AB_Need_details__c = needDetail.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'VIE'
        );
        insert position;

        AR_PricingMatrixService.PositionContext ctx = AR_PricingMatrixService.getPositionContext(position.Id);

        System.assertEquals('VIE', ctx.contractType, 'Le type de contrat doit être peuplé');
    }

    // ------------------------------------------------------------------
    // Héritage hiérarchique du corridor par compte parent (session 97).
    // ------------------------------------------------------------------

    @IsTest
    static void testGetAccountCorridorPercents_noCorridorInChain_returnsNull() {
        // Cas 1 : Compte sans aucun corridor dans toute sa chaîne (y compris sans parent)
        // → défauts 20/25/30 appliqués par l'appelant, cette méthode retourne null.
        Account rootAccount = newTestAccount('Session97 Root No Corridor');
        insert rootAccount;

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(rootAccount.Id, null);
        Test.stopTest();

        System.assertEquals(null, result, 'Aucun corridor trouvé dans la chaîne → null');
    }

    @IsTest
    static void testGetAccountCorridorPercents_ownCorridorNoParent_returnsOwnCorridor() {
        // Cas 2 : Compte avec corridor explicite propre, sans parent
        // → retourne son corridor (non-régression).
        Account account = newTestAccount('Session97 Own Corridor No Parent');
        insert account;

        insert new AR_Account_Corridor__c(
            AR_Account__c = account.Id,
            AR_Floor_Percent__c = 10,
            AR_Target_Percent__c = 15,
            AR_Ideal_Percent__c = 20
        );

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(account.Id, null);
        Test.stopTest();

        System.assertEquals(10, result.floorPercent);
        System.assertEquals(15, result.targetPercent);
        System.assertEquals(20, result.idealPercent);
    }

    @IsTest
    static void testGetAccountCorridorPercents_childInheritsFromParent() {
        // Cas 3 : Compte enfant direct d'un compte à corridor, lui-même sans corridor propre
        // → hérite du parent.
        Account parentAccount = newTestAccount('Session97 Parent With Corridor');
        insert parentAccount;

        insert new AR_Account_Corridor__c(
            AR_Account__c = parentAccount.Id,
            AR_Floor_Percent__c = 7,
            AR_Target_Percent__c = 11,
            AR_Ideal_Percent__c = 18
        );

        Account childAccount = newTestAccount('Session97 Child No Own Corridor');
        childAccount.ParentId = parentAccount.Id;
        insert childAccount;

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(childAccount.Id, null);
        Test.stopTest();

        System.assertEquals(7, result.floorPercent, 'L\'enfant hérite du corridor du parent');
        System.assertEquals(11, result.targetPercent);
        System.assertEquals(18, result.idealPercent);
    }

    @IsTest
    static void testGetAccountCorridorPercents_grandchildInheritsFromGrandparent() {
        // Cas 4 : Compte petit-enfant (2 niveaux), sans corridor propre ni sur son parent,
        // mais son grand-parent a un corridor → hérite du grand-parent.
        Account grandparentAccount = newTestAccount('Session97 Grandparent With Corridor');
        insert grandparentAccount;

        insert new AR_Account_Corridor__c(
            AR_Account__c = grandparentAccount.Id,
            AR_Floor_Percent__c = 6,
            AR_Target_Percent__c = 9,
            AR_Ideal_Percent__c = 14
        );

        Account parentAccount = newTestAccount('Session97 Parent No Corridor');
        parentAccount.ParentId = grandparentAccount.Id;
        insert parentAccount;

        Account grandchildAccount = newTestAccount('Session97 Grandchild No Corridor');
        grandchildAccount.ParentId = parentAccount.Id;
        insert grandchildAccount;

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(grandchildAccount.Id, null);
        Test.stopTest();

        System.assertEquals(6, result.floorPercent, 'Le petit-enfant hérite du corridor du grand-parent');
        System.assertEquals(9, result.targetPercent);
        System.assertEquals(14, result.idealPercent);
    }

    @IsTest
    static void testGetAccountCorridorPercents_childCorridorOverridesParentCorridor() {
        // Cas 5 : Compte avec corridor propre ET un ancêtre (parent ou grand-parent)
        // à corridor différent → son propre corridor gagne.
        Account parentAccount = newTestAccount('Session97 Parent With Corridor For Override');
        insert parentAccount;

        insert new AR_Account_Corridor__c(
            AR_Account__c = parentAccount.Id,
            AR_Floor_Percent__c = 5,
            AR_Target_Percent__c = 8,
            AR_Ideal_Percent__c = 12
        );

        Account childAccount = newTestAccount('Session97 Child With Own Corridor Override');
        childAccount.ParentId = parentAccount.Id;
        insert childAccount;

        insert new AR_Account_Corridor__c(
            AR_Account__c = childAccount.Id,
            AR_Floor_Percent__c = 15,
            AR_Target_Percent__c = 20,
            AR_Ideal_Percent__c = 25
        );

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(childAccount.Id, null);
        Test.stopTest();

        System.assertEquals(15, result.floorPercent, 'Le propre corridor du compte prime sur celui du parent');
        System.assertEquals(20, result.targetPercent);
        System.assertEquals(25, result.idealPercent);
    }

    @IsTest
    static void testGetAccountCorridorPercents_deepChainNoCorridorAnywhere_returnsNull() {
        // Cas 6 : Chaîne à 3+ niveaux sans aucun corridor nulle part
        // → défauts 20/25/30, pas d'erreur, pas de boucle infinie.
        Account level0 = newTestAccount('Session97 Level0');
        insert level0;

        Account level1 = newTestAccount('Session97 Level1');
        level1.ParentId = level0.Id;
        insert level1;

        Account level2 = newTestAccount('Session97 Level2');
        level2.ParentId = level1.Id;
        insert level2;

        Account level3 = newTestAccount('Session97 Level3');
        level3.ParentId = level2.Id;
        insert level3;

        Test.startTest();
        AR_PricingMatrixService.ThresholdPercentsDto result = AR_PricingMatrixService.getAccountCorridorPercents(level3.Id, null);
        Test.stopTest();

        System.assertEquals(null, result, 'Aucun corridor trouvé sur une chaîne profonde → null');
    }
    // ---- Session 155 : le corridor de Paramètres généraux est celui que le moteur applique ----

    private static void setGeneralCorridor(Decimal floorPct, Decimal targetPct, Decimal idealPct) {
        AR_General_Setting__c row = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        row.AR_Floor_Percent_Default__c = floorPct;
        row.AR_Target_Percent_Default__c = targetPct;
        row.AR_Ideal_Percent_Default__c = idealPct;
        update row;
    }

    /** NEARSHORE, coût 200, RFA 0 : MC2 % = (TJM − 200) / TJM. */
    private static AR_PricingResult simulateNearshore(Decimal tjm, Id accountId) {
        AR_PricingMatrixService.SimulateRequest req = new AR_PricingMatrixService.SimulateRequest();
        req.contractType = 'NEARSHORE';
        req.cjmNearshore = 200;
        req.rfaPercent = 0;
        req.proposedTjm = tjm;
        req.top10Comparables = 0;
        req.accountIdForCorridor = accountId;
        return AR_PricingMatrixService.simulate(req);
    }

    @IsTest
    static void testSimulate_noAccountCorridor_usesGeneralSettings_15_20_25() {
        setGeneralCorridor(15, 20, 25);

        AR_PricingResult below = simulateNearshore(232, null); // 13,8 %
        AR_PricingResult low = simulateNearshore(241, null); // 17,0 %
        AR_PricingResult recommended = simulateNearshore(257, null); // 22,2 %
        AR_PricingResult superstar = simulateNearshore(271, null); // 26,2 %

        System.assertEquals('below_floor', below.corridorSegment);
        System.assertEquals('low_margin', low.corridorSegment, '17 % était below_floor avec les constantes 20/25/30');
        System.assertEquals('recommended', recommended.corridorSegment);
        System.assertEquals('superstar', superstar.corridorSegment);
        System.assertEquals(15, low.floorPercentApplied, 'le corridor appliqué est figé avec les valeurs de la base');
        System.assertEquals(20, low.targetPercentApplied);
        System.assertEquals(25, low.idealPercentApplied);
        // TJM plancher = 200 / (1 − 0,15) = 235,29 → 236
        System.assertEquals(236, low.tjmFloor);
    }

    @IsTest
    static void testSimulate_accountCorridorWinsOverGeneralSettings() {
        setGeneralCorridor(15, 20, 25);
        Account corridorAccount = [SELECT Id FROM Account WHERE Name = 'Grand Compte Corridor' LIMIT 1];

        // Grand compte du @TestSetup = 5/8/12 : 17 % y est « superstar », « low_margin » avec 15/20/25.
        AR_PricingResult result = simulateNearshore(241, corridorAccount.Id);

        System.assertEquals('superstar', result.corridorSegment);
        System.assertEquals(5, result.floorPercentApplied);
    }

    /** Les trois champs sont `required` en base (un null ne peut pas être persisté) : le repli champ par
     * champ se prouve donc sur un enregistrement en mémoire, jamais inséré. */
    @IsTest
    static void testThresholdPercentsFrom_emptyField_fallsBackToConstantForThatFieldOnly() {
        AR_General_Setting__c partial = new AR_General_Setting__c(AR_Floor_Percent_Default__c = 15);

        AR_PricingCalculator.ThresholdPercents pcts = AR_PricingMatrixService.thresholdPercentsFrom(partial);

        System.assertEquals(15, pcts.floorPercent, 'champ renseigné → valeur de la base');
        System.assertEquals(AR_PricingCalculator.TARGET_PERCENT_DEFAULT, pcts.targetPercent);
        System.assertEquals(AR_PricingCalculator.IDEAL_PERCENT_DEFAULT, pcts.idealPercent);

        AR_PricingCalculator.ThresholdPercents none = AR_PricingMatrixService.thresholdPercentsFrom(null);
        System.assertEquals(20, none.floorPercent, 'singleton absent → les trois constantes');
        System.assertEquals(25, none.targetPercent);
        System.assertEquals(30, none.idealPercent);
    }

    @IsTest
    static void testGetPricingSettings_returnsEffectiveCorridorFromSingleton() {
        setGeneralCorridor(15, 20, 25);

        AR_PricingMatrixService.PricingSettingsDto settings = AR_PricingMatrixService.getPricingSettings();

        System.assertEquals(15, settings.floorPercentDefault);
        System.assertEquals(20, settings.targetPercentDefault);
        System.assertEquals(25, settings.idealPercentDefault);
    }

    @IsTest
    static void testGetPricingSettings_exposesOfiiTaxRateAndCap_nullWhenEmpty() {
        AR_General_Setting__c row = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        row.AR_Ofii_Tax_Rate__c = 55;
        row.AR_Ofii_Tax_Cap__c = 2506.67;
        update row;
        AR_PricingMatrixService.PricingSettingsDto served = AR_PricingMatrixService.getPricingSettings();
        System.assertEquals(55, served.ofiiTaxRate, 'Taux OFII servi tel quel');
        System.assertEquals(2506.67, served.ofiiTaxCapEur, 'Plafond OFII servi tel quel, en euros');

        row.AR_Ofii_Tax_Rate__c = null;
        row.AR_Ofii_Tax_Cap__c = null;
        update row;
        AR_PricingMatrixService.PricingSettingsDto empty = AR_PricingMatrixService.getPricingSettings();
        System.assertEquals(null, empty.ofiiTaxRate, 'Vide : null, jamais un taux par défaut substitué');
        System.assertEquals(null, empty.ofiiTaxCapEur, 'Vide : null, jamais un plafond par défaut substitué');

        delete row;
        AR_PricingMatrixService.PricingSettingsDto none = AR_PricingMatrixService.getPricingSettings();
        System.assertEquals(null, none.ofiiTaxRate, 'Singleton absent : null');
        System.assertEquals(null, none.ofiiTaxCapEur, 'Singleton absent : null');
    }

    @IsTest
    static void testGetPricingSettings_noSingleton_returnsEngineConstants() {
        delete [SELECT Id FROM AR_General_Setting__c];

        AR_PricingMatrixService.PricingSettingsDto settings = AR_PricingMatrixService.getPricingSettings();

        System.assertEquals(AR_PricingCalculator.FLOOR_PERCENT_DEFAULT, settings.floorPercentDefault);
        System.assertEquals(AR_PricingCalculator.TARGET_PERCENT_DEFAULT, settings.targetPercentDefault);
        System.assertEquals(AR_PricingCalculator.IDEAL_PERCENT_DEFAULT, settings.idealPercentDefault);
    }

    @IsTest
    static void testGetAccountCorridorPercents_stillNullWithoutAccountCorridor_evenWithGeneralCorridor() {
        setGeneralCorridor(15, 20, 25);
        Account standardAccount = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1];

        System.assertEquals(
            null,
            AR_PricingMatrixService.getAccountCorridorPercents(standardAccount.Id, null),
            'le bandeau Grand compte repose sur null = pas de corridor de compte'
        );
    }

    @IsTest
    static void testValidate_usesGeneralCorridor_17PercentValidates_14PercentRefused() {
        setGeneralCorridor(15, 20, 25);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult ok = AR_PricingMatrixService.validateInput(nearshoreInput(position.Id, 241));
        System.assertEquals('Validée', ok.status, '17 % ≥ plancher 15 % : validation directe');

        Boolean refused = false;
        try {
            AR_PricingMatrixService.validateInput(nearshoreInput(position.Id, 232));
        } catch (AuraHandledException e) {
            refused = true;
        }
        System.assert(refused, '13,8 % < plancher 15 % : dérogation obligatoire');
    }

    // ---- Session 157 : un TJM modifié après coup ne peut jamais valider une matrice sous le plancher ----

    /**
     * Rejoue le scénario de l'auditeur : un brouillon enregistré à un TJM confortable, puis une
     * validation dont l'input porte un TJM sous le plancher (l'écran n'avait pas encore recalculé).
     * `validateInput` recalcule à partir de l'input reçu, jamais à partir du brouillon stocké.
     * Rollback explicite à la place de l'annulation automatique d'une transaction Aura : en
     * production l'exception annule saveDraftInput(), ce que le test ne ferait pas seul.
     */
    private static void assertValidateRefusedBelowFloor(Id positionId, Decimal comfortableTjm, Decimal belowFloorTjm) {
        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(positionId, comfortableTjm)
        );
        System.assertEquals('Brouillon', draft.status);
        System.assertNotEquals('below_floor', draft.calculation.corridorSegment, 'le brouillon de départ est confortable');

        AR_PricingMatrixService.MatrixInput stale = nearshoreInput(positionId, belowFloorTjm);
        stale.matrixId = draft.matrixId;

        Savepoint beforeValidate = Database.setSavepoint();
        String message;
        try {
            AR_PricingMatrixService.validateInput(stale);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Database.rollback(beforeValidate);

        System.assertNotEquals(null, message, 'validate() doit refuser un TJM sous le plancher');
        System.assertEquals(Label.AR_Msg_PM_BelowFloorNeedsDerogation, message, 'le message oriente vers la dérogation');
        AR_Price_Matrix__c stored = [
            SELECT AR_Status__c, AR_Proposed_TJM__c, AR_Validated_At__c
            FROM AR_Price_Matrix__c
            WHERE Id = :draft.matrixId
        ];
        System.assertEquals('Brouillon', stored.AR_Status__c, 'la matrice reste un brouillon');
        System.assertEquals(comfortableTjm, stored.AR_Proposed_TJM__c, 'le TJM refusé n\'est pas conservé');
        System.assertEquals(null, stored.AR_Validated_At__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :draft.matrixId],
            'aucun snapshot'
        );
    }

    @IsTest
    static void testValidate_staleComfortableDraft_belowFloorInput_refusedDefaultCorridor() {
        // Corridor par défaut 20/25/30, coût 200 : TJM 205 → 2,4 % < 20 %.
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        assertValidateRefusedBelowFloor(position.Id, 400, 205);
    }

    @IsTest
    static void testValidate_staleComfortableDraft_belowFloorInput_refusedAccountCorridor() {
        // Corridor grand compte 5/8/12 (@TestSetup), plancher 5 % : TJM 205 → 2,4 % < 5 % (un TJM de
        // 215, 7 %, serait en revanche accepté ici et refusé par le corridor par défaut).
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Corridor' LIMIT 1];
        assertValidateRefusedBelowFloor(position.Id, 400, 205);
    }

    @IsTest
    static void testValidate_staleComfortableDraft_belowFloorInput_refusedGeneralCorridor() {
        // Session 155 : corridor de Paramètres généraux 15/20/25, TJM 232 → 13,8 % < 15 %.
        setGeneralCorridor(15, 20, 25);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        assertValidateRefusedBelowFloor(position.Id, 400, 232);
    }

    @IsTest
    static void testSaveDraft_onValidatedMatrix_changedTjm_isRefusedAndStoredTjmUnchanged() {
        // « Modifier un TJM sans dupliquer » une matrice déjà validée : le verrou de
        // AR_PriceMatrixTrigger s'applique aussi au chemin de service (saveDraftInput / autosave).
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(
            nearshoreInput(position.Id, 400)
        );
        System.assertEquals('Validée', validated.status);

        AR_PricingMatrixService.MatrixInput edited = nearshoreInput(position.Id, 205);
        edited.matrixId = validated.matrixId;
        Boolean refused = false;
        try {
            AR_PricingMatrixService.saveDraftInput(edited);
        } catch (Exception e) {
            refused = true;
        }

        System.assert(refused, 'une matrice Validée n\'est modifiable par aucun chemin');
        AR_Price_Matrix__c stored = [
            SELECT AR_Status__c, AR_Proposed_TJM__c FROM AR_Price_Matrix__c WHERE Id = :validated.matrixId
        ];
        System.assertEquals('Validée', stored.AR_Status__c);
        System.assertEquals(400, stored.AR_Proposed_TJM__c);
    }

    // ========================================================================================
    // Session 184f : le serveur recalcule le corridor depuis le compte du besoin par la jonction
    // AB_Need_details__c (comme l'écran), en remontant la hiérarchie — le plus proche gagne.
    // ========================================================================================

    private static Account insertAccount(String name, Id parentId) {
        Account a = newTestAccount(name);
        a.ParentId = parentId;
        insert a;
        return a;
    }

    private static Id insertPositionViaJunction(String name, Id accountId) {
        Contact contact = new Contact(LastName = 'Contact ' + name, AccountId = accountId);
        insert contact;
        AB_Need_details__c need = new AB_Need_details__c(AB_Account__c = accountId, AB_Contact__c = contact.Id);
        insert need;
        // cxsrec__Account__c volontairement vide : c'est le cas réel des besoins rattachés par la jonction.
        cxsrec__cxsPosition__c pos = new cxsrec__cxsPosition__c(
            Name = name,
            AB_Need_details__c = need.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert pos;
        return pos.Id;
    }

    private static void insertCorridor(Id accountId, Decimal floor, Decimal target, Decimal ideal) {
        insert new AR_Account_Corridor__c(
            AR_Account__c = accountId,
            AR_Floor_Percent__c = floor,
            AR_Target_Percent__c = target,
            AR_Ideal_Percent__c = ideal
        );
    }

    @IsTest
    static void testSaveDraftInput_positionViaJunction_grandchildInheritsGrandparentCorridor() {
        Account grandParent = insertAccount('S184f GP', null);
        Account parent = insertAccount('S184f Parent', grandParent.Id);
        Account grandChild = insertAccount('S184f PetitEnfant', parent.Id);
        insertCorridor(grandParent.Id, 3, 4, 6);
        Id positionId = insertPositionViaJunction('S184f Besoin GP', grandChild.Id);

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(positionId, 400)
        );
        Test.stopTest();

        AR_Price_Matrix__c saved = [
            SELECT AR_Floor_Percent_Applied__c, AR_Target_Percent_Applied__c, AR_Ideal_Percent_Applied__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(3, saved.AR_Floor_Percent_Applied__c, 'Corridor du grand-parent, besoin rattaché par la jonction');
        System.assertEquals(4, saved.AR_Target_Percent_Applied__c);
        System.assertEquals(6, saved.AR_Ideal_Percent_Applied__c);
    }

    @IsTest
    static void testSaveDraftInput_positionViaJunction_childOwnCorridorWins() {
        Account grandParent = insertAccount('S184f GP2', null);
        Account child = insertAccount('S184f Enfant propre', grandParent.Id);
        insertCorridor(grandParent.Id, 3, 4, 6);
        insertCorridor(child.Id, 9, 10, 11);
        Id positionId = insertPositionViaJunction('S184f Besoin propre', child.Id);

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(positionId, 400)
        );

        AR_Price_Matrix__c saved = [
            SELECT AR_Floor_Percent_Applied__c, AR_Target_Percent_Applied__c, AR_Ideal_Percent_Applied__c
            FROM AR_Price_Matrix__c
            WHERE Id = :result.matrixId
        ];
        System.assertEquals(9, saved.AR_Floor_Percent_Applied__c, 'L\'enregistrement propre de l\'enfant prime sur celui du grand-parent');
        System.assertEquals(10, saved.AR_Target_Percent_Applied__c);
        System.assertEquals(11, saved.AR_Ideal_Percent_Applied__c);
    }

    @IsTest
    static void testSaveDraftInput_legacyAccountOnly_childInheritsParentCorridor() {
        Account parent = insertAccount('S184f Parent legacy', null);
        Account child = insertAccount('S184f Enfant legacy', parent.Id);
        insertCorridor(parent.Id, 3, 4, 6);
        cxsrec__cxsPosition__c pos = new cxsrec__cxsPosition__c(
            Name = 'S184f Besoin legacy',
            cxsrec__Account__c = child.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert pos;

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(pos.Id, 400)
        );

        System.assertEquals(
            3,
            [SELECT AR_Floor_Percent_Applied__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId].AR_Floor_Percent_Applied__c,
            'Repli sur cxsrec__Account__c conservé'
        );
    }

    @IsTest
    static void testRecalculate_positionViaJunction_usesAccountHierarchyCorridor() {
        Account parent = insertAccount('S184f Parent recalc', null);
        Account child = insertAccount('S184f Enfant recalc', parent.Id);
        insertCorridor(parent.Id, 3, 4, 6);
        Id positionId = insertPositionViaJunction('S184f Besoin recalc', child.Id);
        AR_PricingMatrixService.MatrixSaveResult saved = AR_PricingMatrixService.saveDraftInput(
            nearshoreInput(positionId, 400)
        );
        update new AR_Account_Corridor__c(
            Id = [SELECT Id FROM AR_Account_Corridor__c WHERE AR_Account__c = :parent.Id LIMIT 1].Id,
            AR_Floor_Percent__c = 7,
            AR_Target_Percent__c = 8,
            AR_Ideal_Percent__c = 9
        );

        Test.startTest();
        AR_PricingMatrixService.recalculate(saved.matrixId);
        Test.stopTest();

        System.assertEquals(
            7,
            [SELECT AR_Floor_Percent_Applied__c FROM AR_Price_Matrix__c WHERE Id = :saved.matrixId].AR_Floor_Percent_Applied__c,
            'Le recalcul lit aussi le compte par la jonction et remonte la hiérarchie'
        );
    }

    // ── Pré-remplissages de la création depuis un besoin ─────────────────────────────────────────

    @IsTest
    static void testPlausibleDailyRate_keepsOnlyPlausibleRates() {
        System.assertEquals(650, AR_PricingMatrixService.plausibleDailyRate(650));
        System.assertEquals(50, AR_PricingMatrixService.plausibleDailyRate(50), 'Borne basse incluse');
        System.assertEquals(5000, AR_PricingMatrixService.plausibleDailyRate(5000), 'Borne haute incluse');
        System.assertEquals(null, AR_PricingMatrixService.plausibleDailyRate(49));
        System.assertEquals(null, AR_PricingMatrixService.plausibleDailyRate(5001));
        System.assertEquals(null, AR_PricingMatrixService.plausibleDailyRate(0));
        System.assertEquals(null, AR_PricingMatrixService.plausibleDailyRate(null));
    }

    @IsTest
    static void testGetCreationPrefill_plausibleRate_proposesTjmInOrgCurrency() {
        cxsrec__cxsPosition__c position = prefillPosition('Besoin TJM ok', 650);
        AR_PricingMatrixService.CreationPrefill prefill = AR_PricingMatrixService.getCreationPrefill(position.Id);
        System.assertEquals(650, prefill.proposedTjm);
        System.assertEquals(UserInfo.getDefaultCurrency(), prefill.tjmCurrency);
    }

    @IsTest
    static void testGetCreationPrefill_emptyOrImplausibleRate_proposesNothing() {
        System.assertEquals(null, AR_PricingMatrixService.getCreationPrefill(prefillPosition('Besoin TJM vide', null).Id).proposedTjm);
        cxsrec__cxsPosition__c tooLow = prefillPosition('Besoin TJM bas', 12);
        AR_PricingMatrixService.CreationPrefill prefill = AR_PricingMatrixService.getCreationPrefill(tooLow.Id);
        System.assertEquals(null, prefill.proposedTjm);
        System.assertEquals(null, prefill.tjmCurrency, 'Pas de devise sans montant proposé');
    }

    @IsTest
    static void testGetCreationPrefill_singleCandidate_isProposedAsConsultant() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Consultant' LIMIT 1];
        AR_PricingMatrixService.CreationPrefill prefill = AR_PricingMatrixService.getCreationPrefill(position.Id);
        System.assertEquals(consultantId('MARTIN'), prefill.consultantId);
        System.assertEquals(consultantName('MARTIN'), prefill.consultantLabel);
    }

    @IsTest
    static void testGetCreationPrefill_sameCandidateAppliedTwice_stillSingle() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Consultant' LIMIT 1];
        insert new cxsrec__cxsJob_application__c(
            Name = 'JA doublon',
            cxsrec__Position__c = position.Id,
            cxsrec__Candidate__c = consultantId('MARTIN')
        );
        System.assertEquals(consultantId('MARTIN'), AR_PricingMatrixService.getCreationPrefill(position.Id).consultantId);
    }

    @IsTest
    static void testGetCreationPrefill_twoCandidates_proposesNoConsultant() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Consultant' LIMIT 1];
        insert new cxsrec__cxsJob_application__c(
            Name = 'JA second candidat',
            cxsrec__Position__c = position.Id,
            cxsrec__Candidate__c = consultantId('PETIT')
        );
        System.assertEquals(null, AR_PricingMatrixService.getCreationPrefill(position.Id).consultantId);
    }

    @IsTest
    static void testGetCreationPrefill_noCandidate_proposesNoConsultant() {
        cxsrec__cxsPosition__c position = prefillPosition('Besoin sans candidat', 600);
        AR_PricingMatrixService.CreationPrefill prefill = AR_PricingMatrixService.getCreationPrefill(position.Id);
        System.assertEquals(null, prefill.consultantId);
        System.assertEquals(600, prefill.proposedTjm, 'Le TJM reste proposé indépendamment du candidat');
    }

    @IsTest
    static void testGetCreationPrefill_singleCandidateOfOtherRecordType_proposesNoConsultant() {
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c.getRecordTypeInfosByDeveloperName().get('Consultant').getRecordTypeId();
        Id otherRecordTypeId;
        for (Schema.RecordTypeInfo info : Schema.SObjectType.cxsrec__cxsCandidate__c.getRecordTypeInfosByDeveloperName().values()) {
            if (
                info.isAvailable() &&
                info.isActive() &&
                !info.isMaster() &&
                info.getRecordTypeId() != consultantRecordTypeId &&
                info.getDeveloperName() != 'External_candidate' &&
                info.isDefaultRecordTypeMapping() == false
            ) {
                otherRecordTypeId = info.getRecordTypeId();
                break;
            }
        }
        if (otherRecordTypeId == null) {
            return; // aucun autre type assignable à l'utilisateur de test : cas non constructible
        }
        cxsrec__cxsCandidate__c other = new cxsrec__cxsCandidate__c(
            RecordTypeId = otherRecordTypeId,
            cxsrec__First_name__c = 'Olga',
            cxsrec__Last_name__c = 'AUTRETYPE'
        );
        insert other;
        cxsrec__cxsPosition__c position = prefillPosition('Besoin autre type', null);
        insert new cxsrec__cxsJob_application__c(Name = 'JA autre type', cxsrec__Position__c = position.Id, cxsrec__Candidate__c = other.Id);
        System.assertEquals(null, AR_PricingMatrixService.getCreationPrefill(position.Id).consultantId);
    }

    @IsTest
    static void testGetCreationPrefill_withoutPosition_returnsEmpty() {
        AR_PricingMatrixService.CreationPrefill prefill = AR_PricingMatrixService.getCreationPrefill(null);
        System.assertEquals(null, prefill.proposedTjm);
        System.assertEquals(null, prefill.consultantId);
        System.assertEquals(null, prefill.entityId);
    }

    @IsTest
    static void testCreatorEntity_uniqueMatch_ignoresCaseAndSpaces() {
        AR_PTF_Entity_Referential__c entity = new AR_PTF_Entity_Referential__c(Name = '  ABYLSEN sud ', AR_Active__c = true);
        insert entity;
        Id entityId = entity.Id;
        User creator = newPrefillCreator('Abylsen SUD');

        System.runAs(creator) {
            System.assertEquals(entityId, AR_PricingMatrixService.creatorDefaultEntityId());
        }
    }

    @IsTest
    static void testCreatorEntity_noApproximateMatch_returnsNull() {
        insert new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN SIGMA – Bordeaux', AR_Active__c = true);
        User creator = newPrefillCreator('Abylsen SIGMA');

        System.runAs(creator) {
            System.assertEquals(null, AR_PricingMatrixService.creatorDefaultEntityId());
        }
    }

    @IsTest
    static void testCreatorEntity_twoHomonyms_returnsNull() {
        insert new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN SUD', AR_Active__c = true);
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen Sud', AR_Active__c = true);
        User creator = newPrefillCreator('Abylsen SUD');

        System.runAs(creator) {
            System.assertEquals(null, AR_PricingMatrixService.creatorDefaultEntityId(), 'Deux fiches : rien, l\'utilisateur choisit');
        }
    }

    @IsTest
    static void testCreatorEntity_noCompanyValue_returnsNull() {
        insert new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN SUD', AR_Active__c = true);
        User creator = newPrefillCreator(null);

        System.runAs(creator) {
            System.assertEquals(null, AR_PricingMatrixService.creatorDefaultEntityId());
        }
    }

    @IsTest
    static void testCreatorEntity_inactiveFiche_isIgnored() {
        insert new AR_PTF_Entity_Referential__c(Name = 'ABYLSEN SWITZERLAND', AR_Active__c = false);
        User creator = newPrefillCreator('Abylsen SWITZERLAND');

        System.runAs(creator) {
            System.assertEquals(null, AR_PricingMatrixService.creatorDefaultEntityId());
        }
    }

    /** Utilisateur standard portant la valeur « Abylsen Company » (persona AR_Pricing_User seul). */
    private static User newPrefillCreator(String company) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        Id pricingUserPs = [SELECT Id FROM PermissionSet WHERE Name = 'AR_Pricing_User' LIMIT 1].Id;
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User creator = new User(
            ProfileId = p.Id,
            LastName = 'PrefillCreator',
            FirstName = 'AR',
            Alias = 'arprefil',
            Email = 'ar.prefill.creator@abylsengroup.com.invalid',
            Username = 'ar.prefill.creator.' + suffix + '@abylsengroup.com.invalid',
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.prefill.creator.' + suffix,
            TP_Abylsen_Company__c = company
        );
        // Création de l'utilisateur et de son affectation isolées : MIXED_DML_OPERATION sinon.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert creator;
            insert new PermissionSetAssignment(AssigneeId = creator.Id, PermissionSetId = pricingUserPs);
        }
        return creator;
    }

    private static cxsrec__cxsPosition__c prefillPosition(String name, Decimal tjm) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = name,
            cxsrec__Account__c = [SELECT Id FROM Account WHERE Name = 'Client Standard' LIMIT 1].Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI',
            TP_TJM__c = tjm
        );
        insert position;
        return position;
    }

    // Référentiel Nearshore par séniorité : ligne exacte, repli DEFAULT, blocage, matrice sans séniorité.
    private static AR_Nearshore_Referential__c maroc(String seniority, Decimal rate, String currencyCode) {
        AR_Nearshore_Referential__c r = new AR_Nearshore_Referential__c(
            Name = 'Maroc', AR_Seniority__c = seniority, AR_Daily_Rate__c = rate, AR_Currency__c = currencyCode
        );
        insert r;
        return r;
    }

    private static AR_PricingMatrixService.MatrixInput nearshoreFromReferential(Id positionId, Id countryRowId, String seniority) {
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(positionId, 400);
        input.cjmNearshore = null;
        input.nearshoreCountryId = countryRowId;
        input.seniorityLevel = seniority;
        return input;
    }

    @IsTest
    static void testNearshoreRate_exactSeniorityRowWins() {
        AR_Nearshore_Referential__c exact = maroc('Technicien', 150, 'EUR');
        AR_Nearshore_Referential__c byDefault = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT' LIMIT 1];
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_Price_Matrix__c saved;
        {
            AR_PricingMatrixService.MatrixSaveResult r = AR_PricingMatrixService.saveDraftInput(
                nearshoreFromReferential(position.Id, byDefault.Id, 'Technicien'));
            saved = [SELECT AR_CJM_Nearshore__c, AR_Nearshore_Country__c FROM AR_Price_Matrix__c WHERE Id = :r.matrixId];
        }
        System.assertEquals(150, saved.AR_CJM_Nearshore__c);
        System.assertEquals(exact.Id, saved.AR_Nearshore_Country__c, 'Le lookup pointe vers la ligne réellement appliquée');
    }

    @IsTest
    static void testNearshoreRate_noExactRow_fallsBackToDefault() {
        maroc('Technicien', 150, 'EUR');
        AR_Nearshore_Referential__c byDefault = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT' LIMIT 1];
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_Price_Matrix__c saved;
        {
            AR_PricingMatrixService.MatrixSaveResult r = AR_PricingMatrixService.saveDraftInput(
                nearshoreFromReferential(position.Id, byDefault.Id, 'Senior Consultant'));
            saved = [SELECT AR_CJM_Nearshore__c, AR_Nearshore_Country__c FROM AR_Price_Matrix__c WHERE Id = :r.matrixId];
        }
        System.assertEquals(200, saved.AR_CJM_Nearshore__c);
        System.assertEquals(byDefault.Id, saved.AR_Nearshore_Country__c);
    }

    @IsTest
    static void testNearshoreRate_matrixWithoutSeniority_usesDefaultRow() {
        maroc('Technicien', 150, 'EUR');
        AR_Nearshore_Referential__c byDefault = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT' LIMIT 1];
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreFromReferential(position.Id, byDefault.Id, null);
        AR_Price_Matrix__c saved;
        {
            AR_PricingMatrixService.MatrixSaveResult r = AR_PricingMatrixService.saveDraftInput(input);
            saved = [SELECT AR_CJM_Nearshore__c FROM AR_Price_Matrix__c WHERE Id = :r.matrixId];
        }
        System.assertEquals(200, saved.AR_CJM_Nearshore__c);
    }

    @IsTest
    static void testNearshoreRate_neitherExactNorDefault_blocksWithNamedMessage() {
        delete [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT'];
        AR_Nearshore_Referential__c other = maroc('Technicien', 150, 'EUR');
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Boolean threw = false;
        {
            try {
                AR_PricingMatrixService.saveDraftInput(nearshoreFromReferential(position.Id, other.Id, 'Senior Consultant'));
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('Maroc'), e.getMessage());
                System.assert(e.getMessage().contains('Senior Consultant'), e.getMessage());
            }
        }
        System.assertEquals(true, threw, 'Aucune ligne applicable : blocage, jamais un tarif substitué');
    }

    @IsTest
    static void testNearshoreRate_blankSeniorityOnReferentialRow_isNotTreatedAsDefault() {
        delete [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT'];
        AR_Nearshore_Referential__c blank = maroc(null, 99, 'EUR');
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Boolean threw = false;
        {
            try {
                AR_PricingMatrixService.saveDraftInput(nearshoreFromReferential(position.Id, blank.Id, null));
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testNearshoreRate_currencyMismatchStillBlocks() {
        AR_Nearshore_Referential__c exact = maroc('Technicien', 150, 'MAD');
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Boolean threw = false;
        {
            try {
                AR_PricingMatrixService.saveDraftInput(nearshoreFromReferential(position.Id, exact.Id, 'Technicien'));
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('MAD'), e.getMessage());
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testNearshoreRate_changingSeniorityOnSavedMatrix_recalculatesRate() {
        maroc('Technicien', 150, 'EUR');
        AR_Nearshore_Referential__c byDefault = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT' LIMIT 1];
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_Price_Matrix__c saved;
        {
            AR_PricingMatrixService.MatrixSaveResult first = AR_PricingMatrixService.saveDraftInput(
                nearshoreFromReferential(position.Id, byDefault.Id, 'Technicien'));
            AR_PricingMatrixService.MatrixInput again = nearshoreFromReferential(position.Id, byDefault.Id, 'Senior Consultant');
            again.matrixId = first.matrixId;
            AR_PricingMatrixService.saveDraftInput(again);
            saved = [SELECT AR_CJM_Nearshore__c, AR_Nearshore_Country__c FROM AR_Price_Matrix__c WHERE Id = :first.matrixId];
        }
        System.assertEquals(200, saved.AR_CJM_Nearshore__c);
        System.assertEquals(byDefault.Id, saved.AR_Nearshore_Country__c);
    }

    @IsTest
    static void testGetNearshoreReferentialOptions_exposesSeniorityPerRow() {
        maroc('Technicien', 150, 'EUR');
        List<AR_PricingMatrixService.ReferentialCountryOption> options = AR_PricingMatrixService.getNearshoreReferentialOptions();
        System.assertEquals(2, options.size());
        Set<String> seniorities = new Set<String>{ options[0].seniority, options[1].seniority };
        System.assert(seniorities.contains('DEFAULT') && seniorities.contains('Technicien'), String.valueOf(seniorities));
    }

    // Un BM (AR_Pricing_User seul) lit le référentiel : la règle de choix ne dépend pas du profil.
    @IsTest
    static void testResolveNearshoreRow_asBusinessManager_exactThenDefaultThenBlocked() {
        AR_Nearshore_Referential__c exact = maroc('Technicien', 150, 'EUR');
        Id defaultId = [SELECT Id FROM AR_Nearshore_Referential__c WHERE AR_Seniority__c = 'DEFAULT' LIMIT 1].Id;
        System.runAs(AR_TestPersona.bm()) {
            System.assertEquals(exact.Id, AR_PricingMatrixService.resolveNearshoreRow('Maroc', 'Technicien').Id);
            System.assertEquals(defaultId, AR_PricingMatrixService.resolveNearshoreRow('Maroc', 'Senior Consultant').Id);
            System.assertEquals(defaultId, AR_PricingMatrixService.resolveNearshoreRow('Maroc', null).Id);
            Boolean threw = false;
            try {
                AR_PricingMatrixService.resolveNearshoreRow('Tunisie', 'Technicien');
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('Tunisie / Technicien'), e.getMessage());
            }
            System.assertEquals(true, threw);
        }
    }

    // ------------------------------------------------------------------
    // Session 237 — entité obligatoire, dispense de dérogation (MC2/jour ≥ montant administré)
    // ------------------------------------------------------------------

    /** NEARSHORE, coût 200, RFA 50 % : MC2/jour = TJM × 0,5 − 200 ; sous le plancher 20 % dès que TJM < 667. */
    private static AR_PricingMatrixService.MatrixInput dispenseInput(Id positionId, Decimal tjm, String currencyCode) {
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(positionId, tjm, currencyCode);
        input.rfaPercent = 50;
        return input;
    }

    private static void setDerogationWaiver(Decimal amount) {
        AR_General_Setting__c row = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        row.AR_Derogation_Waiver_Amount__c = amount;
        update row;
    }

    /** Message de la refusée par validateInput, ou null si la validation passe. */
    private static String validateRefusalMessage(AR_PricingMatrixService.MatrixInput input) {
        Savepoint sp = Database.setSavepoint();
        String message;
        try {
            AR_PricingMatrixService.validateInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Database.rollback(sp);
        return message;
    }

    @IsTest
    static void testValidate_missingEntity_throwsAndNamesEntityField() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 400);
        input.entity = null;

        String message = validateRefusalMessage(input);

        System.assertNotEquals(null, message, 'validate() doit refuser une matrice sans entité');
        System.assert(message.contains(Label.AR_Msg_PTF_PrereqEntity), 'Le message doit nommer le champ « Entité House of ABY »');
    }

    @IsTest
    static void testRequestDerogation_missingEntity_throwsAndNamesEntityField() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;
        AR_PricingMatrixService.MatrixInput input = nearshoreInput(position.Id, 205);
        input.entity = null;
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = input;
        req.reason = 'Contexte concurrentiel tendu';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = UserInfo.getUserId();

        String message;
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }

        System.assertNotEquals(null, message, 'La demande de dérogation doit refuser une matrice sans entité');
        System.assert(message.contains(Label.AR_Msg_PTF_PrereqEntity), 'Le message doit nommer le champ « Entité House of ABY »');
    }

    @IsTest
    static void testValidate_mc2PerDayAtWaiver_validatedWithoutDerogation() {
        // MC2/jour = 600 × 0,5 − 200 = 100,0 exactement (borne incluse) ; MC2 % = 16,7 %, sous le plancher.
        setDerogationWaiver(100);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(dispenseInput(position.Id, 600, 'EUR'));

        System.assertEquals('below_floor', result.calculation.corridorSegment, 'la matrice reste sous le plancher');
        System.assertEquals('Validée', result.status, 'MC2/jour au montant de dispense : validation directe');
    }

    @IsTest
    static void testValidate_mc2PerDayJustUnderWaiver_stillNeedsDerogation() {
        // MC2/jour = 599,8 × 0,5 − 200 = 99,9 : une dérogation reste obligatoire.
        setDerogationWaiver(100);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        String message = validateRefusalMessage(dispenseInput(position.Id, 599.8, 'EUR'));

        System.assertEquals(Label.AR_Msg_PM_BelowFloorNeedsDerogation, message, 'MC2/jour 99,9 : dérogation obligatoire');
    }

    @IsTest
    static void testValidate_emptyWaiver_ruleDisabled_keepsCurrentBehaviour() {
        // Champ vide = règle désactivée : même MC2/jour de 100 que ci-dessus, refusée.
        setDerogationWaiver(null);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        String message = validateRefusalMessage(dispenseInput(position.Id, 600, 'EUR'));

        System.assertEquals(Label.AR_Msg_PM_BelowFloorNeedsDerogation, message, 'champ vide : aucune dispense, aucune valeur substituée');
    }

    @IsTest
    static void testValidate_gbpMatrix_waiverComparedInEuros() {
        // Taux 1,17 : MC2/jour = 585 × 0,5 − 200 = 92,5 GBP, soit 108,23 € ≥ 100 € → validée sans dérogation.
        insert new AR_Currency_Rate__c(
            AR_Currency_Code__c = 'GBP',
            AR_Rate_To_EUR__c = 1.17,
            AR_Effective_Date__c = Date.today().addDays(-1)
        );
        setDerogationWaiver(100);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.validateInput(dispenseInput(position.Id, 585, 'GBP'));

        System.assertEquals(92.5, result.calculation.mc2PerDay, 'MC2/jour native en GBP');
        System.assertEquals('Validée', result.status, 'comparée en euros, la MC2/jour atteint le montant de dispense');
    }

    @IsTest
    static void testRequestDerogation_dispensedMatrix_refused() {
        // MC2/jour au montant de dispense : la matrice se valide, une demande de dérogation est refusée.
        setDerogationWaiver(100);
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        Id reasonId = [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id;
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = dispenseInput(position.Id, 600, 'EUR');
        req.reason = 'Contexte concurrentiel tendu';
        req.derogationReasonIds = new List<Id>{ reasonId };
        req.selectedValidatorId = UserInfo.getUserId();

        String message;
        Savepoint sp = Database.setSavepoint();
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Database.rollback(sp);

        System.assertEquals(Label.AR_Msg_PM_DerogationNotNeeded, message, 'pas de dérogation quand la dispense s\'applique');
    }

    // ------------------------------------------------------------------
    // Périodes de frais OM (session 239b, docs/239) : lissage à la sauvegarde, JSON illisible, garde de validation.
    // ------------------------------------------------------------------

    private static final String TWO_PERIODS_JSON = '[{"days":180,"feeIk":12,"feeMeals":0,"feeLodging":0,"feeOmOther":0}]';

    @IsTest
    static void testSaveDraftInput_feePeriods_smoothedAndReloaded() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 700);
        input.feeLodging = 85;
        input.numberOfDays = 200;
        input.feePeriods = TWO_PERIODS_JSON;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // (20 j x 85 + 180 j x 12) / 200 = 19,30 : le calcul porte la moyenne lissée, pas la période 1 seule.
        System.assertEquals(19.3, result.calculation.feeOmPerDay);
        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.loadMatrixInput(result.matrixId, false);
        List<AR_PricingCalculator.FeePeriod> periods = AR_PricingMatrixService.parseFeePeriods(reloaded.feePeriods);
        System.assertEquals(1, periods.size(), 'Une période ajoutée relue à l\'identique');
        System.assertEquals(180, periods[0].days);
        System.assertEquals(12, periods[0].feeIk);
    }

    @IsTest
    static void testSaveDraftInput_feePeriodsUnreadable_throwsExplicitErrorAndWritesNothing() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 700);
        input.feePeriods = '{pas du json';
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__c];

        String message;
        try {
            AR_PricingMatrixService.saveDraftInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }

        System.assertEquals(Label.AR_Msg_PM_FeePeriodsInvalidJson, message, 'Erreur explicite, jamais une liste vide silencieuse');
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__c], 'Aucun enregistrement écrit');
    }

    @IsTest
    static void testPlannedLeaveExceedingMission_draftAccepted_validationRefused() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 700);
        input.numberOfDays = 20;
        input.plannedLeaveDays = 25;

        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(input);
        System.assertNotEquals(null, draft.matrixId, 'Le brouillon est accepté malgré des congés supérieurs à la mission');
        AR_Price_Matrix__c saved = [SELECT AR_Planned_Leave_Days__c FROM AR_Price_Matrix__c WHERE Id = :draft.matrixId];
        System.assertEquals(25, saved.AR_Planned_Leave_Days__c, 'Les congés saisis sont enregistrés');

        Boolean listed = false;
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            if (p.label == Label.AR_Msg_PM_LeaveExceedsMission) {
                listed = true;
            }
        }
        System.assert(listed, 'Le prérequis bloquant apparaît dans la liste de l\'écran');

        String message;
        try {
            AR_PricingMatrixService.validateInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assert(
            message != null && message.contains(Label.AR_Msg_PM_LeaveExceedsMission),
            'Validation refusée nommément : ' + message
        );
    }

    @IsTest
    static void testPlannedLeave_reducesBillableDaysAndRaisesMissionFees() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 700);
        input.numberOfDays = 254;
        input.feeTraining = 2540;
        AR_PricingMatrixService.MatrixSaveResult withoutLeave = AR_PricingMatrixService.saveDraftInput(input);
        AR_Price_Matrix__c a = [SELECT AR_Total_Daily_Cost__c, AR_MC2_Percent__c FROM AR_Price_Matrix__c WHERE Id = :withoutLeave.matrixId];

        input.matrixId = withoutLeave.matrixId;
        input.plannedLeaveDays = 25;
        AR_PricingMatrixService.saveDraftInput(input);
        AR_Price_Matrix__c b = [
            SELECT AR_Total_Daily_Cost__c, AR_MC2_Percent__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c,
                   AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c
            FROM AR_Price_Matrix__c WHERE Id = :withoutLeave.matrixId
        ];
        System.assertEquals(229, AR_PricingMatrixService.billableDaysOf(b), '254 jours de mission - 25 jours de congés');
        // Formation 2540 : 10 €/j sur 254 jours, 2540/229 sur 229 jours facturables.
        System.assert(
            Math.abs((b.AR_Total_Daily_Cost__c - a.AR_Total_Daily_Cost__c) - (2540.0 / 229 - 10)) < 0.01,
            'Le coût journalier augmente de 2540/229 - 10 : ' + a.AR_Total_Daily_Cost__c + ' -> ' + b.AR_Total_Daily_Cost__c
        );
        System.assert(b.AR_MC2_Percent__c < a.AR_MC2_Percent__c, 'La MC2 baisse avec les congés');
    }

    @IsTest
    static void testFeePeriodsExceedingMission_draftAccepted_validationRefused() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 700);
        input.feeLodging = 40;
        input.numberOfDays = 100;
        input.feePeriods = '[{"days":80,"feeIk":20,"feeMeals":0,"feeLodging":0,"feeOmOther":0},'
            + '{"days":40,"feeIk":0,"feeMeals":10,"feeLodging":0,"feeOmOther":0}]';

        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(input);
        System.assertNotEquals(null, draft.matrixId, 'Le brouillon est accepté malgré le dépassement');

        Boolean listed = false;
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            if (p.label == Label.AR_Msg_PM_FeePeriodsExceedMission) {
                listed = true;
            }
        }
        System.assert(listed, 'Le prérequis bloquant apparaît dans la liste de l\'écran');

        String message;
        try {
            AR_PricingMatrixService.validateInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assert(
            message != null && message.contains(Label.AR_Msg_PM_FeePeriodsExceedMission),
            'Validation refusée nommément : ' + message
        );
    }

    // ------------------------------------------------------------------
    // Périodes de TJM (docs/254) : pondéré stocké, JSON illisible, gardes de validation, prix effectif.
    // ------------------------------------------------------------------

    private static final String ONE_TJM_PERIOD_JSON = '[{"days":60,"tjm":700}]';

    @IsTest
    static void testSaveDraftInput_tjmPeriods_weightedStoredAndReloaded() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
        input.numberOfDays = 120;
        input.tjmPeriods = ONE_TJM_PERIOD_JSON;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // (60 × 650 + 60 × 700) / 120 = 675 ; MC2/j = 675 - 417 = 258.
        System.assertEquals(675, result.calculation.tjmWeighted);
        System.assertEquals(258, result.calculation.mc2PerDay, 'MC2 calculée sur le pondéré');
        AR_Price_Matrix__c stored = [
            SELECT AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_MC2_Per_Day__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(650, stored.AR_Proposed_TJM__c, 'La période 1 reste le TJM saisi');
        System.assertEquals(675, stored.AR_TJM_Weighted__c, 'Pondéré écrit par le moteur');
        System.assertEquals(258, stored.AR_MC2_Per_Day__c);

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.loadMatrixInput(result.matrixId, false);
        List<AR_PricingCalculator.TjmPeriod> periods = AR_PricingMatrixService.parseTjmPeriods(reloaded.tjmPeriods);
        System.assertEquals(1, periods.size(), 'Une période ajoutée relue à l\'identique');
        System.assertEquals(60, periods[0].days);
        System.assertEquals(700, periods[0].tjm);
    }

    @IsTest
    static void testSaveDraftInput_tjmPeriodsUnreadableOrNegative_throwsExplicitError() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__c];
        List<String> payloads = new List<String>{ '{pas du json', '[{"days":60,"tjm":-700}]' };

        for (String payload : payloads) {
            AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
            input.numberOfDays = 120;
            input.tjmPeriods = payload;
            String message;
            try {
                AR_PricingMatrixService.saveDraftInput(input);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertEquals(Label.AR_Msg_PM_TjmPeriodsInvalid, message, 'Erreur explicite pour ' + payload);
        }
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__c], 'Aucun enregistrement écrit');
    }

    @IsTest
    static void testTjmPeriodsGuards_draftAcceptedValidationRefusedByName() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        // Durée de mission absente alors que le TJM évolue.
        AR_PricingMatrixService.MatrixInput unknown = cdiInput(position.Id, 45000, null, 650);
        unknown.tjmPeriods = ONE_TJM_PERIOD_JSON;
        assertTjmPrerequisite(unknown, Label.AR_Msg_PM_TjmPeriodsMissionUnknown);

        // Périodes ajoutées couvrant toute la mission (120 ≥ 100).
        AR_PricingMatrixService.MatrixInput exceed = cdiInput(position.Id, 45000, null, 650);
        exceed.numberOfDays = 100;
        exceed.tjmPeriods = '[{"days":60,"tjm":700},{"days":60,"tjm":750}]';
        assertTjmPrerequisite(exceed, Label.AR_Msg_PM_TjmPeriodsExceedMission);

        // Période incomplète : TJM à 0.
        AR_PricingMatrixService.MatrixInput incomplete = cdiInput(position.Id, 45000, null, 650);
        incomplete.numberOfDays = 120;
        incomplete.tjmPeriods = '[{"days":60,"tjm":0}]';
        assertTjmPrerequisite(incomplete, Label.AR_Msg_PM_TjmPeriodIncomplete);

        // Cinq TJM au total (P1 + 4 ajoutées).
        AR_PricingMatrixService.MatrixInput many = cdiInput(position.Id, 45000, null, 650);
        many.numberOfDays = 500;
        many.tjmPeriods = '[{"days":10,"tjm":700},{"days":10,"tjm":700},{"days":10,"tjm":700},{"days":10,"tjm":700}]';
        assertTjmPrerequisite(many, Label.AR_Msg_PM_TjmPeriodsTooMany);
    }

    private static void assertTjmPrerequisite(AR_PricingMatrixService.MatrixInput input, String expectedLabel) {
        Boolean listed = false;
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            if (p.label == expectedLabel) {
                listed = true;
            }
        }
        System.assert(listed, 'Prérequis attendu : ' + expectedLabel);
        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(input);
        System.assertNotEquals(null, draft.matrixId, 'Le brouillon reste accepté');
    }

    private static Boolean negoPricesListed(AR_PricingMatrixService.MatrixInput input) {
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            if (p.label == Label.AR_Msg_PM_NegoPricesMissing && p.blocking) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void testNegoPrices_withoutGrid_blockValidationButNotDraft() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
        input.clientGrid = false;

        System.assert(negoPricesListed(input), 'Ni P2 ni P3, case décochée : prérequis bloquant');
        String refusal = validateRefusalMessage(input);
        System.assertNotEquals(null, refusal, 'La validation est refusée');
        System.assert(refusal.contains(Label.AR_Msg_PM_NegoPricesMissing), 'Le message nomme les prix manquants : ' + refusal);

        input.negoPrice2 = 640;
        System.assert(negoPricesListed(input), 'Le plancher manque encore');
        input.negoPrice3 = 600;
        System.assert(!negoPricesListed(input), 'Les deux prix saisis : plus de blocage');

        input.negoPrice2 = null;
        input.negoPrice3 = null;
        System.assertNotEquals(null, AR_PricingMatrixService.saveDraftInput(input).matrixId, 'Le brouillon reste accepté');
    }

    @IsTest
    static void testNegoPrices_withGrid_noBlockAndPricesCleared() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
        input.clientGrid = true;
        input.negoPrice2 = 640;
        input.negoPrice3 = 600;

        System.assert(!negoPricesListed(input), 'Grille cochée : aucun blocage');
        AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(input);
        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(draft.matrixId);
        System.assertEquals(true, reloaded.clientGrid, 'La case est relue');
        System.assertEquals(null, reloaded.negoPrice2, 'Prix intermédiaire vidé');
        System.assertEquals(null, reloaded.negoPrice3, 'Plancher vidé');
    }

    @IsTest
    static void testNegoPrices_withoutGrid_blockDerogationRequest() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Nearshore' LIMIT 1];
        AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
        req.matrixInput = nearshoreInput(position.Id, 205);
        req.matrixInput.clientGrid = false;
        req.reason = 'Contexte concurrentiel tendu';
        req.derogationReasonIds = new List<Id>{ [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Test A' LIMIT 1].Id };
        req.selectedValidatorId = UserInfo.getUserId();

        String message;
        try {
            AR_PricingMatrixService.requestDerogationInput(req);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertNotEquals(null, message, 'La demande de dérogation est refusée');
        System.assert(message.contains(Label.AR_Msg_PM_NegoPricesMissing), 'Message : ' + message);
    }

    @IsTest
    static void testEffectiveTjm_weightedWhenComputedElseProposed() {
        AR_Price_Matrix__c withWeighted = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 650, AR_TJM_Weighted__c = 675);
        AR_Price_Matrix__c withoutWeighted = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 650);

        System.assertEquals(675, AR_PricingMatrixService.effectiveTjm(withWeighted), 'Le pondéré fait foi');
        System.assertEquals(650, AR_PricingMatrixService.effectiveTjm(withoutWeighted), 'Repli sur le TJM saisi (matrice antérieure)');
    }

    // ------------------------------------------------------------------
    // Régie sans régule (docs/265) : plan reconstruit côté serveur, MC2 pilotée, gardes de validation.
    // ------------------------------------------------------------------

    private static final String RPLSR_AUG6_PRODUCED =
        '{"2027-02":9,"2027-03":18,"2027-04":18,"2027-05":19,"2027-06":18,"2027-07":18,"2027-08":6,"2027-09":18,"2027-10":18,"2027-11":19,"2027-12":18,"2028-01":18}';

    private static AR_PricingMatrixService.MatrixInput rplsrInput(Boolean enabled) {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        update new AR_PTF_Entity_Referential__c(
            Id = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Country__c = 'France'
        );
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, 'Abylsen GAMMA', 700);
        input.startDate = Date.newInstance(2027, 2, 15);
        input.endDate = Date.newInstance(2028, 1, 31);
        input.numberOfDays = 240;
        input.rplsrEnabled = enabled;
        return input;
    }

    @IsTest
    static void testRplsr_plan2Aug6_storedSumsAndPilotedMc2() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);
        input.rplsrDaysPerMonth = 18.17;
        input.rplsrProduced = RPLSR_AUG6_PRODUCED;

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        AR_Price_Matrix__c stored = [
            SELECT AR_RPLSR_Enabled__c, AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
                   AR_MC2_Per_Day__c, AR_MC2_Percent__c, AR_Total_Daily_Cost__c
            FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(true, stored.AR_RPLSR_Enabled__c);
        System.assertEquals(208.96, stored.AR_RPLSR_Days_Sold__c);
        System.assertEquals(197, stored.AR_RPLSR_Days_Produced__c);
        System.assertEquals(417, stored.AR_Total_Daily_Cost__c, 'Le coût unitaire garde son sens');
        // Script de référence : 700 − 417 × 197 / 208,96 = 306,87 → 306,9 ; 43,84 %.
        System.assertEquals(306.9, stored.AR_MC2_Per_Day__c);
        System.assertEquals(43.84, stored.AR_MC2_Percent__c);
        System.assertEquals(306.9, result.calculation.mc2PerDay);
        // Mode éteint pour mémoire : 700 − 417 = 283,0 ; 40,43 %.
        System.assertEquals(283.0, result.calculation.mc2PerDayTheoretical);
        System.assertEquals(40.43, result.calculation.mc2PercentTheoretical);
        System.assertNotEquals(null, result.calculation.rplsrRatio);
        System.assertNotEquals(null, result.rplsrPlan);

        List<AR_WorkingCalendar.PlanMonth> plan = AR_PricingMatrixService.parseRplsrPlan(result.rplsrPlan);
        System.assertEquals(12, plan.size());
        System.assertEquals('2027-02', plan[0].m);
        System.assertEquals(10, plan[0].ouvres, 'Mois partiel, France');
        System.assertEquals(9.09, plan[0].vendus);
        System.assertEquals(6, plan[6].produits, 'Août à 6 j conservé tel que saisi');

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.loadMatrixInput(result.matrixId, false);
        System.assertEquals(true, reloaded.rplsrEnabled);
        System.assertEquals(18.17, reloaded.rplsrDaysPerMonth);
        System.assertEquals(result.rplsrPlan, reloaded.rplsrPlan);
        System.assertNotEquals(null, reloaded.storedResult.rplsrRatio, 'Matrice rouverte : ratio relu des champs figés');
        System.assertEquals(306.9, reloaded.storedResult.mc2PerDay);
        System.assertEquals(283.0, reloaded.storedResult.mc2PerDayTheoretical);
    }

    @IsTest
    static void testRplsr_numberOfDaysFollowsSoldDays_onlyWhenActive() {
        AR_PricingMatrixService.MatrixInput active = rplsrInput(true);
        Id activeId = AR_PricingMatrixService.saveDraftInput(active).matrixId;
        AR_Price_Matrix__c storedActive = [
            SELECT AR_Number_Of_Days__c, AR_RPLSR_Days_Sold__c FROM AR_Price_Matrix__c WHERE Id = :activeId
        ];
        System.assertNotEquals(null, storedActive.AR_RPLSR_Days_Sold__c);
        System.assertEquals(storedActive.AR_RPLSR_Days_Sold__c, storedActive.AR_Number_Of_Days__c, 'Régie par lot : jours mission = jours vendus');
        System.assertNotEquals(240, storedActive.AR_Number_Of_Days__c);

        AR_PricingMatrixService.MatrixInput inactive = rplsrInput(false);
        Id inactiveId = AR_PricingMatrixService.saveDraftInput(inactive).matrixId;
        AR_Price_Matrix__c storedInactive = [SELECT AR_Number_Of_Days__c FROM AR_Price_Matrix__c WHERE Id = :inactiveId];
        System.assertEquals(240, storedInactive.AR_Number_Of_Days__c, 'Mode inactif : jours saisis inchangés');
    }

    @IsTest
    static void testRplsr_defaultBaseAndBalancedPlanWhenNothingSent() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);

        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);

        AR_Price_Matrix__c stored = [
            SELECT AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c
            FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(18.17, stored.AR_RPLSR_Days_Per_Month__c, '218 ÷ 12, HALF_UP');
        System.assertEquals(208.96, stored.AR_RPLSR_Days_Sold__c);
        System.assertEquals(209, stored.AR_RPLSR_Days_Produced__c, 'Répartition équilibrée du cas C2');
    }

    @IsTest
    static void testRplsr_datesChange_rebuildsBalancedPlan() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);
        input.rplsrDaysPerMonth = 18.17;
        input.rplsrProduced = RPLSR_AUG6_PRODUCED;
        Id matrixId = AR_PricingMatrixService.saveDraftInput(input).matrixId;

        // Même mois, fin de mission avancée : les jours produits envoyés sont périmés.
        AR_PricingMatrixService.MatrixInput moved = AR_PricingMatrixService.loadMatrixInput(matrixId, false);
        moved.rplsrProduced = RPLSR_AUG6_PRODUCED;
        moved.endDate = Date.newInstance(2028, 1, 14);
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(moved);

        List<AR_WorkingCalendar.PlanMonth> plan = AR_PricingMatrixService.parseRplsrPlan(result.rplsrPlan);
        System.assertEquals(18, plan[6].produits, 'Août redevient équilibré : modification manuelle perdue (assumé)');

        // Les mêmes dates et le même plan envoyé : conservé.
        AR_PricingMatrixService.MatrixInput same = AR_PricingMatrixService.loadMatrixInput(matrixId, false);
        same.rplsrProduced = '{"2027-02":9,"2027-03":18,"2027-04":18,"2027-05":19,"2027-06":18,"2027-07":18,"2027-08":7,"2027-09":18,"2027-10":18,"2027-11":19,"2027-12":18,"2028-01":9}';
        plan = AR_PricingMatrixService.parseRplsrPlan(AR_PricingMatrixService.saveDraftInput(same).rplsrPlan);
        System.assertEquals(7, plan[6].produits);
    }

    @IsTest
    static void testRplsr_baseChange_rebuildsBalancedPlan() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);
        input.rplsrDaysPerMonth = 18.17;
        input.rplsrProduced = RPLSR_AUG6_PRODUCED;
        Id matrixId = AR_PricingMatrixService.saveDraftInput(input).matrixId;

        AR_PricingMatrixService.MatrixInput changed = AR_PricingMatrixService.loadMatrixInput(matrixId, false);
        changed.rplsrDaysPerMonth = 20;
        changed.rplsrProduced = RPLSR_AUG6_PRODUCED;
        AR_PricingMatrixService.saveDraftInput(changed);

        AR_Price_Matrix__c stored = [SELECT AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        System.assertEquals(stored.AR_RPLSR_Days_Sold__c.setScale(0, RoundingMode.HALF_UP), stored.AR_RPLSR_Days_Produced__c, 'Plan équilibré sur la nouvelle base');
    }

    @IsTest
    static void testRplsr_modeOff_unchangedAndOutputsNull() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(false);
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);

        System.assertEquals(null, result.rplsrPlan);
        System.assertEquals(null, result.calculation.rplsrRatio);
        System.assertEquals(null, result.calculation.totalDailyCostPiloted);
        System.assertEquals(283.0, result.calculation.mc2PerDay, 'MC2 du mode éteint');
        AR_Price_Matrix__c stored = [
            SELECT AR_RPLSR_Enabled__c, AR_RPLSR_Plan__c, AR_RPLSR_Days_Sold__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(false, stored.AR_RPLSR_Enabled__c);
        System.assertEquals(null, stored.AR_RPLSR_Plan__c);
        System.assertEquals(null, stored.AR_RPLSR_Days_Sold__c);
    }

    @IsTest
    static void testRplsr_unreadableProducedJson_throwsExplicitError() {
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__c];
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);
        input.rplsrProduced = '{pas du json';
        String message;
        try {
            AR_PricingMatrixService.saveDraftInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(Label.AR_Msg_PM_RplsrPlanInvalid, message);
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__c], 'Aucun enregistrement écrit');
    }

    @IsTest
    static void testRplsr_unreadableStoredPlan_throwsExplicitError() {
        String message;
        try {
            AR_PricingMatrixService.parseRplsrPlan('{"v":1,"mois":"x"}');
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(Label.AR_Msg_PM_RplsrPlanInvalid, message);
    }

    private static Set<String> prerequisiteLabels(AR_Price_Matrix__c m) {
        Set<String> labels = new Set<String>();
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.rplsrPrerequisites(m)) {
            labels.add(p.label);
        }
        return labels;
    }

    @IsTest
    static void testRplsrGuards_namedAndOffModeSilent() {
        AR_Price_Matrix__c ok = new AR_Price_Matrix__c(
            AR_RPLSR_Enabled__c = true, AR_RPLSR_Days_Per_Month__c = 18.17,
            AR_Start_Date__c = Date.newInstance(2027, 3, 1), AR_End_Date__c = Date.newInstance(2027, 4, 30),
            AR_RPLSR_Plan__c = '{"v":1,"mois":[{"m":"2027-03","ouvres":23,"vendus":18.17,"produits":18},{"m":"2027-04","ouvres":21,"vendus":18.17,"produits":19}]}'
        );
        System.assert(prerequisiteLabels(ok).isEmpty(), 'Plan valide');

        AR_Price_Matrix__c off = ok.clone();
        off.AR_RPLSR_Enabled__c = false;
        off.AR_RPLSR_Plan__c = 'illisible mais ignoré hors mode';
        System.assert(prerequisiteLabels(off).isEmpty(), 'Hors mode, aucune garde');

        AR_Price_Matrix__c noDates = ok.clone();
        noDates.AR_End_Date__c = null;
        System.assert(prerequisiteLabels(noDates).contains(Label.AR_Msg_PM_RplsrDatesMissing));

        for (Decimal badBase : new List<Decimal>{ 0, -1, 23.01, null }) {
            AR_Price_Matrix__c bad = ok.clone();
            bad.AR_RPLSR_Days_Per_Month__c = badBase;
            System.assert(prerequisiteLabels(bad).contains(Label.AR_Msg_PM_RplsrBaseInvalid), 'Base ' + badBase);
        }
        AR_Price_Matrix__c edge = ok.clone();
        edge.AR_RPLSR_Days_Per_Month__c = 23;
        System.assert(!prerequisiteLabels(edge).contains(Label.AR_Msg_PM_RplsrBaseInvalid), '23 est accepté');

        AR_Price_Matrix__c noPlan = ok.clone();
        noPlan.AR_RPLSR_Plan__c = null;
        System.assert(prerequisiteLabels(noPlan).contains(Label.AR_Msg_PM_RplsrPlanMissing));

        AR_Price_Matrix__c missingMonth = ok.clone();
        missingMonth.AR_End_Date__c = Date.newInstance(2027, 5, 31);
        System.assert(prerequisiteLabels(missingMonth).contains(Label.AR_Msg_PM_RplsrPlanMissing), 'Plan ne couvrant pas tous les mois');

        for (String badProduced : new List<String>{ '9.5', '-1', '24', 'null' }) {
            AR_Price_Matrix__c bad = ok.clone();
            bad.AR_RPLSR_Plan__c = ok.AR_RPLSR_Plan__c.replace('"produits":18', '"produits":' + badProduced);
            System.assert(prerequisiteLabels(bad).contains(Label.AR_Msg_PM_RplsrProducedInvalid), 'Produits ' + badProduced);
        }

        AR_Price_Matrix__c none = ok.clone();
        none.AR_RPLSR_Plan__c = ok.AR_RPLSR_Plan__c.replace('"produits":18', '"produits":0').replace('"produits":19', '"produits":0');
        System.assertEquals(new Set<String>{ Label.AR_Msg_PM_RplsrNoProduced }, prerequisiteLabels(none), 'Aucun jour produit : refus nommé, seul');
        AR_Price_Matrix__c one = ok.clone();
        one.AR_RPLSR_Plan__c = ok.AR_RPLSR_Plan__c.replace('"produits":18', '"produits":0').replace('"produits":19', '"produits":1');
        System.assert(prerequisiteLabels(one).isEmpty(), 'Un seul jour produit suffit');
    }

    @IsTest
    static void testRplsrRatioOf_zeroProducedIsARealRatio() {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_RPLSR_Enabled__c = true, AR_RPLSR_Days_Sold__c = 36.34, AR_RPLSR_Days_Produced__c = 0
        );
        System.assertEquals(0, AR_PricingMatrixService.rplsrRatioOf(m), 'Ratio 0, jamais le mode éteint');
        m.AR_RPLSR_Enabled__c = false;
        System.assertEquals(null, AR_PricingMatrixService.rplsrRatioOf(m), 'Mode éteint : ratio absent');
    }

    @IsTest
    static void testRplsrGuards_validationAndDerogationRefusedDraftAccepted() {
        AR_PricingMatrixService.MatrixInput input = rplsrInput(true);
        input.endDate = null;
        input.numberOfDays = null;

        Boolean listed = false;
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            if (p.label == Label.AR_Msg_PM_RplsrDatesMissing) {
                listed = true;
            }
        }
        System.assert(listed, 'Dates absentes nommées');
        System.assertNotEquals(null, AR_PricingMatrixService.saveDraftInput(input).matrixId, 'Le brouillon reste libre');

        String message;
        try {
            AR_PricingMatrixService.validateInput(input);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assert(message != null && message.contains(Label.AR_Msg_PM_RplsrDatesMissing), 'Validation refusée nommément : ' + message);
    }

    @IsTest
    static void testRplsrRatioOf_noSoldDaysMeansNoRatio() {
        System.assertEquals(null, AR_PricingMatrixService.rplsrRatioOf(new AR_Price_Matrix__c(AR_RPLSR_Enabled__c = true, AR_RPLSR_Days_Sold__c = 0, AR_RPLSR_Days_Produced__c = 0)));
        System.assertEquals(null, AR_PricingMatrixService.rplsrRatioOf(new AR_Price_Matrix__c(AR_RPLSR_Enabled__c = false, AR_RPLSR_Days_Sold__c = 10, AR_RPLSR_Days_Produced__c = 10)));
        System.assertEquals(0.5, AR_PricingMatrixService.rplsrRatioOf(new AR_Price_Matrix__c(AR_RPLSR_Enabled__c = true, AR_RPLSR_Days_Sold__c = 10, AR_RPLSR_Days_Produced__c = 5)));
    }

    @IsTest
    static void testDefaultRplsrDaysPerMonth_218() {
        System.assertEquals(18.17, AR_PricingMatrixService.defaultRplsrDaysPerMonth(218));
    }

    @IsTest
    static void testRplsrMention_activeMatrix_carriesDaysAndClassicMc2() {
        // Exemple de Matthieu : TJM 495, coût 380, RFA 0. MC2 classique = (495 - 380) / 495 = 23,2 %.
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_RPLSR_Enabled__c = true,
            AR_RPLSR_Days_Sold__c = 218,
            AR_RPLSR_Days_Produced__c = 212,
            AR_Proposed_TJM__c = 495,
            AR_Total_Daily_Cost__c = 380,
            AR_RFA_Percent__c = 0
        );
        String mention = AR_PricingMatrixService.rplsrMention(m);
        System.assertNotEquals(null, mention, 'Mode actif : mention présente');
        System.assert(mention.contains('212'), 'Jours produits : ' + mention);
        System.assert(mention.contains('218'), 'Jours vendus : ' + mention);
        System.assert(mention.contains('23,2'), 'MC2 régie classique : ' + mention);
    }

    @IsTest
    static void testRplsrMention_inactiveMatrix_isNull() {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(AR_RPLSR_Enabled__c = false, AR_Proposed_TJM__c = 495);
        System.assertEquals(null, AR_PricingMatrixService.rplsrMention(m), 'Mode éteint : aucune mention');
    }

    // ------------------------------------------------------------------
    // Périodes de salaire : CJM pondéré stocké, gardes de validation, statut sans salaire.
    // ------------------------------------------------------------------

    @IsTest
    static void testSalaryPeriods_weightedCjmDrivesMc2AndIsReloaded() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
        input.numberOfDays = 120;
        input.salaryPeriods = '[{"days":60,"salary":50000}]';

        Test.startTest();
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        Test.stopTest();

        // P1 : round(45000 × 2,02 / 218) = 417 ; P2 : round(50000 × 2,02 / 218) = 463 ; (60 × 417 + 60 × 463) / 120 = 440.
        System.assertEquals(440, result.calculation.cjm, 'CJM pondéré par les jours');
        System.assertEquals(2, result.calculation.salaryPeriods.size());
        System.assertEquals(417, result.calculation.salaryPeriods[0].cjm);
        System.assertEquals(60, result.calculation.salaryPeriods[0].days);
        System.assertEquals(463, result.calculation.salaryPeriods[1].cjm);
        System.assertEquals(210, result.calculation.mc2PerDay, 'MC2 = 650 − 440');
        AR_Price_Matrix__c stored = [
            SELECT AR_Annual_Salary__c, AR_Salary_Periods__c, AR_MC2_Per_Day__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(45000, stored.AR_Annual_Salary__c, 'La période 1 reste le salaire saisi');
        System.assertEquals(210, stored.AR_MC2_Per_Day__c);

        AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.loadMatrixInput(result.matrixId, false);
        List<AR_PricingCalculator.SalaryPeriod> periods = AR_PricingMatrixService.parseSalaryPeriods(reloaded.salaryPeriods);
        System.assertEquals(1, periods.size(), 'Une période ajoutée relue à l\'identique');
        System.assertEquals(60, periods[0].days);
        System.assertEquals(50000, periods[0].salary);
    }

    @IsTest
    static void testSalaryPeriods_unreadableOrNegative_throwsExplicitError() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        Integer before = [SELECT COUNT() FROM AR_Price_Matrix__c];
        for (String payload : new List<String>{ '{pas du json', '[{"days":60,"salary":-1}]' }) {
            AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, 45000, null, 650);
            input.numberOfDays = 120;
            input.salaryPeriods = payload;
            String message;
            try {
                AR_PricingMatrixService.saveDraftInput(input);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertEquals(Label.AR_Msg_PM_SalaryPeriodsInvalid, message, 'Erreur explicite pour ' + payload);
        }
        System.assertEquals(before, [SELECT COUNT() FROM AR_Price_Matrix__c], 'Aucun enregistrement écrit');
    }

    @IsTest
    static void testSalaryPeriodsGuards_draftAcceptedValidationRefusedByName() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];

        AR_PricingMatrixService.MatrixInput unknown = cdiInput(position.Id, 45000, null, 650);
        unknown.salaryPeriods = '[{"days":60,"salary":50000}]';
        assertTjmPrerequisite(unknown, Label.AR_Msg_PM_SalaryPeriodsMissionUnknown);

        // Jours incohérents : 60 + 60 ≥ 100 jours de mission.
        AR_PricingMatrixService.MatrixInput exceed = cdiInput(position.Id, 45000, null, 650);
        exceed.numberOfDays = 100;
        exceed.salaryPeriods = '[{"days":60,"salary":50000},{"days":60,"salary":52000}]';
        assertTjmPrerequisite(exceed, Label.AR_Msg_PM_SalaryPeriodsExceedMission);
        String refusal = validateRefusalMessage(exceed);
        System.assert(
            refusal != null && refusal.contains(Label.AR_Msg_PM_SalaryPeriodsExceedMission),
            'Validation refusée nommément : ' + refusal
        );

        AR_PricingMatrixService.MatrixInput incomplete = cdiInput(position.Id, 45000, null, 650);
        incomplete.numberOfDays = 120;
        incomplete.salaryPeriods = '[{"days":60,"salary":0}]';
        assertTjmPrerequisite(incomplete, Label.AR_Msg_PM_SalaryPeriodIncomplete);

        AR_PricingMatrixService.MatrixInput many = cdiInput(position.Id, 45000, null, 650);
        many.numberOfDays = 500;
        many.salaryPeriods = '[{"days":10,"salary":50000},{"days":10,"salary":50000},{"days":10,"salary":50000},{"days":10,"salary":50000}]';
        assertTjmPrerequisite(many, Label.AR_Msg_PM_SalaryPeriodsTooMany);
    }

    @IsTest
    static void testSalaryPeriods_ignoredForContractWithoutSalary() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin CDI' LIMIT 1];
        AR_PricingMatrixService.MatrixInput input = cdiInput(position.Id, null, null, 650);
        input.contractType = 'INDEP';
        input.cjmBeforeMarkup = 300;
        input.markupApplied = 54;
        input.numberOfDays = 100;
        input.salaryPeriods = '[{"days":60,"salary":50000},{"days":60,"salary":0}]';

        Set<String> salaryLabels = new Set<String>{
            Label.AR_Msg_PM_SalaryPeriodIncomplete,
            Label.AR_Msg_PM_SalaryPeriodsExceedMission,
            Label.AR_Msg_PM_SalaryPeriodsMissionUnknown,
            Label.AR_Msg_PM_SalaryPeriodsTooMany
        };
        for (AR_PTFDataService.Prerequisite p : AR_PricingMatrixService.validationPrerequisitesForInput(input)) {
            System.assert(!salaryLabels.contains(p.label), 'Aucune garde de salaire : ' + p.label);
        }
        AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.saveDraftInput(input);
        System.assertEquals(354, result.calculation.cjm, 'CJM INDEP inchangé');
        System.assert(result.calculation.salaryPeriods.isEmpty(), 'Périodes de salaire ignorées');
    }

    // ---------- Session 291c : matrice supprimée ou plus accessible ----------

    private static String gonePrefix() {
        return Label.AR_Msg_PM_MatrixGone;
    }

    private static String messageOf(System.Callable call) {
        try {
            call.call('run', null);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private class OpenMatrixCall implements System.Callable {
        private final Id matrixId;
        private final String what;
        OpenMatrixCall(Id matrixId, String what) {
            this.matrixId = matrixId;
            this.what = what;
        }
        public Object call(String action, Map<String, Object> args) {
            if (what == 'input') {
                return AR_PricingMatrixService.getMatrixInput(matrixId);
            } else if (what == 'context') {
                return AR_PricingMatrixService.resolveRecordContext(matrixId);
            } else if (what == 'recalculate') {
                return AR_PricingMatrixService.recalculate(matrixId);
            }
            return AR_PricingMatrixService.loadMatrixInput(matrixId, false);
        }
    }

    @IsTest
    static void testDeletedMatrix_everyScreenEntryPointRaisesTheNamedMessage() {
        Id gone = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id;
        delete new AR_Price_Matrix__c(Id = gone);
        System.assertEquals(0, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :gone], 'La matrice n’existe plus');
        for (String what : new List<String>{ 'input', 'context', 'recalculate', 'load' }) {
            String message = messageOf(new OpenMatrixCall(gone, what));
            System.assertEquals(gonePrefix(), message, 'Point d’entrée ' + what + ' : message métier, jamais « List has no rows »');
        }
        System.assert(gonePrefix().contains('n\'existe plus') || gonePrefix().contains('no longer'), 'Texte du libellé : ' + gonePrefix());
    }

    @IsTest
    static void testMatrixNotSharedWithTheUser_raisesTheSameMessage() {
        Id matrixId = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id;
        User stranger = AR_TestPersona.bm();
        String message;
        String expectedMessage;
        Integer visible;
        System.runAs(stranger) {
            visible = [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :matrixId];
            message = messageOf(new OpenMatrixCall(matrixId, 'input'));
            // Le libellé suit la langue de l'utilisateur (persona « fr »), pas celle de l'exécutant du test.
            expectedMessage = gonePrefix();
        }
        System.assertEquals(0, visible, 'Prérequis : la matrice est invisible pour cet utilisateur');
        System.assertEquals(expectedMessage, message);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :matrixId], 'La matrice existe toujours pour son propriétaire');
    }

    @IsTest
    static void testRequestedValidatorOnDeletedMatrix_raisesTheNamedMessage() {
        Id gone = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1].Id;
        delete new AR_Price_Matrix__c(Id = gone);
        String message;
        try {
            AR_PricingMatrixService.requireSelectableValidator(gone, UserInfo.getUserId());
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals(gonePrefix(), message);
    }
}