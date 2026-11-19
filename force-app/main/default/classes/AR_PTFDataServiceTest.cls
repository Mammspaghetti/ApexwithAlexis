/**
 * Tests AR_PTFDataService : gating par statut, cartographie des trois catégories de champs
 * (donnée / référentiel / saisie utilisateur), calcul de l'échéancier (port de computePTFSchedule).
 */
@IsTest
private class AR_PTFDataServiceTest {
  @TestSetup
  static void setup() {
    Account acc = new Account(
      Name = 'Client PTF',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001',
      BillingStreet = '10 avenue du Client',
      BillingCity = 'Lyon',
      BillingPostalCode = '69002'
    );
    insert acc;

    Contact hiringManager = new Contact(
      FirstName = 'Marie',
      LastName = 'Client',
      Title = 'Directrice Technique',
      Phone = '0102030405',
      Email = 'marie.client@example.com'
    );
    insert hiringManager;

    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin PTF',
      cxsrec__Account__c = acc.Id,
      cxsrec__Country__c = 'France',
      cxsrec__Status__c = 'Open',
      cxsrec__Contract_type__c = 'CDI',
      cxsrec__Hiringmanager__c = hiringManager.Id
    );
    insert position;

    // Référentiel AR_PTF_Entity_Referential__c (session 46, remplace AR_PTF_Entity__mdt) : objet
    // standard désormais, sa donnée n'est plus déployée avec le code — chaque test la reconstitue
    // ici, à l'identique des trois fiches précédemment portées par le __mdt.
    insert new List<AR_PTF_Entity_Referential__c>{
      // Session 184c3 : GAMMA porte un RIB (les fixtures retombent sur ABYLSEN_AT_V11, seul gabarit
      // par défaut depuis la 184c) ; les tests de blocage bancaire vident le RIB explicitement.
      new AR_PTF_Entity_Referential__c(
        Name = 'Abylsen GAMMA',
        AR_Active__c = true,
        AR_Rib__c = '00000 00000 00000000000 00 (FICTIF test)'
      ),
      new AR_PTF_Entity_Referential__c(
        Name = 'ABMI Groupe',
        AR_Active__c = true,
        AR_Address__c = '28 Allée d\'Aquitaine',
        AR_Postal_Code__c = '92000',
        AR_City__c = 'NANTERRE',
        AR_Phone__c = '+33 (0)1 30 79 12 79',
        AR_Fax__c = '+33 (0)1 30 55 82 85',
        AR_Website__c = 'www.abmi-groupe.com',
        AR_Template_Code__c = 'ABMI_DQ012'
      ),
      // Coordonnées de démonstration FICTIVES (cf. force-app/.../AR_PTF_Entity__mdt.Abylsen_SIGMA,
      // dont ce jeu de test reprend les valeurs) — jamais des coordonnées réelles.
      new AR_PTF_Entity_Referential__c(
        Name = 'Abylsen SIGMA',
        AR_Active__c = true,
        AR_Address__c = '12 rue de la Démonstration (DONNÉE FICTIVE — session 36)',
        AR_Postal_Code__c = '75000',
        AR_City__c = 'Paris (FICTIF)',
        AR_Siret__c = '00000000000 FICTIF',
        AR_Phone__c = '+33000000000',
        AR_Bank_Name__c = 'BANQUE DE DEMONSTRATION (FICTIF)',
        AR_Rib__c = '00000 00000 00000000000 00 (FICTIF)',
        AR_Iban__c = 'FR76 0000 0000 0000 0000 0000 000 (FICTIF)',
        AR_Bic__c = 'FICTFRPP',
        AR_Tribunal_Competent__c = 'Tribunal de Commerce de Nanterre (FICTIF)'
      )
    };

