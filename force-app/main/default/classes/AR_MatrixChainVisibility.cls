/**
 * Requêtes hors partage, volontairement limitées à un entier (MAX/COUNT), jamais à des données de
 * champ, pour AR_MatrixChainService : l'intégrité de la numérotation de chaîne et la détection
 * d'une chaîne partiellement visible sont des invariants globaux, ils ne doivent pas dépendre de ce
 * que l'utilisateur courant a le droit de voir. Classe top-level dédiée (plutôt qu'une classe
 * interne à AR_MatrixChainService) : plus robuste, pattern déjà éprouvé dans ce projet
 * (AR_MatrixVersionService, AR_NotificationService sont eux aussi `without sharing` au niveau
 * top-level).
 */
public without sharing class AR_MatrixChainVisibility {

    public static Integer maxNegotiationVersion(Id rootId) {
        AggregateResult[] results = [
            SELECT MAX(AR_Negotiation_Version__c) maxVersion
            FROM AR_Price_Matrix__c
            WHERE Id = :rootId OR AR_Root_Matrix__c = :rootId
        ];
        Decimal maxVersion = (Decimal) results[0].get('maxVersion');
        return maxVersion != null ? maxVersion.intValue() : 1;
    }

    public static Integer countChainMembers(Id rootId) {
        return [
            SELECT COUNT()
            FROM AR_Price_Matrix__c
            WHERE Id = :rootId OR AR_Root_Matrix__c = :rootId
        ];
    }
}