/**
 * Changement d'entité sur une matrice validée (AR_PricingMatrixService.changeValidatedMatrixEntity) :
 * seule modification permise après validation, sous le persona propriétaire de la matrice.
 */
@IsTest
private class AR_MatrixEntityChangeTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Changement Entite',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Changement Entite', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        insert new List<AR_PTF_Entity_Referential__c>{
            new AR_PTF_Entity_Referential__c(Name = 'Entite Chg A', AR_Active__c = true),
            new AR_PTF_Entity_Referential__c(Name = 'Entite Chg B', AR_Active__c = true),
            new AR_PTF_Entity_Referential__c(Name = 'Entite Chg Inactive', AR_Active__c = false)
        };

        User owner = AR_TestPersona.bm();
        Id entityA = [SELECT Id FROM AR_PTF_Entity_Referential__c WHERE Name = 'Entite Chg A'].Id;
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (String status : new List<String>{ 'Brouillon', 'En dérogation', 'Validée', 'Validée par dérogation', 'Refusée' }) {
            matrices.add(new AR_Price_Matrix__c(
                AR_Position__c = position.Id,
                AR_Position_Name__c = position.Name,
                AR_Account_Country__c = 'France',
                AR_Contract_Type__c = 'NEARSHORE',
                AR_CJM_Nearshore__c = 200,
                AR_RFA_Percent__c = 0,
                AR_Total_Daily_Cost__c = 200,
                AR_TJM_Floor__c = 250,
                AR_TJM_Target__c = 267,
                AR_TJM_Ideal__c = 286,
                AR_Proposed_TJM__c = 300,
                AR_MC2_Percent__c = 33.3,
                AR_Contract_Coefficient_Applied__c = 1.8,
                AR_Working_Days_Applied__c = 218,
                AR_Status__c = status,
                AR_Entity_Ref__c = entityA,
                AR_Selected_Validator__c = UserInfo.getUserId(),
                OwnerId = owner.Id
            ));
        }
        insert matrices;
    }

    private static AR_Price_Matrix__c byStatus(String status) {
        return [
            SELECT Id, OwnerId, AR_Status__c, AR_Entity_Ref__c, AR_Proposed_TJM__c, AR_MC2_Percent__c,
                   AR_Total_Daily_Cost__c, AR_Contract_Coefficient_Applied__c, AR_Working_Days_Applied__c,
                   AR_Derogation_Reason__c
            FROM AR_Price_Matrix__c WHERE AR_Status__c = :status LIMIT 1
        ];
    }

    private static Id entityId(String name) {
        return [SELECT Id FROM AR_PTF_Entity_Referential__c WHERE Name = :name LIMIT 1].Id;
    }

    private static User ownerOf(AR_Price_Matrix__c m) {
        return [SELECT Id FROM User WHERE Id = :m.OwnerId];
    }

    // Libellés lus dans la langue du persona : le message est levé sous sa langue, pas celle du test.
    private static Map<String, String> expected = new Map<String, String>();

    private static String changeAs(User u, Id matrixId, Id entityId) {
        String error;
        System.runAs(u) {
            expected.put('status', Label.AR_Msg_PM_ChangeEntityStatus);
            expected.put('inactive', Label.AR_Msg_PM_ChangeEntityInactive);
            expected.put('required', Label.AR_Msg_PM_ChangeEntityRequired);
            expected.put('noAccess', Label.AR_Msg_PM_ChangeEntityNoAccess);
            try {
                AR_PricingMatrixService.changeValidatedMatrixEntity(matrixId, entityId);
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
        }
        return error;
    }

    @IsTest
    static void testChange_validated_ownerSucceeds_amountsUntouched() {
        AR_Price_Matrix__c before = byStatus('Validée');
        Id entityB = entityId('Entite Chg B');
        System.assertEquals(null, changeAs(ownerOf(before), before.Id, entityB));

        AR_Price_Matrix__c after = byStatus('Validée');
        System.assertEquals(entityB, after.AR_Entity_Ref__c);
        System.assertEquals(before.AR_Proposed_TJM__c, after.AR_Proposed_TJM__c);
        System.assertEquals(before.AR_MC2_Percent__c, after.AR_MC2_Percent__c);
        System.assertEquals(before.AR_Total_Daily_Cost__c, after.AR_Total_Daily_Cost__c);
        System.assertEquals(before.AR_Contract_Coefficient_Applied__c, after.AR_Contract_Coefficient_Applied__c);
        System.assertEquals(before.AR_Working_Days_Applied__c, after.AR_Working_Days_Applied__c);
        System.assertEquals('Validée', after.AR_Status__c);
    }

    @IsTest
    static void testChange_validatedByDerogation_ownerSucceeds() {
        AR_Price_Matrix__c before = byStatus('Validée par dérogation');
        Id entityB = entityId('Entite Chg B');
        System.assertEquals(null, changeAs(ownerOf(before), before.Id, entityB));
        System.assertEquals(entityB, byStatus('Validée par dérogation').AR_Entity_Ref__c);
    }

    @IsTest
    static void testChange_refused_rejectedWithStatusMessage() {
        AR_Price_Matrix__c before = byStatus('Refusée');
        String error = changeAs(ownerOf(before), before.Id, entityId('Entite Chg B'));
        System.assertEquals(
            AR_I18n.format(expected.get('status'), new List<Object>{ 'Refusée' }),
            error
        );
        System.assertEquals(before.AR_Entity_Ref__c, byStatus('Refusée').AR_Entity_Ref__c);
    }

    @IsTest
    static void testChange_draftAndInDerogation_rejected() {
        for (String status : new List<String>{ 'Brouillon', 'En dérogation' }) {
            AR_Price_Matrix__c before = byStatus(status);
            String error = changeAs(ownerOf(before), before.Id, entityId('Entite Chg B'));
            System.assertEquals(
                AR_I18n.format(expected.get('status'), new List<Object>{ status }),
                error,
                status
            );
        }
    }

    @IsTest
    static void testChange_inactiveEntity_rejected() {
        AR_Price_Matrix__c before = byStatus('Validée');
        String error = changeAs(ownerOf(before), before.Id, entityId('Entite Chg Inactive'));
        System.assertEquals(expected.get('inactive'), error);
        System.assertEquals(before.AR_Entity_Ref__c, byStatus('Validée').AR_Entity_Ref__c);
    }

    @IsTest
    static void testChange_missingEntity_rejected() {
        AR_Price_Matrix__c before = byStatus('Validée');
        String error = changeAs(ownerOf(before), before.Id, null);
        System.assertEquals(expected.get('required'), error);
    }

    @IsTest
    static void testChange_nonOwner_rejectedWithReadableMessage() {
        AR_Price_Matrix__c before = byStatus('Validée');
        String error = changeAs(AR_TestPersona.bm(), before.Id, entityId('Entite Chg B'));
        System.assertEquals(expected.get('noAccess'), error);
        System.assertEquals(before.AR_Entity_Ref__c, byStatus('Validée').AR_Entity_Ref__c);
    }

    @IsTest
    static void testChange_onlyEntityIsWritten_otherFieldsUntouched() {
        AR_Price_Matrix__c before = byStatus('Validée');
        changeAs(ownerOf(before), before.Id, entityId('Entite Chg B'));
        AR_Price_Matrix__c after = byStatus('Validée');
        System.assertEquals(before.AR_Derogation_Reason__c, after.AR_Derogation_Reason__c);
        System.assertEquals(before.OwnerId, after.OwnerId);
    }

    @IsTest
    static void testDirectUpdate_stillBlockedByTrigger_andBypassRestored() {
        AR_Price_Matrix__c before = byStatus('Validée');
        System.assertEquals(false, AR_TriggerBypass.serviceContext);
        changeAs(ownerOf(before), before.Id, entityId('Entite Chg B'));
        System.assertEquals(false, AR_TriggerBypass.serviceContext, 'Le verrou doit être rétabli');

        AR_Price_Matrix__c matrix = byStatus('Validée');
        matrix.AR_Entity_Ref__c = entityId('Entite Chg A');
        try {
            update matrix;
            System.assert(false, 'Une mise à jour directe doit rester bloquée');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Validée'), e.getMessage());
        }
    }

    @IsTest
    static void testEntityTemplateInfo_returnsEntityNameAndOwnTemplate() {
        AR_Price_Matrix__c m = byStatus('Validée');
        Map<String, String> info = AR_PTFDataService.getEntityTemplateInfo(m.Id);
        System.assertEquals('Entite Chg A', info.get('entityName'));
        System.assertEquals('ABYLSEN_AT_V11', info.get('templateCode'));
        System.assertEquals(AR_PTFDataService.TEMPLATE_LABELS.get('ABYLSEN_AT_V11'), info.get('templateLabel'));

        update new AR_PTF_Entity_Referential__c(Id = entityId('Entite Chg B'), AR_Template_Code__c = 'ABMI_DQ012');
        changeAs(ownerOf(m), m.Id, entityId('Entite Chg B'));
        Map<String, String> changed = AR_PTFDataService.getEntityTemplateInfo(m.Id);
        System.assertEquals('Entite Chg B', changed.get('entityName'));
        System.assertEquals('ABMI_DQ012', changed.get('templateCode'));
    }

    @IsTest
    static void testEntityTemplateInfo_noEntity_empty() {
        AR_Price_Matrix__c m = byStatus('Validée');
        AR_TriggerBypass.serviceContext = true;
        update new AR_Price_Matrix__c(Id = m.Id, AR_Entity_Ref__c = null);
        AR_TriggerBypass.serviceContext = false;
        System.assertEquals(true, AR_PTFDataService.getEntityTemplateInfo(m.Id).isEmpty());
    }
}