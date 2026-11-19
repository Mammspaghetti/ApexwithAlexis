@IsTest
private class AR_SignedPriceLevelTest {
    @IsTest
    static void testExactAndAboveP1() {
        System.assertEquals('P1', AR_SignedPriceLevel.compute(500, 500, 450, 400, false));
        System.assertEquals('P1', AR_SignedPriceLevel.compute(520, 500, 450, 400, false));
    }

    @IsTest
    static void testBetweenLevels() {
        System.assertEquals('P2', AR_SignedPriceLevel.compute(480, 500, 450, 400, false), 'Entre P1 et P2 : niveau P2');
        System.assertEquals('P2', AR_SignedPriceLevel.compute(450, 500, 450, 400, false));
        System.assertEquals('P3', AR_SignedPriceLevel.compute(420, 500, 450, 400, false));
        System.assertEquals('P3', AR_SignedPriceLevel.compute(400, 500, 450, 400, false));
    }

    @IsTest
    static void testBelowP3_isOffGrid() {
        System.assertEquals('Hors grille', AR_SignedPriceLevel.compute(399, 500, 450, 400, false));
    }

    @IsTest
    static void testEmptyP2P3_onlyP1Exists() {
        System.assertEquals('P1', AR_SignedPriceLevel.compute(500, 500, null, null, false));
        System.assertEquals('Hors grille', AR_SignedPriceLevel.compute(499, 500, null, null, false));
        System.assertEquals('P3', AR_SignedPriceLevel.compute(430, 500, null, 400, false), 'P2 vide mais P3 renseigné : P3 reste atteignable');
    }

    @IsTest
    static void testClientGrid_onlyP1Exists() {
        System.assertEquals('P1', AR_SignedPriceLevel.compute(500, 500, 450, 400, true));
        System.assertEquals('Hors grille', AR_SignedPriceLevel.compute(460, 500, 450, 400, true));
    }

    @IsTest
    static void testMissingValues_returnNull() {
        System.assertEquals(null, AR_SignedPriceLevel.compute(null, 500, 450, 400, false));
        System.assertEquals(null, AR_SignedPriceLevel.compute(500, null, 450, 400, false));
        System.assertEquals(null, AR_SignedPriceLevel.compute(500, null));
    }

    @IsTest
    static void testMatrixOverload() {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(AR_Proposed_TJM__c = 500, AR_Nego_Price_2__c = 450, AR_Nego_Price_3__c = 400, AR_Client_Grid__c = false);
        System.assertEquals('P2', AR_SignedPriceLevel.compute(455, m));
    }
}