    insert new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Brouillon',
      // Dénormalisé habituellement par AR_PricingMatrixService.buildMatrixFromInput (non appelé
      // ici, insertion directe) : posé à la main pour que la collecte PTF (catégorie A) ait une
      // valeur à lire, comme en usage réel.
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'),
      AR_Consultant_Name__c = 'Jean DUPONT',
      AR_Client_Site__c = 'Paris La Défense',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );

  }

  @IsTest
  static void testCollect_draftMatrix_throwsAuraHandledException() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
      input.matrixId = matrix.Id;

      Test.startTest();
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(
          false,
          'Une matrice en Brouillon ne doit jamais autoriser la génération d\'une PTF'
        );
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('validée'),
          'Le message doit expliquer que seule une matrice validée peut générer une PTF, reçu : ' +
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  /** Session 279 : adresse client saisie imprimée et signalée ; inchangée (espaces, CRLF) → non signalée. */
  @IsTest
  static void testCollect_typedClientAddress_printedAndFlagged() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    Test.startTest();
    AR_PTFData base = AR_PTFDataService.collect(matrix.Id, input, 1);
    input.adresseClient = '  Service comptabilité\n5 rue de la Facturation\n69003 Lyon  ';
    AR_PTFData modified = AR_PTFDataService.collect(matrix.Id, input, 1);
    input.adresseClient = '  10 avenue du Client\r\n69002 Lyon \n';
    AR_PTFData unchanged = AR_PTFDataService.collect(matrix.Id, input, 1);
    Test.stopTest();

    System.assertEquals('10 avenue du Client\n69002 Lyon', base.adresseClient, 'Sans saisie : adresse du compte');
    System.assertEquals(false, base.adresseClientModifiee);
    System.assertEquals(base.adresseClient, base.adresseClientCompte);

    System.assertEquals('Service comptabilité\n5 rue de la Facturation\n69003 Lyon', modified.adresseClient,
      'Adresse saisie imprimée, espaces de début/fin retirés');
    System.assertEquals(true, modified.adresseClientModifiee);
    System.assertEquals('10 avenue du Client\n69002 Lyon', modified.adresseClientCompte);
    System.assert(JSON.serialize(modified).contains('"adresseClientModifiee":true'), 'Indicateur présent dans le snapshot');

    System.assertEquals('10 avenue du Client\n69002 Lyon', unchanged.adresseClient);
    System.assertEquals(false, unchanged.adresseClientModifiee, 'Même adresse aux espaces/fins de ligne près : non modifiée');
  }

  /** Session 279 : l'avertissement « adresse manquante » ne vaut que si rien n'est à imprimer. */
  @IsTest
  static void testApplyClientAddress_missingWarningOnlyWithoutAnyAddress() {
    AR_PTFData empty = new AR_PTFData();
    empty.warnings = new List<String>();
    AR_PTFDataService.applyClientAddress(empty, null, '   ');
    System.assertEquals(null, empty.adresseClient);
    System.assert(empty.warnings.contains(Label.AR_Msg_PTF_ClientAddressMissing));

    AR_PTFData typed = new AR_PTFData();
    typed.warnings = new List<String>();
    AR_PTFDataService.applyClientAddress(typed, null, '1 place Saisie');
    System.assertEquals('1 place Saisie', typed.adresseClient);
    System.assertEquals(true, typed.adresseClientModifiee);
    System.assert(typed.warnings.isEmpty(), 'Adresse saisie : plus d\'avertissement');
  }

  @IsTest
  static void testCollect_validatedMatrix_mapsDataAndReferentialCategories() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);
    Test.stopTest();

    // Catégorie A : issu de la donnée Salesforce (matrice, besoin, compte, contact).
    System.assertEquals('Client PTF', data.client);
    System.assertEquals('Abylsen GAMMA', data.entite);
    System.assertEquals('Jean DUPONT', data.consultantNom);
    System.assertEquals('Paris La Défense', data.lieuPrestation);
    System.assertEquals(700, data.tjm);
    System.assertEquals(Date.newInstance(2026, 9, 1), data.dateDebut);
    System.assertEquals('Marie Client', data.interNom);
    System.assertEquals('Directrice Technique', data.interFonction);
    System.assertEquals('0102030405', data.interTel);
    System.assertEquals('marie.client@example.com', data.interEmail);
    System.assert(
      data.adresseClient.contains('10 avenue du Client'),
      'L\'adresse client doit venir de Account.BillingStreet'
    );

    // Catégorie B : référentiel administrable (AR_PTF_Setting__mdt.Default, AR_Settings__mdt.Default).
    // Session 184c3 : défaut du gabarit Abylsen (seul gabarit par défaut depuis la 184c).
    System.assertEquals('Trimestrielle', data.freqReunions);
    System.assertEquals('30 jours fin de mois', data.conditionsReglement);
    System.assertEquals(18.17, data.joursParMois);

    System.assertEquals('AT', data.missionType);
    System.assertEquals(1, data.nbConsultants);
    System.assertEquals('V1', data.version);
    // Session 184d : référence = nomenclature du nom de fichier (la version a sa propre case).
    System.assert(data.reference.startsWith('PTF_ABYLSEN_'), data.reference);
    System.assertEquals(AR_PTFGenerationService.buildNomenclatureFileName(data), data.reference);

    // Dates de mission renseignées : totalHT est un vrai montant calculé, jamais null (session 20c).
    // Session 122 : jours calculés par jours ouvrés réels. Vérifier qu'une valeur est calculée, non null.
    System.assertNotEquals(null, data.totalHT);
    // Session 126 (§1) : jours ouvrés réels, week-ends exclus. 1er sept. → 31 oct. 2026 = 22 + 22 = 44 jours
    // (l'ancien 52 était le résultat du défaut corrigé en 126 : un seul jour de week-end exclu par semaine).
    // 44 jours × 700 € = 30 800 €. Pas de jours fériés (non demandé, cf. prompt session 126).
    System.assertEquals(30800, data.totalHT.setScale(0));
  }

  /**
   * Session 54 : quand le lookup AR_Consultant__c est renseigné, son Name (une donnée) est préféré
   * au texte libre historique AR_Consultant_Name__c (une heuristique de saisie) — même si les deux
   * sont renseignés et divergent. Matrice/besoin/compte propres à ce test (jamais la matrice unique
   * du @TestSetup, lue par ailleurs sans WHERE par 50+ assertions de ce fichier) pour ne prendre
   * aucun risque de rendre ces dernières non déterministes.
   */
  @IsTest
  static void testCollect_consultantLookupPresent_prefersRecordNameOverLegacyText() {
    Account acc = new Account(
      Name = 'Client Session54 Lookup',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001'
    );
    insert acc;
    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin PTF Consultant',
      cxsrec__Account__c = acc.Id,
      cxsrec__Country__c = 'France',
      cxsrec__Status__c = 'Open',
      cxsrec__Contract_type__c = 'CDI'
    );
    insert position;
    Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
      .getRecordTypeInfosByDeveloperName()
      .get('Consultant')
      .getRecordTypeId();
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = consultantRecordTypeId,
      cxsrec__First_name__c = 'Alice',
      cxsrec__Last_name__c = 'MARTIN'
    );
    insert consultant;
    consultant = [SELECT Id, Name FROM cxsrec__cxsCandidate__c WHERE Id = :consultant.Id];

    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client Session54 Lookup',
      // Les deux sont renseignés et divergent délibérément : la préférence doit être sans ambiguïté.
      AR_Consultant_Name__c = 'Texte Libre Obsolete',
      AR_Consultant__c = consultant.Id,
      // Session 184c3 : seul gabarit par défaut = Abylsen (entité avec RIB, dates de mission exigées).
      AR_Entity_Ref__c = AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    // Champ obligatoire du formulaire PTF (session 47) — matrice validée automatiquement, sans
    // dérogation, ne porte ni valideur sélectionné ni effectif : sans cette saisie, requireValideur
    // bloquerait, hors-propos pour ce test.
    input.valideurNom = 'Valideur Test';

    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);
    Test.stopTest();

    System.assertEquals(
      consultant.Name,
      data.consultantNom,
      'Le Name du consultant (donnée) doit être préféré au texte libre (heuristique), même renseigné'
    );
  }

  @IsTest
  static void testCollect_noMissionDates_totalHTIsNullNotZero() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_Status__c = 'Validée',
      AR_Start_Date__c = null,
      AR_End_Date__c = null
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    // Session 184c3 : le gabarit Abylsen refuse de générer sans dates (session 49) — le calcul sans
    // dates se vérifie en mode pré-remplissage (enforceGenerationBlocks = false), celui du formulaire.
    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);
    Test.stopTest();

    // Un montant total à zéro sur une proposition commerciale est faux — sans dates de mission,
    // l'échéancier est vide et totalHT doit rester null (le gabarit affiche "À définir"), jamais un
    // 0 inventé. Cf. constat du 11/08/2026, session 20c §2.
    System.assertEquals(0, data.schedule.size());
    System.assertEquals(null, data.totalHT);
  }

  @IsTest
  static void testCollect_userInputOverridesReferentialDefaults() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_Status__c = 'Validée par dérogation'
    );
    // Session 138 : la version affichée suit le rang dans l'historique — une version déjà générée
    // et cochée est donc nécessaire pour que celle-ci soit la V2 (comme le comptait ce test).
    insert new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-OVERRIDE-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{}',
      AR_Generated_At__c = System.now().addDays(-1),
      AR_Generation_Status__c = 'Généré'
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.freqReunions = 'Hebdomadaire';
    input.materielClient = true;
    input.objet = 'Objet personnalisé de la mission';
    input.interTel = '0600000000';

    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 2);
    Test.stopTest();

    System.assertEquals(
      'Hebdomadaire',
      data.freqReunions,
      'La saisie utilisateur (catégorie C) doit surcharger le défaut du référentiel'
    );
    System.assertEquals(true, data.materielClient);
    System.assertEquals('Objet personnalisé de la mission', data.objet);
    System.assertEquals(
      '0600000000',
      data.interTel,
      'La saisie utilisateur doit surcharger le téléphone du contact hiring manager'
    );
    System.assertEquals('V2', data.version);
  }

  // Socle multi-devises, restitution (session 24b).
  @IsTest
  static void testCollect_matrixWithoutCurrencySet_defaultsToEur() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('EUR', data.currencyCode);
  }

  @IsTest
  static void testCollect_gbpMatrix_currencyCodeReflectsMatrixCurrency() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Currency__c = 'GBP');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('GBP', data.currencyCode);
  }

  // ------------------------------------------------------------------
  // Sélection du gabarit (session 30) : manuel > compte > entité > générique.
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_noOverride_templateCodeDefaultsToAbylsen() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'ABYLSEN_AT_V11',
      data.templateCode,
      'Aucun compte ni saisie manuelle, entité de seed sans code : gabarit Abylsen par défaut (184c)'
    );
    System.assertEquals('Abylsen', data.templateCodeSource);
    System.assertEquals(false, data.isPreview);
  }

  private static AR_PTFData collectAbylsenWith(String objet, String evolutionPrix) {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c LIMIT 1];
    if (matrix.AR_Status__c != 'Validée') {
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    }
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.objet = objet;
    input.evolutionPrix = evolutionPrix;
    return AR_PTFDataService.collect(matrix.Id, input, 1);
  }

  @IsTest
  static void testCollectAbylsen_editedTexts_arePrinted() {
    AR_PTFData data = collectAbylsenWith('Objet saisi par le commercial', 'Prix révisables chaque année');

    System.assertEquals('ABYLSEN_AT_V11', data.templateCode);
    System.assertEquals('Objet saisi par le commercial', data.objetSaisi);
    System.assertEquals('Prix révisables chaque année', data.evolutionPrixSaisie);
    System.assertEquals('Objet saisi par le commercial', data.objet);
  }

  @IsTest
  static void testCollectAbylsen_untouchedTexts_useTemplateWording() {
    AR_PTFData blank = collectAbylsenWith(null, null);
    AR_PTFData prefilled = collectAbylsenWith(blank.objet, blank.evolutionPrix);

    for (AR_PTFData data : new List<AR_PTFData>{ blank, prefilled }) {
      System.assertEquals(null, data.objetSaisi, 'Texte du modèle : rien à imprimer en surcharge');
      System.assertEquals(null, data.evolutionPrixSaisie);
    }
    System.assert(blank.objet.startsWith('Ce document présente les conditions'), blank.objet);
    System.assert(blank.objet.contains(blank.entite.toUpperCase()), 'Entité en majuscules : ' + blank.objet);
    System.assert(blank.objet.contains(blank.client), blank.objet);
    System.assert(blank.evolutionPrix.contains('réévalué par accord des parties'), blank.evolutionPrix);
    System.assertEquals(blank.objet, blank.objetParGabarit.get('ABYLSEN_AT_V11'));
    System.assertNotEquals(blank.objet, blank.objetParGabarit.get('GENERIQUE'));
  }

  @IsTest
  static void testCollectAbylsen_legacyGenericDraft_isTreatedAsUnmodified() {
    AR_PTFData reference = collectAbylsenWith(null, null);
    String legacyObjet = reference.objetParGabarit.get('GENERIQUE');
    String legacyEvolution = 'Les prix sont fermes et non révisables pour la durée de la présente PTF.';

    AR_PTFData data = collectAbylsenWith(legacyObjet, legacyEvolution);
    System.assertEquals(null, data.objetSaisi);
    System.assertEquals(null, data.evolutionPrixSaisie);
    System.assertEquals(reference.objet, data.objet);

    AR_PTFData oldSentence = collectAbylsenWith(
      'La présente Proposition Technique et Financière a pour objet de définir les modalités d\'intervention auprès d\'un ancien compte.',
      null
    );
    System.assertEquals(null, oldSentence.objetSaisi, 'Phrase générique historique d\'un brouillon');
  }

  @IsTest
  static void testCollect_manualTemplateCodeOverride_winsOverEverything() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    cxsrec__cxsPosition__c position = [
      SELECT cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Id = :matrix.AR_Position__c
    ];
    insert new AR_Account_Commercial_Data__c(
      AR_Account__c = position.cxsrec__Account__c,
      AR_PTF_Template_Code__c = 'ABMI_DQ012'
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    // ABYLSEN_AT_V11 côté formulaire face à ABMI_DQ012 côté compte : deux codes VALIDES et différents,
    // seule façon de prouver la précédence sans que le blocage « code inconnu » ne masque le test.
    input.templateCode = 'ABYLSEN_AT_V11';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'ABYLSEN_AT_V11',
      data.templateCode,
      'La saisie manuelle du formulaire doit primer sur la surcharge compte'
    );
    System.assertEquals(
      'Manuel',
      data.templateCodeSource,
      'La provenance doit être figée avec le code — savoir QUEL gabarit sans savoir POURQUOI ne ' +
      'suffit pas à reconstituer la décision des mois plus tard'
    );
  }

  @IsTest
  static void testCollect_accountTemplateCodeOverride_usedWhenNoManualInput() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    cxsrec__cxsPosition__c position = [
      SELECT cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Id = :matrix.AR_Position__c
    ];
    // Session 184c3 : plus de gabarit générique. ABYLSEN_AT_V11 coïncide avec le défaut, mais
    // `templateCodeSource` prouve que c'est bien la surcharge de compte qui a été appliquée (l'entité
    // GAMMA du setup porte un RIB, le DA du propriétaire est renseigné : aucun blocage hors sujet).
    insert new AR_Account_Commercial_Data__c(
      AR_Account__c = position.cxsrec__Account__c,
      AR_PTF_Template_Code__c = 'ABYLSEN_AT_V11'
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('ABYLSEN_AT_V11', data.templateCode);
    System.assertEquals('Compte', data.templateCodeSource);
  }

  // ------------------------------------------------------------------
  // Historique multi-versions figé (session 30, décision documentée en docs/30-...md §4).
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_historique_includesPriorVersionsAndCurrentEntry() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // Version 1 déjà générée (insérée directement, comme le fait
    // AR_PTFGenerationServiceTest.testGeneratePTF_regeneration_...) : cochée par défaut, donc de
    // rang 1 dans l'historique (session 138 : les lignes viennent des champs du document, plus du
    // snapshot ni du compteur technique).
    insert new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-HIST-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"redacteurNom":"Alexis ROQUES","valideurNom":"Jean VALIDEUR"}',
      AR_Generated_At__c = System.now().addDays(-1),
      AR_Generation_Status__c = 'Généré'
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.modificationType = 'Modification de montant';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 2);

    System.assertEquals(2, data.historique.size());
    System.assertEquals('V1', data.historique[0].version);
    System.assertEquals('PTF-TEST-HIST-V1', data.historique[0].reference);
    System.assertEquals('', data.historique[0].objetModification, 'Rang 1 : cellule Modification vide');
    System.assertEquals(
      UserInfo.getName(),
      data.historique[0].responsable,
      'Responsable = CreatedBy du document (ici, l\'utilisateur du test)'
    );
    System.assertEquals('V2', data.historique[1].version);
    System.assertEquals('Modification de montant', data.historique[1].objetModification);
    System.assertEquals(UserInfo.getName(), data.historique[1].responsable);
    System.assertEquals(2, data.displayRank);
    System.assertEquals(
      data.reference,
      data.historique[1].reference,
      'La ligne courante (pas encore en base à cet instant) doit refléter la génération en cours'
    );
  }

  @IsTest
  static void testCollect_historique_uncheckedDocumentIsExcludedAndRanksAreRenumbered() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    List<AR_PTF_Document__c> docs = new List<AR_PTF_Document__c>();
    for (Integer i = 1; i <= 3; i++) {
      docs.add(
        new AR_PTF_Document__c(
          AR_Price_Matrix__c = matrix.Id,
          AR_Position__c = matrix.AR_Position__c,
          AR_Reference__c = 'PTF-TEST-RANK-V' + i,
          AR_Version_Number__c = i,
          AR_Snapshot__c = '{}',
          AR_Generated_At__c = System.now().addDays(-10 + i),
          AR_Generation_Status__c = 'Généré',
          AR_Modification_Type__c = i == 1 ? null : (i == 2 ? 'Modification de montant' : 'Autre'),
          AR_Modification_Detail__c = i == 3 ? 'Ajout d\'un consultant' : null,
          // V2 décochée : disparaît de l'historique, l'ex-V3 devient V2.
          AR_Include_In_History__c = i != 2
        )
      );
    }
    insert docs;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.modificationType = 'Modification de montant';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 4);

    // Session 184d : la référence est la nomenclature du nom de fichier ; la version affichée suit le rang (3).
    System.assert(data.reference.startsWith('PTF_ABYLSEN_'), 'Référence = nomenclature : ' + data.reference);
    System.assertEquals(AR_PTFGenerationService.buildNomenclatureFileName(data), data.reference);
    System.assertEquals('V3', data.version);
    System.assertEquals(3, data.historique.size());
    System.assertEquals('V1', data.historique[0].version);
    System.assertEquals('', data.historique[0].objetModification);
    System.assertEquals('V2', data.historique[1].version);
    System.assertEquals(
      'Ajout d\'un consultant',
      data.historique[1].objetModification,
      'Type « Autre » : le texte du détail seul, sans le mot « Autre »'
    );
    System.assertEquals('PTF-TEST-RANK-V3', data.historique[1].reference, 'L\'ex-V3 devient V2');
    System.assertEquals('V3', data.historique[2].version);
    System.assertEquals('Modification de montant', data.historique[2].objetModification);
  }

  @IsTest
  static void testCollect_v01PtfNoHistorique_showHistoriqueIsFalse() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // Première génération : V01, aucun document précédent.
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('V1', data.version);
    System.assertEquals(1, data.displayRank);
    System.assertEquals(false, data.showHistorique, 'V01 PTF : historique masqué');
  }

  @IsTest
  static void testCollect_v02PtfWithPriorVersion_showHistoriqueIsTrue() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // V1 déjà générée.
    insert new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-SHOW-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{}',
      AR_Generated_At__c = System.now().addDays(-1),
      AR_Generation_Status__c = 'Généré'
    );

    // Deuxième génération : V02, avec au moins une version précédente.
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 2);

    System.assertEquals('V2', data.version);
    System.assertEquals(2, data.displayRank);
    System.assertEquals(true, data.showHistorique, 'V02+ PTF : historique affiché');
  }

  @IsTest
  static void testCollectAvenant_alwaysShowHistorique() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // PTF parent déjà générée (V1).
    AR_PTF_Document__c parentPtf = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-AVENANT-PARENT',
      AR_Document_Type__c = 'PTF',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert parentPtf;

    // Avenant: l'historique montre la PTF parent + la ligne d'avenant.
    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.valideurNom = 'Valideur Test';
    input.prolongationJusquAu = Date.today().addMonths(1);

    AR_PTFData data = AR_PTFDataService.collectAvenant(parentPtf, input, 1);

    System.assertEquals(true, data.showHistorique, 'Avenant : historique toujours affiché');
  }

  @IsTest
  static void testBuildSchedule_missingDates_returnsEmptyList() {
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      null,
      Date.newInstance(2026, 10, 31),
      700,
      18.17,
      1
    );
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void testBuildSchedule_endBeforeStart_returnsEmptyList() {
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 10, 1),
      Date.newInstance(2026, 9, 1),
      700,
      18.17,
      1
    );
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void testBuildSchedule_twoMonths_computesRowsAndCumul() {
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 15),
      Date.newInstance(2026, 10, 31),
      700,
      18,
      1
    );
    System.assertEquals(
      2,
      rows.size(),
      'Du 1er du mois de départ (1er septembre) à fin octobre : 2 mois'
    );
    // Session 122 : jours calculés par jours ouvrés réels
    // Verified that schedule is calculated with actual working days (not fixed 18 per month)
    System.assertEquals('septembre 2026', rows[0].mois);
    System.assertEquals(true, rows[0].jours > 0, 'First month should have positive working days');
    System.assertEquals('octobre 2026', rows[1].mois);
    System.assertEquals(true, rows[1].jours > 0, 'Second month should have positive working days');
    System.assertEquals(true, rows[1].cumul > rows[0].cumul, 'Cumul should increase across months');
  }

  // ------------------------------------------------------------------
  // Session 35 — socle multi-gabarits : codes valides, blocage, lots, nouvelles données.
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // Facturation mensuelle lissée : mois complets à TJM × jours annuels / 12, mois
  // incomplets au prorata ; décochée = échéancier au jour ouvré réel (non-régression).
  // ------------------------------------------------------------------

  @IsTest
  static void testBuildSchedule_lisse_fullMonthsFlatAndPartialMonthsProrated() {
    // Mission du 15/01 au 30/06/2026 ; 218 / 12 = 18,17 j par mois complet ; TJM 700 €.
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 1, 15), Date.newInstance(2026, 6, 30), 700, 18.17, 1, null, true
    );
    System.assertEquals(6, rows.size(), 'Janvier à juin : 6 lignes');
    // Janvier : 12 jours ouvrés couverts sur 22 → 18,17 × 12 / 22 = 9,91 j ; 12 719 € × 12 / 22 = 6 938 €
    System.assertEquals(9.91, rows[0].jours, 'Janvier au prorata (jours)');
    System.assertEquals(6938, rows[0].montant, 'Janvier au prorata (montant)');
    for (Integer i = 1; i <= 4; i++) {
      System.assertEquals(18.17, rows[i].jours, rows[i].mois + ' : mois complet');
      System.assertEquals(12719, rows[i].montant, rows[i].mois + ' : 700 × 18,17');
    }
    // Juin : la mission couvre tous les jours ouvrés du mois (fin le mardi 30) → mois complet
    System.assertEquals(12719, rows[5].montant, 'Juin : mois complet selon la couverture');
    System.assertEquals(70533, rows[5].cumul, 'Total = somme des lignes : 6 938 + 5 × 12 719');
  }

  @IsTest
  static void testBuildSchedule_notLisse_isUnchangedFromRealWorkingDays() {
    List<AR_PTFData.ScheduleRow> realDays = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 1, 15), Date.newInstance(2026, 6, 30), 700, 18.17, 1
    );
    List<AR_PTFData.ScheduleRow> explicitOff = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 1, 15), Date.newInstance(2026, 6, 30), 700, 18.17, 1, null, false
    );
    System.assertEquals(realDays.size(), explicitOff.size());
    for (Integer i = 0; i < realDays.size(); i++) {
      System.assertEquals(realDays[i].jours, explicitOff[i].jours, realDays[i].mois + ' : jours');
      System.assertEquals(realDays[i].montant, explicitOff[i].montant, realDays[i].mois + ' : montant');
    }
    System.assertEquals(12, realDays[0].jours, 'Janvier décoché : 12 jours ouvrés réellement couverts');
    System.assertEquals(8400, realDays[0].montant, 'Janvier décoché : 700 × 12');
  }

  @IsTest
  static void testPreviewPtfLots_lisse_entityExceptionThenMatrixValueThenUncheckedRealDays() {
    AR_Price_Matrix__c m = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    // Exception jours travaillés de l'entité (200 / 12 = 16,67 j), matrice sans valeur figée
    update new AR_PTF_Entity_Referential__c(
      Id = AR_TestPersona.entityRefId('Abylsen GAMMA'),
      AR_Working_Days__c = 200
    );
    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewPtfLots(m.Id, true, null);
    System.assertEquals(2, lots.size(), 'Septembre et octobre 2026');
    System.assertEquals(16.67, lots[0].jours, 'Exception entité : 200 / 12');
    System.assertEquals(11669, lots[0].montant, '700 × 16,67');

    // Jours annuels figés sur la matrice : ils priment sur l'exception de l'entité (218 / 12)
    update new AR_Price_Matrix__c(Id = m.Id, AR_Working_Days_Applied__c = 218);
    lots = AR_PTFDataService.previewPtfLots(m.Id, true, null);
    System.assertEquals(18.17, lots[0].jours, 'Matrice : 218 / 12');
    System.assertEquals(12719, lots[1].montant, 'Octobre complet : 700 × 18,17');

    // Décochée : jours ouvrés réels (septembre 2026 = 22 jours, comme octobre 2026)
    lots = AR_PTFDataService.previewPtfLots(m.Id, false, null);
    System.assertEquals(22, lots[0].jours, 'Décochée : 22 jours ouvrés de septembre 2026');
    System.assertEquals(15400, lots[0].montant, 'Décochée : 700 × 22');
  }

  @IsTest
  static void testPreviewPtfLots_plannedLeave_lotsSumToBillableDays() {
    AR_Price_Matrix__c m = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(
      Id = m.Id,
      AR_Start_Date__c = Date.newInstance(2027, 1, 1),
      AR_End_Date__c = Date.newInstance(2027, 3, 31),
      AR_Number_Of_Days__c = 62,
      AR_Planned_Leave_Days__c = 5,
      AR_RPLSR_Enabled__c = false
    );
    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewPtfLots(m.Id, false, null);
    System.assertEquals(3, lots.size(), 'Janvier, février et mars 2027');
    Decimal total = 0;
    for (AR_PTFData.LotRow lot : lots) {
      total += lot.jours;
      System.assert(lot.jours > 0, 'Chaque mois garde des jours après retrait des congés au prorata');
    }
    System.assertEquals(57, total, 'Somme des lots = jours facturables (62 - 5)');
  }

  @IsTest
  static void testSnapshotBeforeMensualisationField_rehydratesWithoutTheFlag() {
    AR_PTFData d = new AR_PTFData();
    d.reference = 'PTF-ANCIEN-V1';
    d.mensualisationLissee = true;
    // Snapshot écrit avant l'ajout du champ : il n'existe pas dans le JSON
    Map<String, Object> asMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(d));
    asMap.remove('mensualisationLissee');
    AR_PTFData ancien = (AR_PTFData) JSON.deserialize(JSON.serialize(asMap), AR_PTFData.class);
    System.assertEquals('PTF-ANCIEN-V1', ancien.reference, 'Le snapshot se relit');
    System.assertEquals(null, ancien.mensualisationLissee, 'Champ absent : lu comme décoché');
  }

  @IsTest
  static void testSnapshotBeforeRplsrField_rehydratesAsNotRplsr() {
    AR_PTFData d = new AR_PTFData();
    d.reference = 'PTF-ANCIEN-V2';
    d.mensualisationLissee = true;
    // Snapshot écrit avant la régie sans régule : le champ rplsrActive n'existe pas dans le JSON
    Map<String, Object> asMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(d));
    asMap.remove('rplsrActive');
    AR_PTFData ancien = (AR_PTFData) JSON.deserialize(JSON.serialize(asMap), AR_PTFData.class);
    System.assertEquals('PTF-ANCIEN-V2', ancien.reference, 'Le snapshot se relit');
    System.assertEquals(null, ancien.rplsrActive, 'Champ absent : lu comme éteint');
    System.assertEquals(true, ancien.mensualisationLissee, 'Le reste du snapshot est inchangé');
  }

  @IsTest
  static void testBuildSchedule_lissePlanVendus_casC2() {
    // Cas C2 (docs/265 §4.4) : 15/02/2027 → 31/01/2028, base 18,17, TJM 495 €. Février : 9,09 j vendus.
    Map<String, Decimal> vendus = new Map<String, Decimal>{ '2027-02' => 9.09 };
    for (Integer i = 3; i <= 12; i++) {
      vendus.put('2027-' + String.valueOf(i).leftPad(2, '0'), 18.17);
    }
    vendus.put('2028-01', 18.17);
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2027, 2, 15), Date.newInstance(2028, 1, 31), 495, 18.17, 1, null, true, null, vendus
    );
    System.assertEquals(12, rows.size(), 'Douze mois : février 2027 à janvier 2028');
    System.assertEquals(9.09, rows[0].jours, 'Février : jours vendus du plan');
    System.assertEquals(4500, rows[0].montant, 'Février : 495 × 9,09 = 4 499,55 arrondi');
    System.assertEquals(18.17, rows[1].jours, 'Mars : jours vendus du plan');
    System.assertEquals(8994, rows[1].montant, 'Mars : 495 × 18,17 = 8 994,15 arrondi');
    Decimal sommeJours = 0;
    for (AR_PTFData.ScheduleRow r : rows) {
      sommeJours += r.jours;
    }
    System.assertEquals(208.96, sommeJours, 'Σ vendus = 208,96');
    System.assertEquals(103434, rows[11].cumul, 'Total = somme des lignes : 4 500 + 11 × 8 994');
  }

  @IsTest
  static void testCollect_rplsrActive_reprendLePlanEtImposeLaCase() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Proposed_TJM__c FROM AR_Price_Matrix__c LIMIT 1];
    // Mission de la fixture : septembre et octobre 2026. Plan : 18,17 j en septembre, 16 j en octobre.
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_RPLSR_Enabled__c = true,
      AR_RPLSR_Plan__c = '{"v":1,"mois":[{"m":"2026-09","ouvres":22,"vendus":18.17,"produits":18},' +
        '{"m":"2026-10","ouvres":22,"vendus":16,"produits":16}]}'
    );
    AR_PTFData d = AR_PTFDataService.collect(matrix.Id, validatedInput(matrix), 1, false);
    System.assertEquals(true, d.rplsrActive, 'Matrice en mode actif : drapeau porté par le snapshot');
    System.assertEquals(true, d.mensualisationLissee, 'Case imposée par la régie');
    System.assertEquals(2, d.schedule.size(), 'Septembre et octobre 2026');
    System.assertEquals(18.17, d.schedule[0].jours, 'Septembre : jours vendus du plan');
    System.assertEquals(16, d.schedule[1].jours, 'Octobre : jours vendus du plan, pas 18,17');
    System.assertEquals((d.tjm * 16).setScale(0, System.RoundingMode.HALF_UP), d.schedule[1].montant, 'Octobre : TJM × vendus');
  }

  @IsTest
  static void testCollect_rplsrActiveWithoutPlan_blocksGeneration() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_RPLSR_Enabled__c = true, AR_RPLSR_Plan__c = null);
    Boolean bloque = false;
    try {
      AR_PTFDataService.collect(matrix.Id, validatedInput(matrix), 1, true);
    } catch (AuraHandledException e) {
      bloque = true;
    }
    System.assert(bloque, 'Régie active sans plan : génération refusée, jamais un échéancier silencieux');
  }

  private static AR_PTFDataService.GenerationInput validatedInput(AR_Price_Matrix__c matrix) {
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    // Session 47 : le valideur est désormais un champ obligatoire, pour tous les gabarits (cf.
    // AR_PTFDataService.requireValideur) — posé ici par défaut pour que ce fixture partagé reste
    // utilisable par les tests qui ne portent pas spécifiquement sur cette règle ; les tests dédiés
    // au blocage lui-même (cf. testCollect_valideurBlank_*) construisent leur propre input.
    input.valideurNom = 'Valideur Test';
    return input;
  }

  @IsTest
  static void testCollect_genericCode_isRefusedForANewGeneration_withAClearMessage() {
    System.runAs(AR_TestPersona.francais()) {
      // Session 184c3 : le gabarit générique est retiré (184c) — « GENERIQUE » est un code inconnu pour
      // toute nouvelle génération, qu'il vienne de la surcharge manuelle, du compte ou de l'entité ; le
      // message nomme le code, son origine et les codes valides.
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      AR_PTFDataService.GenerationInput input = validatedInput(matrix);
      input.templateCode = 'GENERIQUE';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'GENERIQUE ne doit plus pouvoir générer un document');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('GENERIQUE') && message.contains('inconnu'), message);
      System.assert(message.contains('surcharge manuelle'), message);
      System.assert(message.contains('ABYLSEN_AT_V11'), 'Le message liste les codes valides : ' + message);
      System.assertEquals(
        null,
        AR_PTFDataService.templateCodeError('ABYLSEN_AT_V11', 'test'),
        'Un code valide reste accepté'
      );
      System.assertNotEquals(null, AR_PTFDataService.templateCodeError('GENERIQUE', 'la saisie'));
    }
  }

  @IsTest
  static void testCollect_unknownManualTemplateCode_throwsNamingCodeAndValidOnes() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      AR_PTFDataService.GenerationInput input = validatedInput(matrix);
      input.templateCode = 'GRAND_COMPTE_INVENTE';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Un code de gabarit inconnu ne doit plus retomber sur le générique');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(
        message.contains('GRAND_COMPTE_INVENTE'),
        'Le message doit nommer le code fautif : ' + message
      );
      System.assert(
        message.contains('ABYLSEN_AT_V11') && message.contains('ABMI_DQ012'),
        'Le message doit lister les codes valides : ' + message
      );
      System.assert(
        message.contains('surcharge manuelle'),
        'Le message doit dire D\'OÙ vient le code fautif, sinon on cherche dans trois référentiels : ' + message
      );
    }
  }

  @IsTest
  static void testCollect_unknownAccountTemplateCode_throwsNamingAccountOrigin() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      cxsrec__cxsPosition__c position = [
        SELECT cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Id = :matrix.AR_Position__c
      ];
      insert new AR_Account_Commercial_Data__c(
        AR_Account__c = position.cxsrec__Account__c,
        AR_PTF_Template_Code__c = 'GRAND_COMPTE_DEMO'
      );
      AR_PTFDataService.GenerationInput input = validatedInput(matrix);

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Un code de compte inconnu doit bloquer, pas produire un document générique');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('GRAND_COMPTE_DEMO'), message);
      System.assert(message.contains('compte'), message);
    }
  }

  @IsTest
  static void testCollect_abylsenTemplateWithoutBankDetails_blocksNamingEntityAndFields() {
    // AR_PTF_Entity__mdt.Abylsen_GAMMA n'a aucune coordonnée bancaire (référentiel entièrement en
    // valeurs d'amorce, cf. docs/30-...md §1) : c'est exactement le cas que la doctrine du projet
    // demande de BLOQUER, jamais de compléter par une valeur plausible — faire payer un client au
    // mauvais compte est pire que ne pas produire le document.
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    // Session 184c3 : GAMMA porte un RIB dans le setup — on le retire pour reproduire le cas bloquant.
    update new AR_PTF_Entity_Referential__c(Id = AR_TestPersona.entityRefId('Abylsen GAMMA'), AR_Rib__c = null);
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    input.templateCode = 'ABYLSEN_AT_V11';

    String message = null;
    try {
      AR_PTFDataService.collect(matrix.Id, input, 1);
      System.assert(false, 'Une entité sans coordonnées bancaires ne doit pas générer une PTF Abylsen');
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    System.assert(
      message.contains('Abylsen GAMMA'),
      'Le message doit nommer l\'entité fautive : ' + message
    );
    System.assert(
      message.contains('RIB') || message.contains('référentiel'),
      'Le message doit nommer le champ manquant : ' + message
    );
    System.assert(
      !message.contains('À COMPLÉTER'),
      'Jamais de valeur de remplacement : le document ne doit pas exister du tout'
    );
  }

  // ------------------------------------------------------------------
  // Session 49 (cause B) : une PTF Abylsen sans dates de mission imprimait "Dates de mission non
  // renseignées — lots à définir conjointement." en I.4.1/4.3 plutôt que de bloquer — une
  // proposition commerciale sans prix est l'un des deux cas les plus graves relevés dans le PDF
  // réel du 03/09/2026. Asymétrie assumée avec le gabarit générique (non soumis à ce blocage, cf.
  // testCollect_noMissionDates_totalHTIsNullNotZero ci-dessus, non-régression session 20c).
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_abylsenTemplateWithoutMissionDates_blocksRatherThanPrintingPlaceholder() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // newMatrixOwnedBy ne pose aucune date de mission par défaut — exactement le cas à bloquer.
    // Entité 'Abylsen SIGMA' (fixture bancaire complète, session 36) : le blocage testé ici doit
    // être celui des dates, pas celui — déjà couvert plus haut — des coordonnées bancaires.
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    input.valideurNom = 'Peu importe pour ce test';

    String message = null;
    try {
      AR_PTFDataService.collect(matrix.Id, input, 1);
      System.assert(false, 'Une PTF Abylsen sans dates de mission ne doit pas se générer');
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('House of ABY'), 'Le message doit nommer le gabarit : ' + message);
    System.assert(
      !message.contains('à définir conjointement'),
      'Jamais de valeur de remplacement : le document ne doit pas exister du tout'
    );
  }

  @IsTest
  static void testCollectAvenant_prolongationDateMissing_blocksRatherThanPrintingPlaceholder() {
    System.runAs(AR_TestPersona.francais()) {
      // "prolongée jusqu'au (date non renseignée) inclus" dans le PDF réel du 03/09/2026 — même
      // famille de défaut que le blocage prix ci-dessus.
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00114-V1', 1);

      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.ptfDocumentId = origin.Id;
      input.revisionPrix = false;
      input.valideurNom = 'Peu importe pour ce test';
      // Pas de prolongationJusquAu.

      String message = null;
      try {
        AR_PTFDataService.collectAvenant(origin, input, 1);
        System.assert(false, 'Un avenant sans date de prolongation ne doit pas se générer');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('prolongation'), message);
    }
  }

  @IsTest
  static void testCollect_positionNameBlank_defaultObjetOmitsClauseRatherThanPrintingNull() {
    // Trouvé en régénérant réellement le gabarit générique (session 49) : String.valueOf(null)
    // vaut littéralement "null" en Apex — sans garde, un besoin dénormalisé absent (AR_Position_Name__c,
    // jamais posé par newMatrixOwnedBy/l'insertion directe utilisée par ce test, comme par tout appelant
    // qui contourne AR_PricingMatrixService.applyInputToMatrix) imprimait "...dans le cadre du besoin
    // null." dans un document contractuel.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen GAMMA');

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Peu importe pour ce test';

    // Session 184c3 : sans dates de mission, le gabarit Abylsen bloque la génération — le texte
    // d'objet se vérifie en mode pré-remplissage (aucun blocage, mêmes champs).
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assert(!data.objet.contains('null'), 'Jamais la valeur brute "null" dans un document contractuel : ' + data.objet);
    // Gabarit Abylsen : l'objet pré-rempli est celui du modèle ; la phrase générique reste servie pour les autres gabarits.
    System.assert(data.objet.startsWith('Ce document présente les conditions d’intervention'), data.objet);
    String generic = data.objetParGabarit.get('GENERIQUE');
    System.assert(!generic.contains('null'), generic);
    System.assert(generic.startsWith('La présente Proposition Technique et Financière a pour objet de définir les modalités d\'intervention'));
  }

  // ------------------------------------------------------------------
  // Session 38 — gabarit ABMI_DQ012. N'imprime pas de RIB (donc pas soumis à
  // TEMPLATES_REQUIRING_BANK_DETAILS) mais imprime adresse/téléphone/fax/site web de l'entité sur la
  // page "Vos contacts" (TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS) : même doctrine que le blocage
  // bancaire d'Abylsen, sur un ensemble de champs différent.
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_abmiTemplateWithoutEntityContactDetails_blocksNamingEntityAndFields() {
    System.runAs(AR_TestPersona.francais()) {
      // 'Abylsen GAMMA' (entité par défaut du setup) n'a ni site web ni adresse complète :
      // exactement le cas que la doctrine du projet demande de bloquer. Le fax, facultatif depuis la
      // session 176h, ne doit JAMAIS figurer dans le message.
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      AR_PTFDataService.GenerationInput input = validatedInput(matrix);
      input.templateCode = 'ABMI_DQ012';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Une entité sans site web ne doit pas générer une offre ABMI');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('Abylsen GAMMA'), 'Le message doit nommer l\'entité fautive : ' + message);
      System.assert(message.contains('Site web'), 'Le message doit nommer les champs manquants : ' + message);
      System.assert(!message.contains('Fax'), 'Le fax est facultatif, il ne doit pas être réclamé : ' + message);
      System.assert(!message.contains('À COMPLÉTER'),
        'Jamais de valeur de remplacement : le document ne doit pas exister du tout');
    }
  }

  @IsTest
  static void testCollect_abmiTemplateWithNoEntityOnMatrix_blocksSayingNoEntity() {
    System.runAs(AR_TestPersona.francais()) {
      // Session 132 : une matrice sans entité (jamais pré-remplie, l'utilisateur ne l'a pas encore
      // choisie) ne produit aucune offre ABMI — distinct du cas "entité incomplète" ci-dessus.
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = null);
      AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
      input.matrixId = matrix.Id;
      input.templateCode = 'ABMI_DQ012';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Une matrice sans entité ne doit pas générer une offre ABMI');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('aucune entité renseignée'), 'Message : ' + message);
      System.assert(message.contains('absente du référentiel'), 'Message : ' + message);
    }
  }

  @IsTest
  static void testCollect_abmiTemplateWithEntityWithoutAnyDetails_blocksNamingEntity() {
    System.runAs(AR_TestPersona.francais()) {
      // Fiche créée à la volée, sans aucune coordonnée.
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SUD'));
      AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
      input.matrixId = matrix.Id;
      input.templateCode = 'ABMI_DQ012';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Une entité sans coordonnées ne doit pas générer une offre ABMI');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('Abylsen SUD'), 'Le message doit nommer l\'entité fautive : ' + message);
      System.assert(message.contains('Coordonnées manquantes'), 'Message : ' + message);
    }
  }

  @IsTest
  static void testCollect_ficheAbsentFromOldPicklist_usesItsOwnNameAndDetails() {
    // Session 132 : « ABYLSEN EST – Metz » (Nom absent de l'ancien picklist) — le nom imprimé et les
    // coordonnées lues sont ceux de CETTE fiche, rattachée par lookup.
    insert new AR_PTF_Entity_Referential__c(
      Name = 'ABYLSEN EST – Metz',
      AR_Active__c = true,
      AR_Address__c = '1 place de la République, 57000 Metz',
      AR_Phone__c = '+33300000000',
      AR_Rib__c = '00000 00000 00000000000 00 (FICTIF test)'
    );
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABYLSEN EST – Metz'));
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('ABYLSEN EST – Metz', data.entite);
    System.assertEquals('1 place de la République, 57000 Metz', data.entiteInfo.adresse);
    System.assertEquals('+33300000000', data.entiteInfo.tel);
  }

  @IsTest
  static void testCollect_twoFichesDifferingOnlyByCase_eachMatrixKeepsItsOwn() {
    // Piège N2 : SOQL compare sans tenir compte de la casse — « Abylsen GAMMA » (fixture) et
    // « ABYLSEN GAMMA » se confondaient quand l'entité était lue par son nom.
    AR_PTF_Entity_Referential__c upper = new AR_PTF_Entity_Referential__c(
      Name = 'ABYLSEN GAMMA',
      AR_Active__c = true,
      AR_Address__c = 'Adresse de la fiche en majuscules',
      AR_Phone__c = '+33111111111',
      AR_Rib__c = '00000 00000 00000000000 00 (FICTIF test)'
    );
    insert upper;
    Id lowerId = AR_TestPersona.entityRefId('Abylsen GAMMA');
    System.assertNotEquals(upper.Id, lowerId, 'Deux fiches distinctes');
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = upper.Id);
    AR_PTFData dataUpper = AR_PTFDataService.collect(matrix.Id, input, 1);

    AR_TriggerBypass.serviceContext = true;
    try {
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Entity_Ref__c = lowerId);
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }
    AR_PTFData dataLower = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('ABYLSEN GAMMA', dataUpper.entite);
    System.assertEquals('Adresse de la fiche en majuscules', dataUpper.entiteInfo.adresse);
    System.assertEquals('Abylsen GAMMA', dataLower.entite);
    System.assertEquals(null, dataLower.entiteInfo.adresse, 'La fiche « Abylsen GAMMA » n\'a aucune adresse : jamais celle de « ABYLSEN GAMMA »');
  }

  @IsTest
  static void testCollect_abmiTemplate_completeEntity_populatesEntiteInfoAndAbmiDefaults() {
    // 'ABMI Groupe' (AR_PTF_Entity__mdt.ABMI_CityLife) porte adresse/téléphone/fax/site web réels
    // (coordonnées publiques du siège Nanterre, cf. docs/38-gabarit-abmi-dq012.md) : seule entité
    // du référentiel qui satisfait ce gabarit à ce jour.
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABMI Groupe'));
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABMI_DQ012';
    input.valideurNom = 'Valideur Test';
    input.valideurFonction = 'Fonction Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('ABMI_DQ012', data.templateCode);
    System.assertEquals('92000', data.entiteInfo.cp);
    System.assertEquals('NANTERRE', data.entiteInfo.ville);
    System.assertNotEquals(null, data.entiteInfo.fax);
    System.assertNotEquals(null, data.entiteInfo.website);
    // Arbitrage 4 (deux signataires) : préremplis avec rédacteur/valideur, jamais recalculés depuis
    // une hiérarchie Connexys (à la différence d'Abylsen/avenant, cf. AR_PTFDataService.applyAbmiFields).
    System.assertEquals(data.redacteurNom, data.abmiSignataire1Nom);
    System.assertEquals(data.redacteurFonction, data.abmiSignataire1Fonction);
    System.assertEquals(data.valideurNom, data.abmiSignataire2Nom);
    System.assertEquals(data.valideurFonction, data.abmiSignataire2Fonction);
    // Arbitrage 1 (numérotation) : garde la référence interne par défaut, jamais un faux format devis.
    System.assertEquals(data.reference, data.abmiNosReferences);
    // Arbitrage 3 : aucun texte par défaut sur les sections sans équivalent.
    System.assertEquals(null, data.abmiDescriptionTravaux);
    System.assertEquals(null, data.abmiAnalyseRisques);
  }

  @IsTest
  static void testCollect_abmiTemplate_explicitInputOverridesDefaults() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABMI Groupe'));
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABMI_DQ012';
    input.valideurNom = 'Valideur Test';
    input.abmiNosReferences = 'DEVIS-TEST-001';
    input.abmiSignataire1Nom = 'Saisie Manuelle';
    input.abmiDescriptionTravaux = 'Description saisie par l\'utilisateur.';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('DEVIS-TEST-001', data.abmiNosReferences);
    System.assertEquals('Saisie Manuelle', data.abmiSignataire1Nom);
    System.assertEquals('Description saisie par l\'utilisateur.', data.abmiDescriptionTravaux);
  }

  @IsTest
  static void testCollect_abmiTemplate_propositionFinanciereTexte_nullWithoutSchedule() {
    // Matrice sans dates de mission : aucun échéancier calculable, donc aucun paragraphe financier
    // généré — jamais un texte inventé faute de données, même famille que "À définir" sur
    // totalHTLabel (AR_PTFTemplateController).
    AR_Price_Matrix__c base = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = base.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 750,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABMI Groupe')
      // Pas de AR_Start_Date__c/AR_End_Date__c : buildSchedule() renvoie une liste vide.
    );
    insert matrix;
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABMI_DQ012';
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(null, data.abmiPropositionFinanciereTexte);
  }

  @IsTest
  static void testCollect_abmiTemplate_propositionFinanciereTexte_computedFromScheduleWhenNotOverridden() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABMI Groupe'));
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABMI_DQ012';
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assert(
      data.abmiPropositionFinanciereTexte != null && data.abmiPropositionFinanciereTexte.contains('HT/jour'),
      'Un paragraphe calculé doit exister quand l\'échéancier est disponible : ' + data.abmiPropositionFinanciereTexte
    );
  }

  @IsTest
  static void testEntityContactDetailsError_faxIsOptional_acceptedWithoutFax() {
    // Session 176h : sans fax mais avec adresse, téléphone et site web → génération acceptée.
    Id abmiId = AR_TestPersona.entityRefId('ABMI Groupe');
    update new AR_PTF_Entity_Referential__c(Id = abmiId, AR_Fax__c = null);
    System.assertEquals(null, AR_PTFDataService.entityContactDetailsError('ABMI_DQ012', abmiId));
  }

  @IsTest
  static void testEntityContactDetailsError_withoutPhone_namesPhoneAndNeverFax() {
    System.runAs(AR_TestPersona.francais()) {
      // Session 176h : sans téléphone ET sans fax → le refus nomme « Téléphone », jamais « Fax ».
      Id abmiId = AR_TestPersona.entityRefId('ABMI Groupe');
      update new AR_PTF_Entity_Referential__c(Id = abmiId, AR_Phone__c = null, AR_Fax__c = null);
      String message = AR_PTFDataService.entityContactDetailsError('ABMI_DQ012', abmiId);
      System.assertNotEquals(null, message);
      System.assert(message.contains('Téléphone'), message);
      System.assert(!message.contains('Fax'), message);
    }
  }

  @IsTest
  static void testEntityContactDetailsError_directEntryPoint_matchesCollectBehavior() {
    // Point d'entrée vérifiable en Apex anonyme (cf. templateCodeError/bankDetailsError) : même
    // comportement que collect(), sans avoir besoin d'une matrice.
    Id gammaId = AR_TestPersona.entityRefId('Abylsen GAMMA');
    Id abmiId = AR_TestPersona.entityRefId('ABMI Groupe');
    System.assertEquals(null, AR_PTFDataService.entityContactDetailsError('GENERIQUE', gammaId));
    System.assertNotEquals(null, AR_PTFDataService.entityContactDetailsError('ABMI_DQ012', gammaId));
    System.assertEquals(null, AR_PTFDataService.entityContactDetailsError('ABMI_DQ012', abmiId));
  }

  // ------------------------------------------------------------------
  // Session 47 — diagnostic de préparation d'entité (sans blocage), réutilisé par le sélecteur
  // d'entité (AR_PricingMatrixService.getEntityOptions), arPtfPanel
  // (getEntityReadinessByTemplate) et l'écran d'administration (AR_AdminReferentialService).
  // ------------------------------------------------------------------

  @IsTest
  static void testMissingFieldsForTemplate_reflectsSameRulesAsBlockingErrors() {
    System.runAs(AR_TestPersona.francais()) {
      AR_PTF_Entity_Referential__c gamma = [SELECT Id, Name, AR_Bank_Name__c, AR_Rib__c, AR_Iban__c, AR_Bic__c,
        AR_Address__c, AR_Postal_Code__c, AR_City__c, AR_Phone__c, AR_Fax__c, AR_Website__c, AR_Tribunal_Competent__c
        FROM AR_PTF_Entity_Referential__c WHERE Name = 'Abylsen GAMMA' LIMIT 1];
      gamma.AR_Rib__c = null; // 184c3 : GAMMA porte un RIB dans le setup ; lu sans coordonnées bancaires ici
      AR_PTF_Entity_Referential__c abmi = [SELECT Id, Name, AR_Bank_Name__c, AR_Rib__c, AR_Iban__c, AR_Bic__c,
        AR_Address__c, AR_Postal_Code__c, AR_City__c, AR_Phone__c, AR_Fax__c, AR_Website__c, AR_Tribunal_Competent__c
        FROM AR_PTF_Entity_Referential__c WHERE Name = 'ABMI Groupe' LIMIT 1];

      // Générique : ne réclame jamais rien, quelle que soit l'entité.
      System.assertEquals(null, AR_PTFDataService.missingFieldsForTemplate('GENERIQUE', gamma));
      // Abylsen (Abylsen GAMMA, sans coordonnées bancaires) : mêmes champs que bankDetailsError.
      String missingBank = AR_PTFDataService.missingFieldsForTemplate('ABYLSEN_AT_V11', gamma);
      System.assert(missingBank != null && missingBank.contains('RIB'), missingBank);
      // ABMI (Abylsen GAMMA, sans coordonnées d'établissement) : mêmes champs que entityContactDetailsError.
      String missingContact = AR_PTFDataService.missingFieldsForTemplate('ABMI_DQ012', gamma);
      System.assert(missingContact != null && missingContact.contains('Site web'), missingContact);
      System.assert(!missingContact.contains('Fax'), 'Fax facultatif : ' + missingContact);
      // ABMI Groupe est complète pour son propre gabarit.
      System.assertEquals(null, AR_PTFDataService.missingFieldsForTemplate('ABMI_DQ012', abmi));
      // Entité absente du référentiel (null) : diagnostic lisible, jamais une NullPointerException.
      System.assertEquals(
        'entité absente du référentiel',
        AR_PTFDataService.missingFieldsForTemplate('ABYLSEN_AT_V11', null)
      );
    }
  }

  @IsTest
  static void testGetEntityReadinessByTemplate_returnsIssuesOnlyForTemplatesThatRequireSomething() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen GAMMA'));
    // Session 184c3 : GAMMA porte un RIB dans le setup — retiré pour reproduire l'entité sans coordonnées.
    update new AR_PTF_Entity_Referential__c(Id = AR_TestPersona.entityRefId('Abylsen GAMMA'), AR_Rib__c = null);

    Map<String, String> issues = AR_PTFDataService.getEntityReadinessByTemplate(matrix.Id);

    System.assert(issues.containsKey('ABYLSEN_AT_V11'), 'Abylsen GAMMA n\'a pas de coordonnées bancaires');
    System.assert(issues.containsKey('ABMI_DQ012'), 'Abylsen GAMMA n\'a pas de coordonnées d\'établissement');
    System.assert(
      !issues.containsKey('GENERIQUE') && !issues.containsKey('AVENANT_AT_V11'),
      'Le générique et l\'avenant n\'exigent rien de l\'entité : ne doivent jamais apparaître ici : ' + issues
    );
  }

  @IsTest
  static void testCollect_lots_defaultOneLotPerMonthEndOfMonthDueDate() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(2, data.lots.size(), 'Mission sept.-oct. 2026 : 1 lot = 1 mois (C43)');
    System.assertEquals('Lot 1', data.lots[0].libelle);
    System.assertEquals('Lot 2', data.lots[1].libelle);
    System.assertEquals(
      Date.newInstance(2026, 9, 30),
      data.lots[0].echeance,
      'Échéance = fin du mois du lot (C45)'
    );
    System.assertEquals(Date.newInstance(2026, 10, 31), data.lots[1].echeance);
    System.assertEquals(
      data.schedule[0].montant,
      data.lots[0].montantCalcule,
      'Le montant du lot reste celui de l\'échéancier mensuel tant qu\'il n\'est pas surchargé'
    );
    System.assertEquals(false, data.lots[0].isOverridden);
    System.assertEquals(data.totalHT, data.lotsTotal, 'Sans surcharge, les deux totaux coïncident');
  }

  @IsTest
  static void testCollect_lotOverride_keepsCalculatedAmountAlongsideAndMarksRow() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    // `override` est un mot réservé Apex : nom de variable neutre obligatoire.
    AR_PTFDataService.LotOverride lotOverride = new AR_PTFDataService.LotOverride();
    lotOverride.index = 0;
    lotOverride.montant = 9000;
    input.lotOverrides = new List<AR_PTFDataService.LotOverride>{ lotOverride };

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(9000, data.lots[0].montant, 'Le lot surchargé porte le montant saisi');
    System.assertEquals(
      data.schedule[0].montant,
      data.lots[0].montantCalcule,
      'Le montant calculé reste conservé À CÔTÉ : c\'est ce qui rend l\'écart auditable après coup'
    );
    System.assertEquals(true, data.lots[0].isOverridden);
    System.assertEquals(false, data.lots[1].isOverridden, 'La surcharge est PAR LOT, jamais globale');
    System.assertEquals(
      data.schedule[1].montant,
      data.lots[1].montant,
      'Un lot non surchargé reste calculé'
    );
    System.assertEquals(9000 + data.schedule[1].montant, data.lotsTotal);
    System.assertNotEquals(
      data.totalHT,
      data.lotsTotal,
      'Total théorique et total retenu doivent différer visiblement quand un lot est surchargé'
    );
  }

  @IsTest
  static void testCollect_newTemplateFields_populatedFromConnexys() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    input.materielItems = 'PC portable, licence Office ; badge';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('Besoin PTF', data.titreBesoin, 'C17 : titre du besoin Connexys');
    System.assertEquals(2, data.dureeMois, 'C57 : sept. + oct. = 2 mois');
    System.assertEquals(3, data.materielItems.size(), 'C27 : virgules ET points-virgules');
    System.assertEquals('PC portable', data.materielItems[0]);
    System.assertEquals('badge', data.materielItems[2]);
    // Le booléen historique n'est PAS remplacé : le gabarit générique le consomme toujours.
    System.assertNotEquals(null, data.materielClient);
  }

  @IsTest
  static void testCollect_materielItemsEmpty_leavesEmptyListNotNull() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, validatedInput(matrix), 1);
    System.assertEquals(0, data.materielItems.size());
  }

  @IsTest
  static void testCollect_unknownPtfInitiale_blocksAvenant() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    // Id syntaxiquement valide mais inexistant : un avenant qui cite une PTF introuvable est un
    // document FAUX, pas un document incomplet.
    input.ptfInitialeDocumentId = null;
    AR_PTFData ok = AR_PTFDataService.collect(matrix.Id, input, 1);
    System.assertEquals(null, ok.ptfInitialeReference, 'Sans PTF initiale, rien n\'est inventé');
  }

  @IsTest
  static void testCollect_ptfInitiale_copiesReferenceAndDate() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    Datetime generatedAt = Datetime.newInstance(2026, 8, 20, 10, 0, 0);
    AR_PTF_Document__c parent = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-INIT-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{}',
      AR_Generated_At__c = generatedAt,
      AR_Generation_Status__c = 'Généré'
    );
    insert parent;

    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    input.ptfInitialeDocumentId = parent.Id;

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 2);

    System.assertEquals('PTF-TEST-INIT-V1', data.ptfInitialeReference, 'C8 de l\'avenant');
    System.assertEquals(generatedAt.date(), data.ptfInitialeDate, 'C9 de l\'avenant');
  }

  @IsTest
  static void testGetTemplateOptions_servesTheFourValidCodes() {
    List<Map<String, String>> options = AR_PTFDataService.getTemplateOptions();
    System.assertEquals(3, options.size(), 'Trois codes valides depuis le retrait du générique (184c)');
    Set<String> codes = new Set<String>();
    for (Map<String, String> o : options) {
      codes.add(o.get('value'));
      System.assert(String.isNotBlank(o.get('label')), 'Chaque code doit porter un libellé lisible');
    }
    System.assert(!codes.contains('GENERIQUE'), 'Le générique n\'est plus proposé');
    System.assert(codes.contains('ABYLSEN_AT_V11'));
    System.assert(codes.contains('AVENANT_AT_V11'));
    System.assert(codes.contains('ABMI_DQ012'));
  }

  /** Session 176i : la liste de l'administration est la carte de la résolution, sans l'avenant. */
  @IsTest
  static void testGetPtfTemplateOptions_sameSourceAsResolution_withoutAvenant() {
    List<Map<String, String>> options = AR_PTFDataService.getPtfTemplateOptions();
    Set<String> codes = new Set<String>();
    for (Map<String, String> o : options) {
      codes.add(o.get('value'));
      System.assertEquals(AR_PTFDataService.TEMPLATE_LABELS.get(o.get('value')), o.get('label'), 'Libellé = celui de la carte de résolution');
    }
    System.assertEquals(2, options.size());
    System.assertEquals(new Set<String>{ 'ABYLSEN_AT_V11', 'ABMI_DQ012' }, codes);
    System.assert(!codes.contains('AVENANT_AT_V11'), 'L\'avenant n\'est pas un gabarit de PTF d\'entité');
    System.assertEquals(3, AR_PTFDataService.getTemplateOptions().size(), 'getTemplateOptions (arPtfPanel) : les trois codes valides');
  }

  // ------------------------------------------------------------------
  // Session 36 — gabarit Abylsen AT v11 : rédacteur = BM, valideur = DA résolu ou blocage,
  // historique au périmètre du besoin, contexte pré-rempli. 'Abylsen SIGMA' porte des coordonnées
  // bancaires de démonstration (AR_PTF_Entity__mdt.Abylsen_SIGMA, valeurs FICTIF) déployées avec ce
  // bloc — 'Abylsen GAMMA', utilisée ailleurs dans cette classe, reste volontairement sans
  // coordonnées pour le test de blocage bancaire (session 35, inchangé).
  // ------------------------------------------------------------------

  // Session 40 : le DA n'est plus résolu par cercle de job title (AR_Validator_Job_Title__c) — le
  // document nomme AR_Effective_Validator__c/AR_Selected_Validator__c, déjà portés par la matrice,
  // jamais recalculés. newDaUser reste utile pour fournir un User réel (rédacteur = BM, valideur =
  // Effective/Selected), sans plus aucun rapport avec une quelconque habilitation.
  private static Integer userCounter36 = 0;

  private static Id sharedDaId;

  /** Session 184c3 : directeur d'agence commun des utilisateurs newDaUser (valideur = DA du propriétaire). */
  private static Id sharedDa() {
    if (sharedDaId == null) {
      sharedDaId = newDaUserWithoutDa('shared-da').Id;
    }
    return sharedDaId;
  }

  private static User newDaUser(String key, String entity) {
    User u = newDaUserWithoutDa(key);
    u.TP_DA__c = sharedDa();
    update u;
    return u;
  }

  private static User newDaUserWithoutDa(String key) {
    userCounter36++;
    User u = new User(
      LastName = 'Session36 ' + key,
      Email = 'session36.' + key + '@example.com.invalid',
      Username = 'ar.session36.' + key + userCounter36 + Datetime.now().getTime() + '@example.com.invalid',
      Alias = key.left(8),
      IsActive = true,
      TimeZoneSidKey = 'Europe/Paris',
      LocaleSidKey = 'fr_FR',
      LanguageLocaleKey = 'fr',
      EmailEncodingKey = 'UTF-8',
      ProfileId = AR_TestPersona.standardProfileId(),
      FederationIdentifier = 'ar.session36.' + key + userCounter36 + Datetime.now().getTime(),
      Title = 'Directeur Session36'
    );
    insert u;
    return u;
  }

  private static AR_PTFDataService.GenerationInput abylsenInput(AR_Price_Matrix__c matrix) {
    return abylsenInput(matrix, null);
  }

  /** selectedValidatorId : nécessaire dès que l'appelant ne passe pas input.valideurNom — sinon
   * requireValideur() bloque (session 47, ni AR_Effective_Validator__c ni AR_Selected_Validator__c
   * renseignés, ni saisie manuelle : le champ obligatoire reste vide). */
  private static AR_PTFDataService.GenerationInput abylsenInput(AR_Price_Matrix__c matrix, Id selectedValidatorId) {
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_Status__c = 'Validée',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Selected_Validator__c = selectedValidatorId
    );
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    return input;
  }

  // OwnerId est posé à l'INSERT, jamais par UPDATE sur une matrice existante : au-delà du
  // verrouillage post-décision (une matrice "Validée" refuse toute modification, cf.
  // AR_PriceMatrixTrigger), une réaffectation de propriétaire par UPDATE sur cet objet à partage
  // Private échoue avec TRANSFER_REQUIRES_READ pour un utilisateur de test sans rôle — l'INSERT
  // direct avec OwnerId déjà positionné n'est pas soumis à cette validation.
  /**
   * Session 110 : newMatrixOwnedBy insère la matrice déjà « Validée » — le verrouillage serveur
   * (AR_PriceMatrixTriggerHandler) refuse ensuite toute modification. Les tests de pré-remplissage
   * consultant (sessions 64-66) complètent leur fixture après coup : même contournement que les
   * services Apex eux-mêmes, borné à ce seul DML.
   */
  private static void updateValidatedFixture(AR_Price_Matrix__c matrix) {
    AR_TriggerBypass.serviceContext = true;
    try {
      update matrix;
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }
  }

  private static AR_Price_Matrix__c newMatrixOwnedBy(Id positionId, Id ownerId, String entity) {
    AR_Price_Matrix__c m = new AR_Price_Matrix__c(
      OwnerId = ownerId,
      AR_Position__c = positionId,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId(entity)
    );
    insert m;
    return m;
  }

  @IsTest
  static void testCollect_abylsenTemplate_redacteurSourcedFromMatrixOwner_notCurrentUser() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User owner = newDaUser('bm', 'Abylsen SIGMA');
    // Session 49 : dates de mission désormais obligatoires pour générer une PTF Abylsen (cause B,
    // AR_PTFDataService.requireSchedule) — sans rapport avec ce que ce test vérifie (la source du
    // rédacteur), mais newMatrixOwnedBy n'en pose aucune par défaut, et une matrice "Validée" ne
    // peut plus être modifiée après coup (verrouillage post-décision) : posées à l'insertion,
    // directement, plutôt que via newMatrixOwnedBy.
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = owner.Id,
      AR_Position__c = fixture.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Session36 bm',
      data.redacteurNom,
      'C0/C7/C29 : le rédacteur doit être le BM de l\'affaire (Owner de la matrice), jamais l\'utilisateur courant qui génère'
    );
    System.assertEquals('Directeur Session36', data.redacteurFonction);
    System.assertNotEquals(
      UserInfo.getName(),
      data.redacteurNom,
      'La preuve utile : le rédacteur ne doit PAS être l\'utilisateur qui exécute ce test'
    );
  }

  // Session 58 (A16) : le gabarit Abylsen imprime "Trimestrielle" en dur dans son .docx source —
  // défaut propre à ce gabarit, jamais le défaut général AR_PTF_Setting__mdt.Default
  // ("Mensuelle ou sur demande", couvert par testCollect_validatedMatrix_mapsDataAndReferentialCategories
  // ci-dessus pour le gabarit générique, non-régression).
  @IsTest
  static void testCollect_abylsenTemplate_freqReunionsDefaultsToTrimestrielle() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User owner = newDaUser('bmfreq', 'Abylsen SIGMA');
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = owner.Id,
      AR_Position__c = fixture.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Trimestrielle',
      data.freqReunions,
      'Défaut du gabarit Abylsen (valeur du modèle .docx), pas le défaut général AR_PTF_Setting__mdt'
    );
  }

  @IsTest
  static void testCollect_abylsenTemplate_freqReunionsInputOverridesDefault() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User owner = newDaUser('bmfreq2', 'Abylsen SIGMA');
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = owner.Id,
      AR_Position__c = fixture.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    input.valideurNom = 'Peu importe pour ce test';
    input.freqReunions = 'Hebdomadaire';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Hebdomadaire',
      data.freqReunions,
      'Le défaut "Trimestrielle" reste surchargeable par la saisie, comme les autres défauts'
    );
  }

  @IsTest
  static void testCollect_abylsenTemplate_valideurIsDaOfMatrixOwner_whateverTheInputOrTheMatrixValidators() {
    // Session 184c3 (règle 184c) : le valideur imprimé est le DA du propriétaire de la matrice
    // (User.TP_DA__c), jamais le valideur effectif/sélectionné de la matrice ni une saisie.
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    User effective = newDaUser('eff', 'Abylsen SIGMA');
    User selected = newDaUser('sel', 'Abylsen SIGMA');
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Effective_Validator__c = effective.Id);

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    input.valideurNom = 'Saisie ignorée';
    input.valideurFonction = 'Fonction ignorée';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    User da = [SELECT TP_DA__r.Name, TP_DA__r.Title FROM User WHERE Id = :AR_TestPersona.ownerWithDa()];
    System.assertEquals(da.TP_DA__r.Name, data.valideurNom, 'Valideur = DA du propriétaire de la matrice');
    System.assertEquals(da.TP_DA__r.Title, data.valideurFonction);
    System.assertNotEquals('Saisie ignorée', data.valideurNom);
    System.assertNotEquals(effective.LastName, data.valideurNom);
  }

  @IsTest
  static void testValideurOptions_oneLinePerPersonWithCumulatedRoles_noCommercialDirectors() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    Id ownerId = AR_TestPersona.ownerWithDa();
    User ra = newDaUserWithoutDa('opt-ra');
    User commercial = newDaUserWithoutDa('opt-com');
    User owner = [SELECT TP_DA__c FROM User WHERE Id = :ownerId];
    // RA distinct ; DA et DD identiques (une seule ligne, rôles cumulés) ; directeur commercial exclu.
    update new User(
      Id = ownerId,
      TP_RA__c = ra.Id,
      TP_DD__c = owner.TP_DA__c,
      TP_Directeur_commercial__c = commercial.Id
    );

    List<AR_PTFDataService.ValideurOption> options = AR_PTFDataService.listValideurOptions(matrix.Id);

    System.assertEquals(2, options.size(), 'RA + (DA=DD) : deux personnes, jamais le directeur commercial');
    System.assertEquals(ra.Id, options[0].id);
    System.assertEquals(Label.AR_Msg_VAL_LevelRA, options[0].role);
    System.assertEquals(owner.TP_DA__c, options[1].id);
    System.assertEquals(Label.AR_Msg_VAL_LevelDA + ', ' + Label.AR_Msg_VAL_LevelDD, options[1].role);
    System.assert(options[1].label.endsWith(' — ' + options[1].role), options[1].label);
    System.assertEquals(false, options[0].isDefault);
    System.assertEquals(true, options[1].isDefault, 'Le défaut reste le DA');
  }

  @IsTest
  static void testValideurOptions_entityValidatorsAfterHierarchy_defaultUnchanged() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Entity_Ref__c FROM AR_Price_Matrix__c LIMIT 1];
    User ev = newDaUserWithoutDa('ev-ptf');
    insert new AR_PTF_Entity_Validator__c(
      AR_Entity_Ref__c = matrix.AR_Entity_Ref__c, AR_User__c = ev.Id,
      AR_Unique_Key__c = String.valueOf(matrix.AR_Entity_Ref__c) + ':' + String.valueOf(ev.Id)
    );

    List<AR_PTFDataService.ValideurOption> options = AR_PTFDataService.listValideurOptions(matrix.Id);

    System.assert(options.size() >= 2, 'DA + valideur d\'entité');
    AR_PTFDataService.ValideurOption last = options[options.size() - 1];
    System.assertEquals(ev.Id, last.id, 'Valideur d\'entité trié après la hiérarchie');
    System.assertEquals(Label.AR_Msg_VAL_LevelEntityValidator, last.role);
    System.assertEquals(false, last.isDefault);
    System.assertEquals(true, options[0].isDefault, 'Le défaut reste le DA');
  }

  @IsTest
  static void testCollect_valideurIdInList_isRetainedWithTypedFonction() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    // abylsenInput met à jour la matrice : avant tout DML sur User (MIXED_DML_OPERATION sinon).
    AR_PTFDataService.GenerationInput input = abylsenInput(matrix);
    User ra = newDaUserWithoutDa('chosen-ra');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = AR_TestPersona.ownerWithDa(), TP_RA__c = ra.Id);
    }

    input.valideurId = ra.Id;
    input.valideurNom = 'Saisie ignorée';
    input.valideurFonction = 'Fonction modifiée';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);
    User raUser = [SELECT Name FROM User WHERE Id = :ra.Id];
    System.assertEquals(raUser.Name, data.valideurNom);
    System.assertEquals('Fonction modifiée', data.valideurFonction);

    input.valideurFonction = null;
    data = AR_PTFDataService.collect(matrix.Id, input, 1);
    System.assertEquals('Directeur Session36', data.valideurFonction, 'Fonction vide : Title de la personne');
  }

  @IsTest
  static void testCollect_valideurIdOutsideList_fallsBackToDefaultWithoutTypedFonction() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = abylsenInput(matrix);
    User commercial = newDaUserWithoutDa('outside');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = AR_TestPersona.ownerWithDa(), TP_Directeur_commercial__c = commercial.Id);
    }

    input.valideurId = commercial.Id;
    input.valideurFonction = 'Fonction d\'un autre';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    User da = [SELECT TP_DA__r.Name, TP_DA__r.Title FROM User WHERE Id = :AR_TestPersona.ownerWithDa()];
    System.assertEquals(da.TP_DA__r.Name, data.valideurNom, 'Hors liste : valideur par défaut');
    System.assertEquals(da.TP_DA__r.Title, data.valideurFonction, 'La fonction saisie ne suit pas un valideur refusé');
  }

  @IsTest
  static void testCollect_valideurIdGarbage_fallsBackToDefault() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = abylsenInput(matrix);
    input.valideurId = 'pas-un-id';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);
    User da = [SELECT TP_DA__r.Name FROM User WHERE Id = :AR_TestPersona.ownerWithDa()];
    System.assertEquals(da.TP_DA__r.Name, data.valideurNom);
  }

  @IsTest
  static void testCollect_abylsenTemplate_ownerWithoutDa_blocksNamingTheDirector() {
    System.runAs(AR_TestPersona.francais()) {
      // Session 184c3 : propriétaire sans DA → génération bloquée avec un message actionnable, jamais
      // un repli sur l'utilisateur courant ni sur une saisie.
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      // Dates posées à l'insertion (une matrice « Validée » est verrouillée, et les dates sont exigées
      // avant le valideur) : le blocage testé est bien celui du DA.
      AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
        OwnerId = AR_TestPersona.bm().Id,
        AR_Position__c = fixture.AR_Position__c,
        AR_Contract_Type__c = 'CDI',
        AR_Annual_Salary__c = 43600,
        AR_RFA_Percent__c = 0,
        AR_Proposed_TJM__c = 700,
        AR_Status__c = 'Validée',
        AR_Account_Name__c = 'Client PTF',
        AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
        AR_Start_Date__c = Date.newInstance(2026, 9, 1),
        AR_End_Date__c = Date.newInstance(2026, 10, 31)
      );
      insert matrix;
      AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
      input.matrixId = matrix.Id;
      input.templateCode = 'ABYLSEN_AT_V11';
      input.valideurNom = 'Saisie sans effet';

      String message = null;
      try {
        AR_PTFDataService.collect(matrix.Id, input, 1);
        System.assert(false, 'Un propriétaire sans directeur d\'agence ne doit pas pouvoir générer');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      String ownerName = [SELECT Name FROM User WHERE Id = :matrix.OwnerId].Name;
      System.assert(message.contains(ownerName + ', propriétaire de cette matrice,'), message);
      System.assert(message.contains('ni DA, ni Directeur, ni DD'), message);
      System.assert(!message.contains(UserInfo.getName()), 'Jamais l\'utilisateur courant en repli : ' + message);

      AR_PTFData defaults = AR_PTFDataService.getGenerationDefaults(matrix.Id);
      System.assert(String.isBlank(defaults.valideurNom), 'Le pré-remplissage répond sans valideur, sans bloquer');
      System.assertEquals(message, defaults.valideurBlocage, 'Le même texte sert au pré-remplissage et à la génération');
    }
  }

  @IsTest
  static void testCollectAvenant_ownerWithoutDa_blocksLikeCollect() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.bm().Id, 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00110B-V1', 1);

      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.ptfDocumentId = origin.Id;
      input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
      input.revisionPrix = false;

      String message = null;
      try {
        AR_PTFDataService.collectAvenant(origin, input, 1);
        System.assert(false, 'Le DA reste obligatoire pour un avenant aussi');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      System.assert(message.contains('ni DA, ni Directeur, ni DD'), message);
    }
  }

  // ------------------------------------------------------------------
  // Valideur : DA, sinon Directeur, sinon DD, sur la fiche du propriétaire de la matrice.
  // ------------------------------------------------------------------

  private static User ownerWithChain(Id da, Id directeur, Id dd) {
    User owner = AR_TestPersona.bm();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = owner.Id, TP_DA__c = da, TP_Directeur__c = directeur, TP_DD__c = dd);
    }
    return owner;
  }

  private static void deactivate(User u) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = u.Id, IsActive = false);
    }
  }

  private static AR_PTFData defaultsOfOwner(User owner) {
    AR_Price_Matrix__c fixture = [SELECT AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, owner.Id, 'Abylsen SIGMA');
    return AR_PTFDataService.getGenerationDefaults(matrix.Id);
  }

  private static User userWithNameAndTitle(Id userId) {
    return [SELECT Name, Title FROM User WHERE Id = :userId];
  }

  @IsTest
  static void testValideur_daPresent_isDa() {
    User da = AR_TestPersona.bm();
    User dir = AR_TestPersona.bm();
    User dd = AR_TestPersona.bm();
    AR_PTFData d = defaultsOfOwner(ownerWithChain(da.Id, dir.Id, dd.Id));

    User expected = userWithNameAndTitle(da.Id);
    System.assertEquals(expected.Name, d.valideurNom);
    System.assertEquals(expected.Title, d.valideurFonction);
    System.assertEquals(null, d.valideurBlocage);
  }

  @IsTest
  static void testValideur_daVide_directeur() {
    User dir = AR_TestPersona.bm();
    User dd = AR_TestPersona.bm();
    AR_PTFData d = defaultsOfOwner(ownerWithChain(null, dir.Id, dd.Id));

    User expected = userWithNameAndTitle(dir.Id);
    System.assertEquals(expected.Name, d.valideurNom);
    System.assertEquals(expected.Title, d.valideurFonction);
    System.assertEquals(null, d.valideurBlocage);
  }

  @IsTest
  static void testValideur_daEtDirecteurVides_dd() {
    User dd = AR_TestPersona.bm();
    AR_PTFData d = defaultsOfOwner(ownerWithChain(null, null, dd.Id));

    User expected = userWithNameAndTitle(dd.Id);
    System.assertEquals(expected.Name, d.valideurNom);
    System.assertEquals(expected.Title, d.valideurFonction);
  }

  @IsTest
  static void testValideur_daInactif_suivant() {
    User da = AR_TestPersona.bm();
    User dir = AR_TestPersona.bm();
    deactivate(da);
    User owner = ownerWithChain(da.Id, dir.Id, null);

    AR_PTFData d = defaultsOfOwner(owner);
    System.assertEquals(userWithNameAndTitle(dir.Id).Name, d.valideurNom, 'Un DA inactif compte comme vide');
  }

  @IsTest
  static void testValideur_daEtDirecteurInactifs_dd() {
    User da = AR_TestPersona.bm();
    User dir = AR_TestPersona.bm();
    User dd = AR_TestPersona.bm();
    deactivate(da);
    deactivate(dir);
    User owner = ownerWithChain(da.Id, dir.Id, dd.Id);

    AR_PTFData d = defaultsOfOwner(owner);
    System.assertEquals(userWithNameAndTitle(dd.Id).Name, d.valideurNom);
  }

  @IsTest
  static void testValideur_troisVides_blocageNommeLeProprietaire() {
    System.runAs(AR_TestPersona.francais()) {
      User owner = ownerWithChain(null, null, null);
      AR_PTFData d = defaultsOfOwner(owner);

      String ownerName = userWithNameAndTitle(owner.Id).Name;
      System.assertEquals(null, d.valideurNom);
      System.assert(d.valideurBlocage.startsWith(ownerName + ', propriétaire de cette matrice, n\'a ni DA'), d.valideurBlocage);
      System.assert(d.valideurBlocage.contains('Demandez à un administrateur'), d.valideurBlocage);
    }
  }

  @IsTest
  static void testValideurError_sansNomDuProprietaire_formulationGenerique() {
    System.runAs(AR_TestPersona.francais()) {
      System.assertEquals(null, AR_PTFDataService.valideurError('Jean Dupont', null));
      String message = AR_PTFDataService.valideurError(null, null);
      System.assert(message.startsWith('Le propriétaire de cette matrice n\'a ni DA'), message);
    }
  }

  // ------------------------------------------------------------------
  // Session 110 : le pré-remplissage ne bloque jamais, et le valideur saisi sur la dernière PTF
  // générée est repris quand la matrice ne porte ni valideur effectif ni sélectionné.
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_abylsenTemplate_contexteDefaultsFromBesoinJobDescription() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('ctx', 'Abylsen SIGMA');
    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Job_description__c = 'Descriptif Connexys du besoin, C24.'
    );

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Descriptif Connexys du besoin, C24.',
      data.contexte,
      'C24 : sans saisie, le gabarit Abylsen pré-remplit I.3.1 depuis le descriptif Connexys du besoin'
    );
  }

  @IsTest
  static void testCollect_abylsenTemplate_contexteUserInput_winsOverBesoinDescription() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('ctx2', 'Abylsen SIGMA');
    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Job_description__c = 'Descriptif Connexys du besoin.'
    );

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    input.contexte = 'Contexte amendé par l\'utilisateur';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('Contexte amendé par l\'utilisateur', data.contexte);
  }

  @IsTest
  static void testCollect_genericTemplate_contexteStaysBlank_nonRegression() {
    // Session 142 : le gabarit générique a une section « Besoins client » (I.3.1), donc doit
    // pré-remplir contexte avec le descriptif du besoin Connexys — même règle que tous les autres
    // gabarits qui impriment cette section (Abylsen, ABMI). Contexte vient de TP_Information_complementaire__c
    // en priorité (session 129, 46% remplissage), puis cxsrec__Job_description__c (9%).
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Job_description__c = 'Descriptif Connexys du besoin.'
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('Descriptif Connexys du besoin.', data.contexte);
  }

  @IsTest
  static void testCollect_abylsenTemplate_historique_besoinScope_includesOtherMatrixOnSameBesoin() {
    AR_Price_Matrix__c matrix1 = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('hist', 'Abylsen SIGMA');

    // Deuxième matrice sur le MÊME besoin — c'est le cas que C4 vise (le besoin peut porter N
    // matrices, cf. CLAUDE.md workflow §1).
    AR_Price_Matrix__c matrix2 = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = matrix1.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 750,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Selected_Validator__c = selected.Id,
      // Session 49 : dates de mission désormais obligatoires pour générer une PTF Abylsen (cause B).
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix2;

    // Un document déjà généré sur matrix1 (gabarit générique, périmètre matrice historique).
    insert new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix1.Id,
      AR_Position__c = matrix1.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-BESOIN-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"redacteurNom":"Rédacteur Autre Matrice","historique":[{"version":"V1","objetModification":"Création"}]}',
      AR_Generated_At__c = System.now().addHours(-1),
      AR_Generation_Status__c = 'Généré'
    );

    // matrix2 est déjà inséré Validée/Abylsen SIGMA : pas d'appel à abylsenInput (qui referait un
    // UPDATE sur une matrice déjà verrouillée par la décision post-statut).
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix2.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    AR_PTFData data = AR_PTFDataService.collect(matrix2.Id, input, 1);

    System.assertEquals(
      2,
      data.historique.size(),
      'C4 : périmètre BESOIN — l\'historique doit inclure le document de l\'AUTRE matrice sur le même besoin'
    );
    System.assertEquals('PTF-TEST-BESOIN-V1', data.historique[0].reference);
    System.assertEquals(UserInfo.getName(), data.historique[0].responsable);
  }

  @IsTest
  static void testCollect_abylsenTemplate_historique_previousMatrixVersion_noLongerDrivesLabel() {
    AR_Price_Matrix__c matrix1 = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('rev', 'Abylsen SIGMA');

    AR_Price_Matrix__c matrix2 = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = matrix1.AR_Position__c,
      AR_Previous_Version__c = matrix1.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 770,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Selected_Validator__c = selected.Id,
      // Session 49 : dates de mission désormais obligatoires pour générer une PTF Abylsen (cause B).
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix2;

    // matrix2 est déjà inséré Validée/Abylsen SIGMA : pas d'appel à abylsenInput (qui referait un
    // UPDATE sur une matrice déjà verrouillée par la décision post-statut).
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix2.Id;
    input.templateCode = 'ABYLSEN_AT_V11';
    AR_PTFData data = AR_PTFDataService.collect(matrix2.Id, input, 1);

    AR_PTFData.HistoryRow current = data.historique[data.historique.size() - 1];
    System.assertEquals(
      '',
      current.objetModification,
      'Session 138 : la filiation de la matrice (duplication) ne produit plus « Révision budgétaire » — rang 1, cellule vide'
    );
  }

  @IsTest
  static void testCollect_abylsenTemplate_historique_firstVersion_modificationCellEmpty() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('nocrev', 'Abylsen SIGMA');

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    AR_PTFData.HistoryRow current = data.historique[data.historique.size() - 1];
    System.assertEquals('', current.objetModification, 'Rang 1 : plus de libellé « Création »');
  }

  // ------------------------------------------------------------------
  // Session 37 — cinq correctifs Abylsen + collecte d'un AVENANT.
  // ------------------------------------------------------------------

  @IsTest
  static void testCollect_domaineExpertise_isUserInputNotHardcoded() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.domaineExpertise = 'la cybersécurité industrielle';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('la cybersécurité industrielle', data.domaineExpertise);
  }

  @IsTest
  static void testCollect_domaineExpertiseNotProvided_staysBlank() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      null,
      data.domaineExpertise,
      'Jamais de valeur héritée d\'un exemple (ex. "des méthodes") faute de saisie'
    );
  }

  private static AR_PTF_Document__c insertGeneratedPtfDoc(AR_Price_Matrix__c matrix, String reference, Integer versionNumber) {
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = reference,
      AR_Version_Number__c = versionNumber,
      AR_Snapshot__c = '{"client":"' + reference + '"}',
      AR_Generated_At__c = Datetime.newInstance(2026, 8, 1, 10, 0, 0),
      AR_Generation_Status__c = 'Généré',
      AR_Template_Code__c = 'ABYLSEN_AT_V11'
    );
    insert doc;
    return doc;
  }

  @IsTest
  static void testCollectAvenant_simpleProlongation_priceBlockAbsentAndCitesOrigin() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00110-V1', 1);

    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = origin.Id;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    input.revisionPrix = false;
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals('AV1', data.version);
    System.assert(data.reference.startsWith('PTF_ABYLSEN_') && data.reference.endsWith('_AV1'), 'Numérotation propre AV1 : ' + data.reference);
    System.assertEquals(AR_PTFGenerationService.buildNomenclatureFileName(data), data.reference);
    System.assertEquals('PTF-MAT-00110-V1', data.ptfInitialeReference);
    System.assertEquals(origin.Id, data.ptfInitialeDocumentId);
    System.assertEquals(Date.newInstance(2026, 12, 31), data.prolongationJusquAu);
    System.assertEquals(false, data.revisionPrix);
    System.assert(
      data.lots.isEmpty(),
      'Un avenant de simple prolongation ne doit afficher ni bloc prix ni tableau de lots'
    );
    System.assertEquals('AVENANT_AT_V11', data.templateCode);
  }

  /**
   * Session 57 : le tableau d'identification de la page de garde (partagé PTF/avenant) attend une
   * ligne « Projet » — collectAvenant() ne câblait pas titreBesoin avant cette session (seul
   * collect() le faisait), la cellule serait donc toujours restée vide sur un avenant.
   */
  @IsTest
  static void testCollectAvenant_titreBesoin_sourcedFromPosition() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00110C-V1', 1);

    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = origin.Id;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    input.revisionPrix = false;
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals(
      'Besoin PTF',
      data.titreBesoin,
      'Même source que collect() : Name du besoin Connexys (cxsrec__cxsPosition__c)'
    );
  }

  @IsTest
  static void testCollectAvenant_withPriceRevision_buildsLotsAnchoredOnEffectiveDate() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = fixture.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;
    AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00111-V1', 1);

    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = origin.Id;
    input.prolongationJusquAu = Date.newInstance(2027, 2, 28);
    input.revisionPrix = true;
    input.revisionPrixADateDu = Date.newInstance(2026, 12, 1);
    input.nouveauTjm = 750; // session 123 : obligatoire avec la révision de prix
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals(true, data.revisionPrix);
    System.assertEquals(Date.newInstance(2026, 12, 1), data.revisionPrixADateDu);
    // Session 123b : l'échéancier révisé court de la date d'effet (déc. 2026) à la date de
    // prolongation (fév. 2027) — 3 lots, et non plus « autant de lots que l'origine ».
    System.assertEquals(3, data.lots.size());
    System.assertEquals('Lot 1', data.lots[0].libelle);
    System.assertEquals(Date.newInstance(2026, 12, 31), data.lots[0].echeance);
    System.assertEquals(Date.newInstance(2027, 1, 31), data.lots[1].echeance);
    System.assertEquals(Date.newInstance(2027, 2, 28), data.lots[2].echeance);
    System.assertNotEquals(null, data.lotsTotal);
  }

  @IsTest
  static void testCollectAvenant_priceRevisionWithoutEffectiveDate_throws() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00112-V1', 1);

      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.ptfDocumentId = origin.Id;
      input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
      input.revisionPrix = true;
      input.valideurNom = 'Peu importe pour ce test';

      try {
        AR_PTFDataService.collectAvenant(origin, input, 1);
        System.assert(false, 'Une révision de prix sans date d\'effet doit bloquer');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('date d\'effet'));
      }
    }
  }

  @IsTest
  static void testCollectAvenant_priceRevisionWithoutNewTjm_throws() {
    System.runAs(AR_TestPersona.francais()) {
      // Session 123 : nouveau TJM obligatoire quand revisionPrix = true
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00112-V1', 1);

      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.ptfDocumentId = origin.Id;
      input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
      input.revisionPrix = true;
      input.revisionPrixADateDu = Date.newInstance(2026, 11, 1);
      input.valideurNom = 'Peu importe pour ce test';
      // nouveauTjm est null

      try {
        AR_PTFDataService.collectAvenant(origin, input, 1);
        System.assert(false, 'Une révision de prix sans nouveau TJM doit bloquer');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('nouveau TJM'));
      }
    }
  }

  @IsTest
  static void testCollectAvenant_priceRevisionWithNewTjm_calculatesLotsWithNewTjm() {
    // Session 123 : échéancier recalculé avec le nouveau TJM au lieu de l'ancien
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00112-V1', 1);

    Decimal ancienn = matrix.AR_Proposed_TJM__c; // ancien TJM de la matrice, ex. 600
    Decimal nouveau = 650;

    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = origin.Id;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    input.revisionPrix = true;
    input.revisionPrixADateDu = Date.newInstance(2026, 11, 1);
    input.nouveauTjm = nouveau;
    input.valideurNom = 'Valideur Test';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals(nouveau, data.nouveauTjm, 'Nouveau TJM figé dans le snapshot');
    System.assert(data.lots != null && !data.lots.isEmpty(), 'Lots calculés avec le nouveau TJM');

    // Vérification : si on a un lot de 20 jours, le montant devrait être environ 20 * nouveau TJM
    if (data.lots.size() > 0) {
      Decimal expectedMontant = data.lots[0].jours * nouveau;
      Decimal actualMontant = data.lots[0].montantCalcule;
      System.assertEquals(
        expectedMontant.setScale(0, System.RoundingMode.HALF_UP),
        actualMontant,
        'Lot calculé avec le nouveau TJM'
      );
    }
  }

  @IsTest
  static void testCollectAvenant_interlocuteurClient_isTechnicalContactNotHiringManager() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    Contact technicalContact = new Contact(
      FirstName = 'Julien',
      LastName = 'Technique',
      Title = 'Référent technique',
      Phone = '0600000000',
      Email = 'julien.technique@example.com'
    );
    insert technicalContact;
    update new cxsrec__cxsPosition__c(
      Id = fixture.AR_Position__c,
      cxsrec__Contact_for_questions__c = technicalContact.Id
    );

    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertGeneratedPtfDoc(matrix, 'PTF-MAT-00113-V1', 1);

    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = origin.Id;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    input.valideurNom = 'Peu importe pour ce test';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals(
      'Julien Technique',
      data.interNom,
      'C2/C3 de l\'avenant : interlocuteur technique du besoin, pas le client signataire de la PTF'
    );
    System.assertEquals('Référent technique', data.interFonction);
    System.assertNotEquals(
      'Marie Client',
      data.interNom,
      'Ne doit jamais réutiliser le hiringManager (client signataire) comme sur la PTF'
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Session 145 — l'avenant reprend les contacts figés dans la PTF d'origine
  // ---------------------------------------------------------------------------------------------

  /** PTF d'origine dont le snapshot porte les contacts voulus ; snapshotJson libre pour le cas corrompu. */
  private static AR_PTF_Document__c insertOriginWithSnapshot(AR_Price_Matrix__c matrix, String reference, String snapshotJson) {
    // Snapshot posé à l'insertion : AR_Snapshot__c n'est pas modifiable après création.
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = reference,
      AR_Version_Number__c = 1,
      AR_Snapshot__c = snapshotJson,
      AR_Generated_At__c = Datetime.newInstance(2026, 8, 1, 10, 0, 0),
      AR_Generation_Status__c = 'Généré',
      AR_Template_Code__c = 'ABYLSEN_AT_V11'
    );
    insert doc;
    return doc;
  }

  /** Session 184c3 : DA du propriétaire de test (la règle 184c : valideur = DA, jamais la saisie ni le parent). */
  private static User ownerDa() {
    return [SELECT TP_DA__r.Name, TP_DA__r.Title FROM User WHERE Id = :AR_TestPersona.ownerWithDa()];
  }

  private static String originSnapshotWithContacts() {
    return JSON.serialize(new Map<String, Object>{
      'client' => 'Client PTF',
      'interNom' => 'Benjamin Hayat',
      'interFonction' => 'Resp. Logistique',
      'interTel' => '0176839393',
      'interEmail' => 'benjamin.hayat@client.test',
      'redacteurNom' => 'Rédac Origine',
      'redacteurFonction' => 'Business Manager Origine',
      'valideurNom' => 'Valideur Origine',
      'valideurFonction' => 'Directeur Origine'
    });
  }

  private static AR_PTFDataService.AvenantGenerationInput avenantInput145(Id originId) {
    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = originId;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    return input;
  }

  @IsTest
  static void testCollectAvenant_parentHasInterlocuteur_needHasNoTechnicalContact_reprendLeParent() {
    // (a) Besoin sans contact technique : avant la session 145, interlocuteur vide dans l'avenant.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new cxsrec__cxsPosition__c(Id = fixture.AR_Position__c, cxsrec__Contact_for_questions__c = null);
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00145-V1', originSnapshotWithContacts());

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, avenantInput145(origin.Id), 1);

    System.assertEquals('Benjamin Hayat', data.interNom);
    System.assertEquals('Resp. Logistique', data.interFonction);
    System.assertEquals('0176839393', data.interTel);
    System.assertEquals('benjamin.hayat@client.test', data.interEmail);
    System.assert(
      !data.warnings.contains('Contacts de la PTF d\'origine illisibles, repris depuis le besoin.'),
      'Snapshot lisible : aucun avertissement de repli'
    );
  }

  @IsTest
  static void testCollectAvenant_parentInterlocuteurBeatsTechnicalContact_andBlocIsNeverMixed() {
    // Le parent porte un interlocuteur SANS téléphone ; le contact technique en a un : le téléphone
    // du contact technique ne doit jamais se retrouver accolé au nom du parent.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    Contact technicalContact = new Contact(
      FirstName = 'Julien', LastName = 'Technique', Title = 'Référent', Phone = '0600000000', Email = 'julien@example.com'
    );
    insert technicalContact;
    update new cxsrec__cxsPosition__c(Id = fixture.AR_Position__c, cxsrec__Contact_for_questions__c = technicalContact.Id);
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(
      matrix, 'PTF-MAT-00146-V1',
      JSON.serialize(new Map<String, Object>{ 'interNom' => 'Franck Frichet', 'interEmail' => 'franck@client.test' })
    );

    AR_PTFDataService.AvenantGenerationInput input = avenantInput145(origin.Id);
    input.valideurNom = 'Valideur Saisi'; // valideur obligatoire, absent de ce snapshot parent
    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals('Franck Frichet', data.interNom, 'Le parent prime sur le contact technique');
    System.assertEquals('franck@client.test', data.interEmail);
    System.assertEquals(null, data.interTel, 'Jamais le téléphone d\'un autre contact accolé au nom du parent');
    System.assertEquals(null, data.interFonction);
  }

  @IsTest
  static void testCollectAvenant_formInputBeatsParentSnapshot() {
    // (b) Saisie du formulaire > parent, champ par champ ; le reste vient du parent.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00147-V1', originSnapshotWithContacts());

    AR_PTFDataService.AvenantGenerationInput input = avenantInput145(origin.Id);
    input.interNom = 'Saisie Interlocuteur';
    input.interTel = '0999999999';
    input.redacteurNom = 'Saisie Rédacteur';
    input.valideurNom = 'Saisie Valideur';
    input.valideurFonction = 'Saisie Fonction Valideur';

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals('Saisie Interlocuteur', data.interNom);
    System.assertEquals('0999999999', data.interTel);
    System.assertEquals('Resp. Logistique', data.interFonction, 'Champ non saisi : valeur du parent');
    System.assertEquals('benjamin.hayat@client.test', data.interEmail);
    System.assertEquals('Saisie Rédacteur', data.redacteurNom);
    System.assertEquals(ownerDa().TP_DA__r.Name, data.valideurNom, 'Valideur = DA du propriétaire, la saisie est sans effet');
    System.assertEquals(ownerDa().TP_DA__r.Title, data.valideurFonction);
  }

  @IsTest
  static void testCollectAvenant_corruptedParentSnapshot_fallsBackToNeedAndWarns() {
    System.runAs(AR_TestPersona.francais()) {
      // (c) Snapshot illisible : repli sur la source actuelle (contact technique) + avertissement.
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      Contact technicalContact = new Contact(
        FirstName = 'Julien', LastName = 'Technique', Title = 'Référent', Phone = '0600000000', Email = 'julien@example.com'
      );
      insert technicalContact;
      update new cxsrec__cxsPosition__c(Id = fixture.AR_Position__c, cxsrec__Contact_for_questions__c = technicalContact.Id);
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00148-V1', '{ceci n\'est pas du json');

      AR_PTFDataService.AvenantGenerationInput input = avenantInput145(origin.Id);
      input.valideurNom = 'Valideur Saisi';
      AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

      System.assertEquals('Julien Technique', data.interNom, 'Repli sur le contact technique du besoin');
      System.assertEquals('0600000000', data.interTel);
      System.assert(
        data.warnings.contains('Contacts de la PTF d\'origine illisibles, repris depuis le besoin.'),
        'Le repli est signalé, jamais silencieux : ' + data.warnings
      );
    }
  }

  @IsTest
  static void testCollectAvenant_parentRedacteurAndValideurAreReprised() {
    // (d) Rédacteur (et valideur) de la PTF d'origine repris, y compris leur fonction, sans mélange
    // avec le BM / la matrice.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00149-V1', originSnapshotWithContacts());

    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, avenantInput145(origin.Id), 1);

    System.assertEquals('Rédac Origine', data.redacteurNom);
    System.assertEquals('Business Manager Origine', data.redacteurFonction);
    System.assertEquals(ownerDa().TP_DA__r.Name, data.valideurNom, 'Valideur = DA du propriétaire, pas celui de la PTF d\'origine');
    System.assertEquals(ownerDa().TP_DA__r.Title, data.valideurFonction);
  }

  @IsTest
  static void testCollectAvenant_parentWithoutContacts_keepsPreviousBehaviour() {
    // Snapshot parent lisible mais sans contacts (cas des PTF anciennes) : comportement d'avant.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    Contact technicalContact = new Contact(FirstName = 'Julien', LastName = 'Technique', Title = 'Référent');
    insert technicalContact;
    update new cxsrec__cxsPosition__c(Id = fixture.AR_Position__c, cxsrec__Contact_for_questions__c = technicalContact.Id);
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00150-V1', '{"client":"X"}');

    AR_PTFDataService.AvenantGenerationInput input = avenantInput145(origin.Id);
    input.valideurNom = 'Valideur Saisi';
    AR_PTFData data = AR_PTFDataService.collectAvenant(origin, input, 1);

    System.assertEquals('Julien Technique', data.interNom);
    System.assertEquals(
      [SELECT Name FROM User WHERE Id = :AR_TestPersona.ownerWithDa()].Name,
      data.redacteurNom,
      'Rédacteur = BM (propriétaire de la matrice)'
    );
    System.assertEquals(ownerDa().TP_DA__r.Name, data.valideurNom);
  }

  @IsTest
  static void testGetAvenantDefaults_returnsParentContacts() {
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
    AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00151-V1', originSnapshotWithContacts());

    AR_PTFDataService.AvenantContacts defaults = AR_PTFDataService.getAvenantDefaults(origin.Id);

    System.assertEquals('Benjamin Hayat', defaults.interNom);
    System.assertEquals('0176839393', defaults.interTel);
    System.assertEquals('Rédac Origine', defaults.redacteurNom);
    System.assertEquals(ownerDa().TP_DA__r.Name, defaults.valideurNom);
    System.assertEquals(null, defaults.warning);
  }

  @IsTest
  static void testGetAvenantDefaults_corruptedParent_warns() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = newMatrixOwnedBy(fixture.AR_Position__c, AR_TestPersona.ownerWithDa(), 'Abylsen SIGMA');
      AR_PTF_Document__c origin = insertOriginWithSnapshot(matrix, 'PTF-MAT-00152-V1', '[pas un objet');

      AR_PTFDataService.AvenantContacts defaults = AR_PTFDataService.getAvenantDefaults(origin.Id);

      System.assertEquals('Contacts de la PTF d\'origine illisibles, repris depuis le besoin.', defaults.warning);
    }
  }

  @IsTest
  static void testGetAvenantDefaults_unknownDocument_throwsWithContext() {
    System.runAs(AR_TestPersona.francais()) {
      try {
        AR_PTFDataService.getAvenantDefaults(null);
        System.assert(false, 'Un document introuvable doit lever une erreur nommée');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('valeurs par défaut de l\'avenant'),
          'Le contexte est dans le message : ' + e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void testCollectAvenant_draftMatrix_throws() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
        OwnerId = AR_TestPersona.ownerWithDa(),
        AR_Position__c = fixture.AR_Position__c,
        AR_Contract_Type__c = 'CDI',
        AR_Annual_Salary__c = 43600,
        AR_RFA_Percent__c = 0,
        AR_Proposed_TJM__c = 700,
        AR_Status__c = 'Brouillon',
        AR_Account_Name__c = 'Client PTF',
        AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA')
      );
      insert matrix;
      // Un AR_PTF_Document__c peut exister même si la matrice est repassée en brouillon depuis (cas
      // limite, pas le chemin nominal) : collectAvenant revalide le statut COURANT de la matrice.
      AR_PTF_Document__c origin = new AR_PTF_Document__c(
        AR_Price_Matrix__c = matrix.Id,
        AR_Position__c = matrix.AR_Position__c,
        AR_Reference__c = 'PTF-MAT-00114-V1',
        AR_Version_Number__c = 1,
        AR_Snapshot__c = '{}',
        AR_Generated_At__c = System.now(),
        AR_Generation_Status__c = 'Généré'
      );
      insert origin;

      AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
      input.ptfDocumentId = origin.Id;
      input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
      input.valideurNom = 'Peu importe pour ce test';

      try {
        AR_PTFDataService.collectAvenant(origin, input, 1);
        System.assert(false, 'Un avenant ne doit pas se générer si la matrice n\'est plus validée');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('validée'));
      }
    }
  }

  // --- Session 66 : pré-remplissage PTF consultant, 8 cas limites du tableau §2 ---

  // Session 110 : les tests de pré-remplissage consultant ci-dessous (sessions 64-66) portent sur
  // la cartographie des données, pas sur les blocages de génération. Ils n'ont jamais passé en
  // l'état : fixture sans valideur ni dates de mission, donc requireValideur/requireSchedule
  // levaient avant toute assertion. Ils passent par le mode pré-remplissage de collect
  // (enforceGenerationBlocks = false), celui qu'utilise réellement getGenerationDefaults.
  @IsTest
  static void testCollect_consultantAbsent_aucunPreemplissage() {
    // Cas 3 : Retrait du consultant (AR_Consultant__c = null) → pas de pré-remplissage.
    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = null;
    matrix.AR_Status__c = 'Validée';
    updateValidatedFixture(matrix);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assertEquals(null, data.consultantExperience, 'Cas 3 : Pas de pré-remplissage sans consultant');
    System.assertEquals(null, data.consultantCompetences, 'Cas 3 : Pas de pré-remplissage sans consultant');
  }

  @IsTest
  static void testCollect_saisieExistante_nePasEcraserParSourceVide() {
    // Cas 2 + règle 1 : Source vide ne remplace pas saisie existante.
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
        .getRecordTypeInfosByName()
        .get('Consultant')
        .getRecordTypeId(),
      cxsrec__First_name__c = 'Paul',
      cxsrec__Last_name__c = 'Consultant',
      TP_Experience__c = null, // Vide
      TP_Competences_techniques_et_transverses__c = 'Apex, LWC' // Rempli
    );
    insert consultant;

    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = consultant.Id;
    matrix.AR_Status__c = 'Validée';
    updateValidatedFixture(matrix);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.consultantExperience = 'Saisie utilisateur existante';
    input.consultantCompetences = 'Saisie utilisateur compétences';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assertEquals(
      'Saisie utilisateur existante',
      data.consultantExperience,
      'Cas 2 : Saisie existante ne doit pas être écrasée'
    );
    System.assertEquals(
      'Saisie utilisateur compétences',
      data.consultantCompetences,
      'Cas 2 : Saisie existante ne doit pas être écrasée'
    );
  }

  @IsTest
  static void testCollect_consultantSupprime_pasErreur() {
    // Cas 4 : Consultant supprimé côté Connexys (deleteConstraint=SetNull) →
    // pas de crash, pré-remplissage silencieusement vide.
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
        .getRecordTypeInfosByName()
        .get('Consultant')
        .getRecordTypeId(),
      cxsrec__First_name__c = 'Ephemere',
      cxsrec__Last_name__c = 'Consultant',
      TP_Experience__c = 'Expérience éphémère',
      TP_Competences_techniques_et_transverses__c = 'Compétences éphémères'
    );
    insert consultant;

    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = consultant.Id;
    matrix.AR_Status__c = 'Validée';
    updateValidatedFixture(matrix);

    // Supprimer le consultant APRÈS la création de la matrice (simule deleteConstraint=SetNull)
    delete consultant;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;

    // Doit ne pas lever d'exception
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assertEquals(
      null,
      data.consultantExperience,
      'Cas 4 : Consultant supprimé → pas de pré-remplissage, pas d\'erreur'
    );
    System.assertEquals(
      null,
      data.consultantCompetences,
      'Cas 4 : Consultant supprimé → pas de pré-remplissage, pas d\'erreur'
    );
  }

  @IsTest
  static void testCollect_matrixValidee_genere() {
    // Cas 7 : Matrice "Validée" (pas "En dérogation" ni "Brouillon") → génération OK.
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
        .getRecordTypeInfosByName()
        .get('Consultant')
        .getRecordTypeId(),
      cxsrec__First_name__c = 'Valide',
      cxsrec__Last_name__c = 'Consultant',
      TP_Experience__c = 'Expérience valide',
      TP_Competences_techniques_et_transverses__c = 'Compétences valides'
    );
    insert consultant;

    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = consultant.Id;
    matrix.AR_Status__c = 'Validée';
    updateValidatedFixture(matrix);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assert(data != null);
    System.assertEquals(null, data.consultantExperience, 'Cas 7 : génération OK, fiche non lue (184c)');
  }

  @IsTest
  static void testCollect_matrixValideeParDerogation_genere() {
    // Cas 7 : Matrice "Validée par dérogation" → génération OK aussi.
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
        .getRecordTypeInfosByName()
        .get('Consultant')
        .getRecordTypeId(),
      cxsrec__First_name__c = 'Derogation',
      cxsrec__Last_name__c = 'Consultant',
      TP_Experience__c = 'Expérience dérogation',
      TP_Competences_techniques_et_transverses__c = 'Compétences dérogation'
    );
    insert consultant;

    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = consultant.Id;
    matrix.AR_Status__c = 'Validée par dérogation';
    updateValidatedFixture(matrix);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assert(data != null);
    System.assertEquals(null, data.consultantExperience, 'Cas 7 : génération OK par dérogation, fiche non lue (184c)');
  }

  @IsTest
  static void testCollect_consultantFicheRenseignee_neRemplitPlusExperienceNiCompetences() {
    // Session 184c3 : le pré-remplissage Expérience/Compétences depuis la fiche consultant est retiré
    // (184c) ; seule la saisie du formulaire alimente ces deux champs, la fiche n'est jamais lue.
    cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
      RecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
        .getRecordTypeInfosByName()
        .get('Consultant')
        .getRecordTypeId(),
      cxsrec__First_name__c = 'Partiel',
      cxsrec__Last_name__c = 'Consultant',
      TP_Experience__c = 'Expérience depuis fiche',
      TP_Competences_techniques_et_transverses__c = 'Compétences depuis fiche'
    );
    insert consultant;

    AR_Price_Matrix__c fixture = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_Price_Matrix__c matrix = newMatrixOwnedBy(
      fixture.AR_Position__c,
      AR_TestPersona.ownerWithDa(),
      'Abylsen SIGMA'
    );
    matrix.AR_Consultant__c = consultant.Id;
    matrix.AR_Status__c = 'Validée';
    updateValidatedFixture(matrix);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.consultantCompetences = 'Saisie utilisateur pour compétences';

    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, false);

    System.assertEquals(null, data.consultantExperience, 'La fiche ne pré-remplit plus l\'expérience');
    System.assertEquals(
      'Saisie utilisateur pour compétences',
      data.consultantCompetences,
      'Seule la saisie du formulaire alimente les compétences'
    );
  }

  // Session 122 — account/contact from junction, working days schedule, manual day override.
  // Working days calculation test: schedule rows are built with actual working days per month.

  @IsTest
  static void testPreviewAvenantLots_validParams_returnsLots() {
    Date dateEffet = Date.newInstance(2026, 12, 1);
    Date prolongation = Date.newInstance(2027, 2, 28);
    Decimal nouveauTjm = 750;

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(
      dateEffet,
      prolongation,
      nouveauTjm,
      null
    );

    System.assertNotEquals(null, lots, 'Lots list should not be null');
    System.assertEquals(3, lots.size(), 'December 2026 - February 2027 = 3 lots');
    // Le libellé d'un lot est « Lot N » (depuis la session 37) ; le mois est porté par `mois`.
    System.assertEquals('Lot 1', lots[0].libelle);
    System.assertEquals('décembre 2026', lots[0].mois);
    System.assertEquals('janvier 2027', lots[1].mois);
    System.assertEquals('février 2027', lots[2].mois);
  }

  @IsTest
  static void testPreviewAvenantLots_nullDateEffet_returnsEmptyList() {
    Date prolongation = Date.newInstance(2027, 2, 28);
    Decimal nouveauTjm = 750;

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(null, prolongation, nouveauTjm, null);

    System.assertEquals(0, lots.size(), 'Should return empty list when dateEffet is null');
  }

  @IsTest
  static void testPreviewAvenantLots_nullProlongation_returnsEmptyList() {
    Date dateEffet = Date.newInstance(2026, 12, 1);
    Decimal nouveauTjm = 750;

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(dateEffet, null, nouveauTjm, null);

    System.assertEquals(0, lots.size(), 'Should return empty list when prolongation is null');
  }

  @IsTest
  static void testPreviewAvenantLots_nullNouveauTjm_returnsEmptyList() {
    Date dateEffet = Date.newInstance(2026, 12, 1);
    Date prolongation = Date.newInstance(2027, 2, 28);

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(dateEffet, prolongation, null, null);

    System.assertEquals(0, lots.size(), 'Should return empty list when nouveauTjm is null');
  }

  @IsTest
  static void testPreviewAvenantLots_prolongationBeforeDateEffet_returnsEmptyList() {
    Date dateEffet = Date.newInstance(2027, 2, 28);
    Date prolongation = Date.newInstance(2026, 12, 1);
    Decimal nouveauTjm = 750;

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(
      dateEffet,
      prolongation,
      nouveauTjm,
      null
    );

    System.assertEquals(0, lots.size(), 'Should return empty list when prolongation < dateEffet');
  }

  @IsTest
  static void testPreviewAvenantLots_montantsCalculesCorrectement() {
    // Vérifier que les montants sont calculés avec le nouveau TJM.
    Date dateEffet = Date.newInstance(2026, 12, 1);
    Date prolongation = Date.newInstance(2027, 1, 31);
    Decimal nouveauTjm = 750;

    List<AR_PTFData.LotRow> lots = AR_PTFDataService.previewAvenantLots(
      dateEffet,
      prolongation,
      nouveauTjm,
      null
    );

    System.assertEquals(2, lots.size(), 'December 2026 - January 2027 = 2 lots');
    // Lot calculation: days × TJM / 1 consultant
    // Session 126 : jours ouvrés réels (week-ends exclus, pas de jours fériés).
    // Décembre 2026 : 23 jours ouvrés × 750 = 17 250
    // Janvier 2027  : 21 jours ouvrés × 750 = 15 750
    System.assertEquals(17250, lots[0].montantCalcule);
    System.assertEquals(15750, lots[1].montantCalcule);
  }

  @IsTest
  static void testCollect_abylsenTemplate_contexteFromInfoComplementaire_priorityOverJobDescription() {
    // Session 129 : TP_Information_complementaire__c (46% filled) takes priority over cxsrec__Job_description__c (9% filled)
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('s129-a', 'Abylsen SIGMA');
    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Job_description__c = 'Old job description field',
      TP_Information_complementaire__c = 'Nouvelle source : Information complémentaire du besoin'
    );

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Nouvelle source : Information complémentaire du besoin',
      data.contexte,
      'Session 129: TP_Information_complementaire__c should be prioritized'
    );
  }

  @IsTest
  static void testCollect_abylsenTemplate_contexteFromJobDescriptionWhenInfoEmpty() {
    // Session 129 : fallback to cxsrec__Job_description__c when TP_Information_complementaire__c is blank
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    User selected = newDaUser('s129-b', 'Abylsen SIGMA');
    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Job_description__c = 'Fallback job description',
      TP_Information_complementaire__c = null
    );

    AR_PTFDataService.GenerationInput input = abylsenInput(matrix, selected.Id);
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals(
      'Fallback job description',
      data.contexte,
      'Should fallback to Job_description when Info complémentaire is blank'
    );
  }

  @IsTest
  static void testCollect_session142_phoneFallbackToMobileWhenPhoneEmpty() {
    // Session 142 fix 2 : si Phone vide mais MobilePhone renseigné, utiliser MobilePhone
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // Create new contact with only MobilePhone (no Phone)
    Contact hiringMgr = new Contact(
      FirstName = 'Test',
      LastName = 'HiringMgr',
      AccountId = [SELECT Id FROM Account LIMIT 1].Id,
      Phone = null,
      MobilePhone = '06 12 34 56 78'
    );
    insert hiringMgr;

    update new cxsrec__cxsPosition__c(
      Id = matrix.AR_Position__c,
      cxsrec__Hiringmanager__c = hiringMgr.Id
    );

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assertEquals('06 12 34 56 78', data.interTel, 'Should fallback to MobilePhone when Phone is empty');
  }

  @IsTest
  static void testCollect_session142_addressFallbackToShippingWhenBillingEmpty() {
    // Session 142 fix 3 : si adresse de facturation vide mais adresse de livraison renseignée,
    // utiliser l'adresse de livraison comme bloc (jamais mélanger rue de l'une et ville de l'autre)
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // Create new account with only Shipping address (no Billing)
    Account acc = new Account(
      Name = 'Test Account Shipping Only',
      BillingStreet = null,
      BillingCity = null,
      BillingPostalCode = null,
      ShippingStreet = '123 Rue de la Paix',
      ShippingCity = 'Colombes',
      ShippingPostalCode = '92700',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT'
    );
    insert acc;

    update new cxsrec__cxsPosition__c(Id = matrix.AR_Position__c, cxsrec__Account__c = acc.Id);

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1);

    System.assert(
      String.isNotBlank(data.adresseClient),
      'Address should be populated from Shipping when Billing is empty'
    );
    System.assert(data.adresseClient.containsIgnoreCase('123 Rue de la Paix'), 'Should use Shipping street');
    System.assert(data.adresseClient.containsIgnoreCase('Colombes'), 'Should use Shipping city');
  }


  // ------------------------------------------------------------------
  // Session 148 : brouillon du formulaire PTF / avenant (AR_Price_Matrix__c.AR_PTF_Form_Draft__c).
  // ------------------------------------------------------------------

  private static AR_Price_Matrix__c validatedMatrixForDraft() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    return matrix;
  }

  /** Pose un contenu brut (éventuellement corrompu) dans la colonne, comme un service Apex le ferait. */
  private static void forceRawDraft(Id matrixId, String raw) {
    AR_TriggerBypass.serviceContext = true;
    try {
      update new AR_Price_Matrix__c(Id = matrixId, AR_PTF_Form_Draft__c = raw);
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }
  }

  private static Map<String, Object> storedDraft(Id matrixId) {
    String raw = [SELECT AR_PTF_Form_Draft__c FROM AR_Price_Matrix__c WHERE Id = :matrixId].AR_PTF_Form_Draft__c;
    return String.isBlank(raw) ? null : (Map<String, Object>) JSON.deserializeUntyped(raw);
  }

  private static Map<String, Object> servedDraft(AR_PTFData data) {
    return String.isBlank(data.formDraft) ? null : (Map<String, Object>) JSON.deserializeUntyped(data.formDraft);
  }

  @IsTest
  static void testSavePtfFormDraft_ptfMode_onValidatedMatrix_roundTripsThroughDefaults() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    String input = JSON.serialize(new Map<String, Object>{
      'matrixId' => matrix.Id,
      'templateCode' => 'ABYLSEN_AT_V11',
      'objet' => 'Objet saisi',
      'materielClient' => true,
      'lotOverrides' => new List<Object>{ new Map<String, Object>{ 'index' => 0, 'montant' => 1234 } }
    });

    Test.startTest();
    String returned = AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', input);
    AR_PTFData data = AR_PTFDataService.getGenerationDefaults(matrix.Id);
    Test.stopTest();

    Map<String, Object> returnedEntry = (Map<String, Object>) JSON.deserializeUntyped(returned);
    System.assertEquals('ABYLSEN_AT_V11', (String) returnedEntry.get('templateCode'), 'La méthode renvoie l\'entrée écrite');
    System.assertEquals(UserInfo.getName(), (String) returnedEntry.get('savedByName'));

    System.assertEquals('Validée', [SELECT AR_Status__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id].AR_Status__c,
      'Le statut ne doit pas bouger : seule la colonne brouillon est écrite');
    Map<String, Object> served = servedDraft(data);
    System.assertNotEquals(null, served, 'Le brouillon doit être servi avec les défauts');
    System.assertEquals(null, data.formDraftWarning, 'Aucun avertissement sur un brouillon sain');
    System.assertEquals(1, (Integer) served.get('version'));
    Map<String, Object> ptf = (Map<String, Object>) served.get('ptf');
    System.assertEquals('ABYLSEN_AT_V11', (String) ptf.get('templateCode'));
    System.assertEquals(UserInfo.getUserId(), (String) ptf.get('savedById'));
    System.assertEquals(UserInfo.getName(), (String) ptf.get('savedByName'));
    System.assertNotEquals(null, ptf.get('savedAt'), 'Date d\'enregistrement attendue');
    Map<String, Object> savedInput = (Map<String, Object>) ptf.get('input');
    System.assertEquals('Objet saisi', (String) savedInput.get('objet'));
    System.assertEquals(true, (Boolean) savedInput.get('materielClient'));
    System.assertEquals(1, ((List<Object>) savedInput.get('lotOverrides')).size());
    System.assertEquals(false, served.containsKey('avenant'), 'Pas d\'entrée avenant sans enregistrement avenant');
  }

  @IsTest
  static void testSavePtfFormDraft_avenantMode_keepsPtfEntryAndStoresParentDocument() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    String parentId = 'a00000000000000AAA'; // identifiant quelconque, seulement relu
    AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE","objet":"A"}');

    AR_PTFDataService.savePtfFormDraft(
      matrix.Id,
      'avenant',
      JSON.serialize(new Map<String, Object>{ 'ptfDocumentId' => parentId, 'prolongationJusquAu' => '2026-12-31' })
    );

    Map<String, Object> stored = storedDraft(matrix.Id);
    Map<String, Object> ptf = (Map<String, Object>) stored.get('ptf');
    Map<String, Object> avenant = (Map<String, Object>) stored.get('avenant');
    System.assertEquals('GENERIQUE', (String) ptf.get('templateCode'), 'L\'entrée PTF doit survivre à l\'écriture de l\'avenant');
    System.assertEquals(parentId, (String) avenant.get('parentDocumentId'));
    System.assertEquals(
      '2026-12-31',
      (String) ((Map<String, Object>) avenant.get('input')).get('prolongationJusquAu')
    );
  }

  @IsTest
  static void testSavePtfFormDraft_secondSaveSameMode_replacesInput() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE","objet":"premier"}');
    AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE","objet":"second"}');

    Map<String, Object> ptf = (Map<String, Object>) storedDraft(matrix.Id).get('ptf');
    System.assertEquals('second', (String) ((Map<String, Object>) ptf.get('input')).get('objet'));
  }

  @IsTest
  static void testClearPtfFormDraft_removesOnlyRequestedMode_thenEmptiesField() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE"}');
    AR_PTFDataService.savePtfFormDraft(matrix.Id, 'avenant', '{"ptfDocumentId":"a00000000000000AAA"}');

    AR_PTFDataService.clearPtfFormDraft(matrix.Id, 'ptf');
    Map<String, Object> afterFirst = storedDraft(matrix.Id);
    System.assertEquals(false, afterFirst.containsKey('ptf'));
    System.assertEquals(true, afterFirst.containsKey('avenant'), 'L\'autre mode doit rester');

    AR_PTFDataService.clearPtfFormDraft(matrix.Id, 'avenant');
    System.assertEquals(null, storedDraft(matrix.Id), 'Plus aucune entrée : le champ est vidé');
    // Idempotent : effacer ce qui n'existe pas ne lève rien.
    AR_PTFDataService.clearPtfFormDraft(matrix.Id, 'avenant');
  }

  @IsTest
  static void testGetGenerationDefaults_unreadableDraft_ignoredWithWarning() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = validatedMatrixForDraft();
      forceRawDraft(matrix.Id, '{ceci n\'est pas du json');

      AR_PTFData data = AR_PTFDataService.getGenerationDefaults(matrix.Id);

      System.assertEquals(null, data.formDraft, 'Un brouillon illisible ne doit jamais être servi');
      System.assertNotEquals(null, data.formDraftWarning, 'Le motif doit être renvoyé, pas avalé');
      System.assert(data.formDraftWarning.containsIgnoreCase('illisible'), data.formDraftWarning);
      System.assertNotEquals(null, data.templateCode, 'Les défauts restent servis malgré le brouillon illisible');
    }
  }

  @IsTest
  static void testGetGenerationDefaults_malformedEntry_droppedOthersKept() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    forceRawDraft(
      matrix.Id,
      '{"version":1,"ptf":{"input":"pas un objet"},"avenant":{"input":{"prolongationJusquAu":"2026-12-31"}}}'
    );

    AR_PTFData data = AR_PTFDataService.getGenerationDefaults(matrix.Id);

    Map<String, Object> served = servedDraft(data);
    System.assertEquals(false, served.containsKey('ptf'), 'L\'entrée mal formée doit être écartée');
    System.assertEquals(true, served.containsKey('avenant'), 'L\'entrée saine doit rester');
    System.assert(data.formDraftWarning.contains('ptf'), data.formDraftWarning);
  }

  @IsTest
  static void testGetGenerationDefaults_unknownDraftVersion_ignoredWithWarning() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    forceRawDraft(matrix.Id, '{"version":99,"ptf":{"input":{}}}');

    AR_PTFData data = AR_PTFDataService.getGenerationDefaults(matrix.Id);

    System.assertEquals(null, data.formDraft);
    System.assert(data.formDraftWarning.contains('version'), data.formDraftWarning);
  }

  @IsTest
  static void testGetGenerationDefaults_noDraft_noWarning() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    AR_PTFData data = AR_PTFDataService.getGenerationDefaults(matrix.Id);
    System.assertEquals(null, data.formDraft);
    System.assertEquals(null, data.formDraftWarning);
  }

  @IsTest
  static void testSavePtfFormDraft_invalidInput_explicitErrors() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = validatedMatrixForDraft();
      Map<String, String> badCalls = new Map<String, String>{
        'ptf|{pas du json' => 'illisible',
        'ptf|[1,2]' => 'objet JSON',
        'inconnu|{}' => 'mode inconnu'
      };
      for (String key : badCalls.keySet()) {
        List<String> parts = key.split('\\|', 2);
        try {
          AR_PTFDataService.savePtfFormDraft(matrix.Id, parts[0], parts[1]);
          System.assert(false, 'Une saisie invalide doit lever : ' + key);
        } catch (AuraHandledException e) {
          System.assert(e.getMessage().containsIgnoreCase(badCalls.get(key)), key + ' -> ' + e.getMessage());
        }
      }
      System.assertEquals(null, storedDraft(matrix.Id), 'Aucune écriture sur une saisie rejetée');
    }
  }

  @IsTest
  static void testSavePtfFormDraft_overMaxLength_explicitError() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = validatedMatrixForDraft();
      String input = JSON.serialize(new Map<String, Object>{ 'objet' => 'x'.repeat(131100) });
      try {
        AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', input);
        System.assert(false, 'Un brouillon trop gros doit lever');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().containsIgnoreCase('taille maximale'), e.getMessage());
      }
      System.assertEquals(null, storedDraft(matrix.Id));
    }
  }

  @IsTest
  static void testSavePtfFormDraft_userWithoutWriteRights_explicitError() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    User noRights = AR_TestPersona.sansHabilitation();

    System.runAs(noRights) {
      try {
        AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE"}');
        System.assert(false, 'Un utilisateur sans droit d\'écriture ne doit pas enregistrer');
      } catch (AuraHandledException e) {
        System.assertEquals(
          'Brouillon non enregistré : vous n\'avez pas les droits d\'écriture sur cette matrice',
          e.getMessage()
        );
      }
    }
    System.assertEquals(null, storedDraft(matrix.Id), 'Rien ne doit avoir été écrit');
  }

  @IsTest
  static void testSavePtfFormDraft_businessManagerOwner_canSaveOnValidatedMatrix() {
    AR_Price_Matrix__c matrix = validatedMatrixForDraft();
    User bm = AR_TestPersona.bm();
    AR_TriggerBypass.serviceContext = true;
    try {
      update new AR_Price_Matrix__c(Id = matrix.Id, OwnerId = bm.Id);
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }

    System.runAs(bm) {
      AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE","objet":"par le BM"}');
    }

    Map<String, Object> ptf = (Map<String, Object>) storedDraft(matrix.Id).get('ptf');
    System.assertEquals(bm.Id, (Id) ptf.get('savedById'));
    System.assertEquals('par le BM', (String) ((Map<String, Object>) ptf.get('input')).get('objet'));
    System.assertEquals(false, AR_TriggerBypass.serviceContext, 'Le contournement du verrou ne doit pas fuir hors du DML');
  }

  @IsTest
  static void testSavePtfFormDraft_doesNotUnlockOtherFields() {
    System.runAs(AR_TestPersona.francais()) {
      // Le contournement du verrou ne vaut que pour l'écriture du brouillon : une modification
      // ordinaire de la même matrice, juste après, reste refusée.
      AR_Price_Matrix__c matrix = validatedMatrixForDraft();
      AR_PTFDataService.savePtfFormDraft(matrix.Id, 'ptf', '{"templateCode":"GENERIQUE"}');
      try {
        update new AR_Price_Matrix__c(Id = matrix.Id, AR_Proposed_TJM__c = 999);
        System.assert(false, 'Le verrou post-décision doit rester actif');
      } catch (DmlException e) {
        System.assert(e.getMessage().contains('ne peut plus être modifiée'), e.getMessage());
      }
    }
  }

  @IsTest
  static void testCollect_tribunalResolution_priorityFormInputOverEntityOverGlobal() {
    cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1];
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefId('Abylsen SIGMA'),
      AR_Consultant_Name__c = 'Jean DUPONT',
      AR_Client_Site__c = 'Paris La Défense',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    // Réglage global déployé avec le projet : le test dépend de cette valeur, donc on la vérifie.
    AR_PTF_Setting__mdt settings = AR_PTF_Setting__mdt.getInstance('Default');
    System.assertEquals('Tribunal de Commerce de Lyon', settings?.AR_Default_Tribunal_Competent__c);

    // 1. Saisie du formulaire prioritaire sur l'entité et sur le global
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.tribunalCompetent = 'Tribunal saisi par l\'utilisateur';
    input.templateCode = 'ABYLSEN_AT_V11';
    input.valideurNom = 'Valideur Test'; // autre blocage de génération, sans rapport avec le tribunal
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, input, 1, true);
    System.assertEquals('Tribunal saisi par l\'utilisateur', data.tribunalCompetent);

    // 2. Formulaire vide : le tribunal de l'entité
    input.tribunalCompetent = '';
    data = AR_PTFDataService.collect(matrix.Id, input, 1, true);
    System.assertEquals('Tribunal de Commerce de Nanterre (FICTIF)', data.tribunalCompetent);

    // 3. Formulaire et entité vides : le réglage global. Blocages de génération désactivés ici :
    // l'entité de test n'a pas de coordonnées bancaires (autre blocage, sans rapport).
    AR_PTF_Entity_Referential__c emptyEntity = new AR_PTF_Entity_Referential__c(
      Name = 'Entité sans tribunal'
    );
    insert emptyEntity;
    AR_TriggerBypass.serviceContext = true;
    try {
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Entity_Ref__c = emptyEntity.Id);
    } finally {
      AR_TriggerBypass.serviceContext = false;
    }
    data = AR_PTFDataService.collect(matrix.Id, input, 1, false);
    System.assertEquals('Tribunal de Commerce de Lyon', data.tribunalCompetent);
  }

  @IsTest
  static void testTribunalBlockError_rule() {
    System.runAs(AR_TestPersona.francais()) {
      String msg = AR_PTFDataService.tribunalBlockError('ABYLSEN_AT_V11', null);
      System.assert(msg != null && msg.contains('Tribunal de commerce non renseigné'), msg);
      System.assert(msg.contains('réglage global'), msg);
      System.assertNotEquals(null, AR_PTFDataService.tribunalBlockError('ABYLSEN_AT_V11', ''));
      System.assertNotEquals(null, AR_PTFDataService.tribunalBlockError('ABYLSEN_AT_V11', '   '));
      // Renseigné (formulaire, entité ou global) : pas de blocage
      System.assertEquals(null, AR_PTFDataService.tribunalBlockError('ABYLSEN_AT_V11', 'Tribunal de Commerce de Lyon'));
      // Gabarits qui n'impriment pas le tribunal : jamais de blocage, même vide
      System.assertEquals(null, AR_PTFDataService.tribunalBlockError('AVENANT_AT_V11', null));
      System.assertEquals(null, AR_PTFDataService.tribunalBlockError('ABMI_DQ012', null));
    }
  }

  @IsTest
  static void testMissingFieldsForTemplate_tribunalOnlyIfEntityAndGlobalEmpty() {
    System.runAs(AR_TestPersona.francais()) {
      AR_PTF_Entity_Referential__c noTribunal = new AR_PTF_Entity_Referential__c(
        Name = 'Entité sans tribunal diag',
        AR_Bank_Name__c = 'Banque',
        AR_Rib__c = 'RIB',
        AR_Iban__c = 'IBAN',
        AR_Bic__c = 'BIC'
      );
      // Entité vide + global vide : manque signalé
      String missing = AR_PTFDataService.missingFieldsForTemplate('ABYLSEN_AT_V11', noTribunal, null);
      System.assert(missing != null && missing.contains('Tribunal de commerce'), missing);
      // Entité vide + global renseigné : pas d'avertissement
      System.assertEquals(
        null,
        AR_PTFDataService.missingFieldsForTemplate('ABYLSEN_AT_V11', noTribunal, 'Tribunal de Commerce de Lyon')
      );
      // Entité renseignée + global vide : pas d'avertissement
      noTribunal.AR_Tribunal_Competent__c = 'Tribunal de Commerce de Nanterre';
      System.assertEquals(null, AR_PTFDataService.missingFieldsForTemplate('ABYLSEN_AT_V11', noTribunal, null));
    }
  }

  @IsTest
  static void testGetEntityReadinessByTemplate_tribunalDefaultUsed_noIssue() {
    // Entité sans tribunal mais réglage global « Lyon » déployé : aucun avertissement tribunal.
    AR_PTF_Entity_Referential__c emptyEntity = new AR_PTF_Entity_Referential__c(
      Name = 'Entité sans tribunal pour readiness'
    );
    insert emptyEntity;

    cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c LIMIT 1];
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Brouillon',
      AR_Account_Name__c = 'Client PTF',
      AR_Entity_Ref__c = emptyEntity.Id,
      AR_Consultant_Name__c = 'Jean DUPONT',
      AR_Client_Site__c = 'Paris La Défense',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 10, 31)
    );
    insert matrix;

    Map<String, String> readiness = AR_PTFDataService.getEntityReadinessByTemplate(matrix.Id);
    // Abylsen est signalé (coordonnées bancaires absentes) mais pas pour le tribunal.
    System.assert(readiness.containsKey('ABYLSEN_AT_V11'), 'Les coordonnées bancaires manquent');
    System.assert(!readiness.get('ABYLSEN_AT_V11').contains('Tribunal'), readiness.get('ABYLSEN_AT_V11'));
  }

  // ---------------------------------------------------------------------------------------------
  // Session 176b — SIREN / NIC / SIRET imprimés une seule fois (dédoublonnage au rendu, pas en base)
  // ---------------------------------------------------------------------------------------------

  @IsTest
  static void testDedupeSirenNic_sirenAndNicOnLegalLine_keepsNameAndTva() {
    String bloc = 'EUROPLAZA – Bât. C1\n1 rue Claude Chappe\n57070 METZ\nFrance\n' +
      'Entité juridique : ABYLSEN EST – SIREN 487915605 – TVA FR46487915605 – NIC 00041';

    String result = AR_PTFDataService.dedupeSirenNic(bloc, '48791560500041');

    System.assertEquals(
      'EUROPLAZA – Bât. C1\n1 rue Claude Chappe\n57070 METZ\nFrance\nEntité juridique : ABYLSEN EST – TVA FR46487915605',
      result
    );
  }

  @IsTest
  static void testDedupeSirenNic_sirenNicLineAlone_lineDroppedTvaKept() {
    String bloc = '91 Avenue des Champs Elysées\n75008 PARIS\nFrance\nSIREN 519502462 – NIC 00020\nTVA FR56519502462';

    String result = AR_PTFDataService.dedupeSirenNic(bloc, '51950246200020');

    System.assertEquals('91 Avenue des Champs Elysées\n75008 PARIS\nFrance\nTVA FR56519502462', result);
  }

  @IsTest
  static void testDedupeSirenNic_explicitSiretFragment_removedRcsKept() {
    String bloc = '10 rue du Général de Castelnau\n67000 STRASBOURG\nFrance\nSIRET 83536795400012 – RCS Strasbourg\nTVA FR40835367954';

    String result = AR_PTFDataService.dedupeSirenNic(bloc, '83536795400012');

    System.assert(!result.contains('83536795400012'), 'Le SIRET ne doit plus figurer dans le bloc : ' + result);
    System.assert(result.contains('RCS Strasbourg'), 'Le RCS doit rester : ' + result);
    System.assert(result.contains('TVA FR40835367954'), 'La TVA doit rester : ' + result);
  }

  @IsTest
  static void testDedupeSirenNic_removedLine_neverLeavesEmptyLine_session182() {
    // Session 182 : la ligne SIREN/NIC retirée, au milieu, en fin de bloc ou avec des fins de ligne
    // Windows, ne laisse jamais de ligne vide derrière elle (celles de la source restent intactes).
    String milieu = 'Rue A\nSIREN 519502462 – NIC 00020\nTVA FR56519502462';
    String fin = 'Rue A\nTVA FR56519502462\nSIREN 519502462 – NIC 00020';
    String windows = 'Rue A\r\nSIREN 519502462 – NIC 00020\r\nTVA FR56519502462';
    for (String bloc : new List<String>{ milieu, fin, windows }) {
      String result = AR_PTFDataService.dedupeSirenNic(bloc, '51950246200020');
      System.assert(!result.contains('SIREN'), result);
      System.assert(!result.contains('\n\n') && !result.endsWith('\n') && !result.startsWith('\n'), 'Ligne vide : ' + result);
      System.assert(result.replace('\r', '').split('\n').size() == 2, 'Deux lignes attendues : ' + result);
    }
    // Un saut de ligne déjà présent dans la source n'est pas retiré.
    System.assertEquals('Rue A\n\nTVA X', AR_PTFDataService.dedupeSirenNic('Rue A\n\nTVA X\nSIREN 519502462 – NIC 00020', '51950246200020'));
  }

  @IsTest
  static void testDedupeSirenNic_sirenWithoutSirenInBlock_returnedUnchanged() {
    String bloc = 'Avenue Louise 140\n1050 BRUXELLES\nBelgique\nTVA BE0841565664';

    System.assertEquals(bloc, AR_PTFDataService.dedupeSirenNic(bloc, '48791560500041'));
  }

  @IsTest
  static void testDedupeSirenNic_italianPivaAndForeignNumbers_neverTouched() {
    String italie = 'Via Raimondo Montecuccoli 2\n10121 TORINO (TO)\nItalie\nEntité juridique : ABYLSEN ITALIA S.R.L. (socio unico)\n' +
      'P.IVA / Codice Fiscale 12539860010 – REA TO-1297675\nTVA IT12539860010';
    // Fiche italienne : aucun SIRET → bloc intact.
    System.assertEquals(italie, AR_PTFDataService.dedupeSirenNic(italie, null));
    // Même avec un SIRET français sans rapport, la P.IVA (11 chiffres) n'est pas un fragment SIREN.
    System.assertEquals(italie, AR_PTFDataService.dedupeSirenNic(italie, '48791560500041'));
    // SIREN d'un autre numéro que celui du SIRET : information distincte, conservée.
    String autre = 'Rue X\nSIREN 111111111 – NIC 00099';
    System.assertEquals(autre, AR_PTFDataService.dedupeSirenNic(autre, '48791560500041'));
  }

  @IsTest
  static void testDedupeSirenNic_invalidOrBlankInput_returnedUnchanged() {
    System.assertEquals('SIREN 487915605', AR_PTFDataService.dedupeSirenNic('SIREN 487915605', '4879'));
    System.assertEquals('SIREN 487915605', AR_PTFDataService.dedupeSirenNic('SIREN 487915605', ''));
    System.assertEquals(null, AR_PTFDataService.dedupeSirenNic(null, '48791560500041'));
  }

  @IsTest
  static void testCollect_sirenDedupe_genericDedupedAbmiKeepsBlockIntact() {
    String bloc = 'Bâtiment CITYLIFE\n28 Allée d\'Aquitaine\n92000 NANTERRE\nFrance\n' +
      'Entité juridique : ABMI GROUPE SAS – SIREN 391027620 – TVA FR83391027620 – NIC 00155';
    update new AR_PTF_Entity_Referential__c(
      Id = AR_TestPersona.entityRefId('ABMI Groupe'),
      AR_Address__c = bloc,
      AR_Siret__c = '39102762000155',
      AR_Rib__c = '00000 00000 00000000000 00 (FICTIF test)'
    );
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée', AR_Entity_Ref__c = AR_TestPersona.entityRefId('ABMI Groupe'));

    AR_PTFDataService.GenerationInput generic = new AR_PTFDataService.GenerationInput();
    generic.matrixId = matrix.Id;
    generic.templateCode = 'ABYLSEN_AT_V11'; // 184c3 : gabarit qui imprime le SIRET (le générique est retiré)
    generic.valideurNom = 'Valideur Test';
    AR_PTFData dataGeneric = AR_PTFDataService.collect(matrix.Id, generic, 1);

    AR_PTFDataService.GenerationInput abmi = new AR_PTFDataService.GenerationInput();
    abmi.matrixId = matrix.Id;
    abmi.templateCode = 'ABMI_DQ012';
    abmi.valideurNom = 'Valideur Test';
    abmi.valideurFonction = 'Fonction Test';
    AR_PTFData dataAbmi = AR_PTFDataService.collect(matrix.Id, abmi, 1);

    System.assertEquals('39102762000155', dataGeneric.entiteInfo.siret);
    System.assert(!dataGeneric.entiteInfo.adresse.contains('SIREN'), 'Gabarit qui imprime le SIRET : plus de SIREN dans le bloc (la TVA, elle, reprend ces chiffres et reste) : ' + dataGeneric.entiteInfo.adresse);
    System.assert(!dataGeneric.entiteInfo.adresse.contains('NIC'), 'Plus de NIC dans le bloc : ' + dataGeneric.entiteInfo.adresse);
    System.assert(dataGeneric.entiteInfo.adresse.contains('TVA FR83391027620'), 'La TVA reste : ' + dataGeneric.entiteInfo.adresse);
    System.assertEquals(bloc, dataAbmi.entiteInfo.adresse, 'ABMI n\'imprime pas le SIRET : son bloc reste intact');
  }

  // ---- Session 182 : l'avertissement d'entité ne porte que sur le gabarit réellement résolu ----

  private static List<String> entityWarnings(AR_Price_Matrix__c matrix) {
    List<String> labels = new List<String>();
    for (AR_PTFDataService.Prerequisite p : AR_PTFDataService.validationPrerequisites(matrix)) {
      if (p.label.startsWith('Entité')) {
        labels.add(p.label);
        System.assertEquals(false, p.blocking, 'Un avertissement d\'entité ne bloque jamais la validation');
      }
    }
    return labels;
  }

  @IsTest
  static void testValidationPrerequisites_entityWithoutOwnTemplate_noWarningForOtherTemplates() {
    // 'Abylsen GAMMA' : aucun coordonnée, aucun gabarit propre, aucun gabarit de compte → générique,
    // qui ne réclame rien. Avant la 182, les gabarits ABMI/Abylsen/avenant étaient signalés à tort.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c, AR_Entity_Ref__c, AR_Seniority__c, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c FROM AR_Price_Matrix__c LIMIT 1];
    System.assertEquals(
      new List<String>(),
      entityWarnings(matrix),
      'Résolu au générique : aucun avertissement pour des gabarits qui ne seront pas utilisés'
    );
  }

  @IsTest
  static void testValidationPrerequisites_entityTemplateIncomplete_warnsOnThatTemplateOnly() {
    System.runAs(AR_TestPersona.francais()) {
      AR_PTF_Entity_Referential__c e = new AR_PTF_Entity_Referential__c(
        Name = 'S182 Abylsen sans RIB', AR_Active__c = true, AR_Template_Code__c = 'ABYLSEN_AT_V11'
      );
      insert e;
      AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c, AR_Entity_Ref__c, AR_Seniority__c, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c FROM AR_Price_Matrix__c LIMIT 1];
      matrix.AR_Entity_Ref__c = e.Id;

      List<String> warnings = entityWarnings(matrix);

      System.assertEquals(1, warnings.size(), 'Un seul avertissement : le gabarit résolu. ' + warnings);
      System.assert(warnings[0].contains(AR_PTFDataService.TEMPLATE_LABELS.get('ABYLSEN_AT_V11')), warnings[0]);
      System.assert(!warnings[0].contains(AR_PTFDataService.TEMPLATE_LABELS.get('ABMI_DQ012')), warnings[0]);
    }
  }

  @IsTest
  static void testValidationPrerequisites_accountTemplateWinsOverEntityTemplate() {
    System.runAs(AR_TestPersona.francais()) {
      // Entité complète pour le générique, grand compte sur ABMI_DQ012 : l'entité (sans coordonnées
      // d'établissement) est signalée pour ABMI — le gabarit du compte, pas celui de l'entité.
      AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c, AR_Entity_Ref__c, AR_Seniority__c, AR_Client_Site__c, AR_Start_Date__c, AR_End_Date__c FROM AR_Price_Matrix__c LIMIT 1];
      cxsrec__cxsPosition__c position = [
        SELECT cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Id = :matrix.AR_Position__c
      ];
      insert new AR_Account_Commercial_Data__c(
        AR_Account__c = position.cxsrec__Account__c,
        AR_PTF_Template_Code__c = 'ABMI_DQ012'
      );

      List<String> warnings = entityWarnings(matrix);

      System.assertEquals(1, warnings.size(), warnings.toString());
      System.assert(warnings[0].contains(AR_PTFDataService.TEMPLATE_LABELS.get('ABMI_DQ012')), warnings[0]);
    }
  }

  @IsTest
  static void testExpectedTemplateCode_priorityAccountThenEntityThenAbylsenDefault() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    Id accountId = [SELECT cxsrec__Account__c FROM cxsrec__cxsPosition__c WHERE Id = :matrix.AR_Position__c].cxsrec__Account__c;
    AR_PTF_Entity_Referential__c withCode = new AR_PTF_Entity_Referential__c(AR_Template_Code__c = 'ABYLSEN_AT_V11');
    AR_PTF_Entity_Referential__c withoutCode = new AR_PTF_Entity_Referential__c();

    System.assertEquals('ABYLSEN_AT_V11', AR_PTFDataService.expectedTemplateCode(accountId, withoutCode));
    System.assertEquals('ABYLSEN_AT_V11', AR_PTFDataService.expectedTemplateCode(null, null));
    System.assertEquals('ABYLSEN_AT_V11', AR_PTFDataService.expectedTemplateCode(accountId, withCode));
    insert new AR_Account_Commercial_Data__c(AR_Account__c = accountId, AR_PTF_Template_Code__c = 'ABMI_DQ012');
    System.assertEquals('ABMI_DQ012', AR_PTFDataService.expectedTemplateCode(accountId, withCode));
  }

  // Session 184f : le code de gabarit posé sur un compte vaut pour ses comptes enfants, le plus proche gagne.
  @IsTest
  static void testExpectedTemplateCode_inheritedFromAncestor_nearestWins() {
    Database.DMLOptions allowDuplicates = new Database.DMLOptions();
    allowDuplicates.duplicateRuleHeader.allowSave = true;
    allowDuplicates.optAllOrNone = true;
    Account grandParent = new Account(Name = 'S184f PTF GP', AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT', ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001');
    Database.insert(grandParent, allowDuplicates);
    Account parent = new Account(Name = 'S184f PTF Parent', ParentId = grandParent.Id, AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT', ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001');
    Database.insert(parent, allowDuplicates);
    Account child = new Account(Name = 'S184f PTF Enfant', ParentId = parent.Id, AB_Account_industry__c = 'IT / Telecoms', TP_Business_Line__c = 'IT', ShippingStreet = '1 rue de Test', ShippingCity = 'Paris', ShippingPostalCode = '75001');
    Database.insert(child, allowDuplicates);
    AR_PTF_Entity_Referential__c noCode = new AR_PTF_Entity_Referential__c();

    insert new AR_Account_Commercial_Data__c(AR_Account__c = grandParent.Id, AR_PTF_Template_Code__c = 'ABMI_DQ012');
    System.assertEquals('ABMI_DQ012', AR_PTFDataService.expectedTemplateCode(child.Id, noCode), 'Hérité du grand-parent');

    insert new AR_Account_Commercial_Data__c(AR_Account__c = parent.Id, AR_PTF_Template_Code__c = 'ABYLSEN_AT_V11');
    System.assertEquals('ABYLSEN_AT_V11', AR_PTFDataService.expectedTemplateCode(child.Id, noCode), 'Le parent, plus proche, prime');
    System.assertEquals('ABMI_DQ012', AR_PTFDataService.expectedTemplateCode(grandParent.Id, noCode), 'Le grand-parent garde le sien');
  }
  // ------------------------------------------------------------------
  // TJM par périodes (docs/254d) — dates de bascule saisies, échéancier, relecture d'anciens snapshots.
  // Fixture : mission du mardi 1er sept. au samedi 31 oct. 2026 = 22 jours ouvrés en septembre + 22 en
  // octobre (44), TJM 700 puis 750 à partir du jeudi 1er oct. (22 jours de période 1).
  // ------------------------------------------------------------------

  private static List<AR_PTFData.TjmPeriodRow> twoPeriods(Date secondStart) {
    AR_PTFData.TjmPeriodRow p1 = new AR_PTFData.TjmPeriodRow();
    p1.index = 1;
    p1.dateDebut = Date.newInstance(2026, 9, 1);
    p1.tjm = 700;
    AR_PTFData.TjmPeriodRow p2 = new AR_PTFData.TjmPeriodRow();
    p2.index = 2;
    p2.dateDebut = secondStart;
    p2.tjm = 750;
    return new List<AR_PTFData.TjmPeriodRow>{ p1, p2 };
  }

  private static AR_Price_Matrix__c matrixWithPeriods() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_Number_Of_Days__c = 44,
      AR_TJM_Periods__c = '[{"days":22,"tjm":750}]'
    );
    return matrix;
  }

  @IsTest
  static void testEstimatedPeriodStart_countsBusinessDaysFromMissionStart() {
    System.assertEquals(
      Date.newInstance(2026, 10, 1),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2026, 9, 1), 22, null),
      '22 jours ouvrés en septembre 2026 : la période suivante commence le 1er octobre'
    );
    System.assertEquals(Date.newInstance(2026, 9, 1), AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2026, 9, 1), 0, null));
    System.assertEquals(
      Date.newInstance(2026, 9, 7),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2026, 9, 5), 0, null),
      'Début un samedi : premier jour ouvré = lundi'
    );
    System.assertEquals(null, AR_PTFDataService.estimatedPeriodStart(null, 5, null));
  }

  // Session 274 : calendrier ouvré unique — jamais un férié ni un week-end comme date estimée.
  @IsTest
  static void testEstimatedPeriodStart_skipsFrenchHolidays() {
    // Mission au 03/05/2027 : 3 jours ouvrés (03, 04, 05) puis le 06/05 est l'Ascension → 07/05.
    System.assertEquals(
      Date.newInstance(2027, 5, 7),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2027, 5, 3), 3, 'France')
    );
    System.assertEquals(
      Date.newInstance(2027, 5, 6),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2027, 5, 3), 3, 'Allemagne'),
      'Pays sans calendrier : week-ends seuls'
    );
    System.assertEquals(
      Date.newInstance(2027, 5, 7),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2027, 5, 3), 3, 'Belgique'),
      'Belgique : l\'Ascension (06/05) est aussi férié (calendrier belge, session 288)'
    );
    System.assertEquals(
      Date.newInstance(2027, 1, 4),
      AR_PTFDataService.estimatedPeriodStart(Date.newInstance(2027, 1, 1), 0, 'France'),
      '1er janvier férié, 02-03 week-end : le premier jour ouvré est le 04/01'
    );
  }

  @IsTest
  static void testBuildSchedule_frenchHolidaysAreNotWorkingDays() {
    Date start = Date.newInstance(2027, 1, 1);
    Date finish = Date.newInstance(2027, 3, 31);
    List<AR_PTFData.ScheduleRow> france = AR_PTFDataService.buildSchedule(
      start, finish, 700, 18, 1, null, false, null, null, 'France'
    );
    System.assertEquals(3, france.size());
    System.assertEquals(20, france[0].jours, 'Janvier 2027 : le 1er janvier ne compte pas');
    List<AR_PTFData.ScheduleRow> sansPays = AR_PTFDataService.buildSchedule(
      start, finish, 700, 18, 1, null, false, null, null, null
    );
    System.assertEquals(21, sansPays[0].jours, 'Sans pays : week-ends seuls');
    // Total saisi à la main : redistribution proportionnelle, Σ des lots = total saisi.
    List<AR_PTFData.ScheduleRow> manual = AR_PTFDataService.buildSchedule(
      start, finish, 700, 18, 1, 60, false, null, null, 'France'
    );
    Decimal sum = 0;
    for (AR_PTFData.ScheduleRow row : manual) {
      sum += row.jours;
    }
    System.assertEquals(60, sum, 'Σ des lots = total saisi');
  }

  @IsTest
  static void testBuildSchedule_periods_switchOnMonthBoundary() {
    List<AR_PTFData.TjmPeriodRow> periodes = twoPeriods(Date.newInstance(2026, 10, 1));
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 1), Date.newInstance(2026, 10, 31), 700, 18, 1, null, false, periodes
    );
    System.assertEquals(2, rows.size());
    System.assertEquals(22 * 700, rows[0].montant, 'Septembre entièrement à 700');
    System.assertEquals(22 * 750, rows[1].montant, 'Octobre entièrement à 750');
    System.assertEquals(31900, rows[1].cumul, 'Total HT = somme des lignes');
    System.assertEquals(15400, periodes[0].montant);
    System.assertEquals(16500, periodes[1].montant);
    System.assertEquals(22, periodes[0].jours);
    System.assertEquals(22, periodes[1].jours);
  }

  @IsTest
  static void testBuildSchedule_periods_monthStraddlingGivesOneMixedLine() {
    // Bascule le 15/09 : 10 jours ouvrés à 700 (1–14), 12 à 750 (15–30).
    List<AR_PTFData.TjmPeriodRow> periodes = twoPeriods(Date.newInstance(2026, 9, 15));
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 1), Date.newInstance(2026, 10, 31), 700, 18, 1, null, false, periodes
    );
    System.assertEquals(2, rows.size(), 'Une seule ligne par mois, pas de ligne séparée à la bascule');
    System.assertEquals(10 * 700 + 12 * 750, rows[0].montant, 'Montant mixte de septembre');
    System.assertEquals(22 * 750, rows[1].montant);
    Decimal sommePeriodes = periodes[0].montant + periodes[1].montant;
    System.assertEquals(rows[1].cumul, sommePeriodes, 'Σ montants par période = total des lignes');
    System.assertEquals(10, periodes[0].jours);
    System.assertEquals(34, periodes[1].jours);
  }

  @IsTest
  static void testBuildSchedule_periods_lisseTotalIsTheSumOfTheLines() {
    List<AR_PTFData.TjmPeriodRow> periodes = twoPeriods(Date.newInstance(2026, 10, 1));
    List<AR_PTFData.ScheduleRow> rows = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 1), Date.newInstance(2026, 10, 31), 700, 18.17, 1, null, true, periodes
    );
    System.assertEquals(2, rows.size());
    System.assertEquals((700 * 18.17).setScale(0, RoundingMode.HALF_UP), rows[0].montant, 'Mois complet de période 1');
    System.assertEquals((750 * 18.17).setScale(0, RoundingMode.HALF_UP), rows[1].montant, 'Mois complet de période 2');
    System.assertEquals(rows[0].montant + rows[1].montant, rows[1].cumul);
    System.assertEquals(rows[1].cumul, periodes[0].montant + periodes[1].montant);
  }

  @IsTest
  static void testBuildSchedule_periods_nullOrSinglePeriodIsTheHistoricalCode() {
    List<AR_PTFData.ScheduleRow> avant = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 15), Date.newInstance(2026, 10, 31), 700, 18, 1, null, false
    );
    List<AR_PTFData.ScheduleRow> sansPeriode = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 15), Date.newInstance(2026, 10, 31), 700, 18, 1, null, false, null
    );
    List<AR_PTFData.ScheduleRow> uneSeule = AR_PTFDataService.buildSchedule(
      Date.newInstance(2026, 9, 15), Date.newInstance(2026, 10, 31), 700, 18, 1, null, false,
      new List<AR_PTFData.TjmPeriodRow>{ twoPeriods(null)[0] }
    );
    System.assertEquals(JSON.serialize(avant), JSON.serialize(sansPeriode));
    System.assertEquals(JSON.serialize(avant), JSON.serialize(uneSeule));
  }

  @IsTest
  static void testCollect_periods_datesFeedLabelScheduleAndTotal() {
    AR_Price_Matrix__c matrix = matrixWithPeriods();
    AR_PTFDataService.GenerationInput input = validatedInput(matrix);
    input.tjmPeriodStarts = new List<String>{ '2026-10-01' };
    AR_PTFData d = AR_PTFDataService.collect(matrix.Id, input, 1);
    System.assertEquals(700, d.tjm, 'd.tjm reste le TJM de la période 1');
    System.assertEquals(2, d.tjmPeriodes.size());
    System.assertEquals(Date.newInstance(2026, 10, 1), d.tjmPeriodes[1].dateDebut);
    System.assertEquals(Date.newInstance(2026, 9, 30), d.tjmPeriodes[0].dateFin);
    System.assertEquals(31900, d.totalHT);
    String label = AR_PTFFormatUtil.tjmPeriodesLabel(d.tjmPeriodes, d.currencyCode);
    System.assertEquals(
      '700' + AR_PTFFormatUtil.NBSP + '€ HT/jour jusqu\'au 30/09/2026, puis 750' + AR_PTFFormatUtil.NBSP +
      '€ HT/jour à partir du 01/10/2026',
      label
    );
  }

  @IsTest
  static void testCollect_periods_strictDateErrorsAreNamed() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = matrixWithPeriods();
      Map<String, List<String>> cases = new Map<String, List<String>>{
        'manquante' => new List<String>(),
        'illisible' => new List<String>{ 'pas une date' },
        'ordre' => new List<String>{ '2026-09-01' },
        'mission' => new List<String>{ '2026-11-02' }
      };
      AR_PTFDataService.GenerationInput input = validatedInput(matrix);
      for (String name : cases.keySet()) {
        input.tjmPeriodStarts = cases.get(name);
        try {
          AR_PTFDataService.collect(matrix.Id, input, 1);
          System.assert(false, 'Cas ' + name + ' : une exception est attendue');
        } catch (AuraHandledException e) {
          System.assert(e.getMessage().contains('période 2'), 'Cas ' + name + ' : ' + e.getMessage());
        }
      }
    }
  }

  @IsTest
  static void testGetGenerationDefaults_periods_prefillsEstimatedStartDate() {
    AR_Price_Matrix__c matrix = matrixWithPeriods();
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFData d = AR_PTFDataService.getGenerationDefaults(matrix.Id);
    System.assertEquals(2, d.tjmPeriodes.size());
    System.assertEquals(
      Date.newInstance(2026, 10, 1),
      d.tjmPeriodes[1].dateDebut,
      '22 jours de période 1 : 23e jour ouvré = 1er octobre'
    );
  }

  @IsTest
  static void testPreviewPtfLots_periods_followTheEnteredDate() {
    AR_Price_Matrix__c matrix = matrixWithPeriods();
    List<AR_PTFData.LotRow> estimees = AR_PTFDataService.previewPtfLots(matrix.Id, false, null);
    List<AR_PTFData.LotRow> saisies = AR_PTFDataService.previewPtfLots(matrix.Id, false, new List<String>{ '2026-09-15' });
    System.assertNotEquals(0, estimees.size());
    Decimal totalEstime = 0;
    for (AR_PTFData.LotRow l : estimees) {
      totalEstime += l.montant;
    }
    Decimal totalSaisi = 0;
    for (AR_PTFData.LotRow l : saisies) {
      totalSaisi += l.montant;
    }
    System.assertEquals(31900, totalEstime);
    System.assertEquals(10 * 700 + 12 * 750 + 22 * 750, totalSaisi, 'Bascule le 15/09 : plus de jours à 750');
  }

  @IsTest
  static void testSnapshotBeforeTjmPeriodes_frozenFixtureRehydratesAsNoPeriods() {
    // Snapshot figé tel qu'écrit avant la session 254d : aucune clé tjmPeriodes.
    String frozen = '{"reference":"PTF-ANCIEN-V1","client":"Client Ancien","tjm":650,"currencyCode":"EUR",'
      + '"totalHT":28600,"schedule":[{"mois":"septembre 2026","jours":22,"montant":14300,"cumul":14300},'
      + '{"mois":"octobre 2026","jours":22,"montant":14300,"cumul":28600}]}';
    AR_PTFData ancien = (AR_PTFData) JSON.deserialize(frozen, AR_PTFData.class);
    System.assertEquals('PTF-ANCIEN-V1', ancien.reference);
    System.assertEquals(650, ancien.tjm);
    System.assertEquals(null, ancien.tjmPeriodes, 'Clé absente : lue comme aucune période (chemin actuel)');
    System.assertEquals(null, AR_PTFFormatUtil.tjmPeriodesLabel(ancien.tjmPeriodes, ancien.currencyCode));
  }

  @IsTest
  static void testSnapshotWithTjmPeriodes_roundTrips() {
    AR_PTFData d = new AR_PTFData();
    d.tjm = 700;
    d.tjmPeriodes = twoPeriods(Date.newInstance(2026, 10, 1));
    d.tjmPeriodes[0].dateFin = Date.newInstance(2026, 9, 30);
    d.tjmPeriodes[0].jours = 22;
    d.tjmPeriodes[0].montant = 15400;
    AR_PTFData back = (AR_PTFData) JSON.deserialize(JSON.serialize(d), AR_PTFData.class);
    System.assertEquals(700, back.tjm);
    System.assertEquals(2, back.tjmPeriodes.size());
    System.assertEquals(Date.newInstance(2026, 10, 1), back.tjmPeriodes[1].dateDebut);
    System.assertEquals(750, back.tjmPeriodes[1].tjm);
    System.assertEquals(15400, back.tjmPeriodes[0].montant);
  }

  @IsTest
  static void testLabel_threePeriodsChainAndGbpSymbol() {
    List<AR_PTFData.TjmPeriodRow> three = twoPeriods(Date.newInstance(2026, 10, 1));
    AR_PTFData.TjmPeriodRow p3 = new AR_PTFData.TjmPeriodRow();
    p3.index = 3;
    p3.dateDebut = Date.newInstance(2026, 12, 1);
    p3.tjm = 800;
    three.add(p3);
    String nb = AR_PTFFormatUtil.NBSP;
    System.assertEquals(
      '700' + nb + '£ HT/jour jusqu\'au 30/09/2026, puis 750' + nb + '£ HT/jour à partir du 01/10/2026, puis 800' + nb +
      '£ HT/jour à partir du 01/12/2026',
      AR_PTFFormatUtil.tjmPeriodesLabel(three, 'GBP')
    );
    System.assertEquals('de 700 à 800' + nb + '£/j', AR_PTFFormatUtil.tjmRangeLabel(three, 'GBP'));
  }
}