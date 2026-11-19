/**
 * Session 252 — corridor appliqué à une matrice : grand compte, puis entité PTF (seulement si ses trois
 * seuils sont renseignés), puis paramètres généraux. Une matrice décidée garde ses seuils figés quand
 * son entité change.
 */
@IsTest
private class AR_CorridorEntityTest {
    @TestSetup
    static void setup() {
        Account plain = new Account(
            Name = 'Corridor Entite Sans Grand Compte',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        Account keyAccount = new Account(
            Name = 'Corridor Entite Grand Compte',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert new List<Account>{ plain, keyAccount };
        insert new AR_Account_Corridor__c(
            AR_Account__c = keyAccount.Id,
            AR_Floor_Percent__c = 10,
            AR_Target_Percent__c = 15,
            AR_Ideal_Percent__c = 20
        );
        insert new List<AR_PTF_Entity_Referential__c>{
            new AR_PTF_Entity_Referential__c(
                Name = 'Entite Corridor Complete',
                AR_Active__c = true,
                AR_Floor_Percent__c = 18,
                AR_Target_Percent__c = 23,
                AR_Ideal_Percent__c = 28
            ),
            new AR_PTF_Entity_Referential__c(
                Name = 'Entite Corridor Partielle',
                AR_Active__c = true,
                AR_Floor_Percent__c = 18
            ),
            new AR_PTF_Entity_Referential__c(Name = 'Entite Corridor Vide', AR_Active__c = true),
            new AR_PTF_Entity_Referential__c(
                Name = 'Entite Corridor Autre',
                AR_Active__c = true,
                AR_Floor_Percent__c = 12,
                AR_Target_Percent__c = 17,
                AR_Ideal_Percent__c = 22
            )
        };
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Corridor Entite',
            cxsrec__Account__c = plain.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
    }

    private static Id accountNamed(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
    }

    private static Id entityNamed(String name) {
        return [SELECT Id FROM AR_PTF_Entity_Referential__c WHERE Name = :name LIMIT 1].Id;
    }

    private static AR_PTF_Entity_Referential__c entityRecord(String name) {
        return [
            SELECT Name, AR_Floor_Percent__c, AR_Target_Percent__c, AR_Ideal_Percent__c
            FROM AR_PTF_Entity_Referential__c WHERE Name = :name LIMIT 1
        ];
    }

    private static AR_Price_Matrix__c matrixWith(String status, Id entityId) {
        cxsrec__cxsPosition__c position = [SELECT Id, Name FROM cxsrec__cxsPosition__c LIMIT 1];
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Position_Name__c = position.Name,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = 0,
            AR_Proposed_TJM__c = 300,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_TJM_Target__c = 267,
            AR_TJM_Ideal__c = 286,
            AR_MC2_Percent__c = 33.3,
            AR_Contract_Coefficient_Applied__c = 1.8,
            AR_Working_Days_Applied__c = 218,
            AR_Status__c = status,
            AR_Entity_Ref__c = entityId,
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
        return m;
    }

    @IsTest
    static void testResolve_grandCompteWinsOverCompleteEntity() {
        AR_PricingMatrixService.CorridorResolution r = AR_PricingMatrixService.resolveCorridor(
            accountNamed('Corridor Entite Grand Compte'),
            entityRecord('Entite Corridor Complete')
        );
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_ACCOUNT, r.source);
        System.assertEquals(10, r.pcts.floorPercent);
        System.assertEquals(null, r.entityName);
    }

    @IsTest
    static void testResolve_completeEntityWithoutKeyAccount() {
        AR_PricingMatrixService.CorridorResolution r = AR_PricingMatrixService.resolveCorridor(
            accountNamed('Corridor Entite Sans Grand Compte'),
            entityRecord('Entite Corridor Autre')
        );
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_ENTITY, r.source);
        System.assertEquals('Entite Corridor Autre', r.entityName);
        System.assertEquals(12, r.pcts.floorPercent);
        System.assertEquals(17, r.pcts.targetPercent);
        System.assertEquals(22, r.pcts.idealPercent);
    }

