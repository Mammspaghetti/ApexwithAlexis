/**
 * Niveau de prix auquel une affaire est signée : règle du « niveau le plus haut atteint »
 * (P1 = TJM proposé, P2/P3 = prix de négociation). Utilisé par la confirmation d'une affaire gagnée
 * et par le tableau de bord.
 */
public with sharing class AR_SignedPriceLevel {
    public static final String P1 = 'P1';
    public static final String P2 = 'P2';
    public static final String P3 = 'P3';
    public static final String OFF_GRID = 'Hors grille';

    /**
     * @return le niveau atteint par le montant signé, null si le montant ou P1 est absent.
     *   P2/P3 vides ou case Grille cochée : seul P1 existe, tout montant inférieur est hors grille.
     */
    public static String compute(Decimal signedTjm, Decimal price1, Decimal price2, Decimal price3, Boolean clientGrid) {
        if (signedTjm == null || price1 == null) {
            return null;
        }
        if (signedTjm >= price1) {
            return P1;
        }
        if (clientGrid == true) {
            return OFF_GRID;
        }
        if (price2 != null && signedTjm >= price2) {
            return P2;
        }
        if (price3 != null && signedTjm >= price3) {
            return P3;
        }
        return OFF_GRID;
    }

    public static String compute(Decimal signedTjm, AR_Price_Matrix__c matrix) {
        if (matrix == null) {
            return null;
        }
        return compute(signedTjm, matrix.AR_Proposed_TJM__c, matrix.AR_Nego_Price_2__c, matrix.AR_Nego_Price_3__c, matrix.AR_Client_Grid__c);
    }
}