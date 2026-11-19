@IsTest
private class AR_UserLanguageServiceTest {
    @IsTest
    static void testSwitchFrenchToEnglish() {
        User persona = AR_TestPersona.francais();

        System.runAs(persona) {
            AR_UserLanguageService.setMyLanguage('en_US');
        }

        System.assertEquals('en_US', [SELECT LanguageLocaleKey FROM User WHERE Id = :persona.Id].LanguageLocaleKey);
    }

    @IsTest
    static void testSwitchEnglishToFrench() {
        User persona = AR_TestPersona.francais();
        System.runAs(persona) {
            AR_UserLanguageService.setMyLanguage('en_US');
        }

        System.runAs(persona) {
            AR_UserLanguageService.setMyLanguage('fr');
        }

        System.assertEquals('fr', [SELECT LanguageLocaleKey FROM User WHERE Id = :persona.Id].LanguageLocaleKey);
    }

    @IsTest
    static void testUnsupportedLanguageIsRefused() {
        User persona = AR_TestPersona.francais();
        String message;

        System.runAs(persona) {
            try {
                AR_UserLanguageService.setMyLanguage('de');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }

        System.assert(message != null, 'Une langue hors liste blanche doit lever une AuraHandledException');
        System.assertEquals('fr', [SELECT LanguageLocaleKey FROM User WHERE Id = :persona.Id].LanguageLocaleKey);
    }
}