    @IsTest
    static void testResolve_partialEntityIgnoredFallsBackToDefaults() {
        AR_PricingMatrixService.CorridorResolution r = AR_PricingMatrixService.resolveCorridor(
            accountNamed('Corridor Entite Sans Grand Compte'),
            entityRecord('Entite Corridor Partielle')
        );
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_DEFAULT, r.source);
        System.assertEquals(null, r.entityName);
        System.assertEquals(AR_PricingCalculator.FLOOR_PERCENT_DEFAULT, r.pcts.floorPercent);
    }

    @IsTest
    static void testResolve_emptyEntityAndNoEntityFallBackToDefaults() {
        Id plain = accountNamed('Corridor Entite Sans Grand Compte');
        System.assertEquals(
            AR_PricingMatrixService.CORRIDOR_DEFAULT,
            AR_PricingMatrixService.resolveCorridor(plain, entityRecord('Entite Corridor Vide')).source
        );
        System.assertEquals(
            AR_PricingMatrixService.CORRIDOR_DEFAULT,
            AR_PricingMatrixService.resolveCorridor(plain, null).source
        );
    }

    @IsTest
    static void testGetCorridorPercents_entityOnlyReturnsEntityAndName() {
        AR_PricingMatrixService.ThresholdPercentsDto dto = AR_PricingMatrixService.getAccountCorridorPercents(
            null,
            entityNamed('Entite Corridor Complete')
        );
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_ENTITY, dto.source);
        System.assertEquals('Entite Corridor Complete', dto.entityName);
        System.assertEquals(18, dto.floorPercent);
        System.assertEquals(23, dto.targetPercent);
        System.assertEquals(28, dto.idealPercent);
    }

    @IsTest
    static void testGetCorridorPercents_defaultsReturnNull() {
        System.assertEquals(
            null,
            AR_PricingMatrixService.getAccountCorridorPercents(null, entityNamed('Entite Corridor Partielle'))
        );
        System.assertEquals(
            null,
            AR_PricingMatrixService.getAccountCorridorPercents(accountNamed('Corridor Entite Sans Grand Compte'), null)
        );
    }

    @IsTest
    static void testValidatedMatrix_entityChangeKeepsFrozenThresholds() {
        AR_Price_Matrix__c m = matrixWith('Validée', entityNamed('Entite Corridor Autre'));
        m.AR_Floor_Percent_Applied__c = 20;
        m.AR_Target_Percent_Applied__c = 25;
        m.AR_Ideal_Percent_Applied__c = 30;
        m.AR_Corridor_Source__c = AR_PricingMatrixService.CORRIDOR_DEFAULT;
        insert m;

        AR_PricingMatrixService.changeValidatedMatrixEntity(m.Id, entityNamed('Entite Corridor Complete'));

        AR_Price_Matrix__c after = [
            SELECT AR_Entity_Ref__c, AR_Floor_Percent_Applied__c, AR_Target_Percent_Applied__c,
                   AR_Ideal_Percent_Applied__c, AR_Corridor_Source__c
            FROM AR_Price_Matrix__c WHERE Id = :m.Id
        ];
        System.assertEquals(entityNamed('Entite Corridor Complete'), after.AR_Entity_Ref__c);
        System.assertEquals(20, after.AR_Floor_Percent_Applied__c);
        System.assertEquals(25, after.AR_Target_Percent_Applied__c);
        System.assertEquals(30, after.AR_Ideal_Percent_Applied__c);
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_DEFAULT, after.AR_Corridor_Source__c);
    }

    @IsTest
    static void testDraft_recalculateUsesEntityThresholdsAndStoresOrigin() {
        AR_Price_Matrix__c m = matrixWith('Brouillon', entityNamed('Entite Corridor Complete'));
        insert m;

        AR_PricingResult result = AR_PricingMatrixService.recalculate(m.Id);

        System.assertEquals(18, result.floorPercentApplied);
        System.assertEquals(23, result.targetPercentApplied);
        System.assertEquals(28, result.idealPercentApplied);
        System.assertEquals(AR_PricingMatrixService.CORRIDOR_ENTITY, result.corridorSource);
        System.assertEquals('Entite Corridor Complete', result.corridorEntityName);
    }
}