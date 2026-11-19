/**
 * Tests AR_PTFGenerationService : gating serveur, snapshot immuable + fichier Salesforce Files,
 * régénération (nouveau document, jamais un écrasement), rendu en deux appels séparés (session 20b).
 *
 * generatePTF/generatePTFInput insère le snapshot et rend la main ; renderAndStorePTF, appelé
 * séparément par le LWC dans un second aller-retour, rend le PDF et le stocke — cf. commentaire
 * d'en-tête de AR_PTFGenerationService pour les deux approches essayées et écartées (rendu
 * synchrone dans la même transaction que l'insertion : le PDF se rend vide ; rendu via Queueable :
 * `getContentAsPDF()` lève CalloutException, interdit depuis tout contexte asynchrone).
 *
 * Le rendu PDF réel (Visualforce getContentAsPDF) n'est pas exécutable en contexte de test —
 * Test.isRunningTest() y substitue un Blob factice (cf. AR_PTFGenerationService.renderPdf) ; la
 * couverture porte donc sur l'orchestration (gating, snapshot, Files, versionnement, statut), pas
 * sur le rendu visuel du gabarit — cf. AR_PTFTemplateControllerTest pour la lecture du snapshot.
 *
 * Comme AR_MatrixVersionServiceTest, aucun utilisateur de test restreint n'est créé pour vérifier
 * l'absence de droit d'édition FLS sur AR_PTF_Document__c (immuabilité) : la création d'un User dans
 * cet org managé est jugée trop fragile pour ce jalon (licences, hiérarchie de rôles). La garantie
 * "aucun écrasement" testée ici est celle que le code produit réellement : une régénération insère
 * un nouveau AR_PTF_Document__c et ne modifie jamais le snapshot d'une version précédente.
 */
@IsTest
private class AR_PTFGenerationServiceTest {
  @TestSetup
  static void setup() {
    Account acc = new Account(
      Name = 'Client PTF Gen',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001'
    );
    insert acc;

    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin PTF Gen',
      cxsrec__Account__c = acc.Id,
      cxsrec__Country__c = 'France',
      cxsrec__Status__c = 'Open',
      cxsrec__Contract_type__c = 'CDI'
    );
    insert position;

