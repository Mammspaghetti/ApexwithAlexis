/**
 * Alimente la vue « Mes matrices » de l'app Pricing Tool. `with sharing` : ne retourne que les
 * matrices visibles de l'utilisateur courant (Private + viewAllRecords pour Validator/Admin,
 * cf. docs/architecture-technique.md §5). Filtre/recherche/tri sont faits côté LWC (une seule
 * méthode cacheable, jeu de données limité au périmètre BM/Directeur).
 */
public with sharing class AR_MatrixListService {

    public class MatrixListItem {
        @AuraEnabled public Id matrixId;
        @AuraEnabled public String name;
        // Session 28 : nécessaire à l'action « Dupliquer » depuis la liste (arMatrixDuplicateModal
        // pré-remplit le besoin cible avec celui de la matrice source).
        @AuraEnabled public Id positionId;
        @AuraEnabled public String positionName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountCountry;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String contractType;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal proposedTjm;
        @AuraEnabled public List<AR_PricingResult.TjmPeriod> tjmPeriods;
        // Régie sans régule active (docs/265c §7) : pastille « RSR » à côté du TJM.
        @AuraEnabled public Boolean rplsrActive;
        @AuraEnabled public Decimal mc2PercentHuman;
        @AuraEnabled public String corridorSegment;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        // Session 169 : consultant pour la recherche dans la liste.
        @AuraEnabled public String consultantName;
        // Session 284 : affaire gagnée — besoin au statut Gagné, version gagnante confirmée et son niveau de prix.
        @AuraEnabled public Boolean positionWon;
        @AuraEnabled public Boolean won;
        @AuraEnabled public String signedPriceLevel;
    }

    @AuraEnabled(cacheable=true)
    public static List<MatrixListItem> getMatrices() {
        // Id DESC en second critère : cf. AR_DashboardService pour le rationnel (tri CreatedDate
        // indéfini entre enregistrements créés dans la même transaction).
        List<AR_Price_Matrix__c> matrices = [
            SELECT Id, Name, AR_Position__c, AR_Position_Name__c, AR_Account_Name__c, AR_Account_Country__c, OwnerId,
                   AR_Contract_Type__c, AR_Currency__c, AR_Proposed_TJM__c, AR_TJM_Weighted__c, AR_TJM_Periods__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c, AR_MC2_Percent__c, AR_Corridor_Segment__c,
                   AR_Status__c, CreatedDate, AR_Consultant_Name__c, AR_Consultant__r.Name, AR_RPLSR_Enabled__c,
                   AR_Position__r.cxsrec__Status__c, AR_Won__c, AR_Signed_Price_Level__c
            FROM AR_Price_Matrix__c
            ORDER BY CreatedDate DESC, Id DESC
        ];
        Map<Id, String> ownerNames = ownerNamesFor(matrices);
        List<MatrixListItem> items = new List<MatrixListItem>();
        for (AR_Price_Matrix__c m : matrices) {
            items.add(toItem(m, ownerNames));
        }
        return items;
    }

    /**
     * Requête séparée plutôt que `Owner.Name` dans le SELECT : cette relation polymorphe standard
     * retourne `null` en contexte `@IsTest` sur cet objet alors qu'`OwnerId` est correctement
     * renseigné (reproduit, cf. AR_MatrixListServiceTest — même famille de piège que le DML
     * `AccessLevel` documenté dans docs/05-derogation-emails.md §5, cause exacte non élucidée).
     * OwnerId pointe toujours un User dans ce périmètre (jamais une Queue) — cf. AR_NotificationService.
     */
    public static Map<Id, String> ownerNamesFor(List<AR_Price_Matrix__c> matrices) {
        Set<Id> ownerIds = new Set<Id>();
        for (AR_Price_Matrix__c m : matrices) {
            if (m.OwnerId != null) {
                ownerIds.add(m.OwnerId);
            }
        }
        Map<Id, String> names = new Map<Id, String>();
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ownerIds]) {
            names.put(u.Id, u.Name);
        }
        return names;
    }

    /** Réutilisé par AR_DashboardService (5 dernières matrices) pour ne pas dupliquer le mapping. */
    public static MatrixListItem toItem(AR_Price_Matrix__c m, Map<Id, String> ownerNames) {
        MatrixListItem item = new MatrixListItem();
        item.matrixId = m.Id;
        item.name = m.Name;
        item.positionId = m.AR_Position__c;
        item.positionName = m.AR_Position_Name__c;
        item.accountName = m.AR_Account_Name__c;
        item.accountCountry = m.AR_Account_Country__c;
        item.ownerName = m.OwnerId != null ? ownerNames.get(m.OwnerId) : null;
        item.contractType = m.AR_Contract_Type__c;
        item.currencyCode = m.AR_Currency__c;
        item.proposedTjm = AR_PricingMatrixService.effectiveTjm(m);
        item.tjmPeriods = AR_PricingMatrixService.tjmPeriodsOf(m);
        item.rplsrActive = m.AR_RPLSR_Enabled__c == true;
        item.mc2PercentHuman = m.AR_MC2_Percent__c;
        item.corridorSegment = m.AR_Corridor_Segment__c;
        item.status = m.AR_Status__c;
        item.createdDate = m.CreatedDate;
        // Lookup (session 54) préféré au texte libre historique, plus écrit depuis.
        item.consultantName = m.AR_Consultant__r != null ? m.AR_Consultant__r.Name : m.AR_Consultant_Name__c;
        item.positionWon = m.AR_Position__r != null && m.AR_Position__r.cxsrec__Status__c == 'Gagné';
        item.won = m.AR_Won__c == true;
        item.signedPriceLevel = m.AR_Signed_Price_Level__c;
        return item;
    }
}