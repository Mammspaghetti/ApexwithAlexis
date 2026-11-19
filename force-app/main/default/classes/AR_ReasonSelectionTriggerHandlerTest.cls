/**
 * Tests AR_ReasonSelectionTriggerHandler : contrôle XOR structurel en beforeInsert (le trou de la
 * session 5 corrigé en session 6 — ne pas compter sur la seule discipline du service appelant), et
 * immutabilité d'une sélection de motif une fois son parent décidé.
 */
@IsTest
private class AR_ReasonSelectionTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Client Reason Selection',
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        insert acc;
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin Reason Selection', cxsrec__Account__c = acc.Id, cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open', cxsrec__Contract_type__c = 'CDI'
        );
        insert position;
        insert new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Contract_Type__c = 'CDI',
            AR_Status__c = 'Brouillon',
            AR_Proposed_TJM__c = 500
        );
        insert new AR_Reason__c(
            Name = 'Motif Trigger',
            AR_Applies_To_Derogation__c = true,
            AR_Applies_To_Version__c = true,
            AR_Active__c = true
        );
    }

    @IsTest
    static void testBeforeInsert_neitherParentSet_throws() {
        System.runAs(AR_TestPersona.francais()) {
            Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;

            Boolean threw = false;
            try {
                insert new AR_Reason_Selection__c(AR_Reason__c = reasonId);
            } catch (DmlException e) {
                threw = true;
                System.assert(e.getMessage().contains('exactement un parent'));
            }
            System.assert(threw, 'Aucun des deux lookups parent renseignés doit être rejeté');
        }
    }

    @IsTest
    static void testBeforeInsert_bothParentsSet_throws() {
        System.runAs(AR_TestPersona.francais()) {
            Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;
            AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];

            AR_Derogation__c derogation = new AR_Derogation__c(
                AR_Price_Matrix__c = matrix.Id,
                AR_Decision__c = 'En attente',
                AR_Requested_At__c = System.now()
            );
            insert derogation;

            Boolean threw = false;
            try {
                insert new AR_Reason_Selection__c(
                    AR_Reason__c = reasonId,
                    AR_Price_Matrix__c = matrix.Id,
                    AR_Derogation__c = derogation.Id
                );
            } catch (DmlException e) {
                threw = true;
                System.assert(e.getMessage().contains('exactement un parent'));
            }
            System.assert(threw, 'Les deux lookups parent renseignés en même temps doivent être rejetés');
        }
    }

    @IsTest
    static void testBeforeInsert_exactlyOneParent_succeeds() {
        Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];

        Test.startTest();
        insert new AR_Reason_Selection__c(AR_Reason__c = reasonId, AR_Price_Matrix__c = matrix.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = :matrix.Id]
        );
    }

    @IsTest
    static void testLock_matrixDecided_blocksUpdateAndDelete() {
        Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_Reason_Selection__c selection = new AR_Reason_Selection__c(
            AR_Reason__c = reasonId,
            AR_Price_Matrix__c = matrix.Id
        );
        insert selection;

        // Simule la décision sans passer par le service complet (le trigger de verrouillage lit
        // directement AR_Status__c, indépendamment du chemin qui l'a amené là).
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = 'Validée');
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Test.startTest();
        Boolean updateThrew = false;
        try {
            update new AR_Reason_Selection__c(Id = selection.Id, AR_Reason__c = reasonId);
        } catch (DmlException e) {
            updateThrew = true;
        }
        Boolean deleteThrew = false;
        try {
            delete selection;
        } catch (DmlException e) {
            deleteThrew = true;
        }
        Test.stopTest();

        System.assert(updateThrew, 'Une sélection liée à une matrice décidée ne peut plus être modifiée');
        System.assert(deleteThrew, 'Une sélection liée à une matrice décidée ne peut plus être supprimée');
    }

    @IsTest
    static void testNoLock_matrixStillDraft_allowsUpdate() {
        Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_Reason_Selection__c selection = new AR_Reason_Selection__c(
            AR_Reason__c = reasonId,
            AR_Price_Matrix__c = matrix.Id
        );
        insert selection;

        Test.startTest();
        delete selection;
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE Id = :selection.Id]
        );
    }

    @IsTest
    static void testLock_derogationDecided_blocksUpdate() {
        Id reasonId = [SELECT Id FROM AR_Reason__c LIMIT 1].Id;
        AR_Price_Matrix__c matrix = [SELECT Id FROM AR_Price_Matrix__c LIMIT 1];
        AR_Derogation__c derogation = new AR_Derogation__c(
            AR_Price_Matrix__c = matrix.Id,
            AR_Decision__c = 'En attente',
            AR_Requested_At__c = System.now()
        );
        insert derogation;
        AR_Reason_Selection__c selection = new AR_Reason_Selection__c(
            AR_Reason__c = reasonId,
            AR_Derogation__c = derogation.Id
        );
        insert selection;

        AR_TriggerBypass.serviceContext = true;
        try {
            derogation.AR_Decision__c = 'Acceptée';
            // AccessLevel.SYSTEM_MODE : même contournement FLS documenté dans
            // AR_DerogationService.decide (faux-négatif FLS observé en contexte de test sur ce
            // champ Master-Detail, cf. docs/05-derogation-emails.md §5).
            Database.update(derogation, AccessLevel.SYSTEM_MODE);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }

        Test.startTest();
        Boolean threw = false;
        try {
            update new AR_Reason_Selection__c(Id = selection.Id, AR_Reason__c = reasonId);
        } catch (DmlException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Une sélection liée à une dérogation déjà traitée ne peut plus être modifiée');
    }
}