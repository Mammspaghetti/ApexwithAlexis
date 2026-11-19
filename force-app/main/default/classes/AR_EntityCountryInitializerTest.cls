@IsTest
private class AR_EntityCountryInitializerTest {
  private static AR_PTF_Entity_Referential__c newEntity(String name, String address, String country) {
    return new AR_PTF_Entity_Referential__c(
      Name = name,
      AR_Active__c = true,
      AR_Address__c = address,
      AR_Country__c = country
    );
  }

  @IsTest
  static void testDetectCountry_readableOnItsOwnLine() {
    System.assertEquals(
      'France',
      AR_EntityCountryInitializer.detectCountry('Bâtiment CITYLIFE\n28 Allée d\'Aquitaine\n92000 NANTERRE\nFrance\nEntité juridique : ABMI GROUPE SAS')
    );
    System.assertEquals(
      'Royaume-Uni',
      AR_EntityCountryInitializer.detectCountry('130 Aztec West\r\nBS32 4UB BRISTOL\r\n  royaume-uni  \r\nCompany n° 1')
    );
  }

  @IsTest
  static void testDetectCountry_emptyOrUnreadable_returnsNull() {
    System.assertEquals(null, AR_EntityCountryInitializer.detectCountry(null));
    System.assertEquals(null, AR_EntityCountryInitializer.detectCountry('   '));
    // Adresse de test sans pays, et nom de pays seulement noyé dans une ligne (ABYLSEN LUXEMBOURG SA) :
    // jamais retenu — seul un nom de pays seul sur sa ligne compte.
    System.assertEquals(null, AR_EntityCountryInitializer.detectCountry('TEST — adresse fictive\n1 rue du Test\n75000 PARIS'));
    System.assertEquals(null, AR_EntityCountryInitializer.detectCountry('L-1282 LUXEMBOURG\nABYLSEN LUXEMBOURG SA'));
  }

  @IsTest
  static void testDetectCountry_twoDifferentCountries_isAmbiguousAndNull() {
    System.assertEquals(null, AR_EntityCountryInitializer.detectCountry('1 rue X\nFrance\nBelgique'));
    // Le même pays répété n'est pas une ambiguïté.
    System.assertEquals('France', AR_EntityCountryInitializer.detectCountry('France\n1 rue X\nFrance'));
  }

  @IsTest
  static void testRun_fillsReadable_leavesAmbiguousEmptyAndUnreadable_neverOverwrites() {
    insert new List<AR_PTF_Entity_Referential__c>{
      newEntity('S141 Lisible', '2 rue A\n75008 PARIS\nFrance', null),
      newEntity('S141 Ambigu', '2 rue A\nFrance\nBelgique', null),
      newEntity('S141 Vide', null, null),
      newEntity('S141 Sans pays', '1 rue du Test\n75000 PARIS', null),
      newEntity('S141 Deja saisi', '2 rue A\nFrance', 'Suisse')
    };

    AR_EntityCountryInitializer.Result result = AR_EntityCountryInitializer.run(false);

    Map<String, String> byName = new Map<String, String>();
    for (AR_PTF_Entity_Referential__c e : [
      SELECT Name, AR_Country__c FROM AR_PTF_Entity_Referential__c WHERE Name LIKE 'S141%'
    ]) {
      byName.put(e.Name, e.AR_Country__c);
    }
    System.assertEquals('France', byName.get('S141 Lisible'));
    System.assertEquals(null, byName.get('S141 Ambigu'), 'Ambigu : laissé vide');
    System.assertEquals(null, byName.get('S141 Vide'));
    System.assertEquals(null, byName.get('S141 Sans pays'));
    System.assertEquals('Suisse', byName.get('S141 Deja saisi'), 'Une valeur saisie n\'est jamais écrasée');

    System.assert(result.filled.contains('S141 Lisible → France'));
    System.assert(result.ambiguous.contains('S141 Ambigu'));
    System.assert(result.unreadable.contains('S141 Vide'));
    System.assert(result.unreadable.contains('S141 Sans pays'));
    System.assert(result.alreadySet.contains('S141 Deja saisi → Suisse'));
  }

  @IsTest
  static void testRun_dryRun_reportsButWritesNothing() {
    insert newEntity('S141 DryRun', '2 rue A\nItalie', null);

    AR_EntityCountryInitializer.Result result = AR_EntityCountryInitializer.run(true);

    System.assert(result.dryRun);
    System.assert(result.filled.contains('S141 DryRun → Italie'));
    System.assertEquals(
      null,
      [SELECT AR_Country__c FROM AR_PTF_Entity_Referential__c WHERE Name = 'S141 DryRun'].AR_Country__c,
      'dryRun ne doit rien écrire'
    );
  }

  @IsTest
  static void testRun_inactiveEntityIsIgnored() {
    insert new AR_PTF_Entity_Referential__c(Name = 'S141 Inactive', AR_Active__c = false, AR_Address__c = 'X\nFrance');

    AR_EntityCountryInitializer.run(false);

    System.assertEquals(
      null,
      [SELECT AR_Country__c FROM AR_PTF_Entity_Referential__c WHERE Name = 'S141 Inactive'].AR_Country__c
    );
  }
}