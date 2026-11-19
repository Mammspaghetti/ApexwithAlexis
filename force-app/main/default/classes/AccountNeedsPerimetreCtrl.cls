public with sharing class AccountNeedsPerimetreCtrl {

    private Id accountId;
    public Integer pageSize { get; set; }
    public Integer offsetSize { get; set; }
    private Integer totalSize;

    public AccountNeedsPerimetreCtrl(ApexPages.StandardController std) {
        // Récupération robuste de l'Id (fonctionne en page autonome et en composant sur le layout)
        this.accountId = std.getId();
        if (this.accountId == null) {
            SObject rec = std.getRecord();
            if (rec != null) this.accountId = (Id)rec.get('Id');
        }

        this.pageSize = 20;
        this.offsetSize = 0;
        this.totalSize = countNeedsInternal();
    }

    public Integer getTotalSize() {
        return totalSize;
    }

    public List<cxsrec__cxsPosition__c> getNeeds() {
        if (accountId == null) return new List<cxsrec__cxsPosition__c>();

        List<cxsrec__cxsPosition__c> rows = [
            SELECT Id, Name, Priorit__c, TP_Niveau_d_engagement_Abylsen__c, AB_Contact__c, AB_Need_details__r.AB_contact__c, cxsrec__Status__c, 
            CreatedDate, TP_Besoin_de_mon_Perimetre__c, AB_Need_details__r.AB_Account__c
            FROM cxsrec__cxsPosition__c
            WHERE AB_Need_details__r.AB_Account__c = :accountId
              AND TP_Besoin_de_mon_Perimetre__c = TRUE
            ORDER BY CreatedDate DESC
        ];
        return rows;
    }

    private Integer countNeedsInternal() {
        if (accountId == null) return 0;
        return (Integer)Database.countQuery('SELECT COUNT() FROM cxsrec__cxsPosition__c WHERE AB_Need_details__r.AB_Account__c = :accountId AND TP_Besoin_de_mon_Perimetre__c = TRUE');
    }

    // Navigation
    public PageReference next() {
        if (offsetSize + pageSize < totalSize) {
            offsetSize += pageSize;
        }
        return null;
    }

    public PageReference prev() {
        offsetSize = Math.max(0, offsetSize - pageSize);
        return null;
    }
}