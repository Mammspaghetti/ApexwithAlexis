/**
 * Lecture du journal de purge pour le tableau de bord (session 286).
 *
 * `without sharing` : un Business Manager n'a aucun droit objet sur AR_Purge_Log__c, mais ses simulations
 * purgées doivent compter dans « Simulations ». Le filtrage est fait ICI, côté serveur, selon la règle de
 * visibilité des matrices (19/10) : journaux dont le propriétaire (AR_Owner_Id__c) est l'utilisateur, ou
 * dont l'utilisateur est le RA, DA, DD, Directeur, Directeur commercial ou Directeur commercial groupe du
 * propriétaire. Les porteurs d'AR_Pricing_Manager (droit objet sur le journal) voient tout. Aucun nouveau
 * droit objet n'est accordé : la classe ne remonte que les racines, avec les seuls champs nécessaires.
 */
public without sharing class AR_DashboardPurgeReader {

    private static final String BASE_QUERY = 'SELECT AR_Entity_Id__c, AR_Entity_Name__c, AR_Owner_Id__c, AR_Owner_Name__c, '
        + 'AR_Perimeter__c, AR_Matrix_Created_Date__c FROM AR_Purge_Log__c WHERE AR_Was_Root__c = true';

    public static List<AR_Purge_Log__c> readableRootLogs() {
        Id userId = UserInfo.getUserId();
        // Mode système explicite : le BM n'a aucun droit objet sur le journal, le filtre ci-dessous en tient lieu.
        // Porteur d'AR_Pricing_Manager = seul à avoir le droit objet sur le journal (PermissionSetAssignment n'est
        // pas interrogeable par un utilisateur standard) : il voit tout.
        if (Schema.sObjectType.AR_Purge_Log__c.isAccessible()) {
            return Database.queryWithBinds(BASE_QUERY, new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        }
        Set<String> owners = new Set<String>{ String.valueOf(userId), String.valueOf(userId).left(15) };
        for (User u : [
            SELECT Id FROM User
            WHERE TP_RA__c = :userId OR TP_DA__c = :userId OR TP_DD__c = :userId OR TP_Directeur__c = :userId
               OR TP_Directeur_commercial__c = :userId OR TP_Directeur_commercial_groupe__c = :userId
        ]) {
            owners.add(String.valueOf(u.Id));
            owners.add(String.valueOf(u.Id).left(15));
        }
        return Database.queryWithBinds(
            BASE_QUERY + ' AND AR_Owner_Id__c IN :owners', new Map<String, Object>{ 'owners' => owners }, AccessLevel.SYSTEM_MODE
        );
    }
}