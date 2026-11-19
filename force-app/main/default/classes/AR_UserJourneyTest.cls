/**
 * Session 41 (docs/41-parcours-utilisateur-reel.md) : cinq parcours de bout en bout, chacun sous
 * System.runAs avec un persona AR_TestPersona (jamais l'utilisateur administrateur qui exécute la
 * suite) — le cœur de l'outil n'avait jamais été exercé en utilisateur réel avant cette session (cf.
 * prompt de session, motif déjà constaté en session 40 : System.runAs n'évalue ni CRUD/FLS ni
 * partage pour un administrateur système, qui les contourne tous).
 *
 * Le demandeur et le décideur sont toujours deux utilisateurs différents quand le parcours l'exige
 * (dérogation) : un test où la même persona fait tout ne prouve rien sur le partage.
 *
 * Ce que ces parcours NE prouvent PAS (cf. prompt de session, doctrine déjà établie session 37) :
 * System.runAs n'évalue ni l'accès aux classes Apex ni l'accès aux pages Visualforce — seul un
 * navigateur avec un compte réel le peut. Ces cinq parcours ne remplacent donc pas le contrôle
 * navigateur.
 */
@IsTest
private class AR_UserJourneyTest {

    @TestSetup
    static void setup() {
        // Session 237 : entité de test créée ici (admin) — sinon AR_TestPersona l'insère depuis le runAs du BM, qui n'en a pas le droit.
        insert new AR_PTF_Entity_Referential__c(Name = 'Abylsen GAMMA', AR_Active__c = true);
        // Même jeu de valeurs que AR_PricingMatrixServiceTest (@TestSetup) : singleton nécessaire à
        // chaque classe de test, un objet custom n'est pas pré-peuplé comme le serait un __mdt déployé.
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Working_Days_Per_Year__c = 218,
            AR_Markup_Percent__c = 18,
            AR_Markup_Max__c = 60,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Draft_Purge_Enabled__c = false,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Warning_Days__c = 5,
            AR_Draft_Purge_Max_Per_Run__c = 200
        );
        insert new AR_Reason__c(
            Name = 'Motif Parcours Session 41',
            AR_Applies_To_Derogation__c = true,
            AR_Applies_To_Version__c = true,
            AR_Active__c = true
        );
    }

    // ------------------------------------------------------------------
    // Fabrique de données métier (Compte/Besoin), distincte de AR_TestPersona (utilisateurs) —
    // chaque parcours crée les siens, jamais partagés entre méthodes de test.
    // ------------------------------------------------------------------

    // Compteur d'unicité (session 41) : une règle de doublon Compte existante dans l'org bloque
    // l'insertion de deux comptes de test au nom trop proche (ex. « Client Parcours Duplication
    // Source » / « Client Parcours Duplication Cible », constaté en réel sur ce fichier) — un simple
    // libellé ne suffit pas à garantir l'unicité vue par la règle de correspondance floue.
    private static Integer positionCounter = 0;

    private static cxsrec__cxsPosition__c newPosition(String label, String contractType) {
        positionCounter++;
        Account acc = new Account(
            Name = 'Client ' + label + ' ' + positionCounter + Datetime.now().getTime(),
            AB_Account_industry__c = 'IT / Telecoms',
            TP_Business_Line__c = 'IT',
            ShippingStreet = '1 rue de Test',
            ShippingCity = 'Paris',
            ShippingPostalCode = '75001'
        );
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        Database.SaveResult sr = Database.insert(acc, dmlOptions);
        System.assert(sr.isSuccess(), sr.isSuccess() ? '' : sr.getErrors()[0].getMessage());
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(
            Name = 'Besoin ' + label,
            cxsrec__Account__c = acc.Id,
            cxsrec__Country__c = 'France',
            cxsrec__Status__c = 'Open',
            cxsrec__Contract_type__c = contractType
        );
        insert position;
        return position;
    }

    /** Le BM doit être PROPRIÉTAIRE du compte/besoin pour les voir (Private OWD) — pas l'objet de
     * cette session (le partage Compte/Contact est une contrainte de plateforme documentée, cf.
     * CLAUDE.md), donc contourné ainsi plutôt que d'exiger une règle de partage supplémentaire. */
    private static void assignOwnership(cxsrec__cxsPosition__c position, Id ownerId) {
        AR_TestPersona.makeOwner(position.cxsrec__Account__c, ownerId);
        AR_TestPersona.makePositionOwner(position.Id, ownerId);
    }

    // CDI simple : coût total ≈ 417 (salaire 45000 × 1.01 × 2 / 218), floor ≈ 521, ideal ≈ 596.
    private static AR_PricingMatrixService.MatrixInput cdiInput(Id positionId, Decimal annualSalary, Decimal proposedTjm) {
        AR_PricingMatrixService.MatrixInput input = new AR_PricingMatrixService.MatrixInput();
        input.positionId = positionId;
        input.currencyCode = 'EUR';
        input.contractType = 'CDI';
        input.entity = String.valueOf(AR_TestPersona.entityRefId('Abylsen GAMMA'));
        input.annualSalary = annualSalary;
        input.feeIk = 0;
        input.feeMeals = 0;
        input.feeLodging = 0;
        input.feeOmOther = 0;
        input.gratuityDays = 0;
        input.feeComputer = 0;
        input.feeTraining = 0;
        input.feeEpi = 0;
        input.feeOfiiTax = 0;
        input.feeOther = 0;
        input.rfaPercent = 0;
        input.proposedTjm = proposedTjm;
        input.seniorityLevel = 'Senior Consultant';
        input.clientSite = 'Paris';
        input.clientGrid = true;
        input.startDate = System.today();
        input.endDate = System.today().addMonths(6);
        return input;
    }

    // ------------------------------------------------------------------
    // Parcours 1 — Un BM enregistre une matrice : brouillon, recharge, modification, validation.
    // ------------------------------------------------------------------

    @IsTest
    static void testJourney1_bmRegistersMatrix_draftReloadModifyValidate() {
        User bm = AR_TestPersona.bm();
        cxsrec__cxsPosition__c position = newPosition('Parcours BM', 'CDI');
        assignOwnership(position, bm.Id);

        Id matrixId;
        System.runAs(bm) {
            AR_PricingMatrixService.MatrixSaveResult draft = AR_PricingMatrixService.saveDraftInput(
                cdiInput(position.Id, 45000, 650)
            );
            System.assertEquals('Brouillon', draft.status, 'Une nouvelle matrice doit se sauvegarder en Brouillon');
            matrixId = draft.matrixId;

            AR_PricingMatrixService.MatrixInput reloaded = AR_PricingMatrixService.getMatrixInput(matrixId);
            System.assertEquals(650, reloaded.proposedTjm, 'La recharge doit restituer le TJM saisi');
            reloaded.proposedTjm = 660;

            AR_PricingMatrixService.MatrixSaveResult resaved = AR_PricingMatrixService.saveDraftInput(reloaded);
            System.assertEquals('Brouillon', resaved.status, 'La resauvegarde d\'un Brouillon existant doit rester en Brouillon (session 28b)');

            AR_PricingResult recalculated = AR_PricingMatrixService.recalculate(matrixId);
            System.assertNotEquals(null, recalculated.mc2PercentHuman, 'recalculate() doit rester exerçable par le BM sur son Brouillon');

            AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(reloaded);
            System.assertEquals('Validée', validated.status, 'MC2 au-dessus du plancher : la validation doit passer');
        }

        AR_Price_Matrix__c matrix = [SELECT AR_Status__c, AR_Version_Number__c, AR_Proposed_TJM__c FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        System.assertEquals('Validée', matrix.AR_Status__c);
        System.assertEquals(660, matrix.AR_Proposed_TJM__c);
        System.assertEquals(1, [SELECT COUNT() FROM AR_Matrix_Version__c WHERE AR_Price_Matrix__c = :matrixId], 'La validation doit créer un snapshot');
    }

    // ------------------------------------------------------------------
    // Parcours 2 — Un BM demande une dérogation : motif standardisé + valideur sélectionné, un AUTRE
    // utilisateur que le demandeur.
    // ------------------------------------------------------------------

    @IsTest
    static void testJourney2_bmRequestsDerogation_belowFloorWithReasonAndValidator() {
        // Une demande de dérogation exige DA ou DD renseigné sur le profil du demandeur
        // (AR_PricingMatrixService, « Les champs DA et DD… ») : un BM réel a toujours son DA.
        User bm = AR_TestPersona.bmWithDa();
        User valideur = AR_TestPersona.valideur();
        // Session 291c : le serveur n'accepte qu'un valideur proposé (hiérarchie du propriétaire, valideurs de son
        // entité, valideurs de test, session 291) — le valideur du parcours devient le DA du demandeur.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = bm.Id, TP_DA__c = valideur.Id);
        }
        cxsrec__cxsPosition__c position = newPosition('Parcours Dérogation', 'CDI');
        assignOwnership(position, bm.Id);

        Id matrixId;
        System.runAs(bm) {
            List<AR_ReasonService.ReasonOption> reasons = AR_ReasonService.getReasonOptions('derogation');
            System.assert(!reasons.isEmpty(), 'Un motif de dérogation actif doit être sélectionnable');

            AR_PricingMatrixService.DerogationRequest req = new AR_PricingMatrixService.DerogationRequest();
            req.matrixInput = cdiInput(position.Id, 45000, 480); // < floor ≈ 521 → below_floor
            req.reason = 'Contexte concurrentiel tendu';
            req.selectedValidatorId = valideur.Id;
            req.derogationReasonIds = new List<Id>{ reasons[0].reasonId };

            AR_PricingMatrixService.MatrixSaveResult result = AR_PricingMatrixService.requestDerogationInput(req);
            matrixId = result.matrixId;
            System.assertEquals('En dérogation', result.status);
            System.assertEquals('below_floor', result.calculation.corridorSegment);
        }

        AR_Price_Matrix__c matrix = [SELECT AR_Status__c, AR_Selected_Validator__c FROM AR_Price_Matrix__c WHERE Id = :matrixId];
        System.assertEquals('En dérogation', matrix.AR_Status__c);
        System.assertEquals(valideur.Id, matrix.AR_Selected_Validator__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Derogation__c WHERE AR_Price_Matrix__c = :matrixId AND AR_Decision__c = 'En attente']
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AR_Reason_Selection__c WHERE AR_Price_Matrix__c = null AND AR_Derogation__c != null],
            'Le motif standardisé doit être enregistré, fin de la saisie libre (CLAUDE.md, décision 10/08/2026)'
        );
    }

    // ------------------------------------------------------------------
    // Parcours 3 — Un valideur décide le dossier d'un autre : déjà couvert par la session 40
    // (AR_DerogationServiceTest.testRunAs_validatorPermissionSetHolder_canDecideAndSeesQueue et les
    // deux tests runAs voisins), refactorés dans ce même changement pour utiliser AR_TestPersona au
    // lieu de leur fabrique locale — non dupliqué ici, cf. docs/41-parcours-utilisateur-reel.md.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Parcours 4 — Un BM génère une PTF sur une matrice validée : snapshot AR_PTF_Document__c,
    // ContentVersion, statut Généré. Le contrôle "deux exécutions Apex anonymes séparées" (protocole
    // CLAUDE.md) s'applique à la vérification RÉELLE (getContentAsPDF n'est pas exécuté en contexte
    // de test, cf. AR_PTFGenerationService.renderPdf) : fait séparément en anonyme sur la sandbox,
    // documenté dans docs/41-parcours-utilisateur-reel.md, pas reproductible dans ce test unitaire.
    // ------------------------------------------------------------------

    @IsTest
    static void testJourney4_bmGeneratesPtf_onValidatedMatrix() {
        User bm = AR_TestPersona.bmWithDa();
        cxsrec__cxsPosition__c position = newPosition('Parcours PTF', 'CDI');
        assignOwnership(position, bm.Id);

        // Session 184c3 : seul gabarit par défaut depuis la 184c = Abylsen, qui exige le RIB de l'entité.
        AR_PricingMatrixService.MatrixInput matrixInput = cdiInput(position.Id, 45000, 650);
        matrixInput.entity = String.valueOf(AR_TestPersona.entityRefIdWithBank('Abylsen GAMMA'));

        Id matrixId;
        Id ptfDocumentId;
        System.runAs(bm) {
            AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(
                matrixInput
            );
            matrixId = validated.matrixId;

            AR_PTFDataService.GenerationInput genInput = new AR_PTFDataService.GenerationInput();
            genInput.matrixId = matrixId;
            genInput.templateCode = 'ABYLSEN_AT_V11';
            // Session 47 : le valideur est un champ obligatoire du formulaire — cette matrice, comme
            // l'écrasante majorité des matrices en usage réel, est validée automatiquement (sans
            // dérogation) et ne porte donc ni valideur effectif ni valideur sélectionné.
            genInput.valideurNom = 'Valideur Test';

            AR_PTFGenerationService.PTFGenerationResult genResult = AR_PTFGenerationService.generatePTFInput(genInput);
            System.assertEquals('En cours', genResult.status);
            ptfDocumentId = genResult.ptfDocumentId;

            AR_PTFGenerationService.PTFGenerationResult renderResult = AR_PTFGenerationService.renderAndStorePTF(ptfDocumentId);
            System.assertEquals('Généré', renderResult.status, 'Échec de rendu : ' + renderResult.errorMessage);
            System.assertNotEquals(null, renderResult.contentDocumentId);
        }

        AR_PTF_Document__c doc = [
            SELECT AR_Generation_Status__c, AR_Snapshot__c, AR_Content_Document_Id__c
            FROM AR_PTF_Document__c
            WHERE Id = :ptfDocumentId
        ];
        System.assertEquals('Généré', doc.AR_Generation_Status__c);
        System.assert(String.isNotBlank(doc.AR_Snapshot__c), 'Le snapshot AR_PTFData fait foi, pas seulement le PDF (CLAUDE.md)');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :doc.AR_Content_Document_Id__c]
        );
    }

    // ------------------------------------------------------------------
    // Parcours 5 — Un BM duplique une matrice décidée : vers un nouveau besoin ET vers le même besoin
    // (nouvelle itération de négociation), motif obligatoire, chaîne visible en entier.
    // ------------------------------------------------------------------

    @IsTest
    static void testJourney5_bmDuplicatesDecidedMatrix_sameAndNewNeed() {
        User bm = AR_TestPersona.bm();
        cxsrec__cxsPosition__c sourcePosition = newPosition('Parcours Duplication Source', 'CDI');
        cxsrec__cxsPosition__c targetPosition = newPosition('Parcours Duplication Cible', 'CDI');
        assignOwnership(sourcePosition, bm.Id);
        assignOwnership(targetPosition, bm.Id);

        Id sourceMatrixId;
        Id sameNeedMatrixId;
        Id newNeedMatrixId;
        System.runAs(bm) {
            AR_PricingMatrixService.MatrixSaveResult validated = AR_PricingMatrixService.validateInput(
                cdiInput(sourcePosition.Id, 45000, 650)
            );
            sourceMatrixId = validated.matrixId;

            List<AR_ReasonService.ReasonOption> versionReasons = AR_ReasonService.getReasonOptions('version');
            System.assert(!versionReasons.isEmpty(), 'Un motif de version actif doit être sélectionnable');
            List<Id> reasonIds = new List<Id>{ versionReasons[0].reasonId };

            AR_MatrixChainService.DuplicateResult sameNeedDup = AR_MatrixChainService.duplicateMatrix(
                sourceMatrixId, null, reasonIds, 'Renégociation, même besoin'
            );
            sameNeedMatrixId = sameNeedDup.matrixId;

            AR_MatrixChainService.DuplicateResult newNeedDup = AR_MatrixChainService.duplicateMatrix(
                sourceMatrixId, targetPosition.Id, reasonIds, 'Renégociation, nouveau besoin'
            );
            newNeedMatrixId = newNeedDup.matrixId;

            // Filiation basée sur le STATUT de la source, pas le besoin cible (cf. AR_MatrixChainService,
            // en-tête de classe) : les deux duplications rejoignent la MÊME chaîne, rattachées à la
            // source — 3 maillons attendus, pas 2.
            AR_MatrixChainService.ChainResult chain = AR_MatrixChainService.getChain(sourceMatrixId);
            System.assertEquals(false, chain.partiallyVisible, 'Le BM propriétaire de toute la chaîne doit la voir en entier');
            System.assertEquals(3, chain.nodes.size(), 'Source + duplication même besoin + duplication nouveau besoin');
        }

        AR_Price_Matrix__c sameNeedMatrix = [
            SELECT AR_Status__c, AR_Root_Matrix__c, AR_Previous_Version__c, AR_Position__c
            FROM AR_Price_Matrix__c
            WHERE Id = :sameNeedMatrixId
        ];
        System.assertEquals('Brouillon', sameNeedMatrix.AR_Status__c);
        System.assertEquals(sourceMatrixId, sameNeedMatrix.AR_Root_Matrix__c);
        System.assertEquals(sourceMatrixId, sameNeedMatrix.AR_Previous_Version__c);
        System.assertEquals(sourcePosition.Id, sameNeedMatrix.AR_Position__c);

        AR_Price_Matrix__c newNeedMatrix = [
            SELECT AR_Status__c, AR_Root_Matrix__c, AR_Position__c
            FROM AR_Price_Matrix__c
            WHERE Id = :newNeedMatrixId
        ];
        System.assertEquals('Brouillon', newNeedMatrix.AR_Status__c);
        System.assertEquals(sourceMatrixId, newNeedMatrix.AR_Root_Matrix__c);
        System.assertEquals(targetPosition.Id, newNeedMatrix.AR_Position__c);
    }
}