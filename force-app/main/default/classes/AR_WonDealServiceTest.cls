@IsTest
private class AR_WonDealServiceTest {
    private static cxsrec__cxsPosition__c position;

    private static AR_Price_Matrix__c newMatrix(Id positionId, Id ownerId, Integer version, Decimal p1, Decimal p2, Decimal p3, String status) {
        AR_Price_Matrix__c m = new AR_Price_Matrix__c(
            AR_Position__c = positionId, OwnerId = ownerId, AR_Status__c = status, AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = p1, AR_Nego_Price_2__c = p2, AR_Nego_Price_3__c = p3, AR_Account_Name__c = 'ACME',
            AR_Validated_At__c = Datetime.now().addDays(-version), AR_Negotiation_Version__c = version, AR_Version_Number__c = 1
        );
        insert m;
        return m;
    }

    private static cxsrec__cxsPosition__c newPosition(String status, Id ownerId) {
        cxsrec__cxsPosition__c p = new cxsrec__cxsPosition__c(Name = 'Besoin service', cxsrec__Status__c = status);
        insert p;
        if (ownerId != null) {
            AR_TestPersona.makePositionOwner(p.Id, ownerId);
        }
        return p;
    }

    private static void assertRefused(Id matrixId, String level, Decimal tjm, String expectedMessage) {
        try {
            AR_WonDealService.confirmWonDeal(matrixId, level, tjm, null);
            System.assert(false, 'Un refus était attendu');
        } catch (AuraHandledException e) {
            System.assertEquals(expectedMessage, e.getMessage());
        }
    }

