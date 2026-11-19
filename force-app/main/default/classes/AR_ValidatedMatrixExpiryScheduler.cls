/**
 * Session 175 — Lance AR_ValidatedMatrixExpiryBatch. Prévu pour un System.schedule quotidien :
 *   System.schedule('AR Validated Matrix Expiry', '0 30 3 * * ?', new AR_ValidatedMatrixExpiryScheduler());
 * (scripts/apex/175-schedule-validated-matrix-expiry.apex ; arrêt : 175-unschedule-validated-matrix-expiry.apex).
 *
 * ⚠ Un scheduler inscrit bloque le déploiement de TOUT l'Apex du manifest (docs/deploiement-production.md, ligne 7b) :
 * le désinscrire avant un déploiement, le réinscrire après. Pour couper sans désinscrire : mettre
 * AR_Validated_Matrix_Sync_Enabled__c à false (le batch devient un no-op), mais cela gèle aussi la synchro.
 */
public class AR_ValidatedMatrixExpiryScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AR_ValidatedMatrixExpiryBatch(), 200);
    }
}