/**
 * Session 289 (reprise 287b) : visibilité du journal de purge pour le tableau de bord, par profil.
 * BM → les siens ; DA → ceux de son BM ; autre BM → rien des siens ; Manager → tout.
 */
@IsTest
private class AR_DashboardPurgeReaderTest {

    @IsTest
    static void testReadableRootLogs_byPersona() {
        User bm = AR_TestPersona.bmWithDa();
        Id daId = [SELECT TP_DA__c FROM User WHERE Id = :bm.Id].TP_DA__c;
        User otherBm = AR_TestPersona.bm();
        AR_Purge_Log__c mine = log('PER-MINE', true, bm.Id);
        AR_Purge_Log__c other = log('PER-OTHER', true, otherBm.Id);
        AR_Purge_Log__c notRoot = log('PER-NOTROOT', false, bm.Id);
        insert new List<AR_Purge_Log__c>{ mine, other, notRoot };

        System.runAs(bm) {
            System.assertEquals(new Set<String>{ 'PER-MINE' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'BM : les siens, racines seulement');
        }
        System.runAs(new User(Id = daId)) {
            System.assertEquals(new Set<String>{ 'PER-MINE' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'DA : ceux de son BM');
        }
        System.runAs(otherBm) {
            System.assertEquals(new Set<String>{ 'PER-OTHER' }, perimetersOf(AR_DashboardPurgeReader.readableRootLogs()), 'Autre BM : rien du premier BM');
        }
        System.runAs(AR_TestPersona.manager()) {
            Set<String> seen = perimetersOf(AR_DashboardPurgeReader.readableRootLogs());
            System.assert(seen.contains('PER-MINE') && seen.contains('PER-OTHER'), 'Manager : tout');
            System.assert(!seen.contains('PER-NOTROOT'), 'Seules les racines remontent');
        }
    }

    @IsTest
    static void testReadableRootLogs_userWithoutLogs_getsEmpty() {
        insert log('PER-X', true, AR_TestPersona.bm().Id);
        System.runAs(AR_TestPersona.bm()) {
            System.assert(AR_DashboardPurgeReader.readableRootLogs().isEmpty(), 'Un BM sans journal propre ne voit rien');
        }
    }

    private static AR_Purge_Log__c log(String perimeter, Boolean wasRoot, Id ownerId) {
        return new AR_Purge_Log__c(
            AR_Perimeter__c = perimeter, AR_Was_Root__c = wasRoot, AR_Matrix_Created_Date__c = System.now(),
            AR_Purged_At__c = System.now(), AR_Matrix_Name__c = 'PURGE-TEST', AR_Owner_Id__c = String.valueOf(ownerId)
        );
    }

    private static Set<String> perimetersOf(List<AR_Purge_Log__c> logs) {
        Set<String> out = new Set<String>();
        for (AR_Purge_Log__c l : logs) {
            out.add(l.AR_Perimeter__c);
        }
        return out;
    }
}