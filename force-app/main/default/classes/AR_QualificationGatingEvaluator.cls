/**
 * Règle unique de gating qualification (session 21b) : classe pure, sans SOQL/DML/contexte trigger,
 * seul endroit où vit la logique de sévérité. AR_QualificationGatingHandler ne branche jamais lui-même
 * sur "avertir vs bloquer" — il ne fait que lire la Decision retournée ici.
 */
public class AR_QualificationGatingEvaluator {

    public enum Severity { IGNORE, WARNING, BLOCKING }
    public enum GatingCase { CONFORME, DEROGATION_PENDING, NO_MATRIX }

    private static final Set<String> VALIDATED_STATUSES = new Set<String>{ 'Validée', 'Validée par dérogation' };

    public class Decision {
        public GatingCase matchedCase;
        public Severity appliedSeverity;
        public Boolean blocked;
    }

    public static Decision evaluate(
        cxsrec__cxsPosition__c position,
        List<AR_Price_Matrix__c> matrices,
        AR_Gating_Setting__mdt settings,
        Date today
    ) {
        GatingCase matchedCase = classify(matrices);
        Severity baseSeverity = matchedCase == GatingCase.CONFORME
            ? Severity.IGNORE
            : parseSeverity(
                matchedCase == GatingCase.DEROGATION_PENDING
                    ? settings.AR_Severity_Derogation_Pending__c
                    : settings.AR_Severity_No_Matrix__c
              );

        Boolean capped = position.CreatedDate != null
            && settings.AR_Go_Live_Date__c != null
            && position.CreatedDate.date() < settings.AR_Go_Live_Date__c;
        Severity effectiveSeverity = capped ? capAtWarning(baseSeverity) : baseSeverity;

        Decision decision = new Decision();
        decision.matchedCase = matchedCase;
        decision.appliedSeverity = effectiveSeverity;
        decision.blocked = effectiveSeverity == Severity.BLOCKING;
        return decision;
    }

    private static GatingCase classify(List<AR_Price_Matrix__c> matrices) {
        Boolean hasDerogationPending = false;
        for (AR_Price_Matrix__c matrix : matrices) {
            if (VALIDATED_STATUSES.contains(matrix.AR_Status__c)) {
                return GatingCase.CONFORME;
            }
            if (matrix.AR_Status__c == 'En dérogation') {
                hasDerogationPending = true;
            }
        }
        return hasDerogationPending ? GatingCase.DEROGATION_PENDING : GatingCase.NO_MATRIX;
    }

    private static Severity capAtWarning(Severity inputSeverity) {
        return inputSeverity == Severity.BLOCKING ? Severity.WARNING : inputSeverity;
    }

    /**
     * Une valeur non reconnue en mdt (typo, valeur vide) n'est jamais silencieusement ignorée ni
     * bloquante par surprise — repli sur WARNING, cohérent avec le comportement "explicite et
     * visible" demandé pour toute configuration invalide (cf. AR_QualificationGatingHandler).
     */
    public static Severity parseSeverity(String rawValue) {
        if (rawValue == 'Ignore') {
            return Severity.IGNORE;
        }
        if (rawValue == 'Blocking') {
            return Severity.BLOCKING;
        }
        if (rawValue == 'Warning') {
            return Severity.WARNING;
        }
        return Severity.WARNING;
    }

    public static Boolean isRecognizedSeverity(String rawValue) {
        return rawValue == 'Ignore' || rawValue == 'Warning' || rawValue == 'Blocking';
    }
}