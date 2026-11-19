/**
 * Recalcul asynchrone du partage de la chaîne : matrices dont le propriétaire a changé de fiche (six champs
 * de la chaîne) et matrices des entités PTF dont les valideurs ont changé. Lancé par `AR_UserTrigger` et
 * `AR_PTFEntityValidatorTrigger` ; asynchrone pour ne pas mêler DML sur User et DML de partage. Les matrices
 * d'entité sont traitées par lots : le travail se relance pour le reste.
 */
public class AR_MatrixSharingQueueable implements Queueable {
    private final Set<Id> ownerIds;
    private final Set<Id> entityIds;
    private final List<Id> pendingMatrixIds;

    public AR_MatrixSharingQueueable(Set<Id> ownerIds) {
        this(ownerIds, new Set<Id>(), null);
    }

    public AR_MatrixSharingQueueable(Set<Id> ownerIds, Set<Id> entityIds, List<Id> pendingMatrixIds) {
        this.ownerIds = ownerIds == null ? new Set<Id>() : ownerIds;
        this.entityIds = entityIds == null ? new Set<Id>() : entityIds;
        this.pendingMatrixIds = pendingMatrixIds;
    }

    public void execute(QueueableContext context) {
        if (!ownerIds.isEmpty()) {
            AR_MatrixSharingService.recalculateForOwners(ownerIds);
        }
        if (!entityIds.isEmpty()) {
            List<Id> rest = AR_MatrixSharingService.recalculateEntityBatch(entityIds, pendingMatrixIds);
            if (!rest.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new AR_MatrixSharingQueueable(new Set<Id>(), entityIds, rest));
            }
        }
    }
}