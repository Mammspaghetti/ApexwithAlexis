/**
 * Drapeau statique permettant aux services Apex (AR_PricingMatrixService, AR_MatrixVersionService,
 * AR_DerogationService, AR_DraftPurgeBatch, AR_DerogationReminderBatch, AR_HierarchyNotificationBatch)
 * de contourner le verrouillage de AR_PriceMatrixTrigger / AR_DerogationTriggerHandler lors des
 * transitions qu'ils orchestrent eux-mêmes. Ne jamais laisser ce drapeau actif au-delà du bloc de
 * DML concerné — toujours via un try/finally.
 */
public class AR_TriggerBypass {
    public static Boolean       serviceContext    = false;
      // Formatage volontairement non standard ci-dessus (alignement manuel, commentaire indenté à
      // 6 espaces) : preuve session 29c que Prettier ne repasse plus sur les .cls via le hook
      // pre-commit — cf. package.json (lint-staged) et .prettierignore.
}