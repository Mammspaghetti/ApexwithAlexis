@IsTest
private class AR_PTFHistoryServiceTest {
  private static final String TEST_TEMPLATE_CODE = 'ABYLSEN_AT_V11';

  @TestSetup
  static void setup() {
    List<cxsrec__cxsPosition__c> positions = new List<cxsrec__cxsPosition__c>();
    for (Integer i = 0; i < 20; i++) {
      positions.add(new cxsrec__cxsPosition__c(
        Name = 'TestPos_' + i,
        cxsrec__Status__c = 'Open',
        cxsrec__Country__c = 'France'
      ));
    }
    insert positions;
  }

  private static Integer positionIndex = 0;

  private static Id getTestPosition() {
    List<cxsrec__cxsPosition__c> positions = [
      SELECT Id FROM cxsrec__cxsPosition__c WHERE Name LIKE 'TestPos_%' ORDER BY Name LIMIT 20
    ];
    if (positionIndex < positions.size()) {
      return positions[positionIndex++].Id;
    }
    return positions[0].Id;
  }

  @IsTest
  static void testComputeRanksMultipleDocuments() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc1 = createPTFDoc(m1.Id, testPositionId, now.addHours(-2), 'PTF');
    AR_PTF_Document__c doc2 = createPTFDoc(m1.Id, testPositionId, now.addHours(-1), 'PTF');
    AR_PTF_Document__c doc3 = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    insert new List<AR_PTF_Document__c>{ doc1, doc2, doc3 };

