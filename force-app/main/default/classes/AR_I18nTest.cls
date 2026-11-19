@IsTest
private class AR_I18nTest {
    @IsTest
    static void remplaceLesMarqueursDansLOrdre() {
        System.assertEquals(
            'Le plancher (20 %) doit être inférieur à la cible (25 %).',
            AR_I18n.format('Le plancher ({0} %) doit être inférieur à la cible ({1} %).', new List<Object>{ 20, 25 })
        );
    }

    @IsTest
    static void conserveLesApostrophes() {
        System.assertEquals(
            'L\'entité X n\'est pas configurée.',
            AR_I18n.format('L\'entité {0} n\'est pas configurée.', new List<Object>{ 'X' })
        );
    }

    @IsTest
    static void valeurNulleEtModeleNul() {
        System.assertEquals('Statut : ', AR_I18n.format('Statut : {0}', new List<Object>{ null }));
        System.assertEquals('', AR_I18n.format(null, new List<Object>{ 'x' }));
        System.assertEquals('Sans argument', AR_I18n.format('Sans argument', null));
    }

    @IsTest
    static void marqueurRepeteEtLibelleReel() {
        System.assertEquals('A et A', AR_I18n.format('{0} et {0}', new List<Object>{ 'A' }));
        System.assert(String.isNotBlank(AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ 'a', 'b' })));
    }
}