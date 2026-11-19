/**
 * AR_DerogationTriggerHandler : verrou serveur d'une dérogation — ne peut être modifiée/supprimée
 * que via AR_DerogationService.decide(). Session 27 (prompts/session-27-filet-de-tests.md §2) :
 * « testés pour ce qu'ils empêchent ». La règle « une dérogation ne se traite qu'une fois » est déjà
 * couverte au bon niveau (AR_DerogationServiceTest.testDecide_alreadyDecided_throws, guard FOR UPDATE
 * dans le service) — pas dupliquée ici, ce fichier se concentre sur ce que LE TRIGGER lui-même
 * empêche : toute modification ou suppression hors service, y compris en lot, et le bypass.
 */
@IsTest
private class AR_DerogationTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Verrou Dérogation',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;

        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Verrou Dérogation', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;

        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Position_Name__c = position.Name,
            AR_Account_Country__c = 'France',
            AR_Contract_Type__c = 'NEARSHORE',
            AR_CJM_Nearshore__c = 200,
            AR_RFA_Percent__c = 0,
            AR_Total_Daily_Cost__c = 200,
            AR_TJM_Floor__c = 250,
            AR_TJM_Target__c = 267,
            AR_TJM_Ideal__c = 286,
            AR_Status__c = 'En dérogation',
            AR_Selected_Validator__c = UserInfo.getUserId()
        );
        insert matrix;

        List<AR_Derogation__c> derogations = new List<AR_Derogation__c>{
            new AR_Derogation__c(
                AR_Price_Matrix__c = matrix.Id,
                AR_Selected_Validator__c = UserInfo.getUserId(),
                AR_Requester_Reason__c = 'Cas 1',
                AR_Decision__c = 'En attente',
                AR_Requested_At__c = System.now()
            ),
            new AR_Derogation__c(
                AR_Price_Matrix__c = matrix.Id,
                AR_Selected_Validator__c = UserInfo.getUserId(),
                AR_Requester_Reason__c = 'Cas 2 (pour le lot)',
                AR_Decision__c = 'En attente',
                AR_Requested_At__c = System.now()
            )
        };
        insert derogations;
    }

    // AR_Requester_Reason__c est un LongTextArea : non filtrable en SOQL. Les deux dérogations sont
    // distinguées par ordre d'insertion (un seul DML dans @TestSetup, tri explicite CreatedDate+Id
    // pour ne pas dépendre d'un ordre de retour implicite).
    private static List<AR_Derogation__c> getDerogationsOrdered() {
        return [
            SELECT Id, AR_Validator_Comment__c
            FROM AR_Derogation__c
            ORDER BY CreatedDate ASC, Id ASC
        ];
    }

    private static AR_Derogation__c firstDerogation() {
        return getDerogationsOrdered()[0];
    }

    private static AR_Derogation__c secondDerogation() {
        return getDerogationsOrdered()[1];
    }

    @IsTest
    static void testDirectUpdate_blocked() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Derogation__c derogation = firstDerogation();
            derogation.AR_Validator_Comment__c = 'Tentative de contournement du layout standard';
            try {
                update derogation;
                System.assert(false, 'Une dérogation ne doit pas être modifiable hors AR_DerogationService.decide().');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('ne peut être modifiée que via le traitement du valideur'),
                    'Message inattendu : ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void testDirectDelete_blocked() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Derogation__c derogation = firstDerogation();
            try {
                delete derogation;
                System.assert(false, 'Une dérogation ne doit jamais pouvoir être supprimée.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('ne peut pas être supprimée'), 'Message inattendu : ' + e.getMessage());
            }
        }
    }

    /** Contournement par mise à jour en masse : le blocage doit tenir même noyé dans un lot. */
    @IsTest
    static void testBulkUpdate_allRowsBlocked() {
        AR_Derogation__c d1 = firstDerogation();
        AR_Derogation__c d2 = secondDerogation();
        d1.AR_Validator_Comment__c = 'Lot — ligne 1';
        d2.AR_Validator_Comment__c = 'Lot — ligne 2';

        List<Database.SaveResult> results = Database.update(new List<AR_Derogation__c>{ d1, d2 }, false);

        System.assertEquals(2, results.size());
        for (Database.SaveResult r : results) {
            System.assert(!r.isSuccess(), 'Aucune ligne du lot ne doit passer hors du service.');
        }
    }

    /** Contournement par suppression en masse : même garantie côté delete. */
    @IsTest
    static void testBulkDelete_allRowsBlocked() {
        AR_Derogation__c d1 = firstDerogation();
        AR_Derogation__c d2 = secondDerogation();

        List<Database.DeleteResult> results = Database.delete(new List<AR_Derogation__c>{ d1, d2 }, false);

        System.assertEquals(2, results.size());
        for (Database.DeleteResult r : results) {
            System.assert(!r.isSuccess(), 'Aucune suppression en lot ne doit passer.');
        }
    }

    @IsTest
    static void testBypass_serviceContext_allowsUpdate() {
        AR_Derogation__c derogation = firstDerogation();
        derogation.AR_Validator_Comment__c = 'Écrit par un service interne';
        AR_TriggerBypass.serviceContext = true;
        try {
            update derogation;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        AR_Derogation__c reloaded = [SELECT AR_Validator_Comment__c FROM AR_Derogation__c WHERE Id = :derogation.Id];
        System.assertEquals('Écrit par un service interne', reloaded.AR_Validator_Comment__c);
    }

    @IsTest
    static void testBypassReset_directUpdateBlockedAgainAfterFinally() {
        System.runAs(AR_TestPersona.francais()) {
            AR_Derogation__c derogation = firstDerogation();
            AR_TriggerBypass.serviceContext = true;
            try {
                derogation.AR_Validator_Comment__c = 'Premier accès, sous bypass';
                update derogation;
            } finally {
                AR_TriggerBypass.serviceContext = false;
            }

            derogation.AR_Validator_Comment__c = 'Second accès, sans bypass — doit être refusé';
            try {
                update derogation;
                System.assert(false, 'Après la sortie du bypass, la dérogation doit redevenir verrouillée.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('ne peut être modifiée que via le traitement du valideur'));
            }
        }
    }

    @IsTest
    static void testBypass_serviceContext_allowsDelete() {
        AR_Derogation__c derogation = secondDerogation();
        AR_TriggerBypass.serviceContext = true;
        try {
            delete derogation;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Derogation__c WHERE Id = :derogation.Id]
        );
    }
}