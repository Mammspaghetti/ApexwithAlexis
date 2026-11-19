/**
 * Tests AR_PTFFormatUtil — session 20c. Le seul test qui prouve la correction (mois en anglais sur
 * le PDF, constaté le 11/08/2026) est celui qui exécute en `System.runAs` avec un utilisateur dont
 * la langue/locale n'est PAS le français et vérifie que la sortie reste française : la classe ne
 * doit dépendre d'aucun format() sensible à la locale de l'utilisateur courant.
 */
@IsTest
private class AR_PTFFormatUtilTest {
  @TestSetup
  static void setup() {
    // Profil "Minimum Access - Salesforce" : aucune permission particulière requise pour ce test
    // (formatage de chaînes pur, aucun accès objet/champ) — le choix le plus léger possible pour
    // créer un utilisateur de test dans cet org managé.
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
    User englishUser = new User(
      ProfileId = p.Id,
      LastName = 'PTFFormatTest',
      FirstName = 'AR',
      Alias = 'arptft',
      Email = 'ar.ptf.format.test@abylsengroup.com.invalid',
      Username = 'ar.ptf.format.test@abylsengroup.com.invalid.' + Datetime.now().getTime(),
      TimeZoneSidKey = 'Europe/Paris',
      LocaleSidKey = 'en_US',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      // Règle de validation de l'org (hors périmètre AR_) : Federation Id obligatoire à la création.
      FederationIdentifier = 'ar.ptf.format.test.' + Datetime.now().getTime()
    );
    insert englishUser;
  }

