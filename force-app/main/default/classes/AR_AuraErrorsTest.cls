/**
 * Session 154 — tests de AR_AuraErrors.wrap (couverture par classe exigée au déploiement, cf. 152c).
 * Les branches DML s'appuient sur de vraies erreurs de plateforme (un DmlException ne se construit pas
 * avec un statut) ; chaque test vérifie le message complet, jamais seulement qu'une exception existe.
 */
@IsTest
private class AR_AuraErrorsTest {
  private static final String ACTION = 'l\'enregistrement';

  private static DmlException dmlFailure(SObject record) {
    try {
      insert record;
    } catch (DmlException e) {
      return e;
    }
    return null;
  }

  @IsTest
  static void wrapPassesThroughAnExistingAuraHandledException() {
    AuraHandledException original = new AuraHandledException('Message métier déjà lisible');
    original.setMessage('Message métier déjà lisible');

    AuraHandledException wrapped = AR_AuraErrors.wrap(original, ACTION);

    System.assertEquals('Message métier déjà lisible', wrapped.getMessage());
  }

  @IsTest
  static void wrapDmlRequiredFieldMissingNamesTheField() {
    System.runAs(AR_TestPersona.francais()) {
      DmlException e = dmlFailure(new Contact());
      System.assertNotEquals(null, e, 'Le DML sans nom de famille doit échouer');
      System.assertEquals('REQUIRED_FIELD_MISSING', e.getDmlStatusCode(0));

      AuraHandledException wrapped = AR_AuraErrors.wrap(e, ACTION);

      System.assertEquals(ACTION + ' impossible : LastName est obligatoire [REQUIRED_FIELD_MISSING]', wrapped.getMessage());
      System.assert(!wrapped.getMessage().contains('Script-thrown exception'));
    }
  }

  @IsTest
  static void wrapDmlFieldIntegrityNamesTheField() {
    System.runAs(AR_TestPersona.francais()) {
      DmlException e = dmlFailure(new Contact(LastName = 'AR154', Birthdate = Date.newInstance(1500, 1, 1)));
      System.assertNotEquals(null, e, 'Une date de naissance hors plage doit échouer');
      System.assertEquals('FIELD_INTEGRITY_EXCEPTION', e.getDmlStatusCode(0));

      AuraHandledException wrapped = AR_AuraErrors.wrap(e, 'la validation');

      System.assert(wrapped.getMessage().startsWith('la validation impossible : Birthdate — '), wrapped.getMessage());
      System.assert(wrapped.getMessage().endsWith(' [FIELD_INTEGRITY_EXCEPTION]'), wrapped.getMessage());
    }
  }

  @IsTest
  static void wrapDmlOtherStatusKeepsMessageAndStatusCode() {
    System.runAs(AR_TestPersona.francais()) {
      DmlException e = dmlFailure(new Contact(LastName = 'AR154', Email = 'pas-un-email'));
      System.assertNotEquals(null, e, 'Une adresse e-mail invalide doit échouer');
      String status = e.getDmlStatusCode(0);

      AuraHandledException wrapped = AR_AuraErrors.wrap(e, ACTION);

      System.assertEquals(ACTION + ' impossible : ' + e.getDmlMessage(0) + ' [' + status + ']', wrapped.getMessage());
      System.assert(wrapped.getMessage().contains('pas-un-email'), wrapped.getMessage());
    }
  }

  @IsTest
  static void wrapQueryExceptionShowsMessageAndType() {
    System.runAs(AR_TestPersona.francais()) {
      QueryException qe;
      try {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'AR154-inexistant-xyz' LIMIT 1];
      } catch (QueryException e) {
        qe = e;
      }
      System.assertNotEquals(null, qe, 'La requête sans résultat doit lever QueryException');

      AuraHandledException wrapped = AR_AuraErrors.wrap(qe, 'le chargement');

      System.assertEquals('le chargement impossible : ' + qe.getMessage() + ' [System.QueryException]', wrapped.getMessage());
      System.assert(wrapped.getMessage().contains('List has no rows'), wrapped.getMessage());
    }
  }

  @IsTest
  static void wrapGenericExceptionShowsMessageAndType() {
    System.runAs(AR_TestPersona.francais()) {
      NullPointerException npe;
      try {
        String nothing = null;
        nothing.length();
      } catch (NullPointerException e) {
        npe = e;
      }
      System.assertNotEquals(null, npe, 'Le déréférencement de null doit lever NullPointerException');

      AuraHandledException wrapped = AR_AuraErrors.wrap(npe, ACTION);

      System.assertEquals(ACTION + ' impossible : ' + npe.getMessage() + ' [System.NullPointerException]', wrapped.getMessage());
      System.assert(!wrapped.getMessage().contains('Script-thrown exception'), wrapped.getMessage());

      AuraHandledException withMessage = AR_AuraErrors.wrap(new CalloutException('délai dépassé'), 'la génération');
      System.assertEquals('la génération impossible : délai dépassé [System.CalloutException]', withMessage.getMessage());
    }
  }
}