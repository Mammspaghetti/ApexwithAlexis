/**
 * Tests AR_PTFTemplateController : c'est le contrôleur, indépendamment du moteur PDF (impossible à
 * exécuter en contexte de test), qui doit garantir qu'un id valide produit une structure `ptf`
 * renseignée. Absent en session 20 — Test.isRunningTest() court-circuitait tout rendu PDF avant même
 * que le contrôleur ne soit instancié, laissant sa logique de lecture entièrement hors couverture.
 * Défaut constaté en contrôle navigateur le 11/08/2026 : un PDF structurellement complet mais
 * totalement vide de données, jamais détecté par la suite de tests de la session 20.
 */
@IsTest
private class AR_PTFTemplateControllerTest {
  @TestSetup
  static void setup() {
    Account acc = new Account(
      Name = 'Client Controller Test',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001'
    );
    insert acc;

    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin Controller Test',
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
      AR_Status__c = 'Validée',
      AR_Account_Name__c = 'Client Controller Test',
      AR_Entity_Ref__c = AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'),
      AR_Consultant_Name__c = 'Jean DUPONT',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 9, 30)
    );
  }

  @IsTest
  static void testConstructor_validId_populatesClientTjmAndReference() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    // Dates + livrables renseignés : exerce aussi l'accumulation de totalJours (schedule non vide)
    // et le découpage des livrables, pas seulement les champs texte simples.
    input.livrables = 'Compte-rendu\nRapport final';

    // L'insertion du snapshot est synchrone (précède l'enqueueJob du rendu, cf.
    // AR_PTFGenerationService.generatePTFInput) : ce test porte uniquement sur la lecture par le
    // contrôleur, pas sur le Queueable — pas besoin de Test.startTest/stopTest pour le flusher.
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(
      input
    );

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', result.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    // Les trois champs relevés dans le constat du 11/08/2026 (rendus vides en production).
    System.assertEquals(
      'Client Controller Test',
      controller.ptf.client,
      'Le client doit être lu depuis le snapshot déjà committé'
    );
    System.assertEquals(700, controller.ptf.tjm, 'Le TJM doit être lu depuis le snapshot');
    System.assertEquals(
      result.reference,
      controller.ptf.reference,
      'La référence doit être lue depuis le snapshot'
    );
    System.assertEquals('Jean DUPONT', controller.ptf.consultantNom);
    System.assert(
      controller.ptf.schedule.size() > 0,
      'Des dates de mission renseignées doivent produire un échéancier non vide'
    );
    System.assert(
      controller.totalJours > 0,
      'totalJours doit accumuler les jours de l\'échéancier'
    );
    System.assertEquals(
      new List<String>{ 'Compte-rendu', 'Rapport final' },
      controller.livrableLines
    );

    // Formats français (session 20c) : indépendants de la locale de l'utilisateur courant — cf.
    // AR_PTFFormatUtilTest pour la preuve en runAs locale anglaise. Ici, on vérifie que le
    // contrôleur relie bien ptf.* aux libellés attendus par la page.
    System.assert(
      controller.dateDebutLabel.contains('septembre'),
      'Date de début en français : ' + controller.dateDebutLabel
    );
    System.assert(
      controller.dateFinLabel.contains('septembre'),
      'Date de fin en français : ' + controller.dateFinLabel
    );
    System.assertNotEquals(null, controller.generatedAtLabel);
    System.assert(
      controller.tjmLabel.contains('700') && controller.tjmLabel.contains('€'),
      'TJM formaté : ' + controller.tjmLabel
    );
    System.assert(
      controller.tjmPerDayLabel.endsWith('/j'),
      'TJM par jour doit se terminer par /j : ' + controller.tjmPerDayLabel
    );
    System.assertNotEquals(
      null,
      controller.joursParMoisLabel,
      'Toujours renseigné (référentiel AR_Settings__mdt), jamais "À définir"'
    );

    // Échéancier calculable (dates renseignées) : jamais "À définir", cf. §2 du prompt 20c.
    System.assertEquals(true, controller.hasSchedule);
    System.assertNotEquals('À définir', controller.totalHTLabel);
    System.assertNotEquals('À définir', controller.totalJoursLabel);
    System.assertEquals(
      controller.ptf.schedule.size(),
      controller.scheduleDisplay.size()
    );
    AR_PTFTemplateController.ScheduleRowDisplay firstRow = controller.scheduleDisplay[0];
    System.assertEquals(controller.ptf.schedule[0].mois, firstRow.mois);
    System.assert(firstRow.joursLabel.endsWith('j'));
    System.assert(firstRow.montantLabel.endsWith('€'));
    System.assert(firstRow.cumulLabel.endsWith('€'));
  }

  @IsTest
  static void testConstructor_noMissionDates_totalsAreADefinirNotZero() {
    // Matrice sans dates de mission : distingue "donnée manquante" (À définir) d'un vrai calcul à
    // zéro — c'est le défaut relevé le 11/08/2026 (session 20c §2) sur DEMO ARQUUS - Satory.
    // Session 184c3 : plus de gabarit générique, et le gabarit Abylsen refuse toute génération sans
    // dates de mission (session 49) — le snapshot sans dates (document ancien) est donc posé
    // directement ; le contrôleur lit le snapshot, il ne recalcule rien.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFData snapshot = new AR_PTFData();
    snapshot.client = 'Client Sans Dates';
    snapshot.tjm = 931;
    snapshot.currencyCode = 'EUR';
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-S184C3-SANSDATES-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = JSON.serialize(snapshot),
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'En cours'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(false, controller.hasSchedule);
    System.assertEquals(
      'À définir',
      controller.totalHTLabel,
      'Aucune date de mission : le montant total ne doit jamais être un 0 inventé'
    );
    System.assertEquals(
      'À définir',
      controller.totalJoursLabel,
      'Aucune date de mission : le total de jours ne doit jamais être un 0 inventé'
    );
    // Le TJM, lui, reste toujours calculable (indépendant de l'échéancier) : jamais "À définir".
    System.assert(controller.tjmLabel.contains('931'));
  }

  @IsTest
  static void testConstructor_noIdParameter_returnsEmptyStructureWithoutError() {
    Test.setCurrentPageReference(Page.AR_PTFTemplate);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(null, controller.ptf.client);
    System.assertEquals(0, controller.ptf.schedule.size());
    System.assertEquals(0, controller.livrableLines.size());
    // applyDisplayLabels() ne doit jamais planter sur une structure vide (aucun id fourni).
    System.assertEquals(false, controller.hasSchedule);
    System.assertEquals('À définir', controller.totalHTLabel);
    System.assertEquals('À définir', controller.totalJoursLabel);
    System.assertEquals(null, controller.tjmLabel);
    System.assertEquals(null, controller.dateDebutLabel);
    System.assertEquals(0, controller.scheduleDisplay.size());
  }

  @IsTest
  static void testConstructor_snapshotMissingScheduleAndEntiteInfo_defaultsToEmptyNotNull() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // JSON.deserialize non strict laisse à null les clés absentes : un snapshot plus ancien ou
    // partiel (avant l'ajout d'un champ, par exemple) ne doit pas planter la page pour autant.
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-PARTIAL',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client sans échéancier"}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals('Client sans échéancier', controller.ptf.client);
    System.assertNotEquals(
      null,
      controller.ptf.schedule,
      'schedule absent du JSON doit être remplacé par une liste vide, jamais rester null (itéré par la page)'
    );
    System.assertEquals(0, controller.ptf.schedule.size());
    System.assertNotEquals(
      null,
      controller.ptf.entiteInfo,
      'entiteInfo absent du JSON doit être remplacé par une structure vide, jamais rester null'
    );
  }

  @IsTest
  static void testConstructor_corruptSnapshot_fallsBackToEmptyStructureWithoutThrowing() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-CORRUPT',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = 'ceci n\'est pas du JSON valide',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Échec'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    // Le constructeur ne doit jamais lever d'exception : la page se rend avec une structure vide
    // plutôt qu'une erreur brute (comportement volontaire, cf. commentaire du catch).
    System.assertEquals(null, controller.ptf.client);
    System.assertEquals(0, controller.ptf.schedule.size());
    System.assertNotEquals(null, controller.ptf.entiteInfo);
    System.assertEquals(0, controller.totalJours);
    System.assertEquals(0, controller.livrableLines.size());
  }

  // ------------------------------------------------------------------
  // Socle multi-devises, restitution (session 24b).
  // ------------------------------------------------------------------

  /**
   * Non-régression EUR — le test le plus important de cette partie (prompt) : le texte de la
   * mention légale doit rester EXACTEMENT celui d'avant ce bloc pour une PTF en euros, au caractère
   * près, et aucune mention de devise supplémentaire ne doit apparaître.
   */
  @IsTest
  static void testConstructor_eurMatrix_legalMentionAndLabelsUnchanged() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(input);

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', result.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      'Tous les montants sont exprimés en euros hors taxes. TVA au taux légal en vigueur à la date de facturation.',
      controller.currencyLegalMentionLabel,
      'Texte identique, au caractère près, à celui d\'avant la session 24b pour une PTF EUR'
    );
    System.assertEquals(false, controller.showCurrencyMention, 'Pas de mention "Devise de facturation" supplémentaire pour une PTF EUR');
    System.assertEquals('EUR', controller.currencyCodeLabel);
    System.assert(controller.tjmLabel.contains('€'));
    System.assert(controller.scheduleDisplay[0].montantLabel.endsWith('€'));
  }

  @IsTest
  static void testConstructor_gbpMatrix_usesPoundSymbolAndExplicitCurrencyMention() {
    // Matrice dédiée, GBP posé à l'INSERT (pas un update après coup) : une matrice « Validée » est
    // verrouillée par AR_PriceMatrixTriggerHandler dès sa création dans ce @TestSetup — modifier
    // AR_Currency__c via update() après coup échouerait avec « ne peut plus être modifiée ».
    Account acc = new Account(
      Name = 'Client Devise Livres Sterling PTF',
      AB_Account_industry__c = 'IT / Telecoms',
      TP_Business_Line__c = 'IT',
      ShippingStreet = '1 rue de Test',
      ShippingCity = 'Paris',
      ShippingPostalCode = '75001'
    );
    insert acc;
    cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
      Name = 'Besoin Devise Livres Sterling PTF',
      cxsrec__Account__c = acc.Id,
      cxsrec__Country__c = 'Royaume-Uni',
      cxsrec__Status__c = 'Open',
      cxsrec__Contract_type__c = 'CDI'
    );
    insert position;
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
      OwnerId = AR_TestPersona.ownerWithDa(),
      AR_Position__c = position.Id,
      AR_Contract_Type__c = 'CDI',
      AR_Annual_Salary__c = 43600,
      AR_RFA_Percent__c = 0,
      AR_Proposed_TJM__c = 700,
      AR_Status__c = 'Validée',
      AR_Currency__c = 'GBP',
      AR_Account_Name__c = 'Client Devise Livres Sterling PTF',
      AR_Entity_Ref__c = AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'),
      AR_Consultant_Name__c = 'Jean DUPONT',
      AR_Start_Date__c = Date.newInstance(2026, 9, 1),
      AR_End_Date__c = Date.newInstance(2026, 9, 30)
    );
    insert matrix;

    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(input);

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', result.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(true, controller.showCurrencyMention);
    System.assertEquals('GBP', controller.currencyCodeLabel);
    System.assert(
      controller.tjmLabel.contains('700') && controller.tjmLabel.contains('£'),
      'TJM formaté en livres, jamais en euros : ' + controller.tjmLabel
    );
    System.assert(!controller.tjmLabel.contains('€'), 'Un document GBP ne doit jamais afficher un symbole euro');
    System.assert(controller.scheduleDisplay[0].montantLabel.endsWith('£'));
    System.assert(controller.scheduleDisplay[0].cumulLabel.endsWith('£'));
    System.assertEquals(
      'Tous les montants sont exprimés en livres sterling hors taxes. TVA au taux légal en vigueur à la date de facturation.',
      controller.currencyLegalMentionLabel
    );
  }

  @IsTest
  static void testConstructor_snapshotWithoutCurrencyCode_legacyDocument_defaultsToEur() {
    // Un document PTF généré avant la session 24b n'a pas de "currencyCode" dans son JSON —
    // JSON.deserialize non strict laisse le champ à null, et une régénération/re-rendu ne doit
    // jamais afficher un symbole ou un texte différent de ce que ce document affichait déjà.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-LEGACY',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client Legacy","tjm":700}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(false, controller.showCurrencyMention);
    System.assert(controller.tjmLabel.contains('€'));
  }

  @IsTest
  static void testConstructor_idNotAPtfDocument_returnsEmptyStructureWithoutError() {
    PageReference pageRef = Page.AR_PTFTemplate;
    // Id syntaxiquement valide (18 caractères) mais qui ne référence aucun AR_PTF_Document__c.
    pageRef.getParameters().put('id', UserInfo.getUserId());
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(null, controller.ptf.client);
    System.assertEquals(0, controller.totalJours);
  }

  // ------------------------------------------------------------------
  // Prévisualisation transitoire — paramètre `data` (session 30).
  // ------------------------------------------------------------------

  @IsTest
  static void testConstructor_previewDataParam_populatesFromBase64AndSetsIsPreview() {
    AR_PTFData preview = new AR_PTFData();
    preview.client = 'Client Aperçu';
    preview.tjm = 850;
    preview.reference = 'PTF-APERCU-V1';
    preview.version = 'V1';
    preview.currencyCode = 'EUR';
    // isPreview volontairement laissé à false ici : c'est le CONTRÔLEUR qui doit le forcer à true
    // pour ce chemin, jamais la donnée décodée elle-même — sinon un aperçu mal construit pourrait
    // se faire passer pour un document réel.
    preview.isPreview = false;
    String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview)));

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', encoded);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals('Client Aperçu', controller.ptf.client);
    System.assert(controller.tjmLabel.contains('850'));
    System.assertEquals(
      true,
      controller.ptf.isPreview,
      'Le contrôleur doit forcer isPreview=true pour tout rendu via le paramètre data, même si la donnée décodée portait false'
    );
    // Pas d'historique dans ce payload minimal : repli legacy à une seule ligne (comportement
    // inchangé), preuve que le chemin `data` réutilise la même logique d'affichage que `id`.
    System.assertEquals(1, controller.historiqueDisplay.size());
    System.assertEquals('PTF-APERCU-V1', controller.historiqueDisplay[0].reference);
  }

  // Au-delà de 9 lots, « Lot 10: » ne tient plus dans l'étiquette de 26,5 pt du modèle : la page
  // Abylsen élargit toutes les étiquettes. Jusqu'à 9 lots, rendu strictement identique au modèle.
  @IsTest
  static void testConstructor_lotsLibellesLarges_onlyAboveNineLots() {
    Test.setCurrentPageReference(Page.AR_PTFTemplateAbylsen);
    Test.startTest();
    AR_PTFTemplateController neuf = buildWithLots(9);
    AR_PTFTemplateController dix = buildWithLots(10);
    Test.stopTest();
    System.assertEquals(9, neuf.lotsDisplay.size());
    System.assertEquals(false, neuf.lotsLibellesLarges, '9 lots : étiquettes du modèle');
    System.assertEquals(10, dix.lotsDisplay.size());
    System.assertEquals(true, dix.lotsLibellesLarges, '10 lots : étiquettes élargies');
  }

  private static AR_PTFTemplateController buildWithLots(Integer n) {
    AR_PTFData data = new AR_PTFData();
    data.currencyCode = 'EUR';
    data.lots = new List<AR_PTFData.LotRow>();
    for (Integer i = 0; i < n; i++) {
      AR_PTFData.LotRow lot = new AR_PTFData.LotRow();
      lot.libelle = 'Lot ' + (i + 1);
      lot.montant = 11970;
      lot.montantCalcule = 11970;
      data.lots.add(lot);
    }
    ApexPages.currentPage().getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(data))));
    return new AR_PTFTemplateController();
  }

  @IsTest
  static void testConstructor_dataParamTakesPriorityOverIdParam() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(input);

    AR_PTFData preview = new AR_PTFData();
    preview.client = 'Client Aperçu Prioritaire';
    String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview)));

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', encoded);
    pageRef.getParameters().put('id', result.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      'Client Aperçu Prioritaire',
      controller.ptf.client,
      'data doit primer sur id si les deux sont présents par erreur'
    );
  }

  @IsTest
  static void testConstructor_corruptDataParam_fallsBackToEmptyStructureWithoutThrowing() {
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', 'pas-du-base64-json-valide!!!');
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(null, controller.ptf.client);
    System.assertEquals(0, controller.historiqueDisplay.size());
  }

  // ------------------------------------------------------------------
  // Historique multi-versions figé (session 30) : non-régression au sens 23b, un ancien document
  // rendu de nouveau (usage debug/audit direct via id) ne doit jamais afficher une version postérieure
  // à sa propre génération.
  // ------------------------------------------------------------------

  @IsTest
  static void testConstructor_multipleHistoryRows_displaysAllInOrder() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-HIST-V2',
      AR_Version_Number__c = 2,
      AR_Snapshot__c = '{"client":"Client Historique","historique":[' +
        '{"version":"V1","reference":"PTF-TEST-HIST-V1","objetModification":"Création","redacteurNom":"A"},' +
        '{"version":"V2","reference":"PTF-TEST-HIST-V2","objetModification":"Régénération","redacteurNom":"A"}' +
        ']}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(2, controller.historiqueDisplay.size());
    System.assertEquals('V1', controller.historiqueDisplay[0].version);
    System.assertEquals('Création', controller.historiqueDisplay[0].objetModification);
    System.assertEquals('V2', controller.historiqueDisplay[1].version);
    System.assertEquals('Régénération', controller.historiqueDisplay[1].objetModification);
  }

  @IsTest
  static void testConstructor_oldDocumentWithFrozenHistorique_neverShowsLaterVersion() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // Document V1 dont le snapshot a été figé AVANT que V2 n'existe : son historique ne connaît
    // que lui-même — exactement ce que produit AR_PTFDataService.buildHistorique en pratique.
    AR_PTF_Document__c oldDoc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-OLD-V1',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client Ancien","version":"V1","reference":"PTF-TEST-OLD-V1",' +
        '"historique":[{"version":"V1","reference":"PTF-TEST-OLD-V1","objetModification":"Création"}]}',
      AR_Generated_At__c = System.now().addDays(-10),
      AR_Generation_Status__c = 'Généré'
    );
    insert oldDoc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', oldDoc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      1,
      controller.historiqueDisplay.size(),
      'Un document ancien rendu de nouveau ne doit jamais afficher une version apparue après sa propre génération'
    );
    System.assertEquals('V1', controller.historiqueDisplay[0].version);
    for (AR_PTFTemplateController.HistoryRowDisplay row : controller.historiqueDisplay) {
      System.assertNotEquals('V2', row.version, 'V2 n\'existait pas au moment de la génération de ce document');
    }
  }

  @IsTest
  static void testConstructor_legacySnapshotWithoutHistorique_fallsBackToSingleCurrentRow() {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // Document généré avant la session 30 : pas de clé "historique" dans le JSON du tout.
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-LEGACY-HIST',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client Legacy Historique","version":"V1","reference":"PTF-TEST-LEGACY-HIST","redacteurNom":"Rédacteur Legacy"}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    // Non-régression : un document pré-session-30 doit continuer d'afficher exactement ce qu'il
    // affichait avant cette session — une seule ligne, la version courante, jamais une table vide.
    System.assertEquals(1, controller.historiqueDisplay.size());
    System.assertEquals('V1', controller.historiqueDisplay[0].version);
    System.assertEquals('Rédacteur Legacy', controller.historiqueDisplay[0].redacteurNom);
  }

  // ------------------------------------------------------------------
  // Session 36 — gabarit Abylsen AT v11 : materielLabel (C27), dureeMoisLabel (C57), totaux de lots.
  // ------------------------------------------------------------------

  @IsTest
  static void testApplyDisplayLabels_materielItemsEmpty_labelQuotesClientName() {
    AR_PTFData preview = new AR_PTFData();
    preview.client = 'Client Test';
    preview.materielItems = new List<String>();
    String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview)));

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', encoded);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      'Mis à disposition par « CLIENT TEST »',
      controller.materielLabel,
      'C27 : guillemets français, corrigés en session 49 (cause C #3) — la session 35 avait posé des guillemets droits'
    );
  }

  @IsTest
  static void testApplyDisplayLabels_materielItemsPresent_prefixedByOui() {
    AR_PTFData preview = new AR_PTFData();
    preview.client = 'Client Test';
    preview.materielItems = new List<String>{ 'PC portable', 'Badge' };
    String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview)));

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', encoded);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals('OUI — PC portable, Badge', controller.materielLabel);
  }

  @IsTest
  static void testApplyDisplayLabels_lotsTotals_and_dureeMoisLabel() {
    AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTFDataService.LotOverride lotOverride = new AR_PTFDataService.LotOverride();
    lotOverride.index = 0;
    lotOverride.montant = 5000;
    AR_PTFDataService.GenerationInput input = new AR_PTFDataService.GenerationInput();
    input.matrixId = matrix.Id;
    input.valideurNom = 'Valideur Test';
    input.lotOverrides = new List<AR_PTFDataService.LotOverride>{ lotOverride };

    AR_PTFGenerationService.PTFGenerationResult result = AR_PTFGenerationService.generatePTFInput(input);

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', result.ptfDocumentId);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(true, controller.hasLotOverride);
    System.assertNotEquals(null, controller.lotsTotalLabel);
    System.assertNotEquals(null, controller.lotsTotalCalculeLabel);
    System.assertNotEquals(
      controller.lotsTotalLabel,
      controller.lotsTotalCalculeLabel,
      'Un lot surchargé doit rendre le total retenu visiblement différent du total théorique'
    );
  }

  @IsTest
  static void testApplyDisplayLabels_dureeMois_nullAndPopulated() {
    AR_PTFData withDuree = new AR_PTFData();
    withDuree.dureeMois = 6;
    PageReference pageRef1 = Page.AR_PTFTemplate;
    pageRef1.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(withDuree))));
    Test.setCurrentPageReference(pageRef1);
    AR_PTFTemplateController controller1 = new AR_PTFTemplateController();
    System.assertEquals('6', controller1.dureeMoisLabel);

    AR_PTFData withoutDuree = new AR_PTFData();
    PageReference pageRef2 = Page.AR_PTFTemplate;
    pageRef2.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(withoutDuree))));
    Test.setCurrentPageReference(pageRef2);
    AR_PTFTemplateController controller2 = new AR_PTFTemplateController();
    System.assertEquals(null, controller2.dureeMoisLabel);
  }

  // ------------------------------------------------------------------
  // Session 57 — tableau d'identification (page de garde Abylsen/avenant) : versionNumeroLabel,
  // dérivé de ptf.version ("V1"/"AV2"...) en un numéro zéro-paddé ("01"/"02"...), jamais le préfixe
  // de lettre qui reste le format interne inchangé partout ailleurs.
  // ------------------------------------------------------------------

  @IsTest
  static void testVersionNumeroLabel_ptfVersion_stripsLetterAndZeroPads() {
    AR_PTFData preview = new AR_PTFData();
    preview.version = 'V1';
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview))));
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals('01', controller.versionNumeroLabel);
  }

  @IsTest
  static void testVersionNumeroLabel_avenantVersionAboveNine_noExtraPadding() {
    AR_PTFData preview = new AR_PTFData();
    preview.version = 'AV12';
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview))));
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals('12', controller.versionNumeroLabel);
  }

  @IsTest
  static void testVersionNumeroLabel_blankVersion_staysNullNeverFabricated() {
    Test.setCurrentPageReference(Page.AR_PTFTemplate);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      null,
      controller.versionNumeroLabel,
      'Aucune structure (id/data) fournie : jamais un "00" inventé'
    );
  }

  // ------------------------------------------------------------------
  // Session 138 — répartition de l'historique entre la page de garde (hauteur fixe) et la suite.
  // ------------------------------------------------------------------

  /** Session 279 : un snapshot antérieur (sans adresseClientCompte ni adresseClientModifiee) se relit
   * sans perte — l'ajout des deux propriétés est additif. */
  @IsTest
  static void testOldSnapshot_withoutClientAddressFlags_rendersWithoutLoss() {
    String oldSnapshot = '{"client":"Client Ancien","adresseClient":"1 rue Ancienne\\n75001 Paris",' +
      '"reference":"PTF-OLD-V1","version":"V1","tjm":650,"historique":[]}';
    AR_PTFTemplateController c = controllerFor(oldSnapshot);
    System.assertEquals('Client Ancien', c.ptf.client);
    System.assertEquals('1 rue Ancienne\n75001 Paris', c.ptf.adresseClient, 'Adresse relue telle quelle');
    System.assertEquals('PTF-OLD-V1', c.ptf.reference);
    System.assertEquals(650, c.ptf.tjm);
    System.assertEquals(null, c.ptf.adresseClientModifiee, 'Propriété absente du snapshot ancien : null');
    System.assertEquals(null, c.ptf.adresseClientCompte);
  }

  /** Session 279 : un snapshot récent porte l'adresse saisie et l'indicateur, relus tels quels. */
  @IsTest
  static void testNewSnapshot_withModifiedClientAddress_printsTypedAddress() {
    AR_PTFData d = new AR_PTFData();
    d.client = 'Client Neuf';
    d.reference = 'PTF-NEW-V1';
    d.version = 'V1';
    d.adresseClient = '5 rue Saisie\n69000 Lyon';
    d.adresseClientCompte = '10 avenue du Client\n69002 Lyon';
    d.adresseClientModifiee = true;
    AR_PTFTemplateController c = controllerFor(JSON.serialize(d));
    System.assertEquals('5 rue Saisie\n69000 Lyon', c.ptf.adresseClient, 'L\'adresse imprimée est la saisie');
    System.assertEquals(true, c.ptf.adresseClientModifiee);
  }

  private static String historySnapshot(Integer count, String longDetailAtRow) {
    List<String> rows = new List<String>();
    for (Integer i = 1; i <= count; i++) {
      String modif = i == 1 ? '' : (String.valueOf(i) == longDetailAtRow ? 'Révision du périmètre de la mission suite au comité de pilotage : ajout de deux consultants supplémentaires, extension de la durée de la prestation de trois mois, nouvelle répartition des lots et ajustement du taux journalier' : 'Modification de montant');
      rows.add(
        '{"version":"V' + i + '","reference":"PTF-TEST-SPLIT-V' + i + '","objetModification":"' + modif + '","responsable":"Alexis ROQUES"}'
      );
    }
    return '{"client":"Client Split","reference":"PTF-TEST-SPLIT-V' + count + '","version":"V' + count + '","historique":[' + String.join(rows, ',') + ']}';
  }

  private static AR_PTFTemplateController controllerFor(String snapshot) {
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-SPLIT',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = snapshot,
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);
    return new AR_PTFTemplateController();
  }

  @IsTest
  static void testHistorique_fewRows_allOnCoverNoSuite() {
    AR_PTFTemplateController controller = controllerFor(historySnapshot(3, null));
    System.assertEquals(3, controller.historiqueCoverRows.size());
    System.assertEquals(0, controller.historiqueSuiteRows.size());
    System.assertEquals(false, controller.hasHistoriqueSuite);
  }

  @IsTest
  static void testHistorique_manyRows_overflowGoesToSuiteInOrderWithoutLoss() {
    AR_PTFTemplateController controller = controllerFor(historySnapshot(25, null));
    System.assertEquals(25, controller.historiqueDisplay.size());
    System.assertEquals(
      25,
      controller.historiqueCoverRows.size() + controller.historiqueSuiteRows.size(),
      'Aucune ligne ne doit être perdue entre la garde et la suite'
    );
    System.assert(controller.hasHistoriqueSuite, '25 lignes ne tiennent pas sur la garde');
    System.assert(controller.historiqueCoverRows.size() >= 1);
    System.assertEquals('V1', controller.historiqueCoverRows[0].version, 'La garde commence au rang 1');
    System.assertEquals(
      'V' + (controller.historiqueCoverRows.size() + 1),
      controller.historiqueSuiteRows[0].version,
      'La suite reprend exactement où la garde s\'arrête'
    );
    System.assertEquals('V25', controller.historiqueSuiteRows[controller.historiqueSuiteRows.size() - 1].version);
  }

  @IsTest
  static void testHistorique_longModificationTakesMorePlaceThanShortOnes() {
    Integer withShort = controllerFor(historySnapshot(25, null)).historiqueCoverRows.size();
    Integer withLong = controllerFor(historySnapshot(25, '4')).historiqueCoverRows.size();
    System.assert(
      withLong < withShort,
      'Une modification longue (plusieurs lignes) doit réduire le nombre de lignes tenant sur la garde : ' +
      withLong + ' vs ' + withShort
    );
  }

  @IsTest
  static void testHistoryRowDisplay_longUnbrokenToken_isCutByOrdinarySpacesOthersUntouched() {
    AR_PTFData.HistoryRow row = new AR_PTFData.HistoryRow();
    row.version = 'V2';
    row.objetModification = 'Anticonstitutionnel ' + 'a'.repeat(50);
    row.responsable = 'Alexis ROQUES';
    AR_PTFTemplateController.HistoryRowDisplay display = new AR_PTFTemplateController.HistoryRowDisplay(row);

    System.assertEquals(
      'Anticonstitutionnel ' + 'a'.repeat(18) + ' ' + 'a'.repeat(18) + ' ' + 'a'.repeat(14),
      display.objetModification,
      'Mot de 19 caractères intact ; mot de 50 caractères coupé tous les 18 caractères, rien de perdu'
    );
    System.assertEquals('Alexis ROQUES', display.responsable);
  }

  @IsTest
  static void testEstimateLines_wrapsOnWordsAndBreaksLongTokens() {
    System.assertEquals(1, AR_PTFTemplateController.estimateLines(null, 19));
    System.assertEquals(1, AR_PTFTemplateController.estimateLines('Modification de montant', 30));
    System.assertEquals(2, AR_PTFTemplateController.estimateLines('Modification de montant', 19));
    System.assertEquals(3, AR_PTFTemplateController.estimateLines('x'.repeat(50), 19), 'Mot de 50 caractères coupé en 3');
  }

  @IsTest
  static void testShowHistorique_singleRowV01_isHidden() {
    // Session 151b : un snapshot avec une seule ligne d'historique (V01) ne doit pas afficher le bloc
    // « Historique des modifications ». showHistorique dépend du nombre réel de lignes, pas d'un champ stocké.
    AR_PTFTemplateController controller = controllerFor(historySnapshot(1, null));
    System.assertEquals(1, controller.historiqueDisplay.size());
    System.assertEquals(false, controller.showHistorique, 'V01 seule : pas d\'historique à afficher');
  }

  @IsTest
  static void testShowHistorique_multipleRowsV02Plus_isVisible() {
    // Session 151b : un snapshot avec 3 versions affiche le bloc historique.
    AR_PTFTemplateController controller = controllerFor(historySnapshot(3, null));
    System.assertEquals(3, controller.historiqueDisplay.size());
    System.assertEquals(true, controller.showHistorique, 'V1 + V2 + V3 : historique affiché');
  }

  @IsTest
  static void testShowHistorique_oldSnapshotSingleRow_isHiddenDespiteNoStoredFlag() {
    // Session 151b : un ancien snapshot (avant session 151) sans champ showHistorique qui porte
    // une seule ligne d'historique reconstitue logiquement showHistorique = false.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // Snapshot ancien : pas de clé "showHistorique" du tout (cf. session 151b) mais une historique
    // reconstitue d'une seule ligne (V01).
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-151B-V01',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = '{"client":"Client V01 Ancient","version":"V1","reference":"PTF-TEST-151B-V01","redacteurNom":"Rédacteur Ancient"}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(1, controller.historiqueDisplay.size());
    System.assertEquals(false, controller.showHistorique, 'Ancien snapshot sans champ showHistorique et une seule ligne : caché');
  }

  @IsTest
  static void testShowHistorique_oldSnapshotMultipleRows_isVisibleDespiteNoStoredFlag() {
    // Session 151b : un ancien snapshot (avant session 151) régenéré avec 3 versions — pas de champ
    // showHistorique stocké mais 3 lignes d'historique → doit afficher le bloc.
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    // Ancien snapshot V2 : les trois versions de sa vie (V1 + V2 + maintenant re-rendu V2).
    // Sans clé "showHistorique" (session 151b : elle n'existait pas avant la session 151).
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-151B-V2-ANCIENT',
      AR_Version_Number__c = 2,
      AR_Snapshot__c = '{"client":"Client V2 Ancient","version":"V2","reference":"PTF-TEST-151B-V2-ANCIENT","redacteurNom":"Rédacteur Ancient","historique":[{"version":"V1","reference":"PTF-TEST-151B-V2-ANCIENT","objetModification":"","responsable":"Rédacteur Ancient"},{"version":"V2","reference":"PTF-TEST-151B-V2-ANCIENT","objetModification":"Modification de montant","responsable":"Valideur Ancient"}]}',
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(2, controller.historiqueDisplay.size());
    System.assertEquals(true, controller.showHistorique, 'Ancien snapshot sans champ showHistorique mais 2 lignes : affiché');
  }

  // ------------------------------------------------------------------
  // Session 156b — caractères spéciaux dans le texte libre (commentaire).
  // ------------------------------------------------------------------

  @IsTest
  static void testApplyDisplayLabels_specialCharactersInFreeText_passesUnalteredThroughChain() {
    String specialChars = 'PC + TEL mis à dispo = & < > « » € £';
    AR_PTFData preview = new AR_PTFData();
    preview.client = 'Client Caractères Spéciaux';
    preview.objet = specialChars;
    String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(preview)));

    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', encoded);
    Test.setCurrentPageReference(pageRef);

    Test.startTest();
    AR_PTFTemplateController controller = new AR_PTFTemplateController();
    Test.stopTest();

    System.assertEquals(
      specialChars,
      controller.ptf.objet,
      'Tous les caractères spéciaux doivent traverser la chaîne DTO → contrôleur → snapshot sans altération'
    );
  }
  // ------------------------------------------------------------------
  // TJM par périodes (docs/254d) — la page ne doit jamais tomber en page blanche (resetEmpty).
  // ------------------------------------------------------------------

  private static AR_PTFTemplateController controllerFor(AR_PTFData data) {
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(data))));
    Test.setCurrentPageReference(pageRef);
    return new AR_PTFTemplateController();
  }

  private static AR_PTFData dataWithPeriods(Boolean withPeriods) {
    AR_PTFData d = new AR_PTFData();
    d.client = 'Client Périodes';
    d.reference = 'PTF-PER-V1';
    d.version = 'V1';
    d.currencyCode = 'GBP';
    d.tjm = 650;
    if (withPeriods) {
      AR_PTFData.TjmPeriodRow p1 = new AR_PTFData.TjmPeriodRow();
      p1.index = 1;
      p1.dateDebut = Date.newInstance(2026, 1, 5);
      p1.dateFin = Date.newInstance(2026, 3, 14);
      p1.jours = 50;
      p1.tjm = 650;
      p1.montant = 32500;
      AR_PTFData.TjmPeriodRow p2 = new AR_PTFData.TjmPeriodRow();
      p2.index = 2;
      p2.dateDebut = Date.newInstance(2026, 3, 15);
      p2.dateFin = Date.newInstance(2026, 6, 30);
      p2.jours = 70;
      p2.tjm = 700;
      p2.montant = 49000;
      d.tjmPeriodes = new List<AR_PTFData.TjmPeriodRow>{ p1, p2 };
    }
    return d;
  }

  @IsTest
  static void testConstructor_tjmPeriodes_labelsBuiltServerSide() {
    AR_PTFTemplateController c = controllerFor(dataWithPeriods(true));
    String nb = AR_PTFFormatUtil.NBSP;
    System.assertEquals('PTF-PER-V1', c.ptf.reference, 'Le snapshot se relit, pas de page blanche');
    System.assertEquals(true, c.hasTjmPeriodes);
    System.assertEquals(
      '650' + nb + '£ HT/jour jusqu\'au 14/03/2026, puis 700' + nb + '£ HT/jour à partir du 15/03/2026',
      c.tjmPeriodesLabel
    );
    System.assertEquals(c.tjmPeriodesLabel, c.tjmPrixLabel);
    System.assertEquals('de 650 à 700' + nb + '£/j', c.tjmPerDayLabel);
    System.assertEquals('700' + nb + '£', c.tjmDernierePeriodeLabel);
  }

  // Session 272 : le prix journalier par période ne figure plus dans le corps contractuel de la PTF
  // Abylsen (contrainte légale). L'absence du tableau dans le balisage est gardée par
  // scripts/check-ptf-abylsen-no-daily-rate.js (getContent() interdit en test) ; ici, les montants des
  // lots, eux, restent ceux calculés en amont.
  @IsTest
  static void testAbylsenPage_tjmPeriodes_bodyShowsLotsOnly() {
    AR_PTFData d = dataWithPeriods(true);
    AR_PTFData.LotRow lot = new AR_PTFData.LotRow();
    lot.libelle = 'Lot 1';
    lot.montant = 82500;
    lot.montantCalcule = 82500;
    d.lots = new List<AR_PTFData.LotRow>{ lot };
    PageReference pageRef = Page.AR_PTFTemplateAbylsen;
    pageRef.getParameters().put('data', EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(d))));
    Test.setCurrentPageReference(pageRef);
    AR_PTFTemplateController c = new AR_PTFTemplateController();
    System.assertEquals(true, c.hasTjmPeriodes, 'Les libellés de périodes restent calculés (lecture par les autres gabarits)');
    System.assertEquals(1, c.lotsDisplay.size());
    System.assertEquals('82' + AR_PTFFormatUtil.NBSP + '500' + AR_PTFFormatUtil.NBSP + '£', c.lotsDisplay[0].montantLabel);
  }

  @IsTest
  static void testConstructor_noTjmPeriodes_labelsUnchanged() {
    AR_PTFTemplateController c = controllerFor(dataWithPeriods(false));
    System.assertEquals(false, c.hasTjmPeriodes);
    System.assertEquals(null, c.tjmPeriodesLabel);
    System.assertEquals(c.tjmLabel, c.tjmPrixLabel, 'Sans période, « Prix journalier HT » = tjmLabel comme avant');
    System.assertEquals(c.tjmLabel + '/j', c.tjmPerDayLabel);
  }

  @IsTest
  static void testConstructor_oldSnapshotWithoutTjmPeriodes_rendersAsBefore() {
    // Snapshot enregistré avant la session 254d, relu par l'id du document (chemin de la page réelle).
    String frozen = '{"reference":"PTF-ANCIEN-V1","client":"Client Ancien","tjm":650,"currencyCode":"EUR",'
      + '"schedule":[{"mois":"septembre 2026","jours":22,"montant":14300,"cumul":14300}],"totalHT":14300}';
    AR_Price_Matrix__c matrix = [SELECT Id, AR_Position__c FROM AR_Price_Matrix__c LIMIT 1];
    AR_PTF_Document__c doc = new AR_PTF_Document__c(
      AR_Price_Matrix__c = matrix.Id,
      AR_Position__c = matrix.AR_Position__c,
      AR_Reference__c = 'PTF-TEST-ANCIEN',
      AR_Version_Number__c = 1,
      AR_Snapshot__c = frozen,
      AR_Generated_At__c = System.now(),
      AR_Generation_Status__c = 'Généré'
    );
    insert doc;
    PageReference pageRef = Page.AR_PTFTemplate;
    pageRef.getParameters().put('id', doc.Id);
    Test.setCurrentPageReference(pageRef);
    AR_PTFTemplateController c = new AR_PTFTemplateController();
    System.assertEquals('PTF-ANCIEN-V1', c.ptf.reference, 'resetEmpty() n\'a pas été appelé : pas de page blanche');
    System.assertEquals(false, c.hasTjmPeriodes);
    System.assertEquals('650' + AR_PTFFormatUtil.NBSP + '€', c.tjmLabel);
  }
}