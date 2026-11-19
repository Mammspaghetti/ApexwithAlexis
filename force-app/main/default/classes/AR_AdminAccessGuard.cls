/**
 * Contrôle d'accès à la page d'administration, redécoupé par domaine (session 42, étendu à un
 * quatrième domaine en session 46) : la page d'administration n'est plus un tout ou rien (une
 * Custom Permission d'admin unique, session 23, retirée en session 43) mais quatre habilitations
 * indépendantes — un onglet n'existe que pour qui détient la permission de son domaine, qui n'en
 * détient aucune ne sait pas que la page existe. Masquer les onglets côté LWC n'est qu'un confort —
 * chaque garde ci-dessous est appelée en tête de la méthode `@AuraEnabled` correspondante (cf. table
 * des gardes, prompts/session-42-administration-par-domaine.md §2), le serveur fait foi.
 *
 * Vérifié via les Custom Permissions `AR_Admin_General_Settings` / `AR_Admin_Currency` /
 * `AR_Admin_Referentials` / `AR_Admin_PTF_Entities`, pas par une requête SOQL sur
 * PermissionSetAssignment : cette dernière est un « Setup entity » et lève
 * System.SecurityException pour tout utilisateur sans la permission système « View Setup and
 * Configuration », même pour une requête sur sa propre affectation (docs/23-administration.md).
 */
public without sharing class AR_AdminAccessGuard {

    private static final String GENERAL_SETTINGS_PERMISSION = 'AR_Admin_General_Settings';
    private static final String CURRENCY_PERMISSION = 'AR_Admin_Currency';
    private static final String REFERENTIALS_PERMISSION = 'AR_Admin_Referentials';
    private static final String PTF_ENTITIES_PERMISSION = 'AR_Admin_PTF_Entities';

    public class AdminAccessDto {
        @AuraEnabled public Boolean generalSettings;
        // `currency` seul est un identifiant réservé en Apex (mot-clé multi-devises) — suffixe
        // Access pour rester cohérent avec le reste du DTO sans se heurter à la réserve.
        @AuraEnabled public Boolean currencyAccess;
        @AuraEnabled public Boolean referentials;
        @AuraEnabled public Boolean ptfEntities;
    }

    /** Lève une exception nommant le domaine si l'utilisateur courant n'a pas AR_Admin_General_Settings. */
    public static void requireGeneralSettings() {
        if (!FeatureManagement.checkPermission(GENERAL_SETTINGS_PERMISSION)) {
            throw newAuraException(Label.AR_Msg_ACC_AdminGeneralOnly);
        }
    }

    /** Lève une exception nommant le domaine si l'utilisateur courant n'a pas AR_Admin_Currency. */
    public static void requireCurrency() {
        if (!FeatureManagement.checkPermission(CURRENCY_PERMISSION)) {
            throw newAuraException(Label.AR_Msg_ACC_AdminCurrencyOnly);
        }
    }

    /** Lève une exception nommant le domaine si l'utilisateur courant n'a pas AR_Admin_Referentials. */
    public static void requireReferentials() {
        if (!FeatureManagement.checkPermission(REFERENTIALS_PERMISSION)) {
            throw newAuraException(Label.AR_Msg_ACC_AdminReferentialsOnly);
        }
    }

    /** Lève une exception nommant le domaine si l'utilisateur courant n'a pas AR_Admin_PTF_Entities. */
    public static void requirePtfEntities() {
        if (!FeatureManagement.checkPermission(PTF_ENTITIES_PERMISSION)) {
            throw newAuraException(Label.AR_Msg_ACC_AdminPtfEntitiesOnly);
        }
    }

    /**
     * Les quatre booléens en un seul appel (session 42 §1, étendu session 46) : le shell
     * (arPricingApp) et la page d'administration (arAdminPage) appellent chacun cette méthode une
     * fois au chargement, jamais une méthode par domaine — cf. doctrine session 40 §3 sur le nombre
     * d'appels serveur au démarrage.
     */
    @AuraEnabled(cacheable=true)
    public static AdminAccessDto getAdminAccess() {
        AdminAccessDto dto = new AdminAccessDto();
        dto.generalSettings = FeatureManagement.checkPermission(GENERAL_SETTINGS_PERMISSION);
        dto.currencyAccess = FeatureManagement.checkPermission(CURRENCY_PERMISSION);
        dto.referentials = FeatureManagement.checkPermission(REFERENTIALS_PERMISSION);
        dto.ptfEntities = FeatureManagement.checkPermission(PTF_ENTITIES_PERMISSION);
        return dto;
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}