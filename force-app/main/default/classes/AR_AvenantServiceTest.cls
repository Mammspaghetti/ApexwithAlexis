/**
 * Tests AR_AvenantService (session 180b) : création de la matrice avenant et décision, sous
 * System.runAs d'un Business Manager non administrateur (AR_Pricing_User) — un test en administrateur
 * ne prouverait rien sur l'accès réel (cf. CLAUDE.md, session 37).
 *
 * Fixtures : une source CDI à 35 000 €/an (coût ≈ 324 €/j), TJM 500 € (MC2 ≈ 35 %). Un avenant à 520 €
 * reste au-dessus du plancher (validation d'office), un avenant à 330 € passe sous le plancher de 20 %.
 * Dates fixes (lundi 05/01/2026 → mardi 30/06/2026), jamais relatives à aujourd'hui.
 */
@IsTest
private class AR_AvenantServiceTest {

    private static final Date MISSION_START = Date.newInstance(2026, 1, 5); // lundi
    private static final Date MISSION_END = Date.newInstance(2026, 6, 30); // mardi

    @TestSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_Validated_Matrix_Lifetime_Days__c = 36500,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Max_Per_Run__c = 100,
            AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Working_Days_Per_Year__c = 218
        );
        insert new Account(
            Name = 'Client Avenant',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert new AR_Reason__c(
            Name = 'Motif Avenant A', AR_Applies_To_Version__c = true, AR_Applies_To_Derogation__c = true, AR_Active__c = true
        );
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
    }

    // ---------- Fabriques ----------

    private static Id reasonId() {
        return [SELECT Id FROM AR_Reason__c WHERE Name = 'Motif Avenant A' LIMIT 1].Id;
    }

    private static cxsrec__cxsPosition__c newPositionFor(User owner, String label) {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Client Avenant' LIMIT 1];
        AR_TestPersona.makeOwner(acc.Id, owner.Id);
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin ' + label, cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        AR_TestPersona.makePositionOwner(position.Id, owner.Id);
        return position;
    }

    /** Matrice source posée directement dans son statut (le verrou du trigger ne joue qu'à la mise à jour). */
    private static AR_Price_Matrix__c newSource(User owner, cxsrec__cxsPosition__c position, String status, String contract) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            OwnerId = owner.Id,
            AR_Position__c = position.Id,
            AR_Status__c = status,
            AR_Contract_Type__c = contract,
            AR_Currency__c = 'EUR',
            AR_Annual_Salary__c = contract == 'CDI' ? 35000 : null,
            AR_CJM_Before_Markup__c = contract == 'INDEP' ? 300 : null,
            AR_Markup_Applied__c = contract == 'INDEP' ? 54 : null,
            AR_Proposed_TJM__c = 500,
            AR_RFA_Percent__c = 0,
            AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Seniority__c = 'Senior Consultant',
            AR_Client_Site__c = 'Paris',
            AR_Start_Date__c = MISSION_START,
            AR_End_Date__c = MISSION_END,
            AR_Number_Of_Days__c = AR_AvenantService.countBusinessDays(MISSION_START, MISSION_END),
            AR_Validated_At__c = status == 'Brouillon' ? null : Datetime.newInstance(2026, 3, 1, 12, 0, 0)
        );
        insert m;
        return m;
    }

    private static AR_PTF_Document__c newPtf(AR_Price_Matrix__c matrix, String status) {
        return newPtf(matrix, status, null);
    }

    private static AR_PTF_Document__c newPtf(AR_Price_Matrix__c matrix, String status, String documentType) {
        AR_PTF_Document__c ptf = new AR_PTF_Document__c(
            AR_Document_Type__c = documentType,
            AR_Price_Matrix__c = matrix.Id,
            AR_Position__c = matrix.AR_Position__c,
            AR_Reference__c = 'PTF-AV-' + Datetime.now().getTime(),
            AR_Version_Number__c = 1,
            AR_Generated_At__c = System.now(),
            AR_Generation_Status__c = status
        );
        insert ptf;
        return ptf;
    }

    private class Fixture {
        User bm;
        cxsrec__cxsPosition__c position;
        AR_Price_Matrix__c source;
        AR_PTF_Document__c ptf;
    }

    private static Fixture fixture() {
        Fixture f = new Fixture();
        f.bm = AR_TestPersona.bmWithDa();
        f.position = newPositionFor(f.bm, 'principal');
        f.source = newSource(f.bm, f.position, 'Validée', 'CDI');
        f.ptf = newPtf(f.source, 'Généré');
        return f;
    }

    private static AR_AvenantService.AvenantInput tarifInput(Fixture f, Decimal tjm, Date effective) {
        AR_AvenantService.AvenantInput i = new AR_AvenantService.AvenantInput();
        i.sourceMatrixId = f.source.Id;
        i.tarif = true;
        i.periode = false;
        i.conditions = false;
        i.newTjm = tjm;
        i.effectiveDate = effective;
        i.reasonIds = new List<Id>{ reasonId() };
        return i;
    }

    private static String errorOf(User u, AR_AvenantService.AvenantInput input) {
        String message;
        System.runAs(u) {
            try {
                AR_AvenantService.createAvenantInput(input);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    private static AR_Price_Matrix__c reload(Id matrixId) {
        return [
            SELECT Id, AR_Status__c, AR_Version_Type__c, AR_Amended_PTF__c, AR_Avenant_Changes__c, AR_Previous_Version__c,
                AR_Root_Matrix__c, AR_Negotiation_Version__c, AR_Start_Date__c, AR_End_Date__c, AR_Number_Of_Days__c,
                AR_Proposed_TJM__c, AR_Annual_Salary__c, AR_Fee_Training__c, AR_Total_Daily_Cost__c, AR_MC2_Percent__c,
                AR_Version_Change_Comment__c, LastModifiedDate, OwnerId
            FROM AR_Price_Matrix__c
            WHERE Id = :matrixId
        ];
    }

    // ---------- Tarif ----------

    @IsTest
    static void testTarifAboveFloor_validatesWithSnapshotAndTrace() {
        Fixture f = fixture();
        Date effective = Date.newInstance(2026, 4, 1);
        AR_AvenantService.AvenantInput input = tarifInput(f, 520, effective);
        input.comment = 'Revalorisation demandée par le client';

        AR_AvenantService.AvenantResult result;
        Test.startTest();
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(input);
        }
        Test.stopTest();

        System.assertEquals('Validée', result.status);
        System.assertEquals(false, result.derogationRequired);
        System.assert(result.mc2Percent > 20, 'MC2 au-dessus du plancher : ' + result.mc2Percent);
        AR_Price_Matrix__c av = reload(result.matrixId);
        System.assertEquals('Avenant', av.AR_Version_Type__c);
        System.assertEquals(f.ptf.Id, av.AR_Amended_PTF__c);
        System.assertEquals('Tarif', av.AR_Avenant_Changes__c);
        System.assertEquals(f.source.Id, av.AR_Previous_Version__c);
        System.assertEquals(f.source.Id, av.AR_Root_Matrix__c);
        System.assertEquals(2, av.AR_Negotiation_Version__c);
        System.assertEquals(effective, av.AR_Start_Date__c, 'La matrice avenant décrit la période amendée');
        System.assertEquals(MISSION_END, av.AR_End_Date__c);
        System.assertEquals(AR_AvenantService.countBusinessDays(effective, MISSION_END), av.AR_Number_Of_Days__c);
        System.assertEquals(520, av.AR_Proposed_TJM__c);
        System.assertEquals('Revalorisation demandée par le client', av.AR_Version_Change_Comment__c);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :av.Id], 'Snapshot à la validation');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :av.Id AND AR_Reason__c = :reasonId()]);
    }

    @IsTest
    static void testTarifBelowFloor_staysDraftAndAsksForDerogation() {
        Fixture f = fixture();
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(tarifInput(f, 330, Date.newInstance(2026, 4, 1)));
        }
        System.assertEquals('Brouillon', result.status);
        System.assertEquals(true, result.derogationRequired);
        System.assertEquals('below_floor', result.corridorSegment);
        System.assert(result.mc2Percent < 20, 'MC2 sous le plancher : ' + result.mc2Percent);
        AR_Price_Matrix__c av = reload(result.matrixId);
        System.assertEquals('Brouillon', av.AR_Status__c);
        System.assertEquals('Avenant', av.AR_Version_Type__c, 'La version avenant est créée même sous le plancher');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :av.Id], 'Pas de snapshot avant décision');
    }

    // ---------- Période ----------

    @IsTest
    static void testExtensionOnly_defaultsEffectiveDateToDayAfterCurrentEnd_viaJsonFacade() {
        Fixture f = fixture();
        Date newEnd = Date.newInstance(2026, 12, 31);
        AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
        input.sourceMatrixId = f.source.Id;
        input.tarif = false;
        input.periode = true;
        input.conditions = false;
        input.newEndDate = newEnd;
        input.reasonIds = new List<Id>{ reasonId() };

        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenant(JSON.serialize(input, true));
        }

        AR_Price_Matrix__c av = reload(result.matrixId);
        System.assertEquals(MISSION_END.addDays(1), av.AR_Start_Date__c, 'Date d’effet par défaut = fin d’origine + 1 jour');
        System.assertEquals(newEnd, av.AR_End_Date__c);
        System.assertEquals(AR_AvenantService.countBusinessDays(MISSION_END.addDays(1), newEnd), av.AR_Number_Of_Days__c);
        System.assertEquals(500, av.AR_Proposed_TJM__c, 'Tarif inchangé');
        System.assertEquals('Période', av.AR_Avenant_Changes__c);
        System.assertEquals('Validée', av.AR_Status__c);
    }

    // ---------- Conditions financières ----------

    @IsTest
    static void testConditionsOnly_isStillAnAvenant_andKeepsOneOffFeesReamortised() {
        Fixture f = fixture();
        // Frais ponctuels de la source (formation 2 180 €) : repris sur l'avenant (Q2 B) et réamortis sur sa période.
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = f.source.Id, AR_Fee_Training__c = 2180);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        Date effective = Date.newInstance(2026, 4, 1);
        AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
        input.sourceMatrixId = f.source.Id;
        input.tarif = false;
        input.periode = false;
        input.conditions = true;
        input.effectiveDate = effective;
        input.annualSalary = 33000;
        input.reasonIds = new List<Id>{ reasonId() };

        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(input);
        }

        AR_Price_Matrix__c av = reload(result.matrixId);
        System.assertEquals('Avenant', av.AR_Version_Type__c, 'Q4 B : seul le coût change, c’est quand même un avenant');
        System.assertEquals('Conditions financières', av.AR_Avenant_Changes__c);
        System.assertEquals(f.ptf.Id, av.AR_Amended_PTF__c);
        System.assertEquals(33000, av.AR_Annual_Salary__c);
        System.assertEquals(2180, av.AR_Fee_Training__c, 'Frais ponctuels repris, pas remis à zéro');
        Decimal days = AR_AvenantService.countBusinessDays(effective, MISSION_END);
        Decimal expectedCost = (33000 * 2.02 / 218).setScale(0, RoundingMode.HALF_UP) + 2180 / days; // le moteur arrondit le CJM à l'euro
        System.assert(
            Math.abs(av.AR_Total_Daily_Cost__c - expectedCost) < 0.05,
            'Coût journalier attendu ' + expectedCost + ' (frais ponctuels / jours de l’avenant), reçu ' + av.AR_Total_Daily_Cost__c
        );
    }

    /** Session 239b : l'avenant reprend les périodes de frais de la source, et sa base de calcul les lit. */
    @IsTest
    static void testConditionsOnly_feePeriodsFollowTheCopyAndTheBaseline() {
        Fixture f = fixture();
        // 20 j : tient dans la période de l'avenant (avril-juin 2026, ~65 j ouvrés), sinon la garde de validation refuse.
        String periods = '[{"days":20,"feeIk":12,"feeMeals":0,"feeLodging":0,"feeOmOther":0}]';
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = f.source.Id, AR_Fee_Periods__c = periods);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
        input.sourceMatrixId = f.source.Id;
        input.tarif = false;
        input.periode = false;
        input.conditions = true;
        input.effectiveDate = Date.newInstance(2026, 4, 1);
        input.annualSalary = 33000;
        input.reasonIds = new List<Id>{ reasonId() };

        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(input);
        }
        // Transaction propre : la création de l'avenant consomme déjà une part de la limite SOQL.
        AR_PricingResult baseline;
        System.runAs(f.bm) {
            Test.startTest();
            baseline = AR_AvenantService.baselineResult(result.matrixId);
            Test.stopTest();
        }

        AR_Price_Matrix__c avenant = [SELECT AR_Fee_Periods__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId];
        // Réécrites en forme canonique par la sauvegarde : on compare le contenu, pas la chaîne.
        List<AR_PricingCalculator.FeePeriod> copied = AR_PricingMatrixService.parseFeePeriods(avenant.AR_Fee_Periods__c);
        System.assertEquals(1, copied.size(), 'Périodes de la source reprises sur l\'avenant');
        System.assertEquals(20, copied[0].days);
        System.assertEquals(12, copied[0].feeIk);
        System.assertEquals(2, baseline.feeOmPeriods.size(), 'La base de calcul de l\'avenant lit les périodes (P1 + 1 ajoutée)');
    }

    // ---------- Refus ----------

    @IsTest
    static void testNoAnswer_isRefused() {
        Fixture f = fixture();
        AR_AvenantService.AvenantInput input = tarifInput(f, null, null);
        input.tarif = false;
        System.assert(errorOf(f.bm, input).contains('au moins une'), 'Aucune réponse « Oui » doit être refusée');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Root_Matrix__c = :f.source.Id OR Id = :f.source.Id]);
    }

    @IsTest
    static void testReasonIsMandatory() {
        Fixture f = fixture();
        AR_AvenantService.AvenantInput input = tarifInput(f, 520, Date.newInstance(2026, 4, 1));
        input.reasonIds = new List<Id>();
        System.assert(errorOf(f.bm, input).contains('motif'));
    }

    @IsTest
    static void testFieldRules_areEnforcedByTheServer() {
        Fixture f = fixture();
        Date ok = Date.newInstance(2026, 4, 1);
        System.assert(errorOf(f.bm, tarifInput(f, null, ok)).contains('TJM'), 'tarif sans TJM');
        System.assert(errorOf(f.bm, tarifInput(f, 0, ok)).contains('TJM'), 'TJM nul');
        System.assert(errorOf(f.bm, tarifInput(f, 520, null)).contains('date d’effet'), 'tarif sans date d’effet');
        System.assert(errorOf(f.bm, tarifInput(f, 520, Date.newInstance(2025, 12, 1))).contains('précéder'), 'effet avant le début');
        System.assert(errorOf(f.bm, tarifInput(f, 520, Date.newInstance(2026, 7, 15))).contains('comprise'), 'effet après la fin');

        AR_AvenantService.AvenantInput stray = tarifInput(f, 520, ok);
        stray.tarif = false;
        stray.periode = true;
        stray.newEndDate = Date.newInstance(2026, 12, 31);
        System.assert(errorOf(f.bm, stray).contains('TJM est fourni'), 'TJM fourni alors que tarif = Non');

        AR_AvenantService.AvenantInput badEnd = tarifInput(f, 520, ok);
        badEnd.periode = true;
        badEnd.newEndDate = ok;
        System.assert(errorOf(f.bm, badEnd).contains('postérieure'), 'fin <= effet');

        AR_AvenantService.AvenantInput noEnd = tarifInput(f, 520, ok);
        noEnd.periode = true;
        System.assert(errorOf(f.bm, noEnd).contains('nouvelle date de fin'), 'période sans fin');

        AR_AvenantService.AvenantInput endWithoutPeriod = tarifInput(f, 520, ok);
        endWithoutPeriod.newEndDate = Date.newInstance(2026, 12, 31);
        System.assert(errorOf(f.bm, endWithoutPeriod).contains('question « période »'), 'fin fournie alors que période = Non');

        AR_AvenantService.AvenantInput costWithoutAnswer = tarifInput(f, 520, ok);
        costWithoutAnswer.feeMeals = 10;
        System.assert(errorOf(f.bm, costWithoutAnswer).contains('conditions financières'), 'coût fourni alors que conditions = Non');

        AR_AvenantService.AvenantInput indepCostOnCdi = tarifInput(f, 520, ok);
        indepCostOnCdi.conditions = true;
        indepCostOnCdi.cjmBeforeMarkup = 250;
        System.assert(errorOf(f.bm, indepCostOnCdi).contains('indépendant'), 'CJM d’achat sur un CDI');
    }

    @IsTest
    static void testSalaryOnIndependentIsRefused() {
        User bm = AR_TestPersona.bm();
        cxsrec__cxsPosition__c position = newPositionFor(bm, 'indep');
        AR_Price_Matrix__c source = newSource(bm, position, 'Validée', 'INDEP');
        newPtf(source, 'Généré');
        AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
        input.sourceMatrixId = source.Id;
        input.tarif = false;
        input.periode = false;
        input.conditions = true;
        input.effectiveDate = Date.newInstance(2026, 4, 1);
        input.annualSalary = 40000;
        input.reasonIds = new List<Id>{ reasonId() };
        System.assert(errorOf(bm, input).contains('CDI ou CDD'));

        input.annualSalary = null;
        input.cjmBeforeMarkup = 280; // le coût d'achat reste modifiable pour un INDEP (Q3, signalé)
        AR_AvenantService.AvenantResult result;
        System.runAs(bm) {
            result = AR_AvenantService.createAvenantInput(input);
        }
        System.assertEquals('Avenant', reload(result.matrixId).AR_Version_Type__c);
    }

    @IsTest
    static void testPtfOfAnotherChain_isRefused() {
        Fixture f = fixture();
        cxsrec__cxsPosition__c otherPosition = newPositionFor(f.bm, 'autre chaîne');
        AR_Price_Matrix__c otherSource = newSource(f.bm, otherPosition, 'Validée', 'CDI');
        AR_PTF_Document__c foreignPtf = newPtf(otherSource, 'Généré');
        AR_AvenantService.AvenantInput input = tarifInput(f, 520, Date.newInstance(2026, 4, 1));
        input.amendedPtfId = foreignPtf.Id;
        System.assert(errorOf(f.bm, input).contains('n’appartient pas à la chaîne'));
    }

    @IsTest
    static void testPtfNotGeneratedOrAvenantType_doesNotCount() {
        User bm = AR_TestPersona.bm();
        cxsrec__cxsPosition__c position = newPositionFor(bm, 'sans ptf');
        AR_Price_Matrix__c source = newSource(bm, position, 'Validée', 'CDI');
        newPtf(source, 'En cours');
        newPtf(source, 'Échec');
        newPtf(source, 'Généré', 'Avenant');

        String message;
        System.runAs(bm) {
            try {
                AR_AvenantService.getAvenantContext(source.Id);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        System.assert(message != null && message.contains('rien à amender') && message.contains('Dupliquer'), 'Reçu : ' + message);
    }

    @IsTest
    static void testDraftSource_isRefused() {
        User bm = AR_TestPersona.bm();
        cxsrec__cxsPosition__c position = newPositionFor(bm, 'brouillon');
        AR_Price_Matrix__c source = newSource(bm, position, 'Brouillon', 'CDI');
        AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
        input.sourceMatrixId = source.Id;
        input.tarif = true;
        input.newTjm = 520;
        input.effectiveDate = Date.newInstance(2026, 4, 1);
        input.reasonIds = new List<Id>{ reasonId() };
        System.assert(errorOf(bm, input).contains('matrice validée'));
    }

    @IsTest
    static void testMatrixOfAnotherBm_isNotAccessible() {
        Fixture f = fixture();
        User stranger = AR_TestPersona.bm();
        String message = errorOf(stranger, tarifInput(f, 520, Date.newInstance(2026, 4, 1)));
        System.assert(message != null && message.contains('non accessible'), 'Reçu : ' + message);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :f.source.Id OR AR_Root_Matrix__c = :f.source.Id]);
    }

    // ---------- Taxe OFII calculée : taux et plafond servis au contexte ----------

    @IsTest
    static void testGetAvenantContext_servesOfiiTaxRateAndCap_nullWhenEmpty() {
        Fixture f = fixture();
        AR_General_Setting__c row = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        row.AR_Ofii_Tax_Rate__c = 55;
        row.AR_Ofii_Tax_Cap__c = 2506.67;
        update row;
        System.runAs(f.bm) {
            AR_AvenantService.AvenantContext ctx = AR_AvenantService.getAvenantContext(f.source.Id);
            System.assertEquals(55, ctx.ofiiTaxRate, 'Taux servi tel quel');
            System.assertEquals(2506.67, ctx.ofiiTaxCapEur, 'Plafond servi tel quel, en euros');
        }

        row.AR_Ofii_Tax_Rate__c = null;
        row.AR_Ofii_Tax_Cap__c = null;
        update row;
        System.runAs(f.bm) {
            AR_AvenantService.AvenantContext ctx = AR_AvenantService.getAvenantContext(f.source.Id);
            System.assertEquals(null, ctx.ofiiTaxRate, 'Vide : null, jamais un taux substitué');
            System.assertEquals(null, ctx.ofiiTaxCapEur, 'Vide : null, jamais un plafond substitué');
        }
    }

    // ---------- Avenant d'un avenant (Q8) ----------

    @IsTest
    static void testAvenantOfAnAvenant_amendsTheInitialPtf() {
        Fixture f = fixture();
        AR_AvenantService.AvenantResult first;
        System.runAs(f.bm) {
            first = AR_AvenantService.createAvenantInput(tarifInput(f, 520, Date.newInstance(2026, 4, 1)));
        }

        AR_AvenantService.AvenantResult second;
        Test.startTest(); // limites remises à zéro : chaque création est une transaction à part en production
        System.runAs(f.bm) {
            AR_AvenantService.AvenantContext ctx = AR_AvenantService.getAvenantContext(first.matrixId);
            System.assertEquals(true, ctx.sourceIsAvenant);
            System.assertEquals(f.ptf.Id, ctx.amendedPtfId, 'Source avenant : la PTF initiale, jamais un avenant');

            AR_AvenantService.AvenantInput input = new AR_AvenantService.AvenantInput();
            input.sourceMatrixId = first.matrixId;
            input.tarif = false;
            input.periode = true;
            input.conditions = false;
            input.newEndDate = Date.newInstance(2026, 12, 31);
            input.reasonIds = new List<Id>{ reasonId() };
            second = AR_AvenantService.createAvenantInput(input);
        }
        Test.stopTest();
        AR_Price_Matrix__c av2 = reload(second.matrixId);
        System.assertEquals(f.ptf.Id, av2.AR_Amended_PTF__c, 'AV2 rattaché à la PTF initiale');
        System.assertEquals(first.matrixId, av2.AR_Previous_Version__c);
        System.assertEquals(f.source.Id, av2.AR_Root_Matrix__c);
        System.assertEquals(3, av2.AR_Negotiation_Version__c);
        System.assertEquals(MISSION_END.addDays(1), av2.AR_Start_Date__c, 'Prolongation après la fin de la matrice amendée');
    }

    // ---------- La source n'est jamais modifiée ----------

    @IsTest
    static void testSourceIsLeftUntouched() {
        Fixture f = fixture();
        AR_Price_Matrix__c before = reload(f.source.Id);
        // Création mesurée seule (préparation hors de la frontière, comme en production).
        Test.startTest();
        System.runAs(f.bm) {
            AR_AvenantService.createAvenantInput(tarifInput(f, 520, Date.newInstance(2026, 4, 1)));
            System.assert(Limits.getQueries() < 85, 'Requêtes SOQL d’une création isolée : ' + Limits.getQueries());
        }
        Test.stopTest();
        AR_Price_Matrix__c after = reload(f.source.Id);
        System.assertEquals(before.LastModifiedDate, after.LastModifiedDate);
        System.assertEquals('Validée', after.AR_Status__c);
        System.assertEquals(before.AR_Proposed_TJM__c, after.AR_Proposed_TJM__c);
        System.assertEquals(before.AR_Start_Date__c, after.AR_Start_Date__c);
        System.assertEquals(before.AR_End_Date__c, after.AR_End_Date__c);
        System.assertEquals(before.AR_Number_Of_Days__c, after.AR_Number_Of_Days__c);
        System.assertEquals(null, after.AR_Version_Type__c);
        System.assertEquals(null, after.AR_Amended_PTF__c);
    }

    // ---------- Liste « Matrice validée » ----------

    @IsTest
    static void testValidatedList_staysOnOriginWhileAvenantIsDraft() {
        Fixture f = fixture();
        System.assertEquals(1, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :f.source.Id], 'Pré-requis : la source est listée');
        AR_AvenantService.AvenantResult draftAvenant;
        Test.startTest();
        System.runAs(f.bm) {
            draftAvenant = AR_AvenantService.createAvenantInput(tarifInput(f, 330, Date.newInstance(2026, 4, 1)));
        }
        Test.stopTest();
        System.assertEquals('Brouillon', draftAvenant.status);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :f.source.Id], 'Avenant en brouillon : l’origine reste listée');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Price_Matrix__c = :draftAvenant.matrixId]);
    }

    @IsTest
    static void testValidatedList_switchesToValidatedAvenant() {
        Fixture f = fixture();
        AR_AvenantService.AvenantResult validatedAvenant;
        Test.startTest();
        System.runAs(f.bm) {
            validatedAvenant = AR_AvenantService.createAvenantInput(tarifInput(f, 520, Date.newInstance(2026, 5, 1)));
            // Garde-fou : la synchro « Matrice validée » avale ses erreurs (dont une limite SOQL) — une création
            // d'avenant doit rester loin du plafond de 100 requêtes pour qu'elle ne soit jamais coupée en silence.
            // Seuil 85 : partage de la chaîne : +2 requêtes (fiche du propriétaire, valideurs de test).
            System.assert(Limits.getQueries() < 85, 'Requêtes SOQL d’une création d’avenant : ' + Limits.getQueries());
        }
        Test.stopTest();
        System.assertEquals('Validée', validatedAvenant.status);
        List<AR_Validated_Matrix__c> entries = [SELECT Id, AR_Price_Matrix__c, Name FROM AR_Validated_Matrix__c WHERE AR_Position__c = :f.position.Id];
        System.assertEquals(1, entries.size(), 'Une entrée par chaîne');
        System.assertEquals(validatedAvenant.matrixId, entries[0].AR_Price_Matrix__c, 'L’entrée bascule sur l’avenant validé');
        System.assert(entries[0].Name.contains('Avenant'), 'Libellé : ' + entries[0].Name);
    }

    // ---------- Contexte ----------

    @IsTest
    static void testContext_returnsSourceFiguresAndDates() {
        Fixture f = fixture();
        AR_AvenantService.AvenantContext ctx;
        System.runAs(f.bm) {
            ctx = AR_AvenantService.getAvenantContext(f.source.Id);
        }
        System.assertEquals(f.ptf.Id, ctx.amendedPtfId);
        System.assertEquals(1, ctx.ptfOptions.size());
        System.assertEquals('CDI', ctx.contractType);
        System.assertEquals('EUR', ctx.currencyCode);
        System.assertEquals(500, ctx.proposedTjm);
        System.assertEquals(35000, ctx.annualSalary);
        System.assertEquals(false, ctx.sourceIsAvenant);
        System.assertEquals(MISSION_START, ctx.missionStartDate);
        System.assertEquals(MISSION_END, ctx.currentEndDate);
        System.assertEquals(MISSION_END.addDays(1), ctx.defaultExtensionEffectiveDate);
        System.assertEquals(AR_AvenantService.countBusinessDays(MISSION_START, MISSION_END), ctx.sourceNumberOfDays);
    }

    @IsTest
    static void testSourceWithTwoSalaryPeriods_avenantStartsAtTheLastSalary() {
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Salary_Periods__c = '[{"days":40,"salary":42000}]'));

        AR_AvenantService.AvenantContext ctx;
        AR_AvenantService.AvenantResult result;
        Test.startTest();
        System.runAs(f.bm) {
            ctx = AR_AvenantService.getAvenantContext(f.source.Id);
            result = AR_AvenantService.createAvenantInput(tarifInput(f, 520, Date.newInstance(2026, 4, 1)));
        }
        Test.stopTest();

        System.assertEquals(42000, ctx.annualSalary, 'Salaire proposé pour l’avenant = celui de la période 2');
        System.assertEquals(35000, ctx.sourceAnnualSalary, 'Période 1 de la source, base de son CJM pondéré');
        AR_Price_Matrix__c av = [
            SELECT AR_Annual_Salary__c, AR_Salary_Periods__c FROM AR_Price_Matrix__c WHERE Id = :result.matrixId
        ];
        System.assertEquals(42000, av.AR_Annual_Salary__c, 'L’avenant part du salaire de la dernière période');
        System.assertEquals(null, av.AR_Salary_Periods__c, 'Périodes remises à vide');
        System.assertEquals(35000, [SELECT AR_Annual_Salary__c FROM AR_Price_Matrix__c WHERE Id = :f.source.Id].AR_Annual_Salary__c);
    }

    @IsTest
    static void testCurrentSalary_ignoresPeriodsOutsideSalariedContracts_andIncompleteRows() {
        AR_Price_Matrix__c cdi = new AR_Price_Matrix__c(
            AR_Contract_Type__c = 'CDI', AR_Annual_Salary__c = 35000,
            AR_Salary_Periods__c = '[{"days":10,"salary":40000},{"days":10,"salary":null}]'
        );
        System.assertEquals(40000, AR_AvenantService.currentSalary(cdi), 'Dernière période renseignée');
        cdi.AR_Salary_Periods__c = null;
        System.assertEquals(35000, AR_AvenantService.currentSalary(cdi), 'Sans période : période 1');
        AR_Price_Matrix__c indep = new AR_Price_Matrix__c(
            AR_Contract_Type__c = 'INDEP', AR_Annual_Salary__c = null, AR_Salary_Periods__c = '[{"days":10,"salary":40000}]'
        );
        System.assertEquals(null, AR_AvenantService.currentSalary(indep), 'INDEP : périodes ignorées');
    }

    // ---------- Règle de décision et jours ouvrés ----------

    private static AR_PricingResult mc2(Decimal percent) {
        AR_PricingResult r = new AR_PricingResult();
        r.mc2PercentHuman = percent;
        return r;
    }

    @IsTest
    static void testRequiresHumanValidation_isAStrictDropOfTheMc2_atTheHundredthOfAPoint() {
        System.assertEquals(true, AR_AvenantService.requiresHumanValidation(mc2(30), mc2(29.99)), 'Baisse d’un centième');
        System.assertEquals(false, AR_AvenantService.requiresHumanValidation(mc2(30), mc2(30)), 'Égalité');
        System.assertEquals(false, AR_AvenantService.requiresHumanValidation(mc2(30), mc2(30.01)), 'Hausse');
        System.assertEquals(false, AR_AvenantService.requiresHumanValidation(mc2(30.004), mc2(30)), 'Écart sous le centième : ignoré');
        System.assertEquals(false, AR_AvenantService.requiresHumanValidation(mc2(30), mc2(29.996)), 'Écart sous le centième : ignoré');
        System.assertEquals(false, AR_AvenantService.requiresHumanValidation(mc2(10), mc2(10)), 'Sous le plancher mais sans baisse : pas de dérogation');
        System.assertEquals(true, AR_AvenantService.requiresHumanValidation(mc2(40), mc2(25)), 'Au-dessus du plancher mais en baisse');
        System.assertEquals(true, AR_AvenantService.requiresHumanValidation(null, mc2(30)), 'Repli fermé');
        System.assertEquals(true, AR_AvenantService.requiresHumanValidation(mc2(30), null), 'Repli fermé');
        System.assertEquals(true, AR_AvenantService.requiresHumanValidation(mc2(30), new AR_PricingResult()), 'Repli fermé');
    }

    private static void setSource(Fixture f, AR_Price_Matrix__c changes) {
        changes.Id = f.source.Id;
        AR_TriggerBypass.serviceContext = true;
        try {
            update changes;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    private static AR_AvenantService.AvenantInput periodInput(Fixture f, Date effective, Date newEnd) {
        AR_AvenantService.AvenantInput i = new AR_AvenantService.AvenantInput();
        i.sourceMatrixId = f.source.Id;
        i.tarif = false;
        i.periode = true;
        i.conditions = false;
        i.effectiveDate = effective;
        i.newEndDate = newEnd;
        i.reasonIds = new List<Id>{ reasonId() };
        return i;
    }

    @IsTest
    static void testPeriodOnly_sameMc2_isValidatedDirectly() {
        Fixture f = fixture(); // aucun frais ponctuel : la durée ne change pas le coût par jour
        AR_AvenantService.AvenantResult result;
        Test.startTest();
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_END.addDays(1), Date.newInstance(2026, 12, 31)));
        }
        Test.stopTest();
        System.assertEquals(false, result.derogationRequired);
        System.assertEquals('Validée', result.status);
        Decimal before;
        System.runAs(f.bm) {
            before = AR_AvenantService.baselineResult(result.matrixId).mc2PercentHuman;
        }
        System.assertEquals(
            before.setScale(2, RoundingMode.HALF_UP),
            result.mc2Percent.setScale(2, RoundingMode.HALF_UP),
            'MC2 identique à la matrice amendée'
        );
    }

    /** Session 237 : règle de dispense désactivée (montant vide) pour un test qui isole la baisse de MC2 %. */
    private static void disableDispense() {
        List<AR_General_Setting__c> rows = [SELECT Id FROM AR_General_Setting__c];
        for (AR_General_Setting__c row : rows) {
            row.AR_Derogation_Waiver_Amount__c = null;
        }
        update rows;
    }

    @IsTest
    static void testPeriodShortened_oneOffFeesReamortisedOnFewerDays_asksForDerogation() {
        disableDispense(); // Session 237 : ce test porte sur la baisse de MC2 %, sans dispense de MC2/jour.
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Fee_Training__c = 2180));
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_START, Date.newInstance(2026, 3, 31)));
        }
        System.assertEquals(true, result.derogationRequired, 'Frais ponctuels sur moins de jours : la MC2 baisse');
        System.assertEquals('Brouillon', result.status);
        System.assertNotEquals('below_floor', result.corridorSegment, 'Au-dessus du plancher : c’est la baisse qui décide');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :result.matrixId], 'Pas de snapshot avant décision');
    }

    /** Montant de dispense de MC2/jour fixé pour le test (null = règle désactivée). */
    private static void setWaiverAmount(Decimal amount) {
        List<AR_General_Setting__c> rows = [SELECT Id FROM AR_General_Setting__c];
        for (AR_General_Setting__c row : rows) {
            row.AR_Derogation_Waiver_Amount__c = amount;
        }
        update rows;
        AR_PricingMatrixService.resetDispenseAmountCache();
    }

    @IsTest
    static void testPeriodShortened_mc2PerDayAboveWaiver_isValidatedWithoutDerogation() {
        setWaiverAmount(1); // MC2/jour au-dessus de 1 € : la dispense s'applique à l'avenant
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Fee_Training__c = 2180));
        AR_AvenantService.AvenantResult result;
        // Limites remises à zéro : en production, la création de l'avenant est seule dans sa transaction.
        Test.startTest();
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_START, Date.newInstance(2026, 3, 31)));
        }
        Test.stopTest();
        System.assert(result.mc2PerDay >= 1, 'MC2/jour au montant de dispense : ' + result.mc2PerDay);
        System.assertEquals(false, result.derogationRequired, 'MC2 % en baisse, MC2/jour dispensée : pas de dérogation');
        System.assertEquals('Validée', result.status);
    }

    @IsTest
    static void testPeriodShortened_sameAvenantWithoutWaiver_asksForDerogation() {
        setWaiverAmount(null); // même avenant, dispense vidée
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Fee_Training__c = 2180));
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_START, Date.newInstance(2026, 3, 31)));
        }
        System.assertEquals(true, result.derogationRequired, 'Sans dispense, la baisse de MC2 % demande une dérogation');
        System.assertEquals('Brouillon', result.status);
    }

    @IsTest
    static void testPeriodExtended_oneOffFeesOnMoreDays_isValidatedDirectly() {
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Fee_Training__c = 2180));
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_END.addDays(1), Date.newInstance(2026, 12, 31)));
        }
        System.assertEquals(false, result.derogationRequired, 'Plus de jours : la MC2 monte, pas de dérogation');
        System.assertEquals('Validée', result.status);
    }

    @IsTest
    static void testAlreadyBelowFloor_equalMc2_isValidatedDirectly() {
        Fixture f = fixture();
        setSource(f, new AR_Price_Matrix__c(AR_Proposed_TJM__c = 330)); // MC2 de la source sous le plancher
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(periodInput(f, MISSION_END.addDays(1), Date.newInstance(2026, 12, 31)));
        }
        System.assertEquals('below_floor', result.corridorSegment, 'La matrice reste sous le plancher');
        System.assertEquals(false, result.derogationRequired, 'Le plancher n’entre plus en jeu : la MC2 n’a pas baissé');
        System.assertEquals('Validée', result.status);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :result.matrixId], 'Snapshot à la validation');
    }

    @IsTest
    static void testAboveFloorButMc2Drops_asksForDerogation_andTheDraftCannotBeValidatedFromTheScreen() {
        disableDispense(); // Session 237 : ce test porte sur la baisse de MC2 %, sans dispense de MC2/jour.
        Fixture f = fixture();
        AR_AvenantService.AvenantResult result;
        System.runAs(f.bm) {
            result = AR_AvenantService.createAvenantInput(tarifInput(f, 480, Date.newInstance(2026, 4, 1)));
        }
        System.assertEquals(true, result.derogationRequired);
        System.assertEquals('Brouillon', result.status);
        System.assertNotEquals('below_floor', result.corridorSegment, 'Baisse au-dessus du plancher');

        // L'écran charge ensuite le Brouillon : transaction distincte (limites remises à zéro).
        AR_PricingMatrixService.MatrixInput screenInput;
        String refusal;
        Test.startTest();
        System.runAs(f.bm) {
            screenInput = AR_PricingMatrixService.getMatrixInput(result.matrixId);
            try {
                AR_PricingMatrixService.validateInput(screenInput);
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
        }
        Test.stopTest();
        System.assertNotEquals(null, screenInput.avenantMc2Before, 'L’écran reçoit la MC2 à comparer');
        System.assert(screenInput.avenantMc2Before > result.mc2Percent, 'Avant ' + screenInput.avenantMc2Before + ' > après ' + result.mc2Percent);
        System.assert(refusal != null && refusal.contains('Rentabilité en baisse'), 'Refus serveur : ' + refusal);
        System.assertEquals('Brouillon', reload(result.matrixId).AR_Status__c);
    }

    @IsTest
    static void testOrdinaryMatrix_carriesNoAvenantBaseline() {
        Fixture f = fixture();
        AR_PricingMatrixService.MatrixInput sourceInput;
        System.runAs(f.bm) {
            sourceInput = AR_PricingMatrixService.getMatrixInput(f.source.Id);
        }
        System.assertEquals(null, sourceInput.avenantMc2Before, 'Matrice ordinaire : règle du plancher, pas de comparaison');
    }

    @IsTest
    static void testCountBusinessDays_mirrorsTheScreenCalculation() {
        Date monday = Date.newInstance(2026, 10, 12);
        System.assertEquals(5, AR_AvenantService.countBusinessDays(monday, monday.addDays(6)), 'Lundi → dimanche');
        System.assertEquals(1, AR_AvenantService.countBusinessDays(monday, monday), 'Bornes incluses');
        System.assertEquals(0, AR_AvenantService.countBusinessDays(monday.addDays(5), monday.addDays(6)), 'Samedi-dimanche');
        System.assertEquals(0, AR_AvenantService.countBusinessDays(monday.addDays(1), monday), 'Fin avant début');
        System.assertEquals(0, AR_AvenantService.countBusinessDays(null, monday));
        // Session 274 : calendrier unique, jours fériés France selon le pays de l'entité.
        Date jan1 = Date.newInstance(2027, 1, 1);
        Date jan31 = Date.newInstance(2027, 1, 31);
        System.assertEquals(20, AR_AvenantService.countBusinessDays(jan1, jan31, 'France'));
        System.assertEquals(20, AR_AvenantService.countBusinessDays(jan1, jan31, 'Belgique'), 'Belgique : 1er janvier férié (session 288)');
        System.assertEquals(21, AR_AvenantService.countBusinessDays(jan1, jan31, 'Allemagne'), 'Pays sans calendrier : week-ends seuls');
        System.assertEquals(21, AR_AvenantService.countBusinessDays(jan1, jan31));
        System.assertEquals(127, AR_AvenantService.countBusinessDays(MISSION_START, MISSION_END), 'Mission de la fixture');
    }

    // ---------- Session 180d : génération du document, jouée par le vrai utilisateur ----------

    /** PTF d'origine dotée d'un snapshot lisible (valideur, rédacteur, interlocuteur) comme une PTF réelle. */
    private static void giveParentSnapshot(Fixture f) {
        AR_PTFData parent = new AR_PTFData();
        parent.reference = f.ptf.AR_Reference__c;
        parent.valideurNom = 'Valideur Origine';
        parent.valideurFonction = 'Directeur d\'Activité';
        parent.redacteurNom = 'Rédacteur Origine';
        parent.interNom = 'Client Interlocuteur';
        update new AR_PTF_Document__c(Id = f.ptf.Id, AR_Snapshot__c = JSON.serialize(parent));
    }

    private static AR_PTFGenerationService.PTFGenerationResult generateAs(User u, Id matrixId) {
        AR_PTFGenerationService.PTFGenerationResult started;
        System.runAs(u) {
            started = AR_PTFGenerationService.generateAvenantIfNeeded(matrixId);
        }
        return started;
    }

    @IsTest
    static void testGenerateAvenant_asTheBusinessManager_validatedDirectly() {
        Fixture f = fixture();
        giveParentSnapshot(f);
        AR_AvenantService.AvenantResult created;
        // Création et génération sont deux transactions distinctes en usage réel : limites remises à zéro entre les deux.
        Test.startTest();
        System.runAs(f.bm) {
            created = AR_AvenantService.createAvenantInput(tarifInput(f, 560, Date.newInstance(2026, 4, 1)));
        }
        Test.stopTest();
        System.assertEquals('Validée', created.status);

        AR_PTFGenerationService.PTFGenerationResult started = generateAs(f.bm, created.matrixId);
        AR_PTFGenerationService.PTFGenerationResult rendered;
        System.runAs(f.bm) {
            rendered = AR_PTFGenerationService.renderAndStorePTF(started.ptfDocumentId);
        }

        System.assertEquals('Généré', rendered.status, '' + rendered.errorMessage);
        System.assertEquals(null, rendered.warning, 'Le BM voit son besoin : fichier rattaché sans réserve');
        AR_PTF_Document__c doc = [
            SELECT AR_Price_Matrix__c, AR_Parent_PTF__c, AR_Avenant_Number__c FROM AR_PTF_Document__c WHERE Id = :started.ptfDocumentId
        ];
        System.assertEquals(created.matrixId, doc.AR_Price_Matrix__c);
        System.assertEquals(f.ptf.Id, doc.AR_Parent_PTF__c);
        System.assertEquals(1, doc.AR_Avenant_Number__c);
        AR_PTFData data = (AR_PTFData) JSON.deserialize(
            [SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :doc.Id].AR_Snapshot__c, AR_PTFData.class
        );
        System.assertEquals(560, data.nouveauTjm);
        System.assertEquals(Date.newInstance(2026, 4, 1), data.revisionPrixADateDu);
        System.assertEquals(
            [SELECT TP_DA__r.Name FROM User WHERE Id = :f.bm.Id].TP_DA__r.Name, data.valideurNom,
            'Valideur = DA du propriétaire de la matrice (184c), non celui de la PTF d\'origine'
        );
        System.assertEquals('Client Interlocuteur', data.interNom);
    }

    @IsTest
    static void testGenerateAvenant_asAnotherValidator_afterTheDerogationIsAccepted() {
        Fixture f = fixture();
        giveParentSnapshot(f);
        // Le valideur doit être dans la chaîne du propriétaire pour voir la matrice (règle de visibilité, session 199) :
        // il est relié comme Directeur avant la création, la ligne de partage étant calculée à la création.
        User validator = AR_TestPersona.valideur();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = f.bm.Id, TP_Directeur__c = validator.Id);
        }
        AR_AvenantService.AvenantResult created;
        // Création mesurée seule (préparation hors de la frontière, comme en production).
        Test.startTest();
        System.runAs(f.bm) {
            created = AR_AvenantService.createAvenantInput(tarifInput(f, 330, Date.newInstance(2026, 4, 1)));
            System.assert(Limits.getQueries() < 85, 'Requêtes SOQL d’une création isolée : ' + Limits.getQueries());
        }
        Test.stopTest();
        System.assertEquals(true, created.derogationRequired);
        System.assertEquals(null, generateAs(f.bm, created.matrixId), 'Brouillon : rien à générer avant la décision');

        // Décision du valideur (écriture système, comme AR_DerogationService.decide)
        AR_TriggerBypass.serviceContext = true;
        update new AR_Price_Matrix__c(
            Id = created.matrixId, AR_Status__c = 'Validée par dérogation', AR_Validated_At__c = System.now()
        );
        AR_TriggerBypass.serviceContext = false;

        AR_PTFGenerationService.PTFGenerationResult started = generateAs(validator, created.matrixId);
        System.assertNotEquals(null, started, 'Le valideur déclenche la génération à sa décision');
        AR_PTFGenerationService.PTFGenerationResult rendered;
        System.runAs(validator) {
            rendered = AR_PTFGenerationService.renderAndStorePTF(started.ptfDocumentId);
        }
        System.assertEquals('Généré', rendered.status, '' + rendered.errorMessage);
        System.assert(
            rendered.warning != null && rendered.warning.contains('rattaché au besoin'),
            'Ce valideur ne voit pas le besoin du BM : le document est généré, la réserve est affichée. Reçu : ' + rendered.warning
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :created.matrixId AND ContentDocument.Title LIKE 'PTF_ABYLSEN%'],
            'Le fichier reste rattaché à la matrice avenant'
        );
        System.assertEquals(null, generateAs(validator, created.matrixId), 'Pas de second document');
        System.assertEquals(
            f.bm.Id,
            [SELECT OwnerId FROM AR_Price_Matrix__c WHERE Id = :created.matrixId].OwnerId,
            'La matrice reste à son BM : le rédacteur imprimé est le sien, pas celui du valideur'
        );
    }

    @IsTest
    static void testLegacyAvenantFormSwitch_readsTheSetting() {
        System.assertEquals(false, AR_PTFGenerationService.isLegacyAvenantFormEnabled(), 'Désactivé par défaut');
        AR_General_Setting__c setting = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        update new AR_General_Setting__c(Id = setting.Id, AR_Legacy_Avenant_Form_Enabled__c = true);
        System.assertEquals(true, AR_PTFGenerationService.isLegacyAvenantFormEnabled());
        delete setting;
        System.assertEquals(false, AR_PTFGenerationService.isLegacyAvenantFormEnabled(), 'Réglage absent : faux');
    }
}