    insert new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Brouillon',
      AR_Account_Name__c = 'Client PTF Gen',
      AR_Entity_Ref__c = AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'),
      AR_Consultant_Name__c = 'Paul MARTIN',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 9, 30)
    );
  }

  private static AR_PTFDataService.GenerationInput inputFor(Id matrixId) {
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrixId;
    // Session 47 : le valideur est désormais un champ obligatoire du formulaire, pour tous les
    // gabarits (cf. AR_PTFDataService.requireValideur) — posé ici par défaut, comme
    // AR_PTFDataServiceTest.validatedInput.
    input.valideurNom = 'Valideur Test';
    // Session 138 : à partir du rang 2 un type de modification est obligatoire — valeur valide posée
    // par défaut (ignorée au rang 1), les tests dédiés la retirent explicitement.
    input.modificationType = 'Modification de montant';
    return input;
  }

  /**
   * Session 138 : seul un document au statut « Généré » compte dans l'historique (AR_PTFHistoryService
   * exclut « En cours » et « Échec ») — generatePTFInput laisse « En cours » jusqu'au rendu, que ces
   * tests n'exécutent pas : on reproduit l'état que le rendu réel produirait.
   */
  private static void markGenerated(Id ptfDocumentId) {
    update new AR_PTF_Document__c(Id = ptfDocumentId, AR_Generation_Status__c = 'Généré');
  }

  @IsTest
  static void testGeneratePTF_draftMatrix_throws() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];

      Test.startTest();
      try {
        AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));
        System.assert(
          false,
          'Générer une PTF depuis un brouillon doit être impossible côté serveur'
        );
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('validée'));
      }
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM AR_PTF_Document__c],
        'Aucun document ne doit avoir été créé pour une matrice non validée'
      );
    }
  }

  @IsTest
  static void testGeneratePTF_returnsImmediatelyWithSnapshotButNoFileYet() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    Test.stopTest();

    // Premier appel : retour immédiat, avant tout rendu. Le snapshot fait foi tout de suite, le
    // fichier arrive au second appel (renderAndStorePTF) — cf. docs/20-generation-ptf.md §4.5.
    System.assertEquals(1, result.versionNumber);
    System.assertNotEquals(null, result.ptfDocumentId);
    System.assertEquals(
      null,
      result.contentDocumentId,
      'Le fichier n\'est pas encore prêt au retour de generatePTFInput'
    );
    System.assertEquals('En cours', result.status);

    AR_PTF_Document__c doc = [
      SELECT AR_Price_Matrix__c, AR_Position__c, AR_Version_Number__c, AR_Reference__c,
             AR_Snapshot__c, AR_Content_Document_Id__c, AR_Generation_Status__c
      FROM AR_PTF_Document__c
      WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals(matrix.Id, doc.AR_Price_Matrix__c);
    System.assertEquals(matrix.AR_Position__c, doc.AR_Position__c);
    System.assertEquals(1, doc.AR_Version_Number__c);
    // C'est la garantie centrale de cette session : le snapshot est complet dès l'insertion
    // synchrone, indépendamment de la réussite ou de la lenteur du rendu PDF.
    System.assert(doc.AR_Snapshot__c.contains('"client":"Client PTF Gen"'));
    System.assert(doc.AR_Snapshot__c.contains('"consultantNom":"Paul MARTIN"'));
    System.assertEquals(null, doc.AR_Content_Document_Id__c);
    System.assertEquals('En cours', doc.AR_Generation_Status__c);
  }

  @IsTest
  static void testRenderAndStorePTF_afterGenerate_storesFileAndSetsStatusGenere() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult finished = AR_PTFGenerationService.renderAndStorePTF(
      started.ptfDocumentId
    );
    Test.stopTest();

    System.assertEquals('Généré', finished.status);
    System.assertNotEquals(null, finished.contentDocumentId);
    System.assertEquals(null, finished.errorMessage);

    AR_PTF_Document__c doc = [
      SELECT AR_Content_Document_Id__c, AR_Generation_Status__c, AR_Generation_Error__c
      FROM AR_PTF_Document__c
      WHERE Id = :started.ptfDocumentId
    ];
    System.assertEquals('Généré', doc.AR_Generation_Status__c);
    System.assertEquals(null, doc.AR_Generation_Error__c);
    System.assertNotEquals(null, doc.AR_Content_Document_Id__c);

    // Lié à la matrice ET au besoin (spec §4 « Stocker »).
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId = :doc.AR_Content_Document_Id__c
    ];
    Set<Id> linkedEntityIds = new Set<Id>();
    for (ContentDocumentLink link : links) {
      linkedEntityIds.add(link.LinkedEntityId);
    }
    System.assert(
      linkedEntityIds.contains(matrix.Id),
      'Le fichier doit être lié à la matrice'
    );
    System.assert(
      linkedEntityIds.contains(matrix.AR_Position__c),
      'Le fichier doit être lié au besoin Connexys'
    );
  }

  /**
   * Session 54 : les initiales de la référence de fichier (consultantTrigramme) doivent utiliser le
   * Name du consultant lié (AR_Consultant__c) plutôt que l'ancien texte libre (AR_Consultant_Name__c)
   * quand les deux sont renseignés et divergent — cf. AR_PTFDataService.collect (préférence posée là,
   * consultantTrigramme lui-même inchangé). Matrice/besoin/compte propres à ce test, jamais la
   * matrice unique du @TestSetup (19 lectures sans WHERE dans ce fichier).
   */
  @IsTest
  static void testRenderAndStorePTF_consultantLookupPresent_trigramFromRecordNotLegacyText() {
    Account acc = new Account(
      Name = 'Client Session54 GenLookup',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001'
    );
    insert acc;
    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin PTF Gen Consultant',
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
      AR_Account_Name__c = 'Client Session54 GenLookup',
      // Dernier mot distinct du Name du consultant, quel que soit son format — garantit que le trigramme du texte libre ("ZQW") ne peut jamais coïncider avec celui du Name réel.
      AR_Consultant_Name__c = 'Zoe QWERTY',
      AR_Consultant__c = consultant.Id,
      AR_Entity_Ref__c = AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'),
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 9, 30)
    );
    insert matrix;

    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );

    Test.startTest();
    AR_PTFGenerationService.renderAndStorePTF(started.ptfDocumentId);
    Test.stopTest();

    ContentVersion cv = [
      SELECT Title
      FROM ContentVersion
      WHERE FirstPublishLocationId = :matrix.Id
      LIMIT 1
    ];
    System.assert(
      !cv.Title.contains('ZQW'),
      'Le trigramme ne doit jamais venir du texte libre quand le lookup est renseigné, obtenu : ' + cv.Title
    );
    String expectedTrigram = expectedTrigram(consultant.Name);
    if (expectedTrigram != null) {
      System.assert(
        cv.Title.contains(expectedTrigram),
        'Le trigramme doit venir du Name du consultant lié (' + consultant.Name + '), obtenu : ' + cv.Title
      );
    }
  }

  /** Reproduit l'algorithme privé AR_PTFGenerationService.consultantTrigramme, pour ne jamais
   * supposer le format exact (Prénom Nom ou l'inverse) du Name managé par le package Connexys. */
  private static String expectedTrigram(String consultantName) {
    return AR_PTFGenerationService.userTrigramme(consultantName);
  }

  @IsTest
  static void testGeneratePTF_validatedByDerogation_succeeds() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(
      Id = matrix.Id,
      AR_Status__c = 'Validée par dérogation'
    );

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    AR_PTFGenerationService.PTFGenerationResult finished = AR_PTFGenerationService.renderAndStorePTF(
      started.ptfDocumentId
    );
    Test.stopTest();

    System.assertNotEquals(null, started.ptfDocumentId);
    System.assertEquals('Généré', finished.status);
  }

  @IsTest
  static void testGeneratePTF_regeneration_incrementsVersionAndPreservesPreviousSnapshot() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // Version 1 insérée directement (pas via le service) : cette assertion porte sur le
    // versionnement, pas sur le rendu — pas besoin de passer par generatePTFInput deux fois.
    AR_PTF_Document__c firstVersion = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Version 1 gelée"}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert firstVersion;

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult second = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    Test.stopTest();

    System.assertEquals(2, second.versionNumber);
    System.assertNotEquals(
      firstVersion.Id,
      second.ptfDocumentId,
      'Une régénération crée un nouveau document, jamais un écrasement (traçabilité du parcours de prix)'
    );

    List<AR_PTF_Document__c> docs = [
      SELECT Id, AR_Version_Number__c, AR_Snapshot__c
      FROM AR_PTF_Document__c
      WHERE AR_Price_Matrix__c = :matrix.Id
      ORDER BY AR_Version_Number__c ASC
    ];
    System.assertEquals(2, docs.size());
    System.assertEquals(
      '{"client":"Version 1 gelée"}',
      docs[0].AR_Snapshot__c,
      'Le snapshot de la première version ne doit jamais être modifié par une régénération ultérieure'
    );
  }

  @IsTest
  static void testGeneratePTF_blankPayload_throws() {
    System.runAs(AR_TestPersona.francais()) {
      Test.startTest();
      try {
        AR_PTFGenerationService.generatePTF('');
        System.assert(false, 'Un payload vide doit être rejeté avant toute désérialisation');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('vide'));
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void testGeneratePTF_jsonFacade_delegatesToGeneratePTFInput() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    String payload = JSON.serialize(inputFor(matrix.Id));

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTF(
      payload
    );
    Test.stopTest();

    System.assertEquals(1, result.versionNumber);
    System.assertNotEquals(null, result.ptfDocumentId);
  }

  @IsTest
  static void testRenderAndStorePTF_missingSnapshot_setsEchecStatusWithError() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-BROKEN',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = null,
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'En cours'
    );
    insert doc;

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.renderAndStorePTF(
      doc.Id
    );
    Test.stopTest();

    // Corollaire de la session 20b : un échec de rendu ne doit jamais produire un document
    // d'apparence normale mais vide — le statut et le message d'erreur le rendent visible.
    System.assertEquals('Échec', result.status);
    System.assertNotEquals(null, result.errorMessage);
    System.assert(result.errorMessage.contains('AR_PTFRenderException'));

    AR_PTF_Document__c reloaded = [
      SELECT AR_Generation_Status__c, AR_Generation_Error__c, AR_Content_Document_Id__c
      FROM AR_PTF_Document__c
      WHERE Id = :doc.Id
    ];
    System.assertEquals('Échec', reloaded.AR_Generation_Status__c);
    System.assertNotEquals(null, reloaded.AR_Generation_Error__c);
    System.assertEquals(null, reloaded.AR_Content_Document_Id__c);
  }

  // ------------------------------------------------------------------
  // Prévisualisation transitoire (session 30) — le test le plus important de cette partie.
  // ------------------------------------------------------------------

  @IsTest
  static void testBuildPreviewData_neverPersistsAnythingAndDoesNotConsumeVersionNumber() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    String payload = JSON.serialize(inputFor(matrix.Id));

    Test.startTest();
    String preview1 = AR_PTFGenerationService.buildPreviewData(payload);
    String preview2 = AR_PTFGenerationService.buildPreviewData(payload);
    Test.stopTest();

    // Aucune trace : ni AR_PTF_Document__c, ni ContentVersion — c'est la garantie centrale de la
    // prévisualisation (cf. docs/30-ptf-previsualisation-et-gabarits.md §2).
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AR_PTF_Document__c],
      'Une prévisualisation ne doit jamais insérer de document, même appelée plusieurs fois'
    );
    System.assertEquals(0, [SELECT COUNT() FROM ContentVersion]);

    AR_PTFData data1 = (AR_PTFData) JSON.deserialize(
      Blob.valueOf(EncodingUtil.base64Decode(preview1).toString()).toString(),
      AR_PTFData.class
    );
    System.assertEquals(true, data1.isPreview);
    System.assertEquals(
      'V1',
      data1.version,
      'Le numéro peeké doit être celui qu\'obtiendrait la première génération réelle'
    );

    // Le numéro de version de la génération RÉELLE suivante n'a pas bougé : deux prévisualisations
    // successives n'ont rien consommé.
    AR_PTFGenerationService.PTFGenerationResult real = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    System.assertEquals(
      1,
      real.versionNumber,
      'La génération réelle doit obtenir V1, comme si aucun aperçu n\'avait jamais été demandé'
    );
  }

  @IsTest
  static void testBuildPreviewData_draftMatrix_throwsLikeRealGeneration() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    String payload = JSON.serialize(inputFor(matrix.Id));

    Boolean threw = false;
    try {
      AR_PTFGenerationService.buildPreviewData(payload);
    } catch (AuraHandledException e) {
      threw = true;
    }

    System.assert(
      threw,
      'La prévisualisation doit revalider le statut exactement comme la génération réelle (AR_PTFDataService.collect est la source unique de vérité)'
    );
  }

  // ------------------------------------------------------------------
  // Gabarit figé sur le document (session 30).
  // ------------------------------------------------------------------

  @IsTest
  static void testGeneratePTF_freezesTemplateCodeOnDocument() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    Test.stopTest();

    AR_PTF_Document__c doc = [
      SELECT AR_Template_Code__c FROM AR_PTF_Document__c WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals('ABYLSEN_AT_V11', doc.AR_Template_Code__c);
  }

  // ------------------------------------------------------------------
  // Historique multi-versions : non-régression au sens 23b — une ancienne version rendue à
  // nouveau ne doit jamais afficher une version apparue après sa propre génération.
  // ------------------------------------------------------------------

  @IsTest
  static void testGeneratePTF_v1SnapshotNeverGainsV2InItsOwnFrozenHistorique() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult v1 = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    markGenerated(v1.ptfDocumentId);
    AR_PTFGenerationService.PTFGenerationResult v2 = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    Test.stopTest();

    AR_PTF_Document__c v1Doc = [
      SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :v1.ptfDocumentId
    ];
    AR_PTFData v1Data = (AR_PTFData) JSON.deserialize(v1Doc.AR_Snapshot__c, AR_PTFData.class);
    System.assertEquals(
      1,
      v1Data.historique.size(),
      'Le snapshot de V1 a été figé avant que V2 n\'existe : son historique ne doit jamais grandir rétroactivement'
    );
    System.assertEquals('V1', v1Data.historique[0].version);

    AR_PTF_Document__c v2Doc = [
      SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :v2.ptfDocumentId
    ];
    AR_PTFData v2Data = (AR_PTFData) JSON.deserialize(v2Doc.AR_Snapshot__c, AR_PTFData.class);
    System.assertEquals(2, v2Data.historique.size(), 'V2 connaît V1 et se connaît elle-même');
  }

  @IsTest
  static void testListPTFDocuments_returnsMostRecentVersionFirstWithStatus() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    // AR_Generated_At__c fixé dans le passé (pas System.now()) : listPTFDocuments trie sur ce champ
    // à la milliseconde, et la V2 générée juste après (via collect(), quelques lignes plus bas) peut
    // se voir attribuer le même System.now() si l'exécution est assez rapide — un test qui compare
    // deux appels à System.now() proches est intrinsèquement fragile. Constaté en session 38 : ce
    // test échouait de façon reproductible (jamais aléatoire) après l'ajout de quelques lignes de
    // travail dans collect() (session 38, ABMI_DQ012), qui suffisaient à faire coïncider les deux
    // timestamps à la milliseconde près. Le fond du test (tri décroissant) n'a pas changé.
    insert new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Version 1"}',
      AR_Generated_At__c = System.now().addMinutes(-5),
      AR_Generation_Status__c = 'Généré',
      AR_Content_Document_Id__c = '069000000000000AAA'
    );

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    AR_PTFGenerationService.renderAndStorePTF(started.ptfDocumentId);
    Test.stopTest();

    List<AR_PTFHistoryService.PTFDocumentRow> summaries = AR_PTFGenerationService.listPTFDocuments(
      matrix.Id
    );

    System.assertEquals(2, summaries.size());
    System.assertEquals(2, summaries[0].versionNumber, 'Trié version décroissante');
    System.assertEquals('Généré', summaries[0].status);
    System.assertNotEquals(null, summaries[0].contentDocumentId);
    System.assertEquals(1, summaries[1].versionNumber);
    System.assertEquals('Généré', summaries[1].status);
  }

  // ------------------------------------------------------------------
  // Session 35 — aiguillage réel des gabarits.
  // ------------------------------------------------------------------

  @IsTest
  static void testResolveTemplatePage_eachKnownCodeGetsItsOwnPage() {
    // Une page par gabarit (décision d'architecture session 35) : ces documents sont contractuels,
    // une régression de mise en page sur l'un parce qu'on a touché l'autre coûte plus cher que du
    // CSS répété.
    System.assertEquals(
      Page.AR_PTFTemplate.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage('GENERIQUE').getUrl()
    );
    System.assertEquals(
      Page.AR_PTFTemplateAbylsen.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage('ABYLSEN_AT_V11').getUrl()
    );
    System.assertEquals(
      Page.AR_PTFAvenant.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage('AVENANT_AT_V11').getUrl()
    );
    System.assertEquals(
      Page.AR_PTFTemplateAbmi.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage('ABMI_DQ012').getUrl()
    );
  }

  @IsTest
  static void testResolveTemplatePage_blankCode_stillGeneric() {
    // Les documents antérieurs à la session 30 ne portent aucun code : ils doivent continuer de se
    // rendre à l'identique, sinon tout l'historique déjà généré devient irrécupérable.
    System.assertEquals(
      Page.AR_PTFTemplate.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage(null).getUrl()
    );
    System.assertEquals(
      Page.AR_PTFTemplate.getUrl(),
      AR_PTFGenerationService.resolveTemplatePage('').getUrl()
    );
  }

  @IsTest
  static void testLegacyDocuments_withoutCodeOrOnGenerique_stayReadableAndRenderable() {
    // Session 184c3 : le générique est refusé pour toute NOUVELLE génération (184c), mais un document
    // ancien — sans code, ou figé en GENERIQUE — reste listé, rendu et prévisualisable.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    insert new List<AR_PTF_Document__c>{
      new AR_PTF_Document__c(
        AR_Price_Matrix__c = matrix.Id, AR_Position__c = matrix.AR_Position__c,
        AR_Reference__c = 'PTF-LEGACY-SANSCODE-V1', AR_Version_Number__c = 1, AR_Snapshot__c = '{}',
        AR_Generated_At__c = System.now().addDays(-2), AR_Generation_Status__c = 'Généré'
      ),
      new AR_PTF_Document__c(
        AR_Price_Matrix__c = matrix.Id, AR_Position__c = matrix.AR_Position__c,
        AR_Reference__c = 'PTF-LEGACY-GENERIQUE-V2', AR_Version_Number__c = 2, AR_Snapshot__c = '{}',
        AR_Template_Code__c = 'GENERIQUE',
        AR_Generated_At__c = System.now().addDays(-1), AR_Generation_Status__c = 'En cours'
      )
    };

    System.assertEquals(2, AR_PTFGenerationService.listPTFDocuments(matrix.Id).size(), 'Les documents anciens restent listés');
    System.assertEquals(Page.AR_PTFTemplate.getUrl(), AR_PTFGenerationService.resolveTemplatePage(null).getUrl());
    System.assertEquals(Page.AR_PTFTemplate.getUrl(), AR_PTFGenerationService.resolveTemplatePage('').getUrl());
    System.assertEquals(Page.AR_PTFTemplate.getUrl(), AR_PTFGenerationService.resolveTemplatePage('GENERIQUE').getUrl());

    Id legacyId = [SELECT Id FROM AR_PTF_Document__c WHERE AR_Reference__c = 'PTF-LEGACY-GENERIQUE-V2'].Id;
    AR_PTFGenerationService.PTFGenerationResult rendered = AR_PTFGenerationService.renderAndStorePTF(legacyId);
    System.assertEquals('Généré', rendered.status, 'Le rendu d\'un document ancien reste possible : ' + rendered.errorMessage);
  }

  @IsTest
  static void testResolveTemplatePage_unknownCode_throwsInsteadOfSilentlyFallingBack() {
    String message = null;
    try {
      AR_PTFGenerationService.resolveTemplatePage('GRAND_COMPTE_DEMO');
      System.assert(false, 'Un code inconnu ne doit plus retomber silencieusement sur le générique');
    } catch (AR_PTFGenerationService.AR_PTFRenderException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('GRAND_COMPTE_DEMO'), message);
    System.assert(message.contains('ABYLSEN_AT_V11'), 'Le message doit lister les codes valides : ' + message);
  }

  // ------------------------------------------------------------------
  // Session 39 — la prévisualisation ouvrait toujours la page générique quel que soit le gabarit
  // résolu ou surchargé (correct tant que les pages 36-38 étaient des coquilles, plus du tout
  // depuis qu'elles sont mises en page) : getPreviewPageUrl expose le MÊME aiguillage que la
  // génération réelle, pour que l'un ne puisse jamais diverger de l'autre.
  // ------------------------------------------------------------------

  @IsTest
  static void testGetPreviewPageUrl_matchesResolveTemplatePage_forEachKnownCode() {
    for (String code : new List<String>{ 'GENERIQUE', 'ABYLSEN_AT_V11', 'AVENANT_AT_V11', 'ABMI_DQ012' }) {
      System.assertEquals(
        AR_PTFGenerationService.resolveTemplatePage(code).getUrl(),
        AR_PTFGenerationService.getPreviewPageUrl(code),
        'La page de prévisualisation doit être exactement celle qui serait utilisée à la génération réelle pour ' + code
      );
    }
  }

  @IsTest
  static void testGetPreviewPageUrl_blankCode_stillGeneric() {
    System.assertEquals(Page.AR_PTFTemplate.getUrl(), AR_PTFGenerationService.getPreviewPageUrl(null));
  }

  @IsTest
  static void testRenderAndStore_documentWithUnknownFrozenCode_failsLoudlyNotSilently() {
    // Cas réel possible : un document généré avant que le code de son compte ne soit corrigé. Le
    // rendu doit ÉCHOUER visiblement (statut Échec + message), jamais produire un PDF générique qui
    // aurait l'air d'un document valide sur le mauvais modèle.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-BADCODE-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"reference":"PTF-TEST-BADCODE-V1"}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'En cours',
      AR_Template_Code__c = 'GABARIT_QUI_NEXISTE_PAS'
    );
    insert doc;

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.renderAndStorePTF(doc.Id);
    Test.stopTest();

    System.assertEquals('Échec', result.status);
    System.assert(
      result.errorMessage.contains('GABARIT_QUI_NEXISTE_PAS'),
      'Le message d\'échec doit nommer le code fautif : ' + result.errorMessage
    );
    AR_PTF_Document__c reloaded = [
      SELECT AR_Generation_Status__c, AR_Content_Document_Id__c
      FROM AR_PTF_Document__c
      WHERE Id = :doc.Id
    ];
    System.assertEquals('Échec', reloaded.AR_Generation_Status__c);
    System.assertEquals(null, reloaded.AR_Content_Document_Id__c, 'Aucun fichier ne doit être produit');
  }

  // ------------------------------------------------------------------
  // Session 37 — avenant : rattachement à la PTF d'origine, numérotation propre (AV1, AV2…),
  // non-régression sur le document d'origine et sur le compteur de version PTF.
  // ------------------------------------------------------------------

  private static AR_PTFDataService.AvenantGenerationInput avenantInputFor(Id ptfDocumentId) {
    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.ptfDocumentId = ptfDocumentId;
    input.prolongationJusquAu = Date.newInstance(2026, 12, 31);
    input.valideurNom = 'Valideur Test Avenant';
    input.valideurFonction = 'Directeur Test';
    return input;
  }

  private static AR_PTF_Document__c generatedOriginPtf(Id matrixId, Id positionId) {
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrixId,
      AR_Position__c = positionId,
      AR_Reference__c = 'PTF-MAT-ORIG-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client PTF Gen"}',
      AR_Generated_At__c = Datetime.newInstance(2026, 8, 1, 9, 0, 0),
      AR_Generation_Status__c = 'Généré',
      AR_Content_Document_Id__c = '069000000000000AAA',
      AR_Template_Code__c = 'ABYLSEN_AT_V11'
    );
    insert doc;
    return doc;
  }

  @IsTest
  static void testGenerateAvenantInput_success_insertsAvenantAttachedToOrigin() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      avenantInputFor(origin.Id)
    );
    Test.stopTest();

    AR_PTF_Document__c avenant = [
      SELECT AR_Document_Type__c, AR_Parent_PTF__c, AR_Avenant_Number__c, AR_Reference__c,
             AR_Price_Matrix__c, AR_Position__c, AR_Template_Code__c, AR_Generation_Status__c
      FROM AR_PTF_Document__c
      WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals('Avenant', avenant.AR_Document_Type__c);
    System.assertEquals(origin.Id, avenant.AR_Parent_PTF__c);
    System.assertEquals(1, avenant.AR_Avenant_Number__c);
    System.assert(avenant.AR_Reference__c.startsWith('PTF_ABYLSEN_') && avenant.AR_Reference__c.endsWith('_AV1'), avenant.AR_Reference__c);
    System.assertEquals(matrix.Id, avenant.AR_Price_Matrix__c);
    System.assertEquals(matrix.AR_Position__c, avenant.AR_Position__c);
    System.assertEquals('AVENANT_AT_V11', avenant.AR_Template_Code__c);
    System.assertEquals('En cours', avenant.AR_Generation_Status__c, 'Même principe en deux temps que generatePTFInput');
  }

  @IsTest
  static void testGenerateAvenantInput_originNotGenerated_throwsAndInsertsNothing() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
      AR_PTF_Document__c origin = new AR_PTF_Document__c(
        AR_Price_Matrix__c = matrix.Id,
        AR_Position__c = matrix.AR_Position__c,
        AR_Reference__c = 'PTF-MAT-ORIG-V1',
        AR_Version_Number__c = 1,
        AR_Snapshot__c = '{}',
        AR_Generated_At__c = System.now(),
        AR_Generation_Status__c = 'Échec'
      );
      insert origin;

      Test.startTest();
      try {
        AR_PTFGenerationService.generateAvenantInput(avenantInputFor(origin.Id));
        System.assert(false, 'Un avenant ne doit pas pouvoir se créer depuis une PTF non générée');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('déjà générée'));
      }
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Document_Type__c = 'Avenant'],
        'Aucun avenant ne doit avoir été inséré'
      );
    }
  }

  @IsTest
  static void testGenerateAvenantInput_doesNotModifyOriginDocument() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    AR_PTF_Document__c before = [
      SELECT AR_Reference__c, AR_Version_Number__c, AR_Snapshot__c, AR_Generation_Status__c,
             AR_Content_Document_Id__c
      FROM AR_PTF_Document__c
      WHERE Id = :origin.Id
    ];

    Test.startTest();
    AR_PTFGenerationService.generateAvenantInput(avenantInputFor(origin.Id));
    Test.stopTest();

    AR_PTF_Document__c after = [
      SELECT AR_Reference__c, AR_Version_Number__c, AR_Snapshot__c, AR_Generation_Status__c,
             AR_Content_Document_Id__c
      FROM AR_PTF_Document__c
      WHERE Id = :origin.Id
    ];
    System.assertEquals(
      before.AR_Reference__c,
      after.AR_Reference__c,
      'Preuve « en base » exigée par le prompt de session : même référence après création de l\'avenant'
    );
    System.assertEquals(before.AR_Version_Number__c, after.AR_Version_Number__c, 'Même version');
    System.assertEquals(before.AR_Snapshot__c, after.AR_Snapshot__c, 'Même snapshot');
    System.assertEquals(before.AR_Generation_Status__c, after.AR_Generation_Status__c, 'Même statut');
    System.assertEquals(before.AR_Content_Document_Id__c, after.AR_Content_Document_Id__c, 'Même fichier');
  }

  @IsTest
  static void testNextVersionNumber_avenantDoesNotConsumeNextPtfVersion() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    System.assertEquals(
      2,
      AR_PTFGenerationService.nextVersionNumber(matrix.Id),
      'Avant tout avenant, le prochain numéro de version PTF doit être 2'
    );

    Test.startTest();
    AR_PTFGenerationService.generateAvenantInput(avenantInputFor(origin.Id));
    Test.stopTest();

    System.assertEquals(
      2,
      AR_PTFGenerationService.nextVersionNumber(matrix.Id),
      'Un avenant ne doit jamais décaler le prochain numéro de version de la PTF d\'origine ' +
      '(vérification exigée par le prompt de session, point 5)'
    );
  }

  @IsTest
  static void testNextAvenantNumber_incrementsPerParentIndependentlyFromPtfVersion() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    System.assertEquals(1, AR_PTFGenerationService.nextAvenantNumber(origin.Id));

    Test.startTest();
    AR_PTFGenerationService.generateAvenantInput(avenantInputFor(origin.Id));
    Test.stopTest();

    System.assertEquals(
      2,
      AR_PTFGenerationService.nextAvenantNumber(origin.Id),
      'Le deuxième avenant de la même PTF doit porter le numéro 2'
    );
  }

  @IsTest
  static void testListPTFDocuments_includesAvenantsWithOwnLabelAndType() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    Test.startTest();
    AR_PTFGenerationService.generateAvenantInput(avenantInputFor(origin.Id));
    Test.stopTest();

    List<AR_PTFHistoryService.PTFDocumentRow> summaries = AR_PTFGenerationService.listPTFDocuments(
      matrix.Id
    );
    System.assertEquals(2, summaries.size());
    Map<String, AR_PTFHistoryService.PTFDocumentRow> byType = new Map<String, AR_PTFHistoryService.PTFDocumentRow>();
    for (AR_PTFHistoryService.PTFDocumentRow s : summaries) {
      byType.put(s.documentType, s);
    }
    System.assertEquals('PTF', byType.get('PTF').documentType);
    System.assertEquals('Avenant', byType.get('Avenant').documentType);
    System.assertEquals(1, byType.get('Avenant').avenantNumber);
  }

  // ------------------------------------------------------------------
  // Session 138 — rang d'affichage, modification obligatoire à partir du rang 2, historique figé.
  // ------------------------------------------------------------------

  @IsTest
  static void testGeneratePTF_rank2WithoutModificationType_throwsAndCreatesNoDocument() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
      markGenerated(AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id)).ptfDocumentId);

      AR_PTFDataService.GenerationInput second = inputFor(matrix.Id);
      second.modificationType = null;
      Boolean thrown = false;
      Test.startTest();
      try {
        AR_PTFGenerationService.generatePTFInput(second);
      } catch (AuraHandledException e) {
        thrown = true;
        System.assert(
          e.getMessage().contains('obligatoire'),
          'Message lisible attendu, reçu : ' + e.getMessage()
        );
      }
      Test.stopTest();

      System.assert(thrown, 'Rang 2 sans type de modification : erreur attendue');
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :matrix.Id],
        'Aucun document ne doit être créé quand la saisie est refusée'
      );
    }
  }

  @IsTest
  static void testGeneratePTF_rank2TypeAutreWithoutDetail_throwsAndCreatesNoDocument() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
      markGenerated(AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id)).ptfDocumentId);

      AR_PTFDataService.GenerationInput second = inputFor(matrix.Id);
      second.modificationType = 'Autre';
      second.modificationDetail = '   ';
      Boolean thrown = false;
      Test.startTest();
      try {
        AR_PTFGenerationService.generatePTFInput(second);
      } catch (AuraHandledException e) {
        thrown = true;
        System.assert(e.getMessage().contains('détail'), 'Reçu : ' + e.getMessage());
      }
      Test.stopTest();

      System.assert(thrown);
      System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :matrix.Id]);
    }
  }

  @IsTest
  static void testGeneratePTF_rank2InvalidType_throwsAndCreatesNoDocument() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
      markGenerated(AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id)).ptfDocumentId);

      AR_PTFDataService.GenerationInput second = inputFor(matrix.Id);
      second.modificationType = 'Type inventé';
      Boolean thrown = false;
      try {
        AR_PTFGenerationService.generatePTFInput(second);
      } catch (AuraHandledException e) {
        thrown = true;
        System.assert(e.getMessage().contains('invalide'), 'Reçu : ' + e.getMessage());
      }
      System.assert(thrown);
      System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :matrix.Id]);
    }
  }

  @IsTest
  static void testGeneratePTF_rank1WithModification_isIgnoredAndNotStored() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFDataService.GenerationInput input = inputFor(matrix.Id);
    input.modificationType = 'Autre';
    input.modificationDetail = 'Texte à ignorer';

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(input);

    AR_PTF_Document__c doc = [
      SELECT AR_Modification_Type__c, AR_Modification_Detail__c, AR_Include_In_History__c, AR_Snapshot__c
      FROM AR_PTF_Document__c
      WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals(null, doc.AR_Modification_Type__c);
    System.assertEquals(null, doc.AR_Modification_Detail__c);
    System.assertEquals(true, doc.AR_Include_In_History__c);
    AR_PTFData data = (AR_PTFData) JSON.deserialize(doc.AR_Snapshot__c, AR_PTFData.class);
    System.assertEquals('', data.historique[0].objetModification, 'Rang 1 : cellule Modification vide dans le snapshot');
  }

  @IsTest
  static void testGeneratePTF_v1v2v3WithV2Unchecked_newPtfIsV3WithThreeHistoryRows() {
    AR_Price_Matrix__c matrix = [SELECT Id, Name FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

    AR_PTFGenerationService.PTFGenerationResult v1 = AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));
    markGenerated(v1.ptfDocumentId);
    AR_PTFGenerationService.PTFGenerationResult v2 = AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));
    markGenerated(v2.ptfDocumentId);
    AR_PTFDataService.GenerationInput third = inputFor(matrix.Id);
    third.modificationType = 'Autre';
    third.modificationDetail = '  Ajout d\'un second consultant  ';
    AR_PTFGenerationService.PTFGenerationResult v3 = AR_PTFGenerationService.generatePTFInput(third);
    markGenerated(v3.ptfDocumentId);

    // Dates distinctes et croissantes (l'ordre des rangs suit AR_Generated_At__c, à la milliseconde).
    update new List<AR_PTF_Document__c>{
      new AR_PTF_Document__c(Id = v1.ptfDocumentId, AR_Generated_At__c = System.now().addDays(-3)),
      new AR_PTF_Document__c(Id = v2.ptfDocumentId, AR_Generated_At__c = System.now().addDays(-2), AR_Include_In_History__c = false),
      new AR_PTF_Document__c(Id = v3.ptfDocumentId, AR_Generated_At__c = System.now().addDays(-1))
    };

    AR_PTFGenerationService.PTFGenerationResult v4 = AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));

    AR_PTF_Document__c doc = [
      SELECT AR_Reference__c, AR_Version_Number__c, AR_Snapshot__c, AR_Modification_Type__c
      FROM AR_PTF_Document__c
      WHERE Id = :v4.ptfDocumentId
    ];
    // Session 184d : la référence est le nom de fichier de la nomenclature (PTF_ABYLSEN_…), plus le compteur
    // technique ; l'unicité des documents reste portée par AR_Version_Number__c.
    AR_PTFData v4Data = (AR_PTFData) JSON.deserialize(doc.AR_Snapshot__c, AR_PTFData.class);
    System.assert(doc.AR_Reference__c.startsWith('PTF_ABYLSEN_'), 'Référence = nomenclature : ' + doc.AR_Reference__c);
    System.assertEquals(AR_PTFGenerationService.buildNomenclatureFileName(v4Data), doc.AR_Reference__c);
    Set<Decimal> versionNumbers = new Set<Decimal>();
    for (AR_PTF_Document__c d : [SELECT AR_Version_Number__c FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :matrix.Id]) {
      versionNumbers.add(d.AR_Version_Number__c);
    }
    System.assertEquals(
      [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Price_Matrix__c = :matrix.Id],
      versionNumbers.size(),
      'Autant de numéros de version distincts que de documents'
    );
    System.assertEquals(4, doc.AR_Version_Number__c, 'Le compteur technique ne bouge pas : 4e document de la matrice');
    System.assertEquals('Modification de montant', doc.AR_Modification_Type__c);

    AR_PTFData data = (AR_PTFData) JSON.deserialize(doc.AR_Snapshot__c, AR_PTFData.class);
    System.assertEquals(3, data.historique.size());
    System.assertEquals('V1', data.historique[0].version);
    System.assertEquals('', data.historique[0].objetModification);
    System.assertEquals('V2', data.historique[1].version);
    System.assertEquals('Ajout d\'un second consultant', data.historique[1].objetModification, 'Ex-V3, détail rogné');
    System.assertEquals('V3', data.historique[2].version);
    System.assertEquals('Modification de montant', data.historique[2].objetModification);
    System.assertEquals(UserInfo.getName(), data.historique[2].responsable);

    // Contrôleur : « Version numéro » zéro-paddé depuis le rang, et lignes d'historique du snapshot.
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', v4.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    System.assertEquals('03', controller.versionNumeroLabel);
    System.assertEquals(3, controller.historiqueDisplay.size());
    System.assertEquals(UserInfo.getName(), controller.historiqueDisplay[2].responsable);
  }

  @IsTest
  static void testGeneratePTF_uncheckingLaterDoesNotRewriteExistingSnapshot() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTFGenerationService.PTFGenerationResult v1 = AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));
    update new AR_PTF_Document__c(
      Id = v1.ptfDocumentId,
      AR_Generated_At__c = System.now().addDays(-2),
      AR_Generation_Status__c = 'Généré'
    );
    AR_PTFGenerationService.PTFGenerationResult v2 = AR_PTFGenerationService.generatePTFInput(inputFor(matrix.Id));

    String frozenBefore = [SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :v2.ptfDocumentId].AR_Snapshot__c;
    update new AR_PTF_Document__c(Id = v1.ptfDocumentId, AR_Include_In_History__c = false);
    String frozenAfter = [SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :v2.ptfDocumentId].AR_Snapshot__c;

    System.assertEquals(frozenBefore, frozenAfter, 'Décocher une version ne réécrit jamais un snapshot existant');
    AR_PTFData data = (AR_PTFData) JSON.deserialize(frozenAfter, AR_PTFData.class);
    System.assertEquals(2, data.historique.size());
  }

  @IsTest
  static void testGeneratePTF_jsonEntryPoint_carriesModificationAndSurfacesReadableError() {
    System.runAs(AR_TestPersona.francais()) {
      AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');

      // Point d'entrée réel du LWC : payload JSON (cf. docs/19-payload-json.md).
      AR_PTFDataService.GenerationInput first = inputFor(matrix.Id);
      AR_PTFGenerationService.PTFGenerationResult v1 = AR_PTFGenerationService.generatePTF(JSON.serialize(first));
      markGenerated(v1.ptfDocumentId);

      AR_PTFDataService.GenerationInput second = inputFor(matrix.Id);
      second.modificationType = null;
      Boolean thrown = false;
      try {
        AR_PTFGenerationService.generatePTF(JSON.serialize(second));
      } catch (AuraHandledException e) {
        thrown = true;
        System.assert(e.getMessage().contains('obligatoire'), 'Message lisible attendu, reçu : ' + e.getMessage());
      }
      System.assert(thrown);

      second.modificationType = 'Autre';
      second.modificationDetail = 'Détail saisi';
      AR_PTFGenerationService.PTFGenerationResult v2 = AR_PTFGenerationService.generatePTF(JSON.serialize(second));
      AR_PTF_Document__c doc = [
        SELECT AR_Modification_Type__c, AR_Modification_Detail__c FROM AR_PTF_Document__c WHERE Id = :v2.ptfDocumentId
      ];
      System.assertEquals('Autre', doc.AR_Modification_Type__c);
      System.assertEquals('Détail saisi', doc.AR_Modification_Detail__c);
    }
  }

  @IsTest
  static void testGenerateAvenant_blankPayload_throwsReadableError() {
    System.runAs(AR_TestPersona.francais()) {
      Boolean thrown = false;
      try {
        AR_PTFGenerationService.generateAvenant('');
      } catch (AuraHandledException e) {
        thrown = true;
        System.assert(e.getMessage().contains('vide'), 'Reçu : ' + e.getMessage());
      }
      System.assert(thrown);
    }
  }

  @IsTest
  static void testGenerateAvenant_jsonEntryPoint_noModificationRequiredAndDoesNotConsumeRank() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    AR_PTF_Document__c origin = generatedOriginPtf(matrix.Id, matrix.AR_Position__c);

    // Session 138 : « avenants — aucun changement ». Aucun type de modification n'est demandé et
    // l'avenant ne compte pas dans le rang d'affichage des PTF.
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenant(
      JSON.serialize(avenantInputFor(origin.Id))
    );

    AR_PTF_Document__c avenant = [
      SELECT AR_Document_Type__c, AR_Modification_Type__c FROM AR_PTF_Document__c WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals('Avenant', avenant.AR_Document_Type__c);
    System.assertEquals(null, avenant.AR_Modification_Type__c);
    System.assertEquals(
      2,
      AR_PTFHistoryService.nextDisplayRank(matrix.Id, 'ABYLSEN_AT_V11'),
      'L\'origine compte pour un rang, l\'avenant pour aucun'
    );
  }

  // ------------------------------------------------------------------
  // Session 153b : document resté « En cours » — reprise du rendu et passage en « Échec »
  // ------------------------------------------------------------------

  private static Id startedStaleDoc() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c LIMIT 1];
    if (matrix.AR_Status__c != 'Validée') {
      // Une matrice validée est verrouillée : un second appel de l'assistant ne doit pas la réécrire.
      update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    }
    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generatePTFInput(
      inputFor(matrix.Id)
    );
    return started.ptfDocumentId;
  }

  @IsTest
  static void testRetryRenderPTF_staleEnCours_rendersAndSetsGenere() {
    Id docId = startedStaleDoc();
    Test.setCreatedDate(docId, System.now().addMinutes(-10));

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.retryRenderPTF(
      docId
    );
    Test.stopTest();

    System.assertEquals('Généré', result.status);
    AR_PTF_Document__c doc = [
      SELECT AR_Generation_Status__c, AR_Content_Document_Id__c, AR_Generation_Error__c
      FROM AR_PTF_Document__c
      WHERE Id = :docId
    ];
    System.assertEquals('Généré', doc.AR_Generation_Status__c);
    System.assertNotEquals(null, doc.AR_Content_Document_Id__c, 'Le fichier doit être stocké');
    System.assertEquals(null, doc.AR_Generation_Error__c);
  }

  @IsTest
  static void testRetryRenderPTF_recentEnCours_isRefusedAndLeavesDocumentUntouched() {
    System.runAs(AR_TestPersona.francais()) {
      Id docId = startedStaleDoc();

      Test.startTest();
      try {
        AR_PTFGenerationService.retryRenderPTF(docId);
        System.assert(false, 'Un document de moins de 2 minutes peut être en cours de rendu : refus attendu');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('récente'), e.getMessage());
      }
      Test.stopTest();

      AR_PTF_Document__c doc = [
        SELECT AR_Generation_Status__c, AR_Content_Document_Id__c
        FROM AR_PTF_Document__c
        WHERE Id = :docId
      ];
      System.assertEquals('En cours', doc.AR_Generation_Status__c);
      System.assertEquals(null, doc.AR_Content_Document_Id__c);
    }
  }

  @IsTest
  static void testRetryRenderPTF_alreadyGenere_isRefusedAndStoresNoSecondFile() {
    Id docId = startedStaleDoc();
    AR_PTFGenerationService.renderAndStorePTF(docId);
    Integer filesBefore = [SELECT COUNT() FROM ContentVersion];
    Test.setCreatedDate(docId, System.now().addMinutes(-10));

    Test.startTest();
    try {
      AR_PTFGenerationService.retryRenderPTF(docId);
      System.assert(false, 'Un document déjà généré ne se reprend pas');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Généré'), e.getMessage());
    }
    Test.stopTest();

    System.assertEquals(filesBefore, [SELECT COUNT() FROM ContentVersion], 'Aucun second fichier');
  }

  @IsTest
  static void testRetryRenderPTF_staleWithBrokenSnapshot_setsEchecWithMotif() {
    Id docId = startedStaleDoc();
    update new AR_PTF_Document__c(Id = docId, AR_Snapshot__c = null);
    Test.setCreatedDate(docId, System.now().addMinutes(-10));

    Test.startTest();
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.retryRenderPTF(
      docId
    );
    Test.stopTest();

    System.assertEquals('Échec', result.status);
    AR_PTF_Document__c doc = [
      SELECT AR_Generation_Status__c, AR_Generation_Error__c
      FROM AR_PTF_Document__c
      WHERE Id = :docId
    ];
    System.assertEquals('Échec', doc.AR_Generation_Status__c);
    System.assert(doc.AR_Generation_Error__c.contains('Snapshot'), doc.AR_Generation_Error__c);
  }

  @IsTest
  static void testRetryRenderPTF_unknownId_throws() {
    System.runAs(AR_TestPersona.francais()) {
      Id missing = Id.valueOf(AR_PTF_Document__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
      Test.startTest();
      try {
        AR_PTFGenerationService.retryRenderPTF(missing);
        System.assert(false, 'Un Id inexistant doit lever une exception');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('introuvable'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void testMarkRenderFailed_enCours_becomesEchecWithReason() {
    System.runAs(AR_TestPersona.francais()) {
      Id docId = startedStaleDoc();

      Test.startTest();
      AR_PTFGenerationService.markRenderFailed(docId, 'Délai dépassé côté client');
      Test.stopTest();

      AR_PTF_Document__c doc = [
        SELECT AR_Generation_Status__c, AR_Generation_Error__c
        FROM AR_PTF_Document__c
        WHERE Id = :docId
      ];
      System.assertEquals('Échec', doc.AR_Generation_Status__c);
      System.assert(doc.AR_Generation_Error__c.contains('Délai dépassé côté client'));
      System.assert(doc.AR_Generation_Error__c.contains('Rendu interrompu'));
    }
  }

  @IsTest
  static void testMarkRenderFailed_blankReasonAndLongReason_areBoundedAndNamed() {
    System.runAs(AR_TestPersona.francais()) {
      Id docId = startedStaleDoc();
      Id otherId = startedStaleDoc();

      Test.startTest();
      AR_PTFGenerationService.markRenderFailed(docId, '');
      AR_PTFGenerationService.markRenderFailed(otherId, 'x'.repeat(900));
      Test.stopTest();

      Map<Id, AR_PTF_Document__c> docs = new Map<Id, AR_PTF_Document__c>(
        [SELECT AR_Generation_Error__c FROM AR_PTF_Document__c WHERE Id IN :new Set<Id>{ docId, otherId }]
      );
      System.assert(docs.get(docId).AR_Generation_Error__c.contains('motif inconnu'));
      System.assertEquals(500, docs.get(otherId).AR_Generation_Error__c.length());
    }
  }

  @IsTest
  static void testMarkRenderFailed_alreadyGenere_isNeverOverwritten() {
    Id docId = startedStaleDoc();
    AR_PTFGenerationService.renderAndStorePTF(docId);

    Test.startTest();
    AR_PTFGenerationService.markRenderFailed(docId, 'Réponse perdue côté client');
    Test.stopTest();

    AR_PTF_Document__c doc = [
      SELECT AR_Generation_Status__c, AR_Generation_Error__c, AR_Content_Document_Id__c
      FROM AR_PTF_Document__c
      WHERE Id = :docId
    ];
    System.assertEquals('Généré', doc.AR_Generation_Status__c, 'Un rendu terminé n\'est jamais écrasé');
    System.assertEquals(null, doc.AR_Generation_Error__c);
    System.assertNotEquals(null, doc.AR_Content_Document_Id__c);
  }

  // Session 177 — tests de nomenclature PTF
  @IsTest
  static void testNomenclaturePTF_nominal_includesManagerAndConsultantTrigrams() {
    AR_Price_Matrix__c matrix = [SELECT Id, OwnerId FROM AR_Price_Matrix__c LIMIT 1];
    String ownerName = [SELECT Name FROM User WHERE Id = :matrix.OwnerId].Name;
    matrix.AR_Status__c = 'Validée';
    matrix.AR_Consultant_Name__c = 'Jean DUPONT';
    update matrix;

    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, inputFor(matrix.Id), 1);
    Test.stopTest();

    System.assertEquals(ownerName, data.managerName, 'Le manager est le propriétaire de la matrice');
    String managerTrigram = AR_PTFGenerationService.userTrigramme(ownerName);
    String expected = 'PTF_ABYLSEN_' + (managerTrigram == null ? '' : managerTrigram + '_') +
      'Client_PTF_Gen_JDU_20260901-20260930';
    System.assertEquals(expected, AR_PTFGenerationService.buildNomenclatureFileName(data));
  }

  @IsTest
  static void testNomenclaturePTF_noConsultant_omitsTrigram() {
    AR_Price_Matrix__c matrix = [SELECT Id, OwnerId FROM AR_Price_Matrix__c LIMIT 1];
    String ownerName = [SELECT Name FROM User WHERE Id = :matrix.OwnerId].Name;
    matrix.AR_Status__c = 'Validée';
    matrix.AR_Consultant_Name__c = null;
    update matrix;

    Test.startTest();
    AR_PTFData data = AR_PTFDataService.collect(matrix.Id, inputFor(matrix.Id), 1);
    Test.stopTest();

    System.assertEquals(null, data.consultantNom);
    String managerTrigram = AR_PTFGenerationService.userTrigramme(ownerName);
    String expected = 'PTF_ABYLSEN_' + (managerTrigram == null ? '' : managerTrigram + '_') +
      'Client_PTF_Gen_20260901-20260930';
    System.assertEquals(expected, AR_PTFGenerationService.buildNomenclatureFileName(data));
  }

  @IsTest
  static void testSanitizeForFileName_accentedNames_transliteratesBeforeReplacingSeparators() {
    System.assertEquals('Societe_Generale', AR_PTFGenerationService.sanitizeForFileName('Société Générale'));
    System.assertEquals('ELECTRICITE_DE_FRANCE', AR_PTFGenerationService.sanitizeForFileName('ÉLECTRICITÉ DE FRANCE'));
    System.assertEquals('Coeur_Defense', AR_PTFGenerationService.sanitizeForFileName('Cœur Défense'));
    System.assertEquals('Credit_Agricole_CIB', AR_PTFGenerationService.sanitizeForFileName('Crédit Agricole CIB'));
  }

  @IsTest
  static void testBuildNomenclatureFileName_accentedClientAndNames_noStrayUnderscore() {
    AR_PTFData data = new AR_PTFData();
    data.client = 'Société Générale';
    data.managerName = 'Éric DUPONT';
    data.consultantNom = 'José GARCÍA';
    data.dateDebut = Date.newInstance(2026, 9, 1);
    data.dateFin = Date.newInstance(2026, 9, 30);

    System.assertEquals(
      'PTF_ABYLSEN_EDU_Societe_Generale_JGA_20260901-20260930',
      AR_PTFGenerationService.buildNomenclatureFileName(data),
      'Une lettre accentuée ne doit jamais devenir « _ » dans la référence'
    );
  }

  @IsTest
  static void testUserTrigramme_nominal_returnsFirstLetterFirstNameAndTwoLettersLastName() {
    String result = AR_PTFGenerationService.userTrigramme('Alexis ROQUES');
    System.assertEquals('ARO', result, 'Alexis ROQUES doit donner ARO');
  }

  @IsTest
  static void testUserTrigramme_withAccents_removesAccents() {
    String result = AR_PTFGenerationService.userTrigramme('José GARCÍA');
    System.assertEquals('JGA', result, 'José GARCÍA doit donner JGA (sans accents)');
  }

  @IsTest
  static void testUserTrigramme_leadingAccentInFirstName_keepsLetter() {
    System.assertEquals('EDU', AR_PTFGenerationService.userTrigramme('Éric DUPONT'), 'Éric DUPONT doit donner EDU, pas RDU');
    System.assertEquals('CTO', AR_PTFGenerationService.userTrigramme('Celine TOULEMONDE'), 'Celine TOULEMONDE doit donner CTO');
  }

  @IsTest
  static void testUserTrigramme_singleName_returnsNull() {
    String result = AR_PTFGenerationService.userTrigramme('Cher');
    System.assertEquals(null, result, 'Un seul token doit retourner null');
  }

  @IsTest
  static void testUserTrigramme_twoLetterLastName_returnsValidTrigram() {
    String result = AR_PTFGenerationService.userTrigramme('Jean LY');
    System.assertEquals('JLY', result, 'Jean LY doit donner JLY');
  }

  @IsTest
  static void testUserTrigramme_shortLastName_returnsNull() {
    String result = AR_PTFGenerationService.userTrigramme('Jean D');
    System.assertEquals(null, result, 'Dernier token avec une lettre doit retourner null');
  }

  @IsTest
  static void testUserTrigramme_blankInput_returnsNull() {
    String result = AR_PTFGenerationService.userTrigramme('');
    System.assertEquals(null, result, 'Chaîne vide doit retourner null');
    result = AR_PTFGenerationService.userTrigramme('   ');
    System.assertEquals(null, result, 'Chaîne blanche doit retourner null');
  }

  // ------------------------------------------------------------------
  // Session 180d — avenant piloté par la matrice : le document se rattache à la MATRICE AVENANT,
  // cite la PTF amendée, et lit tarif, dates et échéancier sur la matrice (jamais sur un formulaire).
  // ------------------------------------------------------------------

  private static final Date AV_START = Date.newInstance(2026, 10, 1); // jeudi
  private static final Date AV_END = Date.newInstance(2026, 12, 31); // jeudi

  /** Origine validée + PTF d'origine générée ; l'avenant est ensuite posé directement (comme AR_AvenantServiceTest). */
  private static AR_PTF_Document__c validatedOriginWithPtf() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
    return generatedOriginPtf(matrix.Id, matrix.AR_Position__c);
  }

  private static AR_Price_Matrix__c newAvenantMatrix(
    AR_PTF_Document__c origin,
    String changes,
    Decimal tjm,
    String status
  ) {
    AR_Price_Matrix__c base = [
      SELECT Id, AR_Position__c, AR_Entity_Ref__c
      FROM AR_Price_Matrix__c
      WHERE Id = :origin.AR_Price_Matrix__c
    ];
    AR_Price_Matrix__c m = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = base.AR_Position__c,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = tjm,
      AR_Status__c = status,
      AR_Account_Name__c = 'Client PTF Gen',
      AR_Entity_Ref__c = base.AR_Entity_Ref__c,
      AR_Consultant_Name__c = 'Paul MARTIN',
      AR_Start_Date__c = AV_START,
      AR_End_Date__c = AV_END,
      AR_Number_Of_Days__c = AR_AvenantService.countBusinessDays(AV_START, AV_END),
      AR_Version_Type__c = 'Avenant',
      AR_Amended_PTF__c = origin.Id,
      AR_Avenant_Changes__c = changes,
      AR_Previous_Version__c = base.Id,
      AR_Negotiation_Version__c = 3,
      AR_Effective_Validator__c = UserInfo.getUserId()
    );
    insert m;
    return m;
  }

  private static AR_PTFData snapshotOf(Id documentId) {
    return (AR_PTFData) JSON.deserialize(
      [SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :documentId].AR_Snapshot__c,
      AR_PTFData.class
    );
  }

  private static AR_PTFDataService.AvenantGenerationInput matrixInput(Id matrixId) {
    AR_PTFDataService.AvenantGenerationInput input = new AR_PTFDataService.AvenantGenerationInput();
    input.matrixId = matrixId;
    return input;
  }

  @IsTest
  static void testMatrixAvenant_tarifEtPeriode_documentOnAvenantMatrixWithMatrixValues() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif;Période', 780, 'Validée');

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(av.Id)
    );

    AR_PTF_Document__c doc = [
      SELECT AR_Document_Type__c, AR_Parent_PTF__c, AR_Avenant_Number__c, AR_Reference__c, AR_Price_Matrix__c,
             AR_Template_Code__c, AR_Generation_Status__c
      FROM AR_PTF_Document__c
      WHERE Id = :result.ptfDocumentId
    ];
    System.assertEquals(av.Id, doc.AR_Price_Matrix__c, 'Le document se rattache à la matrice avenant');
    System.assertEquals(origin.Id, doc.AR_Parent_PTF__c, 'Parent = la PTF amendée');
    System.assertEquals('Avenant', doc.AR_Document_Type__c);
    System.assertEquals(1, doc.AR_Avenant_Number__c);
    System.assert(doc.AR_Reference__c.startsWith('PTF_ABYLSEN_') && doc.AR_Reference__c.endsWith('_AV1'), doc.AR_Reference__c);
    System.assertEquals('AVENANT_AT_V11', doc.AR_Template_Code__c);
    System.assertEquals('En cours', doc.AR_Generation_Status__c);

    AR_PTFData data = snapshotOf(doc.Id);
    System.assertEquals(780, data.tjm, 'TJM lu sur la matrice avenant');
    System.assertEquals(780, data.nouveauTjm);
    System.assertEquals(AV_START, data.revisionPrixADateDu, 'Date d\'effet = début de la matrice avenant');
    System.assertEquals(AV_START, data.dateDebut);
    System.assertEquals(AV_END, data.dateFin);
    System.assertEquals(AV_END, data.prolongationJusquAu, 'Période = Oui : fin de la matrice');
    System.assertEquals(true, data.revisionPrix);
    System.assertEquals(origin.Id, data.ptfInitialeDocumentId);
    System.assertEquals('PTF-MAT-ORIG-V1', data.ptfInitialeReference);
    System.assertEquals('AV1', data.version);
    System.assert(!data.schedule.isEmpty(), 'Échéancier calculé sur la période de l\'avenant');
    System.assert(!data.lots.isEmpty());
    Decimal days = 0;
    for (AR_PTFData.ScheduleRow row : data.schedule) {
      days += row.jours;
    }
    Decimal avenantDays = AR_AvenantService.countBusinessDays(AV_START, AV_END);
    System.assertEquals(avenantDays, days, 'Les jours de l\'échéancier sont ceux de la matrice avenant');
    System.assertEquals(null, snapshotOf(origin.Id).prolongationJusquAu, 'La PTF d\'origine n\'est pas touchée');
  }

  @IsTest
  static void testMatrixAvenant_prolongationAuMemeTarif_imprimeLEcheancierDeLaPeriode() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Période', 700, 'Validée');

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(av.Id)
    );

    AR_PTFData data = snapshotOf(result.ptfDocumentId);
    System.assertEquals(AV_END, data.prolongationJusquAu);
    System.assertEquals(true, data.revisionPrix, 'Q5 B : échéancier imprimé même sans changement de tarif');
    System.assertEquals(700, data.nouveauTjm, 'Le tarif inchangé est celui de la matrice');
    System.assertEquals(AV_START, data.revisionPrixADateDu);
    System.assert(!data.schedule.isEmpty());
  }

  @IsTest
  static void testMatrixAvenant_tarifSeul_neImprimePasLaProlongation() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');

    AR_PTFData data = snapshotOf(AR_PTFGenerationService.generateAvenantInput(matrixInput(av.Id)).ptfDocumentId);

    System.assertEquals(null, data.prolongationJusquAu, 'Période = Non : pas de paragraphe de prolongation');
    System.assertEquals(true, data.revisionPrix);
    System.assertEquals(650, data.nouveauTjm);
    System.assert(!data.schedule.isEmpty());
  }

  @IsTest
  static void testMatrixAvenant_coutSeul_genereQuandMemeUnDocumentSansBlocDePrix() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Conditions financières', 700, 'Validée');

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(av.Id)
    );

    System.assertNotEquals(null, result.ptfDocumentId, 'Q4 B : le document est généré même si seul le coût change');
    AR_PTFData data = snapshotOf(result.ptfDocumentId);
    System.assertEquals(false, data.revisionPrix);
    System.assertEquals(null, data.prolongationJusquAu);
    System.assertEquals(null, data.nouveauTjm);
    System.assert(data.schedule.isEmpty());
  }

  @IsTest
  static void testMatrixAvenant_refusals_nameTheCause() {
    System.runAs(AR_TestPersona.francais()) {
      AR_PTF_Document__c origin = validatedOriginWithPtf();
      AR_Price_Matrix__c draft = newAvenantMatrix(origin, 'Tarif', 650, 'Brouillon');
      AR_Price_Matrix__c ok = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');
      Id notAvenant = origin.AR_Price_Matrix__c;

      Map<Id, String> expected = new Map<Id, String>{
        draft.Id => 'n\'est pas validé',
        notAvenant => 'n\'est pas un avenant'
      };
      for (Id matrixId : expected.keySet()) {
        try {
          AR_PTFGenerationService.generateAvenantInput(matrixInput(matrixId));
          System.assert(false, 'Refus attendu pour ' + matrixId);
        } catch (AuraHandledException e) {
          System.assert(e.getMessage().contains(expected.get(matrixId)), 'Reçu : ' + e.getMessage());
        }
      }
      // PTF indiquée différente de celle que la matrice amende
      AR_PTF_Document__c other = new AR_PTF_Document__c(
        AR_Price_Matrix__c = origin.AR_Price_Matrix__c,
        AR_Position__c = origin.AR_Position__c,
        AR_Reference__c = 'PTF-MAT-OTHER-V2',
        AR_Version_Number__c = 2,
        AR_Snapshot__c = '{}',
        AR_Generated_At__c = System.now(),
        AR_Generation_Status__c = 'Généré'
      );
      insert other;
      AR_PTFDataService.AvenantGenerationInput wrong = matrixInput(ok.Id);
      wrong.ptfDocumentId = other.Id;
      try {
        AR_PTFGenerationService.generateAvenantInput(wrong);
        System.assert(false, 'Refus attendu : la PTF indiquée n\'est pas celle que la matrice amende');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('pas celle que cet avenant amende'), 'Reçu : ' + e.getMessage());
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Document_Type__c = 'Avenant'],
        'Aucun document inséré par un refus'
      );
    }
  }

  @IsTest
  static void testGenerateAvenantIfNeeded_createsOnceThenIsIdempotent() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');

    System.assertEquals(
      null,
      AR_PTFGenerationService.generateAvenantIfNeeded(origin.AR_Price_Matrix__c),
      'Une matrice qui n\'est pas un avenant : rien à faire'
    );
    AR_PTFGenerationService.PTFGenerationResult first = AR_PTFGenerationService.generateAvenantIfNeeded(av.Id);
    System.assertNotEquals(null, first);
    System.assertEquals('En cours', first.status);
    System.assertEquals(
      null,
      AR_PTFGenerationService.generateAvenantIfNeeded(av.Id),
      'Un document En cours existe déjà : pas de doublon (double clic, deux onglets)'
    );

    AR_PTFGenerationService.renderAndStorePTF(first.ptfDocumentId);
    System.assertEquals(null, AR_PTFGenerationService.generateAvenantIfNeeded(av.Id), 'Idem une fois Généré');
    System.assertEquals(1, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Document_Type__c = 'Avenant']);
  }

  @IsTest
  static void testGenerateAvenantIfNeeded_notValidated_doesNothing() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c draft = newAvenantMatrix(origin, 'Tarif', 650, 'Brouillon');

    System.assertEquals(null, AR_PTFGenerationService.generateAvenantIfNeeded(draft.Id));
    System.assertEquals(0, [SELECT COUNT() FROM AR_PTF_Document__c WHERE AR_Document_Type__c = 'Avenant']);
  }

  @IsTest
  static void testGenerateAvenantIfNeeded_afterFailure_retriesWithTheSameAvenantNumber() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');
    AR_PTFGenerationService.PTFGenerationResult first = AR_PTFGenerationService.generateAvenantIfNeeded(av.Id);
    update new AR_PTF_Document__c(Id = first.ptfDocumentId, AR_Generation_Status__c = 'Échec');

    AR_PTFGenerationService.PTFGenerationResult retry = AR_PTFGenerationService.generateAvenantIfNeeded(av.Id);

    System.assertNotEquals(null, retry, 'Un document en Échec ne bloque pas la reprise');
    System.assertNotEquals(first.ptfDocumentId, retry.ptfDocumentId);
    System.assertEquals(1, retry.versionNumber, 'Un échec ne consomme pas de numéro d\'avenant');
    System.assertEquals(
      1,
      [SELECT AR_Avenant_Number__c FROM AR_PTF_Document__c WHERE Id = :retry.ptfDocumentId].AR_Avenant_Number__c
    );
  }

  @IsTest
  static void testMatrixAvenant_secondAvenantOnTheSamePtf_isAV2_andFirstIsKept() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c first = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');
    AR_PTFGenerationService.PTFGenerationResult r1 = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(first.Id)
    );
    AR_PTFGenerationService.renderAndStorePTF(r1.ptfDocumentId);
    // Avenant d'avenant (Q8 A) : deuxième matrice avenant, qui amende toujours la PTF initiale.
    AR_Price_Matrix__c second = newAvenantMatrix(origin, 'Période', 650, 'Validée');

    AR_PTFGenerationService.PTFGenerationResult r2 = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(second.Id)
    );

    AR_PTF_Document__c doc2 = [
      SELECT AR_Avenant_Number__c, AR_Parent_PTF__c, AR_Price_Matrix__c, AR_Reference__c
      FROM AR_PTF_Document__c
      WHERE Id = :r2.ptfDocumentId
    ];
    System.assertEquals(2, doc2.AR_Avenant_Number__c);
    System.assertEquals(origin.Id, doc2.AR_Parent_PTF__c);
    System.assertEquals(second.Id, doc2.AR_Price_Matrix__c);
    System.assert(doc2.AR_Reference__c.startsWith('PTF_ABYLSEN_') && doc2.AR_Reference__c.endsWith('_AV2'), doc2.AR_Reference__c);
    System.assertEquals(
      'Généré',
      [SELECT AR_Generation_Status__c FROM AR_PTF_Document__c WHERE Id = :r1.ptfDocumentId].AR_Generation_Status__c,
      'Le premier avenant est conservé'
    );
  }

  @IsTest
  static void testMatrixAvenant_fileName_carriesAvenantPeriodAndAvNumber() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif;Période', 780, 'Validée');
    AR_PTFGenerationService.PTFGenerationResult started = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(av.Id)
    );

    AR_PTFGenerationService.PTFGenerationResult rendered = AR_PTFGenerationService.renderAndStorePTF(
      started.ptfDocumentId
    );

    System.assertEquals('Généré', rendered.status);
    ContentVersion cv = [SELECT Title FROM ContentVersion WHERE FirstPublishLocationId = :av.Id LIMIT 1];
    System.assert(cv.Title.startsWith('PTF_ABYLSEN_'), 'Reçu : ' + cv.Title);
    System.assert(cv.Title.endsWith('_20261001-20261231_AV1'), 'Période de l\'avenant puis numéro AV : ' + cv.Title);
    System.assert(cv.Title.contains('Client_PTF_Gen'), 'Reçu : ' + cv.Title);
  }

  @IsTest
  static void testLegacyAvenant_staysOnOriginMatrix_andIsListedWithoutRedirect() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      avenantInputFor(origin.Id)
    );

    System.assertEquals(
      origin.AR_Price_Matrix__c,
      [SELECT AR_Price_Matrix__c FROM AR_PTF_Document__c WHERE Id = :result.ptfDocumentId].AR_Price_Matrix__c,
      'Un avenant historique reste rattaché à la matrice de la PTF d\'origine'
    );
    AR_PTFData data = snapshotOf(result.ptfDocumentId);
    System.assertEquals(Date.newInstance(2026, 12, 31), data.prolongationJusquAu, 'Prolongation du formulaire inchangée');
    System.assertEquals(false, data.revisionPrix);
    Boolean listed = false;
    for (AR_PTFHistoryService.PTFDocumentRow row : AR_PTFGenerationService.listPTFDocuments(origin.AR_Price_Matrix__c)) {
      if (row.ptfDocumentId == result.ptfDocumentId) {
        listed = true;
        System.assertEquals(null, row.avenantMatrixId, 'Pas de renvoi pour un avenant historique');
      }
    }
    System.assert(listed, 'Un ancien avenant reste listé');
  }

  @IsTest
  static void testOriginList_showsMatrixAvenantWithRedirectToItsMatrix() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generateAvenantInput(
      matrixInput(av.Id)
    );

    AR_PTFHistoryService.PTFDocumentRow onOrigin;
    for (AR_PTFHistoryService.PTFDocumentRow row : AR_PTFGenerationService.listPTFDocuments(origin.AR_Price_Matrix__c)) {
      if (row.ptfDocumentId == result.ptfDocumentId) {
        onOrigin = row;
      }
    }
    System.assertNotEquals(null, onOrigin, 'La matrice d\'origine liste l\'avenant de sa PTF');
    System.assertEquals('Avenant', onOrigin.documentType);
    System.assertEquals(1, onOrigin.avenantNumber);
    System.assertEquals(av.Id, onOrigin.avenantMatrixId);
    System.assertEquals('V3', onOrigin.avenantMatrixLabel);

    AR_PTFHistoryService.PTFDocumentRow onAvenant;
    for (AR_PTFHistoryService.PTFDocumentRow row : AR_PTFGenerationService.listPTFDocuments(av.Id)) {
      if (row.ptfDocumentId == result.ptfDocumentId) {
        onAvenant = row;
      }
    }
    System.assertNotEquals(null, onAvenant, 'La matrice avenant liste son propre document');
    System.assertEquals(null, onAvenant.avenantMatrixId, 'Pas de renvoi vers soi-même');
  }

  @IsTest
  static void testGetAvenantState_avenantAndNonAvenant() {
    AR_PTF_Document__c origin = validatedOriginWithPtf();
    AR_Price_Matrix__c av = newAvenantMatrix(origin, 'Tarif', 650, 'Validée');

    AR_PTFGenerationService.AvenantState plain = AR_PTFGenerationService.getAvenantState(origin.AR_Price_Matrix__c);
    System.assertEquals(false, plain.isAvenant);
    System.assertEquals(null, plain.amendedPtfId);

    AR_PTFGenerationService.AvenantState state = AR_PTFGenerationService.getAvenantState(av.Id);
    System.assertEquals(true, state.isAvenant);
    System.assertEquals('Validée', state.matrixStatus);
    System.assertEquals(origin.Id, state.amendedPtfId);
    System.assertEquals('PTF-MAT-ORIG-V1', state.amendedPtfReference);
    System.assertEquals(origin.AR_Price_Matrix__c, state.amendedPtfMatrixId);
    System.assertEquals(AV_START, state.effectiveDate);
    System.assertEquals(AV_END, state.endDate);
    System.assertEquals(650, state.proposedTjm);
    System.assertEquals(true, state.printsPriceBlock, 'Tarif = Oui : bloc tarif et échéancier imprimé');

    AR_Price_Matrix__c costOnly = newAvenantMatrix(origin, 'Conditions financières', 700, 'Validée');
    System.assertEquals(false, AR_PTFGenerationService.getAvenantState(costOnly.Id).printsPriceBlock);
    AR_Price_Matrix__c extension = newAvenantMatrix(origin, 'Période', 700, 'Validée');
    System.assertEquals(true, AR_PTFGenerationService.getAvenantState(extension.Id).printsPriceBlock, 'Q5 B');
  }

  @IsTest
  static void testLegacyAvenantFileName_alsoCarriesTheAvNumber() {
    AR_PTFData data = new AR_PTFData();
    data.client = 'Client X';
    data.managerName = 'Alexis ROQUES';
    data.consultantNom = 'Paul MARTIN';
    data.dateDebut = Date.newInstance(2026, 1, 5);
    data.dateFin = Date.newInstance(2026, 6, 30);
    data.templateCode = 'AVENANT_AT_V11';
    data.version = 'AV2';
    System.assertEquals(
      'PTF_ABYLSEN_ARO_Client_X_PMA_20260105-20260630_AV2',
      AR_PTFGenerationService.buildNomenclatureFileName(data)
    );
    data.templateCode = 'ABYLSEN_AT_V11';
    data.version = 'V2';
    System.assertEquals(
      'PTF_ABYLSEN_ARO_Client_X_PMA_20260105-20260630',
      AR_PTFGenerationService.buildNomenclatureFileName(data),
      'Une PTF ne reçoit jamais de suffixe AV'
    );
  }
}