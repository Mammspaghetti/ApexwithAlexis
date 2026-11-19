@IsTest
private class AR_WonDealDetectorTest {
    @TestSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default', AR_Validated_Matrix_Sync_Enabled__c = true,
            AR_Draft_Purge_Days__c = 30, AR_Draft_Purge_Max_Per_Run__c = 100, AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20, AR_Target_Percent_Default__c = 25, AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60, AR_Markup_Percent__c = 18, AR_Max_Derogation_Penalty__c = 70, AR_Working_Days_Per_Year__c = 218
        );
    }

    private static cxsrec__cxsPosition__c newPosition(String name) {
        cxsrec__cxsPosition__c p = new cxsrec__cxsPosition__c(Name = name, cxsrec__Status__c = 'Open');
        insert p;
        return p;
    }

    private static AR_Price_Matrix__c newMatrix(Id positionId, Id ownerId, String status, Boolean won) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId, OwnerId = ownerId, AR_Status__c = status, AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = 500, AR_Account_Name__c = 'ACME', AR_Validated_At__c = Datetime.now().addDays(-1),
            AR_Negotiation_Version__c = 1, AR_Version_Number__c = 1, AR_Won__c = won
        );
        insert m;
        return m;
    }

    private static void setStatus(Id positionId, String status) {
        update new cxsrec__cxsPosition__c(Id = positionId, cxsrec__Status__c = status);
    }

    @IsTest
    static void testWon_stampsValidatedOnly_andNotifiesOwnerAndDa() {
        User owner = AR_TestPersona.bmWithDa();
        Id daId = [SELECT TP_DA__c FROM User WHERE Id = :owner.Id].TP_DA__c;
        cxsrec__cxsPosition__c p = newPosition('Besoin gagné');
        AR_Price_Matrix__c validated = newMatrix(p.Id, owner.Id, 'Validée', false);
        AR_Price_Matrix__c draft = newMatrix(p.Id, owner.Id, 'Brouillon', false);

        Test.startTest();
        setStatus(p.Id, 'Gagné');
        Test.stopTest();

        System.assertNotEquals(null, [SELECT AR_Position_Won_At__c FROM AR_Price_Matrix__c WHERE Id = :validated.Id].AR_Position_Won_At__c);
        System.assertEquals(null, [SELECT AR_Position_Won_At__c FROM AR_Price_Matrix__c WHERE Id = :draft.Id].AR_Position_Won_At__c);
        System.assertEquals(1, AR_NotificationService.wonDealRecipientsSent.size());
        System.assertEquals(new Set<Id>{ owner.Id, daId }, AR_NotificationService.wonDealRecipientsSent[0]);
    }

    @IsTest
    static void testWon_ownerWithoutDa_singleRecipient() {
        User owner = AR_TestPersona.bm();
        cxsrec__cxsPosition__c p = newPosition('Besoin sans DA');
        newMatrix(p.Id, owner.Id, 'Validée', false);

        Test.startTest();
        setStatus(p.Id, 'Gagné');
        Test.stopTest();

        System.assertEquals(1, AR_NotificationService.wonDealRecipientsSent.size());
        System.assertEquals(new Set<Id>{ owner.Id }, AR_NotificationService.wonDealRecipientsSent[0]);
    }

    @IsTest
    static void testWon_alreadyConfirmed_noSecondNotification_onReturnToWon() {
        User owner = AR_TestPersona.bm();
        cxsrec__cxsPosition__c p = newPosition('Besoin déjà confirmé');
        newMatrix(p.Id, owner.Id, 'Validée', true);

        Test.startTest();
        setStatus(p.Id, 'Gagné');
        setStatus(p.Id, 'Open');
        setStatus(p.Id, 'Gagné');
        Test.stopTest();

        System.assertEquals(0, AR_NotificationService.wonDealRecipientsSent.size());
    }

    @IsTest
    static void testWon_secondPassageWithoutConfirmation_notifiesAgain_andNoValidated_isNoOp() {
        User owner = AR_TestPersona.bm();
        cxsrec__cxsPosition__c withoutValidated = newPosition('Sans validée');
        newMatrix(withoutValidated.Id, owner.Id, 'Brouillon', false);
        cxsrec__cxsPosition__c p = newPosition('Besoin à confirmer');
        newMatrix(p.Id, owner.Id, 'Validée', false);

        Test.startTest();
        setStatus(withoutValidated.Id, 'Gagné');
        System.assertEquals(0, AR_NotificationService.wonDealRecipientsSent.size(), 'Aucune matrice validée : aucun effet');
        setStatus(p.Id, 'Gagné');
        Test.stopTest();

        System.assertEquals(1, AR_NotificationService.wonDealRecipientsSent.size());
    }
}