    Map<Id, Integer> ranks = AR_PTFHistoryService.computeRanks(m1.Id, TEST_TEMPLATE_CODE);
    System.assertEquals(1, ranks.get(doc1.Id), 'Doc1 should have rank 1');
    System.assertEquals(2, ranks.get(doc2.Id), 'Doc2 should have rank 2');
    System.assertEquals(3, ranks.get(doc3.Id), 'Doc3 should have rank 3');
  }

  @IsTest
  static void testFailedAndAvenantDontConsumeRank() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc1 = createPTFDoc(m1.Id, testPositionId, now.addHours(-3), 'PTF');
    doc1.AR_Include_In_History__c = true;

    AR_PTF_Document__c docFailed = createPTFDoc(m1.Id, testPositionId, now.addHours(-2), 'PTF');
    docFailed.AR_Include_In_History__c = true;
    docFailed.AR_Generation_Status__c = 'Échec';

    AR_PTF_Document__c docAvenant = createPTFDoc(m1.Id, testPositionId, now.addHours(-1), 'Avenant');
    docAvenant.AR_Include_In_History__c = true;

    AR_PTF_Document__c doc2 = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    doc2.AR_Include_In_History__c = true;

    insert new List<AR_PTF_Document__c>{ doc1, docFailed, docAvenant, doc2 };

    Map<Id, Integer> ranks = AR_PTFHistoryService.computeRanks(m1.Id, TEST_TEMPLATE_CODE);
    System.assertEquals(1, ranks.get(doc1.Id), 'Doc1 should have rank 1');
    System.assert(!ranks.containsKey(docFailed.Id), 'Failed doc should not consume rank');
    System.assert(!ranks.containsKey(docAvenant.Id), 'Avenant should not consume rank');
    System.assertEquals(2, ranks.get(doc2.Id), 'Doc2 should have rank 2');
  }

  @IsTest
  static void testBesoinScopeSharedSequence() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    AR_Price_Matrix__c m2 = createMatrix(testPositionId);
    insert new List<AR_Price_Matrix__c>{ m1, m2 };

    Datetime now = System.now();
    AR_PTF_Document__c doc1_m1 = createPTFDoc(m1.Id, testPositionId, now.addHours(-3), 'PTF');
    doc1_m1.AR_Include_In_History__c = true;

    AR_PTF_Document__c doc1_m2 = createPTFDoc(m2.Id, testPositionId, now.addHours(-2), 'PTF');
    doc1_m2.AR_Include_In_History__c = true;

    AR_PTF_Document__c doc2_m1 = createPTFDoc(m1.Id, testPositionId, now.addHours(-1), 'PTF');
    doc2_m1.AR_Include_In_History__c = true;

    insert new List<AR_PTF_Document__c>{ doc1_m1, doc1_m2, doc2_m1 };

    Map<Id, Integer> ranksM1 = AR_PTFHistoryService.computeRanks(m1.Id, TEST_TEMPLATE_CODE);
    Map<Id, Integer> ranksM2 = AR_PTFHistoryService.computeRanks(m2.Id, TEST_TEMPLATE_CODE);

    System.assertEquals(1, ranksM1.get(doc1_m1.Id), 'M1 doc1 should have rank 1 (besoin scope)');
    System.assertEquals(2, ranksM2.get(doc1_m2.Id), 'M2 doc1 should have rank 2 (besoin scope, shared sequence)');
    System.assertEquals(3, ranksM1.get(doc2_m1.Id), 'M1 doc2 should have rank 3 (besoin scope, shared sequence)');
  }

  @IsTest
  static void testNextDisplayRankAllUnchecked() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc1 = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    doc1.AR_Include_In_History__c = false;
    insert doc1;

    Integer nextRank = AR_PTFHistoryService.nextDisplayRank(m1.Id, TEST_TEMPLATE_CODE);
    System.assertEquals(1, nextRank, 'Next rank should be 1 when all documents unchecked');
  }

  @IsTest
  static void testGetNextDisplayRankAuraEntryPoint() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;
    System.assertEquals(
      1,
      AR_PTFHistoryService.getNextDisplayRank(m1.Id, TEST_TEMPLATE_CODE),
      'Aucune PTF : la prochaine est la première, pas de modification demandée'
    );

    Datetime now = System.now();
    AR_PTF_Document__c included = createPTFDoc(m1.Id, testPositionId, now.addHours(-2), 'PTF');
    included.AR_Include_In_History__c = true;
    AR_PTF_Document__c excluded = createPTFDoc(m1.Id, testPositionId, now.addHours(-1), 'PTF');
    excluded.AR_Include_In_History__c = false;
    insert new List<AR_PTF_Document__c>{ included, excluded };

    System.assertEquals(
      2,
      AR_PTFHistoryService.getNextDisplayRank(m1.Id, TEST_TEMPLATE_CODE),
      'Un document décoché ne compte pas : une PTF cochée -> la prochaine est V2'
    );
    System.assertEquals(
      AR_PTFHistoryService.nextDisplayRank(m1.Id, TEST_TEMPLATE_CODE),
      AR_PTFHistoryService.getNextDisplayRank(m1.Id, TEST_TEMPLATE_CODE),
      'Même source que la génération'
    );
  }

  @IsTest
  static void testModificationLabelRank1Empty() {
    Id testPositionId = getTestPosition();
    AR_PTF_Document__c doc = new AR_PTF_Document__c();
    doc.AR_Modification_Type__c = 'Modification de montant';
    doc.AR_Modification_Detail__c = 'Some detail';

    String label = AR_PTFHistoryService.getModificationLabel(doc, 1);
    System.assertEquals('', label, 'Rank 1 should have empty label even with type set');
  }

  @IsTest
  static void testModificationLabelAutreType() {
    Id testPositionId = getTestPosition();
    AR_PTF_Document__c doc = new AR_PTF_Document__c();
    doc.AR_Modification_Type__c = 'Autre';
    doc.AR_Modification_Detail__c = 'Custom modification reason';

    String label = AR_PTFHistoryService.getModificationLabel(doc, 2);
    System.assertEquals(
      'Custom modification reason',
      label,
      'Autre type should return detail text only'
    );
  }

  @IsTest
  static void testModificationLabelOtherType() {
    Id testPositionId = getTestPosition();
    AR_PTF_Document__c doc = new AR_PTF_Document__c();
    doc.AR_Modification_Type__c = 'Modification de montant';
    doc.AR_Modification_Detail__c = 'Ignored detail';

    String label = AR_PTFHistoryService.getModificationLabel(doc, 2);
    System.assertEquals(
      'Modification de montant',
      label,
      'Non-Autre type should return the picklist label'
    );
  }

  @IsTest
  static void testModificationLabelEmpty() {
    Id testPositionId = getTestPosition();
    AR_PTF_Document__c doc = new AR_PTF_Document__c();

    String label = AR_PTFHistoryService.getModificationLabel(doc, 2);
    System.assertEquals('', label, 'Empty type should return empty string');
  }

  private static AR_Price_Matrix__c createMatrix(Id positionId) {
    AR_Price_Matrix__c matrix = new AR_Price_Matrix__c();
    matrix.AR_Position__c = positionId;
    matrix.AR_Status__c = 'Brouillon';
    return matrix;
  }

  @IsTest
  static void testSetIncludedInHistoryCentralScenario() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();

    // Create matrix owned by bmUser so it's visible in System.runAs(bmUser)
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c v1 = createPTFDoc(m1.Id, testPositionId, now.addHours(-2), 'PTF');
    v1.AR_Include_In_History__c = true;
    AR_PTF_Document__c v2 = createPTFDoc(m1.Id, testPositionId, now.addHours(-1), 'PTF');
    v2.AR_Include_In_History__c = true;
    AR_PTF_Document__c v3 = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    v3.AR_Include_In_History__c = true;
    insert new List<AR_PTF_Document__c>{ v1, v2, v3 };

    // Exécuter les opérations sous bmUser context
    System.runAs(bmUser) {
      // Initial: V1(1), V2(2), V3(3)
      Map<Id, Integer> initialRanks = AR_PTFHistoryService.computeRanks(m1.Id, TEST_TEMPLATE_CODE);
      System.assertEquals(1, initialRanks.get(v1.Id));
      System.assertEquals(2, initialRanks.get(v2.Id));
      System.assertEquals(3, initialRanks.get(v3.Id));

      // Uncheck V2
      List<AR_PTFHistoryService.PTFDocumentRow> rows = AR_PTFHistoryService.setIncludedInHistory(v2.Id, false);
      Map<Id, Integer> afterUncheck = new Map<Id, Integer>();
      for (AR_PTFHistoryService.PTFDocumentRow row : rows) {
        if (row.displayRank != null) {
          afterUncheck.put(row.ptfDocumentId, row.displayRank);
        }
      }
      System.assertEquals(1, afterUncheck.get(v1.Id));
      System.assert(!afterUncheck.containsKey(v2.Id), 'V2 should not be in ranks after unchecking');
      System.assertEquals(2, afterUncheck.get(v3.Id), 'V3 should now have rank 2');

      // Recheck V2
      rows = AR_PTFHistoryService.setIncludedInHistory(v2.Id, true);
      Map<Id, Integer> afterRecheck = new Map<Id, Integer>();
      for (AR_PTFHistoryService.PTFDocumentRow row : rows) {
        if (row.displayRank != null) {
          afterRecheck.put(row.ptfDocumentId, row.displayRank);
        }
      }
      System.assertEquals(1, afterRecheck.get(v1.Id));
      System.assertEquals(2, afterRecheck.get(v2.Id));
      System.assertEquals(3, afterRecheck.get(v3.Id), 'V3 should be back to rank 3');
    }
  }

  @IsTest
  static void testBesoinScopeEmptyMatrixBishopState() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c matrixA = createMatrix(testPositionId);
    AR_Price_Matrix__c matrixB = createMatrix(testPositionId);
    insert new List<AR_Price_Matrix__c>{ matrixA, matrixB };

    Datetime now = System.now();
    AR_PTF_Document__c docA = createPTFDoc(matrixA.Id, testPositionId, now.addHours(-1), 'PTF');
    docA.AR_Include_In_History__c = true;
    insert docA;

    // Matrix B has no documents yet. ABYLSEN_AT_V11 is besoin scope (décision 137): the sequence
    // is shared with matrix A's document, so the next rank is 2.
    Integer nextRankB = AR_PTFHistoryService.nextDisplayRank(matrixB.Id, TEST_TEMPLATE_CODE);
    System.assertEquals(2, nextRankB, 'Next rank for empty matrix should be 2 (besoin scope)');
  }

  @IsTest
  static void testDocumentWithoutStatusIsEligible() {
    Id testPositionId = getTestPosition();
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c docNoStatus = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    docNoStatus.AR_Include_In_History__c = true;
    docNoStatus.AR_Generation_Status__c = null; // Pre-session-20b document
    insert docNoStatus;

    Map<Id, Integer> ranks = AR_PTFHistoryService.computeRanks(m1.Id, TEST_TEMPLATE_CODE);
    System.assertEquals(1, ranks.get(docNoStatus.Id), 'Document with null status should consume rank');
  }

  @IsTest
  static void testSetIncludedInHistoryWithoutPermissionThrowsError() {
    Id testPositionId = getTestPosition();
    User userWithoutPermission = AR_TestPersona.sansHabilitation();

    // Create matrix as admin, then try to modify as user without permission
    AR_Price_Matrix__c m1 = createMatrix(testPositionId);
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    doc.AR_Include_In_History__c = true;
    insert doc;

    // Try to update under user context — should get permission error
    System.runAs(userWithoutPermission) {
      try {
        AR_PTFHistoryService.setIncludedInHistory(doc.Id, false);
        System.assert(false, 'Should have thrown exception for user without Edit permission');
      } catch (Exception e) {
        System.assert(e instanceof AuraHandledException, 'Expected AuraHandledException, got: ' + e.getTypeName());
        System.assertEquals(
          'Vous n\'avez pas les droits pour modifier cette PTF.',
          e.getMessage(),
          'Message français attendu, got: ' + e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void testSetModificationAutreWithDetail() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    doc.AR_Include_In_History__c = true;
    insert doc;


    System.runAs(bmUser) {
      List<AR_PTFHistoryService.PTFDocumentRow> rows = AR_PTFHistoryService.setModification(
        doc.Id,
        'Autre',
        'Custom modification reason'
      );

      // Verify the document was updated
      AR_PTF_Document__c updated = [
        SELECT AR_Modification_Type__c, AR_Modification_Detail__c
        FROM AR_PTF_Document__c
        WHERE Id = :doc.Id
      ];
      System.assertEquals('Autre', updated.AR_Modification_Type__c);
      System.assertEquals('Custom modification reason', updated.AR_Modification_Detail__c);

      // Verify row contains the modification
      Boolean foundRow = false;
      for (AR_PTFHistoryService.PTFDocumentRow row : rows) {
        if (row.ptfDocumentId == doc.Id) {
          foundRow = true;
          System.assertEquals('Autre', row.modificationType);
          System.assertEquals('Custom modification reason', row.modificationDetail);
        }
      }
      System.assert(foundRow, 'Document row should be in returned rows');
    }
  }

  @IsTest
  static void testSetModificationAutreWithoutDetailThrowsError() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    insert doc;


    System.runAs(bmUser) {
      try {
        AR_PTFHistoryService.setModification(doc.Id, 'Autre', '');
        System.assert(false, 'Should have thrown error for empty detail');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('obligatoire'), 'Error should be in French');
      }
    }
  }

  @IsTest
  static void testSetModificationAutreWithoutDetailBlankThrowsError() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    insert doc;


    System.runAs(bmUser) {
      try {
        AR_PTFHistoryService.setModification(doc.Id, 'Autre', '   ');
        System.assert(false, 'Should have thrown error for whitespace-only detail');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('obligatoire'), 'Error should be in French');
      }
    }
  }

  @IsTest
  static void testSetModificationValidPicklistValue() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    insert doc;


    System.runAs(bmUser) {
      List<AR_PTFHistoryService.PTFDocumentRow> rows = AR_PTFHistoryService.setModification(
        doc.Id,
        'Modification de montant',
        null
      );

      AR_PTF_Document__c updated = [
        SELECT AR_Modification_Type__c, AR_Modification_Detail__c
        FROM AR_PTF_Document__c
        WHERE Id = :doc.Id
      ];
      System.assertEquals('Modification de montant', updated.AR_Modification_Type__c);
      System.assertEquals(null, updated.AR_Modification_Detail__c, 'Detail should be cleared');
    }
  }

  @IsTest
  static void testSetModificationInvalidPicklistValueThrowsError() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    insert doc;


    System.runAs(bmUser) {
      try {
        AR_PTFHistoryService.setModification(doc.Id, 'INVALID_VALUE', null);
        System.assert(false, 'Should have thrown error for invalid picklist value');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('invalide'), 'Error should be in French');
      }
    }
  }

  @IsTest
  static void testSetModificationAvenantThrowsError() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c avenant = createPTFDoc(m1.Id, testPositionId, now, 'Avenant');
    insert avenant;


    System.runAs(bmUser) {
      try {
        AR_PTFHistoryService.setModification(avenant.Id, 'Modification de montant', null);
        System.assert(false, 'Should have thrown error for Avenant');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('non autorisée'), 'Error should be in French');
      }
    }
  }

  @IsTest
  static void testSetModificationClearType() {
    Id testPositionId = getTestPosition();
    User bmUser = AR_TestPersona.bm();
    
    // Create matrix owned by bmUser
    AR_Price_Matrix__c m1 = new AR_Price_Matrix__c(
      OwnerId = bmUser.Id,
      AR_Position__c = testPositionId,
      AR_Status__c = 'Brouillon'
    );
    insert m1;

    Datetime now = System.now();
    AR_PTF_Document__c doc = createPTFDoc(m1.Id, testPositionId, now, 'PTF');
    doc.AR_Modification_Type__c = 'Modification de montant';
    doc.AR_Modification_Detail__c = 'Some detail';
    insert doc;


    System.runAs(bmUser) {
      // Clear by passing null type
      List<AR_PTFHistoryService.PTFDocumentRow> rows = AR_PTFHistoryService.setModification(doc.Id, null, null);

      AR_PTF_Document__c updated = [
        SELECT AR_Modification_Type__c, AR_Modification_Detail__c
        FROM AR_PTF_Document__c
        WHERE Id = :doc.Id
      ];
      System.assertEquals(null, updated.AR_Modification_Type__c);
      System.assertEquals(null, updated.AR_Modification_Detail__c);
    }
  }


  private static AR_PTF_Document__c createPTFDoc(
    Id matrixId,
    Id positionId,
    Datetime generatedAt,
    String docType
  ) {
    AR_PTF_Document__c doc = new AR_PTF_Document__c();
    doc.AR_Price_Matrix__c = matrixId;
    doc.AR_Position__c = positionId;
    doc.AR_Generated_At__c = generatedAt;
    doc.AR_Document_Type__c = docType;
    doc.AR_Generation_Status__c = 'Généré';
    doc.AR_Version_Number__c = 1;
    doc.AR_Reference__c = 'PTF-TEST-V1';
    doc.AR_Template_Code__c = TEST_TEMPLATE_CODE;
    return doc;
  }


  /** Session 279 : indicateur « adresse client modifiée » lu dans le snapshot (absent → faux). */
  @IsTest
  static void testIsClientAddressModified_readsSnapshotFlag() {
    System.assertEquals(true, AR_PTFHistoryService.isClientAddressModified('{"client":"X","adresseClientModifiee":true}'));
    System.assertEquals(false, AR_PTFHistoryService.isClientAddressModified('{"client":"X","adresseClientModifiee":false}'));
    System.assertEquals(false, AR_PTFHistoryService.isClientAddressModified('{"client":"X"}'), 'Snapshot ancien');
    System.assertEquals(false, AR_PTFHistoryService.isClientAddressModified(null));
  }
}