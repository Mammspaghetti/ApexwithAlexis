@IsTest
private class AR_MatrixListServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Liste Matrices',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Liste Matrices', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        insert new List<AR_Price_Matrix__c>{
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id,
                AR_Account_Name__c = acc.Name,
                AR_Account_Country__c = 'France',
                AR_Position_Name__c = position.Name,
                AR_Contract_Type__c = 'NEARSHORE',
                AR_Status__c = 'Brouillon',
                AR_Proposed_TJM__c = 300,
                AR_MC2_Percent__c = 28.5,
                AR_Corridor_Segment__c = 'recommended'
            ),
            new AR_Price_Matrix__c(
                AR_Position__c = position.Id,
                AR_Account_Name__c = acc.Name,
                AR_Position_Name__c = position.Name,
                AR_Contract_Type__c = 'CDI',
                AR_Status__c = 'Validée',
                AR_Proposed_TJM__c = 500,
                AR_MC2_Percent__c = 32.1,
                AR_Corridor_Segment__c = 'superstar'
            )
        };
    }

    @IsTest
    static void testGetMatrices_returnsAllVisibleMatricesWithMappedFields() {
        List<AR_MatrixListService.MatrixListItem> items = AR_MatrixListService.getMatrices();

        System.assertEquals(2, items.size());
        Set<String> statuses = new Set<String>();
        for (AR_MatrixListService.MatrixListItem item : items) {
            statuses.add(item.status);
            System.assertNotEquals(null, item.matrixId);
            System.assertEquals('Client Liste Matrices', item.accountName);
            System.assertEquals('Besoin Liste Matrices', item.positionName);
            System.assertNotEquals(null, item.createdDate);
            System.assertEquals(UserInfo.getName(), item.ownerName, 'Owner par défaut = créateur du test');
        }
        System.assert(statuses.contains('Brouillon'));
        System.assert(statuses.contains('Validée'));
    }

    /**
     * Session 28 §5 : positionId ajouté au DTO pour que l'action « Dupliquer » de la liste
     * (arMatrixDuplicateModal) puisse pré-remplir le besoin cible sans requête supplémentaire.
     */
    @IsTest
    static void testGetMatrices_includesPositionId() {
        cxsrec__cxsPosition__c position = [SELECT Id FROM cxsrec__cxsPosition__c WHERE Name = 'Besoin Liste Matrices' LIMIT 1];

        List<AR_MatrixListService.MatrixListItem> items = AR_MatrixListService.getMatrices();

        for (AR_MatrixListService.MatrixListItem item : items) {
            System.assertEquals(position.Id, item.positionId);
        }
    }

    /**
     * Session 169 : consultantName ajouté à la liste pour rechercher par nom de consultant.
     */
    @IsTest
    static void testGetMatrices_includesConsultantName() {
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Status__c = 'Brouillon' LIMIT 1];
        matrix.AR_Consultant_Name__c = 'Alice Dupont';
        update matrix;

        List<AR_MatrixListService.MatrixListItem> items = AR_MatrixListService.getMatrices();

        Boolean found = false;
        for (AR_MatrixListService.MatrixListItem item : items) {
            if (item.status == 'Brouillon') {
                System.assertEquals('Alice Dupont', item.consultantName);
                found = true;
                break;
            }
        }
        System.assert(found, 'Aucune matrice Brouillon trouvée');
    }

    /** Le lookup consultant (session 54) l'emporte sur le texte libre historique. */
    @IsTest
    static void testGetMatrices_consultantLookupPreferredOverFreeText() {
        Id consultantRecordTypeId = Schema.SObjectType.cxsrec__cxsCandidate__c
            .getRecordTypeInfosByDeveloperName()
            .get('Consultant')
            .getRecordTypeId();
        cxsrec__cxsCandidate__c consultant = new cxsrec__cxsCandidate__c(
            RecordTypeId = consultantRecordTypeId,
            cxsrec__First_name__c = 'Claire',
            cxsrec__Last_name__c = 'LEFEBVRE'
        );
        insert consultant;
        String expectedName = [SELECT Name FROM cxsrec__cxsCandidate__c WHERE Id = :consultant.Id].Name;

        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c WHERE AR_Status__c = 'Brouillon' LIMIT 1];
        matrix.AR_Consultant__c = consultant.Id;
        matrix.AR_Consultant_Name__c = 'Ancien texte libre';
        update matrix;

        Boolean found = false;
        for (AR_MatrixListService.MatrixListItem item : AR_MatrixListService.getMatrices()) {
            if (item.matrixId == matrix.Id) {
                System.assertEquals(expectedName, item.consultantName);
                found = true;
            }
        }
        System.assert(found, 'Matrice Brouillon absente de la liste');
    }
}