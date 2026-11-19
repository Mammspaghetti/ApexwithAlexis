/**
 * Périmètre du besoin (TP_P_rim_tre__c), figé sur la matrice au moment de la validation.
 * Lecture ciblée d'un seul champ en mode système : le valideur d'une dérogation n'a pas
 * forcément accès au besoin, et la valeur figée ne doit pas dépendre de qui valide.
 */
public without sharing class AR_PerimeterSnapshot {
    public static String perimeterOfMatrix(Id matrixId) {
        List<AR_Price_Matrix__c> rows = [
            SELECT AR_Position__r.TP_P_rim_tre__c
            FROM AR_Price_Matrix__c
            WHERE Id = :matrixId
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].AR_Position__r == null) {
            return null;
        }
        String value = rows[0].AR_Position__r.TP_P_rim_tre__c;
        return value == null ? null : value.left(255);
    }
}