/**
 * Tests unitaires purs de AR_QualificationGatingEvaluator : aucune DML, positions/matrices
 * construites en mémoire (CreatedDate assigné via put(), seul moyen d'écrire un champ d'audit sur
 * un sObject non inséré).
 */
@IsTest
private class AR_QualificationGatingEvaluatorTest {

    private static cxsrec__cxsPosition__c positionCreatedOn(Date createdDate) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c();
        position.put('CreatedDate', (Datetime) Datetime.newInstance(createdDate, Time.newInstance(0, 0, 0, 0)));
        return position;
    }

    private static AR_Gating_Setting__mdt settings(String severityNoMatrix, String severityDerogation, Date goLiveDate) {
        return new AR_Gating_Setting__mdt(
            AR_Severity_No_Matrix__c = severityNoMatrix,
            AR_Severity_Derogation_Pending__c = severityDerogation,
            AR_Go_Live_Date__c = goLiveDate
        );
    }

    @IsTest
    static void testConforme_matriceValidee_severiteIgnoree() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(AR_Status__c = 'Validée')
        };
        AR_Gating_Setting__mdt config = settings('Blocking', 'Blocking', Date.newInstance(2020, 1, 1));

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, config, Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.CONFORME, decision.matchedCase);
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.IGNORE, decision.appliedSeverity);
        System.assertEquals(false, decision.blocked, 'Une matrice validée ne doit jamais bloquer, quelle que soit la config');
    }

    @IsTest
    static void testConforme_matriceValideeParDerogation_severiteIgnoree() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(AR_Status__c = 'Validée par dérogation')
        };
        AR_Gating_Setting__mdt config = settings('Blocking', 'Blocking', Date.newInstance(2020, 1, 1));

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, config, Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.CONFORME, decision.matchedCase);
        System.assertEquals(false, decision.blocked);
    }

    @IsTest
    static void testDerogationEnAttente_severiteEstUnParametre() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(AR_Status__c = 'En dérogation')
        };
        Date today = Date.newInstance(2026, 8, 17);

        AR_QualificationGatingEvaluator.Decision warningDecision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, settings('Warning', 'Warning', Date.newInstance(2020, 1, 1)), today
        );
        AR_QualificationGatingEvaluator.Decision blockingDecision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, settings('Warning', 'Blocking', Date.newInstance(2020, 1, 1)), today
        );

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.DEROGATION_PENDING, warningDecision.matchedCase);
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, warningDecision.appliedSeverity);
        System.assertEquals(false, warningDecision.blocked);

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.DEROGATION_PENDING, blockingDecision.matchedCase);
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.BLOCKING, blockingDecision.appliedSeverity);
        System.assertEquals(true, blockingDecision.blocked, 'Même état de matrice, seule la config change : preuve que la sévérité est un paramètre');
    }

    @IsTest
    static void testSansMatrice_severiteEstUnParametre() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        Date today = Date.newInstance(2026, 8, 17);

        AR_QualificationGatingEvaluator.Decision warningDecision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, settings('Warning', 'Warning', Date.newInstance(2020, 1, 1)), today
        );
        AR_QualificationGatingEvaluator.Decision blockingDecision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, settings('Blocking', 'Warning', Date.newInstance(2020, 1, 1)), today
        );

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.NO_MATRIX, warningDecision.matchedCase);
        System.assertEquals(false, warningDecision.blocked);
        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.NO_MATRIX, blockingDecision.matchedCase);
        System.assertEquals(true, blockingDecision.blocked);
    }

    @IsTest
    static void testSansMatrice_seulementBrouillonOuRefusee_traiteCommeSansMatrice() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(AR_Status__c = 'Brouillon'),
            new AR_Price_Matrix__c(AR_Status__c = 'Refusée')
        };

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, matrices, settings('Blocking', 'Blocking', Date.newInstance(2020, 1, 1)), Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(AR_QualificationGatingEvaluator.GatingCase.NO_MATRIX, decision.matchedCase);
        System.assertEquals(true, decision.blocked);
    }

    @IsTest
    static void testBesoinAvantBascule_plafonneAvertissement_memeSiConfigBloquant() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 1, 1));
        AR_Gating_Setting__mdt config = settings('Blocking', 'Blocking', Date.newInstance(2026, 6, 1));

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, new List<AR_Price_Matrix__c>(), config, Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, decision.appliedSeverity);
        System.assertEquals(false, decision.blocked, 'Besoin créé avant la date de bascule : jamais bloquant');
    }

    @IsTest
    static void testBesoinApresBascule_severiteConfigureeDirecte_sansPlafond() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 7, 1));
        AR_Gating_Setting__mdt config = settings('Blocking', 'Blocking', Date.newInstance(2026, 6, 1));

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, new List<AR_Price_Matrix__c>(), config, Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(AR_QualificationGatingEvaluator.Severity.BLOCKING, decision.appliedSeverity);
        System.assertEquals(true, decision.blocked, 'Besoin créé à partir de la date de bascule : sévérité configurée immédiatement, sans délai');
    }

    @IsTest
    static void testBesoinCreeExactementLeJourDeBascule_nEstPasAnterieur() {
        cxsrec__cxsPosition__c position = positionCreatedOn(Date.newInstance(2026, 6, 1));
        AR_Gating_Setting__mdt config = settings('Blocking', 'Blocking', Date.newInstance(2026, 6, 1));

        AR_QualificationGatingEvaluator.Decision decision = AR_QualificationGatingEvaluator.evaluate(
            position, new List<AR_Price_Matrix__c>(), config, Date.newInstance(2026, 8, 17)
        );

        System.assertEquals(true, decision.blocked, 'Créé le jour même de la bascule : pas antérieur, sévérité normale');
    }

    @IsTest
    static void testParseSeverity_valeurNonReconnue_replisurWarning() {
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, AR_QualificationGatingEvaluator.parseSeverity('Bloquant'));
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, AR_QualificationGatingEvaluator.parseSeverity(null));
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, AR_QualificationGatingEvaluator.parseSeverity(''));
        System.assertEquals(false, AR_QualificationGatingEvaluator.isRecognizedSeverity('Bloquant'));
        System.assertEquals(true, AR_QualificationGatingEvaluator.isRecognizedSeverity('Blocking'));
    }

    @IsTest
    static void testParseSeverity_valeursReconnues() {
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.IGNORE, AR_QualificationGatingEvaluator.parseSeverity('Ignore'));
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.WARNING, AR_QualificationGatingEvaluator.parseSeverity('Warning'));
        System.assertEquals(AR_QualificationGatingEvaluator.Severity.BLOCKING, AR_QualificationGatingEvaluator.parseSeverity('Blocking'));
    }
}