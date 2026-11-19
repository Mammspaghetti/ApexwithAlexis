// Session 175 : suit le statut du besoin Connexys pour garder la liste « Matrice validée » propre.
// Trigger AR_ distinct des triggers managés de Connexys (jamais touchés) ; ne réagit qu'à un changement de
// cxsrec__Status__c dont un côté est Open, et ne lève jamais d'erreur vers Connexys (cf. handlePositions).
// Session 284 : passage à « Gagné » → AR_WonDealDetector (indépendant de la synchro, jamais d'erreur vers Connexys).
trigger AR_PositionStatusTrigger on cxsrec__cxsPosition__c (after update) {
    AR_ValidatedMatrixSyncService.handlePositions(Trigger.new, Trigger.oldMap);
    AR_WonDealDetector.handlePositions(Trigger.new, Trigger.oldMap);
}