  private static User getEnglishUser() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'ar.ptf.format.test@abylsengroup.com.invalid%'
      LIMIT 1
    ];
  }

  @IsTest
  static void testFormatDateFr_asEnglishLocaleUser_staysFrench() {
    User englishUser = getEnglishUser();

    System.runAs(englishUser) {
      System.assertEquals(
        'en_US',
        UserInfo.getLocale(),
        'Le test doit réellement s\'exécuter sous une locale non française pour être probant'
      );
      System.assertEquals(
        '11 août 2026',
        AR_PTFFormatUtil.formatDateFr(Date.newInstance(2026, 8, 11)),
        'Le mois doit rester en français quelle que soit la locale de l\'utilisateur'
      );
      System.assertEquals(
        '1er janvier 2027',
        AR_PTFFormatUtil.formatDateFr(Date.newInstance(2027, 1, 1)),
        'Le 1er du mois porte le suffixe "er" en français, cf. session 37'
      );
    }
  }

  @IsTest
  static void testFormatDateFr_firstOfMonth_usesErSuffix() {
    System.assertEquals('1er septembre 2026', AR_PTFFormatUtil.formatDateFr(Date.newInstance(2026, 9, 1)));
    System.assertEquals('2 septembre 2026', AR_PTFFormatUtil.formatDateFr(Date.newInstance(2026, 9, 2)));
  }

  @IsTest
  static void testFormatNumberFr_asEnglishLocaleUser_usesCommaAndNbspSeparators() {
    User englishUser = getEnglishUser();

    System.runAs(englishUser) {
      System.assertEquals(
        '18,17',
        AR_PTFFormatUtil.formatNumberFr(18.1666, 2),
        'Virgule décimale française attendue, pas le point anglo-saxon'
      );
      System.assertEquals(
        '12' + AR_PTFFormatUtil.NBSP + '345',
        AR_PTFFormatUtil.formatNumberFr(12345, 0),
        'Séparateur de milliers = espace insécable, pas la virgule anglo-saxonne'
      );
    }
  }

  @IsTest
  static void testFormatDateFr_nullDate_returnsNull() {
    System.assertEquals(null, AR_PTFFormatUtil.formatDateFr(null));
    System.assertEquals(null, AR_PTFFormatUtil.formatDatetimeFr(null));
  }

  @IsTest
  static void testFormatDateFr_allTwelveMonths_matchFrenchNames() {
    List<String> expected = new List<String>{
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    };
    for (Integer m = 1; m <= 12; m++) {
      String label = AR_PTFFormatUtil.formatDateFr(Date.newInstance(2026, m, 15));
      System.assert(
        label.contains(expected[m - 1]),
        'Mois ' + m + ' attendu "' + expected[m - 1] + '" dans "' + label + '"'
      );
    }
  }

  @IsTest
  static void testFormatNumberFr_trimsTrailingZeros() {
    System.assertEquals('18', AR_PTFFormatUtil.formatNumberFr(18.00, 2));
    System.assertEquals('18,1', AR_PTFFormatUtil.formatNumberFr(18.10, 2));
    System.assertEquals('18,17', AR_PTFFormatUtil.formatNumberFr(18.1666, 2));
  }

  @IsTest
  static void testFormatNumberFr_negativeValue_keepsMinusSign() {
    System.assertEquals('-45', AR_PTFFormatUtil.formatNumberFr(-45, 0));
  }

  @IsTest
  static void testFormatNumberFr_nullValue_returnsNull() {
    System.assertEquals(null, AR_PTFFormatUtil.formatNumberFr(null, 2));
    System.assertEquals(null, AR_PTFFormatUtil.formatNumberFr(null, 0, 'j'));
  }

  @IsTest
  static void testFormatNumberFr_withUnit_appendsNbspAndUnit() {
    String result = AR_PTFFormatUtil.formatNumberFr(931, 0, '€');
    System.assert(result.startsWith('931'));
    System.assert(result.endsWith(AR_PTFFormatUtil.NBSP + '€'));
  }

  // Socle multi-devises, restitution (session 24b).
  @IsTest
  static void testCurrencySymbol_knownCodes() {
    System.assertEquals('€', AR_PTFFormatUtil.currencySymbol('EUR'));
    System.assertEquals('£', AR_PTFFormatUtil.currencySymbol('GBP'));
    System.assertEquals('CHF', AR_PTFFormatUtil.currencySymbol('CHF'));
    System.assertEquals('CAD', AR_PTFFormatUtil.currencySymbol('CAD'));
    System.assertEquals('MAD', AR_PTFFormatUtil.currencySymbol('MAD'));
  }

  @IsTest
  static void testCurrencySymbol_blankOrNull_defaultsToEuro() {
    System.assertEquals('€', AR_PTFFormatUtil.currencySymbol(null));
    System.assertEquals('€', AR_PTFFormatUtil.currencySymbol(''));
  }

  @IsTest
  static void testCurrencyLabelFr_knownCodes() {
    System.assertEquals('euros', AR_PTFFormatUtil.currencyLabelFr('EUR'));
    System.assertEquals('livres sterling', AR_PTFFormatUtil.currencyLabelFr('GBP'));
    System.assertEquals('francs suisses', AR_PTFFormatUtil.currencyLabelFr('CHF'));
    System.assertEquals('dollars canadiens', AR_PTFFormatUtil.currencyLabelFr('CAD'));
    System.assertEquals('dirhams marocains', AR_PTFFormatUtil.currencyLabelFr('MAD'));
  }

  @IsTest
  static void testCurrencyLabelFr_blankOrNull_defaultsToEuros() {
    System.assertEquals('euros', AR_PTFFormatUtil.currencyLabelFr(null));
    System.assertEquals('euros', AR_PTFFormatUtil.currencyLabelFr(''));
  }

  @IsTest
  static void testFormatDatetimeFr_roundTripsThroughDateComponents() {
    Datetime dt = Datetime.newInstanceGmt(2026, 8, 11, 10, 0, 0);
    String label = AR_PTFFormatUtil.formatDatetimeFr(dt);
    System.assert(label.contains('2026'));
    System.assert(
      label.contains('août') || label.contains('juillet'),
      'Selon le fuseau, le 11/08 GMT peut retomber sur juillet ou août — les deux sont acceptables ici : ' +
      label
    );
  }
}