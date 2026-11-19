/**
 * AR_PriceMatrixTriggerHandler : verrou serveur d'une matrice décidée. Session 27
 * (prompts/session-27-filet-de-tests.md §2) : « testés pour ce qu'ils empêchent, pas seulement pour
 * ce qu'ils laissent passer » — déjà 100 % de couverture de ligne (via les services), mais rien
 * n'assertait explicitement le refus, le contournement par lot, ni le comportement du bypass.
 */
@IsTest
private class AR_PriceMatrixTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Verrou Matrice',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Verrou', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (String status : new List<String>{ 'Brouillon', 'En dérogation', 'Validée', 'Validée par dérogation', 'Refusée' }) {
            matrices.add(baseMatrix(position.Id, position.Name, status));
        }
        insert matrices;
    }

    private static AR_Price_Matrix__c baseMatrix(Id positionId, String positionName, String status) {
        return new AR_Price_Matrix__c(
            AR_Position__c = positionId,
            AR_Position_Name__c = positionName,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = 0,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_TJM_Target__c = 267,
            AR_TJM_Ideal__c = 286,
            AR_Status__c = status,
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
    }

    private static AR_Price_Matrix__c getByStatus(String status) {
        return [SELECT Id, AR_Status__c, AR_Derogation_Reason__c FROM AR_Price_Matrix__c WHERE AR_Status__c = :status LIMIT 1];
    }

    private static void assertDirectUpdateBlocked(String status) {
        AR_Price_Matrix__c matrix = getByStatus(status);
        matrix.AR_Derogation_Reason__c = 'Tentative de contournement';
        try {
            update matrix;
            System.assert(false, 'Une matrice au statut « ' + status + ' » ne doit plus être modifiable par API directe.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('ne peut plus être modifiée'),
                'Message d\'erreur inattendu pour le statut ' + status + ' : ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testDirectUpdate_onValidee_blocked() {
        System.runAs(AR_TestPersona.francais()) {
            assertDirectUpdateBlocked('Validée');
        }
    }

    @IsTest
    static void testDirectUpdate_onValideeParDerogation_blocked() {
        System.runAs(AR_TestPersona.francais()) {
            assertDirectUpdateBlocked('Validée par dérogation');
        }
    }

    @IsTest
    static void testDirectUpdate_onRefusee_blocked() {
        System.runAs(AR_TestPersona.francais()) {
            assertDirectUpdateBlocked('Refusée');
        }
    }

    @IsTest
    static void testDirectUpdate_onBrouillon_allowed() {
        AR_Price_Matrix__c matrix = getByStatus('Brouillon');
        matrix.AR_Derogation_Reason__c = 'Édition normale en cours de saisie';
        update matrix; // ne doit lever aucune exception
        AR_Price_Matrix__c reloaded = [SELECT AR_Derogation_Reason__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assertEquals('Édition normale en cours de saisie', reloaded.AR_Derogation_Reason__c);
    }

    /**
     * Gap connu, documenté (docs/architecture-technique.md §5.2, session 25) : le trigger autorise
     * TOUTE édition tant que le statut est « En dérogation », y compris des champs de décision
     * (AR_Effective_Validator__c, AR_Validated_At__c) qui ne devraient être touchés que par
     * AR_DerogationService.decide(). Non exploité/tranché dans cette session (hors périmètre) — ce
     * test verrouille le comportement ACTUEL pour qu'un futur changement soit un choix explicite,
     * pas une régression silencieuse découverte en production.
     */
    @IsTest
    static void testDirectUpdate_onEnDerogation_stillAllowed_knownGap() {
        AR_Price_Matrix__c matrix = getByStatus('En dérogation');
        matrix.AR_Derogation_Reason__c = 'Édition directe pendant instruction — gap connu';
        update matrix; // ne doit lever aucune exception : c'est le gap documenté, pas un défaut de ce test
        AR_Price_Matrix__c reloaded = [SELECT AR_Derogation_Reason__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assertEquals('Édition directe pendant instruction — gap connu', reloaded.AR_Derogation_Reason__c);
    }

    /**
     * Contournement par mise à jour en masse : un update groupé ne doit PAS laisser passer une ligne
     * décidée sous prétexte qu'elle est mélangée à des lignes éditables dans le même DML.
     * Database.update(allOrNone=false) pour observer le résultat ligne à ligne plutôt qu'une seule
     * exception globale qui masquerait laquelle a été bloquée.
     */
    @IsTest
    static void testBulkUpdate_mixedStatuses_blocksOnlyDecidedRows() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Price_Matrix__c editable = getByStatus('Brouillon');
            AR_Price_Matrix__c locked = getByStatus('Validée');
            editable.AR_Derogation_Reason__c = 'Lot — ligne éditable';
            locked.AR_Derogation_Reason__c = 'Lot — tentative sur ligne verrouillée';

            List<Database.SaveResult> results = Database.update(
                new List<AR_Price_Matrix__c>{ editable, locked },
                false
            );

            System.assertEquals(2, results.size());
            System.assert(results[0].isSuccess(), 'La ligne Brouillon du lot doit passer.');
            System.assert(!results[1].isSuccess(), 'La ligne Validée du lot ne doit PAS passer, même en lot.');
            System.assert(
                results[1].getErrors()[0].getMessage().contains('ne peut plus être modifiée')
            );
        }
    }

    @IsTest
    static void testBypass_serviceContext_allowsDirectUpdateOnDecidedMatrix() {
        AR_Price_Matrix__c matrix = getByStatus('Validée');
        matrix.AR_Derogation_Reason__c = 'Écriture via un service interne (snapshot, transition)';
        AR_TriggerBypass.serviceContext = true;
        try {
            update matrix;
        } finally {
            // Toujours en finally : un bypass qui resterait actif au-delà de son bloc DML est une
            // porte ouverte sur TOUTE transaction suivante du même contexte d'exécution.
            AR_TriggerBypass.serviceContext = false;
        }
        AR_Price_Matrix__c reloaded = [SELECT AR_Derogation_Reason__c FROM AR_Price_Matrix__c WHERE Id = :matrix.Id];
        System.assertEquals('Écriture via un service interne (snapshot, transition)', reloaded.AR_Derogation_Reason__c);
        System.assertEquals(false, AR_TriggerBypass.serviceContext, 'le bypass ne doit jamais rester actif après son bloc');
    }

    @IsTest
    static void testBypassReset_directUpdateBlockedAgainAfterFinally() {
        System.runAs(AR_TestPersona.francais()) {
            // Le bypass ci-dessus est remis à false dans son propre test (isolation Apex garantie entre
            // méthodes de test), mais ce test verrouille explicitement qu'un bypass n'a pas d'effet
            // rémanent au sein de la MÊME méthode, une fois le bloc try/finally qui l'a positionné sorti.
            AR_Price_Matrix__c matrix = getByStatus('Validée');
            AR_TriggerBypass.serviceContext = true;
            try {
                matrix.AR_Derogation_Reason__c = 'Premier accès, sous bypass';
                update matrix;
            } finally {
                AR_TriggerBypass.serviceContext = false;
            }

            matrix.AR_Derogation_Reason__c = 'Second accès, sans bypass — doit être refusé';
            try {
                update matrix;
                System.assert(false, 'Après la sortie du bypass, la même matrice décidée doit redevenir verrouillée.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('ne peut plus être modifiée'));
            }
        }
    }

    /**
     * Reprise réelle d'un Brouillon (hors bypass) : l'avertissement de purge doit être réinitialisé,
     * sans quoi un brouillon repris serait quand même supprimé plus tard (AR_DraftPurgeBatch).
     */
    @IsTest
    static void testDraftResume_resetsPurgeWarning() {
        AR_Price_Matrix__c matrix = getByStatus('Brouillon');
        AR_TriggerBypass.serviceContext = true;
        try {
            matrix.AR_Purge_Warning_Sent__c = true;
            matrix.AR_Purge_Warning_Sent_Date__c = Date.today().addDays(-1);
            update matrix;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        matrix.AR_Derogation_Reason__c = 'Le propriétaire rouvre son brouillon';
        update matrix; // update réel, hors bypass : doit déclencher la réinitialisation

        AR_Price_Matrix__c reloaded = [
            SELECT AR_Purge_Warning_Sent__c, AR_Purge_Warning_Sent_Date__c
            FROM AR_Price_Matrix__c
            WHERE Id = :matrix.Id
        ];
        System.assertEquals(false, reloaded.AR_Purge_Warning_Sent__c);
        System.assertEquals(null, reloaded.AR_Purge_Warning_Sent_Date__c);
    }
}