    @IsTest
    static void testOwnerConfirmsP2_thenDaSwitchesVersion_firstIsUnchecked() {
        User owner = AR_TestPersona.bmWithDa();
        User da = [SELECT Id FROM User WHERE Id = :[SELECT TP_DA__c FROM User WHERE Id = :owner.Id].TP_DA__c];
        cxsrec__cxsPosition__c p = newPosition('Gagné', owner.Id);
        AR_Price_Matrix__c v1 = newMatrix(p.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        AR_Price_Matrix__c v2 = newMatrix(p.Id, owner.Id, 2, 480, 440, 400, 'Validée par dérogation');

        System.runAs(owner) {
            AR_WonDealService.confirmWonDeal(v1.Id, 'P2', null, Date.newInstance(2026, 11, 10));
        }
        AR_Price_Matrix__c r1 = [SELECT AR_Won__c, AR_Signed_TJM__c, AR_Signed_Price_Level__c, AR_Won_Date__c, AR_Won_Confirmed_By__c, AR_Won_Confirmed_At__c FROM AR_Price_Matrix__c WHERE Id = :v1.Id];
        System.assertEquals(true, r1.AR_Won__c);
        System.assertEquals(450, r1.AR_Signed_TJM__c);
        System.assertEquals('P2', r1.AR_Signed_Price_Level__c);
        System.assertEquals(Date.newInstance(2026, 11, 10), r1.AR_Won_Date__c);
        System.assertEquals(owner.Id, r1.AR_Won_Confirmed_By__c);
        System.assertNotEquals(null, r1.AR_Won_Confirmed_At__c);

        System.runAs(da) {
            AR_WonDealService.confirmWonDeal(v2.Id, null, 480, null);
        }
        System.assertEquals(false, [SELECT AR_Won__c FROM AR_Price_Matrix__c WHERE Id = :v1.Id].AR_Won__c);
        System.assertEquals(null, [SELECT AR_Signed_Price_Level__c FROM AR_Price_Matrix__c WHERE Id = :v1.Id].AR_Signed_Price_Level__c);
        AR_Price_Matrix__c r2 = [SELECT AR_Won__c, AR_Signed_Price_Level__c, AR_Won_Confirmed_By__c, AR_Won_Date__c FROM AR_Price_Matrix__c WHERE Id = :v2.Id];
        System.assertEquals(true, r2.AR_Won__c);
        System.assertEquals('P1', r2.AR_Signed_Price_Level__c);
        System.assertEquals(da.Id, r2.AR_Won_Confirmed_By__c);
        System.assertEquals(Date.today(), r2.AR_Won_Date__c);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Position__c = :p.Id AND AR_Won__c = true]);
    }

    @IsTest
    static void testFreeAmount_computesLevel() {
        User owner = AR_TestPersona.bm();
        cxsrec__cxsPosition__c p = newPosition('Gagné', owner.Id);
        AR_Price_Matrix__c v1 = newMatrix(p.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        System.runAs(owner) {
            AR_WonDealService.confirmWonDeal(v1.Id, '', 420, null);
        }
        AR_Price_Matrix__c r = [SELECT AR_Signed_TJM__c, AR_Signed_Price_Level__c FROM AR_Price_Matrix__c WHERE Id = :v1.Id];
        System.assertEquals(420, r.AR_Signed_TJM__c);
        System.assertEquals('P3', r.AR_Signed_Price_Level__c);
        System.runAs(owner) {
            AR_WonDealService.confirmWonDeal(v1.Id, null, 300, null);
        }
        System.assertEquals('Hors grille', [SELECT AR_Signed_Price_Level__c FROM AR_Price_Matrix__c WHERE Id = :v1.Id].AR_Signed_Price_Level__c);
    }

    @IsTest
    static void testRefusals() {
        User owner = AR_TestPersona.bm();
        User other = AR_TestPersona.bm();
        cxsrec__cxsPosition__c won = newPosition('Gagné', owner.Id);
        cxsrec__cxsPosition__c open = newPosition('Open', owner.Id);
        AR_Price_Matrix__c ok = newMatrix(won.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        AR_Price_Matrix__c draft = newMatrix(won.Id, owner.Id, 2, 500, 450, 400, 'Brouillon');
        AR_Price_Matrix__c notWon = newMatrix(open.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        AR_Price_Matrix__c noP3 = newMatrix(won.Id, owner.Id, 3, 500, 450, null, 'Validée');
        System.runAs(owner) {
            assertRefused(draft.Id, 'P1', null, Label.AR_Won_Err_NotValidated);
            assertRefused(notWon.Id, 'P1', null, Label.AR_Won_Err_NotWon);
            assertRefused(ok.Id, 'P9', null, Label.AR_Won_Err_BadLevel);
            assertRefused(noP3.Id, 'P3', null, Label.AR_Won_Err_BadLevel);
            assertRefused(ok.Id, null, null, Label.AR_Won_Err_NoAmount);
        }
        System.runAs(other) {
            assertRefused(ok.Id, 'P1', null, Label.AR_Won_Err_NotAllowed);
        }
        System.assertEquals(0, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE AR_Won__c = true]);
    }

    @IsTest
    static void testPendingAndDetail_andJsonFacade() {
        User owner = AR_TestPersona.bm();
        cxsrec__cxsPosition__c p = newPosition('Gagné', owner.Id);
        cxsrec__cxsPosition__c done = newPosition('Gagné', owner.Id);
        AR_Price_Matrix__c v1 = newMatrix(p.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        AR_Price_Matrix__c v2 = newMatrix(p.Id, owner.Id, 2, 480, 440, 400, 'Validée');
        AR_Price_Matrix__c confirmed = newMatrix(done.Id, owner.Id, 1, 500, null, null, 'Validée');
        System.runAs(owner) {
            List<AR_WonDealService.WonDealDTO> pending = AR_WonDealService.getPendingWonDeals();
            System.assertEquals(2, pending.size());
            AR_WonDealService.confirmWonDealJson(JSON.serialize(new Map<String, Object>{ 'matrixId' => confirmed.Id, 'priceLevel' => 'P1' }));
            pending = AR_WonDealService.getPendingWonDeals();
            System.assertEquals(1, pending.size());
            System.assertEquals(p.Id, pending[0].positionId);
            System.assertEquals(2, pending[0].versions.size());
            System.assertEquals(true, pending[0].versions[0].canConfirm);
            AR_WonDealService.WonDealDTO detail = AR_WonDealService.getWonDeal(done.Id);
            System.assertEquals(true, detail.confirmed, 'Le détail inclut la version déjà confirmée');
            System.assertEquals('P1', detail.versions[0].signedPriceLevel);
            try {
                AR_WonDealService.confirmWonDealJson('');
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assertEquals(Label.AR_Won_Err_Payload, e.getMessage());
            }
        }
    }

    @IsTest
    static void testPendingWhenPositionBelongsToSomeoneElse_daSeesItOtherBmDoesNot() {
        User owner = AR_TestPersona.bmWithDa();
        User da = [SELECT Id FROM User WHERE Id = :[SELECT TP_DA__c FROM User WHERE Id = :owner.Id].TP_DA__c];
        User positionOwner = AR_TestPersona.bm();
        User otherBm = AR_TestPersona.bm();
        // Besoin « Gagné » appartenant à un tiers : ni le DA ni l'autre BM n'y ont accès via le partage du besoin.
        cxsrec__cxsPosition__c p = newPosition('Gagné', positionOwner.Id);
        newMatrix(p.Id, owner.Id, 1, 500, 450, 400, 'Validée');
        System.runAs(da) {
            List<AR_WonDealService.WonDealDTO> pending = AR_WonDealService.getPendingWonDeals();
            System.assertEquals(1, pending.size(), 'Le DA voit l\'affaire à confirmer de son BM');
            System.assertEquals(p.Id, pending[0].positionId);
            System.assertEquals(true, pending[0].versions[0].canConfirm);
        }
        System.runAs(otherBm) {
            System.assertEquals(0, AR_WonDealService.getPendingWonDeals().size(), 'Un autre BM ne la voit pas');
        }
    }
}