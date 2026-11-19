/**
 * Bascule de la langue de l'utilisateur courant depuis le sélecteur FR/EN du panneau latéral.
 * Seules les deux langues de l'application sont acceptées ; la mise à jour ne porte que sur
 * l'utilisateur qui l'appelle.
 */
public with sharing class AR_UserLanguageService {
    private static final Set<String> SUPPORTED_LANGUAGES = new Set<String>{ 'fr', 'en_US' };

    @AuraEnabled
    public static void setMyLanguage(String languageKey) {
        if (!SUPPORTED_LANGUAGES.contains(languageKey)) {
            throw new AuraHandledException('Langue non prise en charge : ' + languageKey);
        }
        try {
            update new User(Id = UserInfo.getUserId(), LanguageLocaleKey = languageKey);
        } catch (Exception e) {
            throw AR_AuraErrors.wrap(e, 'la mise à jour de la langue');
        }
    }
}