/**
 * Tests de AR_ValidatedMatrixSyncService (session 174) : liste « Matrice validée » alimentée par
 * AR_PriceMatrixTrigger. Chaque test fabrique ses besoins ; jamais de filtre sur Name (les MAT- sont des
 * AutoNumber continus de l'org) — on cherche les entrées par AR_Price_Matrix__c.
 */
@isTest
private class AR_ValidatedMatrixSyncServiceTest {
    @testSetup
    static void setup() {
        insert new AR_General_Setting__c(
            Name = 'Default',
            AR_Validated_Matrix_Sync_Enabled__c = true,
            // Session 175 : les fixtures sont datées du 13/10/2026 (fixes, pour des libellés stables) ; sans cette
            // durée de vie très large elles expireraient avec le temps et ces tests casseraient en 2027.
            AR_Validated_Matrix_Lifetime_Days__c = 36500,
            AR_Draft_Purge_Days__c = 30,
            AR_Draft_Purge_Max_Per_Run__c = 100,
            AR_Draft_Purge_Warning_Days__c = 14,
            AR_Floor_Percent_Default__c = 20,
            AR_Target_Percent_Default__c = 25,
            AR_Ideal_Percent_Default__c = 30,
            AR_Markup_Max__c = 60,
            AR_Markup_Percent__c = 18,
            AR_Max_Derogation_Penalty__c = 70,
            AR_Working_Days_Per_Year__c = 218
        );
    }

    // ---------- Fabriques ----------

    private static void setSync(Boolean enabled) {
        AR_General_Setting__c settings = [SELECT Id FROM AR_General_Setting__c LIMIT 1];
        settings.AR_Validated_Matrix_Sync_Enabled__c = enabled;
        update settings;
    }

    private static cxsrec__cxsPosition__c newPosition(String label, String status) {
        cxsrec__cxsPosition__c position = new cxsrec__cxsPosition__c(Name = 'Besoin ' + label, cxsrec__Status__c = status);
        insert position;
        return position;
    }

    private static cxsrec__cxsPosition__c openPosition(String label) {
        return newPosition(label, 'Open');
    }

    private static AR_Price_Matrix__c newMatrix(
        cxsrec__cxsPosition__c position,
        String status,
        Id rootId,
        Integer version
    ) {
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id,
            AR_Status__c = status,
            AR_Contract_Type__c = 'CDI',
            AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'ACME',
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Root_Matrix__c = rootId,
            AR_Negotiation_Version__c = version,
            AR_Version_Number__c = 1,
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        );
        insert matrix;
        return matrix;
    }

    private static AR_Price_Matrix__c validated(cxsrec__cxsPosition__c position) {
        return newMatrix(position, 'Validée', null, 1);
    }

    private static List<AR_Validated_Matrix__c> entriesForPosition(Id positionId) {
        return [
            SELECT Id, Name, AR_Price_Matrix__c, AR_Position__c, AR_Root_Key__c, AR_Matrix_Key__c
            FROM AR_Validated_Matrix__c
            WHERE AR_Position__c = :positionId
            ORDER BY Name
        ];
    }

    private static AR_Validated_Matrix__c entryOf(Id matrixId) {
        List<AR_Validated_Matrix__c> entries = [
            SELECT Id, Name, AR_Price_Matrix__c, AR_Position__c, AR_Root_Key__c, AR_Matrix_Key__c
            FROM AR_Validated_Matrix__c
            WHERE AR_Price_Matrix__c = :matrixId
        ];
        System.assert(entries.size() <= 1, 'Une entrée par matrice au maximum');
        return entries.isEmpty() ? null : entries[0];
    }

    // Les services posent les statuts sous bypass (la matrice décidée est verrouillée) : même chemin ici.
    private static void setStatus(AR_Price_Matrix__c matrix, String status) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update new AR_Price_Matrix__c(Id = matrix.Id, AR_Status__c = status);
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    private static void updateUnderBypass(AR_Price_Matrix__c changes) {
        AR_TriggerBypass.serviceContext = true;
        try {
            update changes;
        } finally {
            AR_TriggerBypass.serviceContext = false;
        }
    }

    // ---------- Entrée ----------

    @isTest
    static void testValidatedMatrixOfOpenPositionEntersList() {
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c matrix = validated(position);

        AR_Validated_Matrix__c entry = entryOf(matrix.Id);
        System.assertNotEquals(null, entry, 'La matrice validée d\'un besoin Open entre dans la liste');
        System.assertEquals(position.Id, entry.AR_Position__c, 'Besoin copié depuis la matrice');
        System.assertEquals(String.valueOf(matrix.Id), entry.AR_Root_Key__c, 'Sans racine : clé de chaîne = Id de la matrice');
        System.assertEquals(String.valueOf(matrix.Id), entry.AR_Matrix_Key__c, 'Clé unique = Id de la matrice');
        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', entry.Name, 'Libellé au format validé');
    }

    @isTest
    static void testValidatedByDerogationAlsoEnters() {
        cxsrec__cxsPosition__c position = openPosition('A');

        AR_Price_Matrix__c matrix = newMatrix(position, 'Validée par dérogation', null, 1);

        System.assertNotEquals(null, entryOf(matrix.Id), 'Validée par dérogation : entre aussi');
    }

    @isTest
    static void testDraftAndPendingAndRefusedNeverEnter() {
        cxsrec__cxsPosition__c position = openPosition('A');

        newMatrix(position, 'Brouillon', null, 1);
        newMatrix(position, 'En dérogation', null, 1);
        newMatrix(position, 'Refusée', null, 1);

        System.assertEquals(0, entriesForPosition(position.Id).size(), 'Aucun statut non validé n\'entre dans la liste');
    }

    @isTest
    static void testMatrixTurningValidatedOnUpdateEnters() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c draft = newMatrix(position, 'Brouillon', null, 1);
        System.assertEquals(null, entryOf(draft.Id), 'Brouillon : pas d\'entrée');

        setStatus(draft, 'Validée');

        System.assertNotEquals(null, entryOf(draft.Id), 'Passage à Validée : l\'entrée apparaît');
    }

    @isTest
    static void testPositionNotOpenNeverEnters() {
        for (String status : new List<String>{ 'Gagné', 'Perdu', 'Supprimé' }) {
            cxsrec__cxsPosition__c position = newPosition(status, status);
            AR_Price_Matrix__c matrix = validated(position);
            System.assertEquals(null, entryOf(matrix.Id), 'Besoin « ' + status + ' » : la matrice validée n\'entre pas');
        }
    }

    // ---------- Une entrée par chaîne ----------

    // Session 180a : l'entrée de la chaîne est RÉUTILISÉE (même Id) et repointée sur la nouvelle version, jamais
    // supprimée puis recréée — sinon Step.AR_Validated_Matrix__c se vide (SetNull) en plein processus.
    @isTest
    static void testNewVersionReplacesPreviousEntry() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        Id entryV1 = entryOf(v1.Id).Id;

        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2);

        List<AR_Validated_Matrix__c> entries = entriesForPosition(position.Id);
        System.assertEquals(1, entries.size(), 'Une seule entrée par chaîne');
        System.assertEquals(entryV1, entries[0].Id, 'L\'entrée de la V1 est réutilisée, pas recréée');
        System.assertEquals(v2.Id, entries[0].AR_Price_Matrix__c, 'L\'entrée pointe maintenant sur la V2');
        System.assertEquals(String.valueOf(v2.Id), entries[0].AR_Matrix_Key__c, 'Clé unique repointée sur la V2');
        System.assertEquals(String.valueOf(v1.Id), entries[0].AR_Root_Key__c, 'Clé de chaîne = racine');
        System.assert(entries[0].Name.contains(', V2 ('), 'Libellé en V2 : ' + entries[0].Name);
        System.assertEquals(null, entryOf(v1.Id), 'Plus aucune entrée ne désigne la V1');
        System.assertEquals(1, [SELECT COUNT() FROM AR_Price_Matrix__c WHERE Id = :v1.Id], 'La vraie V1 reste');
    }

    // Une version avenant validée reprend l'entrée de la chaîne avec le libellé « V3 Avenant ».
    @isTest
    static void testAvenantVersionReusesEntryWithAvenantLabel() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2);
        Id entryId = entryOf(v2.Id).Id;

        AR_Price_Matrix__c v3 = new AR_Price_Matrix__c(
            AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 520,
            AR_Account_Name__c = 'ACME', AR_Consultant_Name__c = 'Jean DUPONT', AR_Root_Matrix__c = v1.Id,
            AR_Negotiation_Version__c = 3, AR_Version_Number__c = 1, AR_Version_Type__c = 'Avenant',
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 14, 12, 0, 0)
        );
        insert v3;

        List<AR_Validated_Matrix__c> entries = entriesForPosition(position.Id);
        System.assertEquals(1, entries.size(), 'Une seule entrée par chaîne');
        System.assertEquals(entryId, entries[0].Id, 'Même entrée qu\'avant l\'avenant');
        System.assertEquals(v3.Id, entries[0].AR_Price_Matrix__c);
        System.assertEquals('ACME - Jean DUPONT, V3 Avenant (14/10/2026)', entries[0].Name);
    }

    // Le type de version fait partie des champs surveillés : la marquer après coup renomme l'entrée.
    @isTest
    static void testMarkingVersionTypeRenamesEntry() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', entryOf(v1.Id).Name);

        updateUnderBypass(new AR_Price_Matrix__c(Id = v1.Id, AR_Version_Type__c = 'Avenant'));
        System.assertEquals('ACME - Jean DUPONT, V1 Avenant (13/10/2026)', entryOf(v1.Id).Name);

        updateUnderBypass(new AR_Price_Matrix__c(Id = v1.Id, AR_Version_Type__c = null));
        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', entryOf(v1.Id).Name, 'null = Négociation : libellé sans « Avenant »');
    }

    // Pendant une dérogation sur la version suivante, l'entrée reste celle de la version en vigueur.
    @isTest
    static void testPendingDerogationOnNextVersionKeepsEntryOnCurrentVersion() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        Id entryId = entryOf(v1.Id).Id;

        newMatrix(position, 'En dérogation', v1.Id, 2);

        AR_Validated_Matrix__c entry = entryOf(v1.Id);
        System.assertEquals(entryId, entry.Id, 'Entrée inchangée pendant la dérogation');
        System.assert(entry.Name.contains(', V1 ('), 'Libellé toujours V1 : ' + entry.Name);
    }

    // Plus aucune gagnante sur la chaîne (refus de la seule version validée) : l'entrée est bien retirée.
    @isTest
    static void testChainWithoutWinnerStillLosesItsEntry() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        Id entryId = entryOf(v1.Id).Id;

        setStatus(v1, 'Refusée');

        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE Id = :entryId], 'Entrée retirée');
    }

    // Le rang dans la chaîne (AR_Negotiation_Version__c) décide, jamais AR_Version_Number__c (1 partout ici).
    @isTest
    static void testLowerRankValidatedLaterDoesNotReplaceHigherRank() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = newMatrix(position, 'Brouillon', null, 1);
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2);
        System.assertNotEquals(null, entryOf(v2.Id), 'La V2 validée a son entrée');

        setStatus(v1, 'Validée');

        List<AR_Validated_Matrix__c> entries = entriesForPosition(position.Id);
        System.assertEquals(1, entries.size(), 'Une entrée par chaîne');
        System.assertEquals(v2.Id, entries[0].AR_Price_Matrix__c, 'La version de plus haut rang garde l\'entrée');
    }

    @isTest
    static void testTwoChainsHaveTwoEntries() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c first = validated(position);
        AR_Price_Matrix__c second = validated(position);

        System.assertEquals(2, entriesForPosition(position.Id).size(), 'Deux chaînes : deux entrées');
        System.assertNotEquals(null, entryOf(first.Id));
        System.assertNotEquals(null, entryOf(second.Id));
    }

    // ---------- Sortie ----------

    @isTest
    static void testMatrixNoLongerValidatedLeavesList() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = validated(position);
        System.assertNotEquals(null, entryOf(matrix.Id));

        setStatus(matrix, 'En dérogation');
        System.assertEquals(null, entryOf(matrix.Id), 'Retour en dérogation : l\'entrée sort');

        setStatus(matrix, 'Validée par dérogation');
        System.assertNotEquals(null, entryOf(matrix.Id), 'Re-validée : l\'entrée revient');

        setStatus(matrix, 'Refusée');
        System.assertEquals(null, entryOf(matrix.Id), 'Refus : l\'entrée sort');
    }

    @isTest
    static void testDeletedMatrixLeavesList() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = validated(position);
        System.assertNotEquals(null, entryOf(matrix.Id));

        delete matrix;

        System.assertEquals(0, entriesForPosition(position.Id).size(), 'Matrice supprimée : plus d\'entrée');
        System.assertEquals(0, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Matrix_Key__c = :String.valueOf(matrix.Id)]);
    }

    @isTest
    static void testUndeletedMatrixComesBack() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = validated(position);
        delete matrix;
        System.assertEquals(0, entriesForPosition(position.Id).size());

        undelete matrix;

        System.assertNotEquals(null, entryOf(matrix.Id), 'Matrice restaurée et validée : l\'entrée revient');
    }

    @isTest
    static void testDeletingLatestVersionLetsPreviousValidatedVersionBack() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2);
        System.assertEquals(null, entryOf(v1.Id));

        delete v2;

        List<AR_Validated_Matrix__c> entries = entriesForPosition(position.Id);
        System.assertEquals(1, entries.size(), 'Une entrée subsiste pour la chaîne');
        System.assertEquals(v1.Id, entries[0].AR_Price_Matrix__c, 'La dernière version validée restante prend l\'entrée');
    }

    // ---------- Renommage ----------

    @isTest
    static void testRenameWhenAccountConsultantVersionOrDateChange() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = validated(position);
        Id entryId = entryOf(matrix.Id).Id;
        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', entryOf(matrix.Id).Name);

        updateUnderBypass(new AR_Price_Matrix__c(Id = matrix.Id, AR_Account_Name__c = 'GLOBEX'));
        System.assertEquals('GLOBEX - Jean DUPONT, V1 (13/10/2026)', entryOf(matrix.Id).Name, 'Changement de compte');

        updateUnderBypass(new AR_Price_Matrix__c(Id = matrix.Id, AR_Consultant_Name__c = 'Marie MARTIN'));
        System.assertEquals('GLOBEX - Marie MARTIN, V1 (13/10/2026)', entryOf(matrix.Id).Name, 'Changement de consultant');

        updateUnderBypass(new AR_Price_Matrix__c(Id = matrix.Id, AR_Negotiation_Version__c = 4));
        System.assertEquals('GLOBEX - Marie MARTIN, V4 (13/10/2026)', entryOf(matrix.Id).Name, 'Changement de version');

        updateUnderBypass(new AR_Price_Matrix__c(Id = matrix.Id, AR_Validated_At__c = Datetime.newInstance(2026, 11, 2, 12, 0, 0)));
        System.assertEquals('GLOBEX - Marie MARTIN, V4 (02/11/2026)', entryOf(matrix.Id).Name, 'Changement de date');

        System.assertEquals(entryId, entryOf(matrix.Id).Id, 'Renommage en place : même entrée, pas de recréation');
    }

    @isTest
    static void testLinkedConsultantNameWinsOverFreeText() {
        cxsrec__cxsPosition__c position = openPosition('A');
        cxsrec__cxsCandidate__c candidate = new cxsrec__cxsCandidate__c(
            Name = 'Paul Linked', cxsrec__First_name__c = 'Paul', cxsrec__Last_name__c = 'Linked'
        );
        insert candidate;
        AR_Price_Matrix__c matrix = validated(position);
        System.assert(entryOf(matrix.Id).Name.contains('Jean DUPONT'), 'Texte libre en l\'absence de fiche liée');

        updateUnderBypass(new AR_Price_Matrix__c(Id = matrix.Id, AR_Consultant__c = candidate.Id));

        String name = entryOf(matrix.Id).Name;
        System.assert(name.contains(' - ' + [SELECT Name FROM cxsrec__cxsCandidate__c WHERE Id = :candidate.Id].Name + ', V1'), 'Fiche liée : ' + name);
        System.assert(!name.contains('Jean DUPONT'), 'Le texte libre n\'est plus utilisé : ' + name);
    }

    @isTest
    static void testMissingConsultant() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'ACME', AR_Negotiation_Version__c = 1, AR_Version_Number__c = 1,
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        );
        insert matrix;

        System.assertEquals(
            'ACME - consultant non renseigné, V1 (13/10/2026)', entryOf(matrix.Id).Name, 'Consultant vide : libellé de repli'
        );
    }

    // Matrices validées avant l'existence de AR_Validated_At__c : date de création, jamais une date vide.
    @isTest
    static void testMissingValidatedAtFallsBackOnCreatedDate() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'ACME', AR_Consultant_Name__c = 'Jean DUPONT', AR_Negotiation_Version__c = 1,
            AR_Version_Number__c = 1
        );
        insert matrix;

        String expectedDate = [SELECT CreatedDate FROM AR_Price_Matrix__c WHERE Id = :matrix.Id].CreatedDate
            .format('dd/MM/yyyy', 'Europe/Paris');
        System.assertEquals('ACME - Jean DUPONT, V1 (' + expectedDate + ')', entryOf(matrix.Id).Name);
    }

    // ---------- Troncature ----------

    @isTest
    static void testNameTruncatesAccountFirstAndNeverCutsVersionOrDate() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c matrix = new AR_Price_Matrix__c(
            AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
            AR_Account_Name__c = 'A'.repeat(200), AR_Consultant_Name__c = 'Jean DUPONT', AR_Negotiation_Version__c = 12,
            AR_Version_Number__c = 1, AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        );
        insert matrix;

        String name = entryOf(matrix.Id).Name;
        System.assertEquals(80, name.length(), 'Le libellé remplit exactement les 80 caractères : ' + name);
        System.assert(name.endsWith(' - Jean DUPONT, V12 (13/10/2026)'), 'Consultant, version et date intacts : ' + name);
        System.assert(name.contains('…'), 'Le compte tronqué est marqué : ' + name);
    }

    @isTest
    static void testExtremeConsultantNameStillFitsAndKeepsVersionAndDate() {
        String name = AR_ValidatedMatrixSyncService.buildName(new AR_Price_Matrix__c(
            AR_Account_Name__c = 'ACME',
            AR_Consultant_Name__c = 'C'.repeat(255),
            AR_Negotiation_Version__c = 3,
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        ));

        System.assert(name.length() <= 80, 'Au plus 80 caractères : ' + name.length());
        System.assert(name.endsWith(', V3 (13/10/2026)'), 'Version et date jamais coupées : ' + name);
        System.assert(name.startsWith('ACME - '), 'Compte court conservé : ' + name);
    }

    @isTest
    static void testAvenantNameTruncatesAccountFirstAndKeepsAvenantAndDate() {
        String name = AR_ValidatedMatrixSyncService.buildName(new AR_Price_Matrix__c(
            AR_Account_Name__c = 'A'.repeat(200),
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Negotiation_Version__c = 12,
            AR_Version_Type__c = 'Avenant',
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        ));

        System.assertEquals(80, name.length(), 'Le libellé remplit exactement les 80 caractères : ' + name);
        System.assert(name.endsWith(' - Jean DUPONT, V12 Avenant (13/10/2026)'), 'Consultant, version, « Avenant » et date intacts : ' + name);
        System.assert(name.contains('…'), 'Le compte tronqué est marqué : ' + name);
    }

    @isTest
    static void testShortNameIsNotTruncated() {
        String name = AR_ValidatedMatrixSyncService.buildName(new AR_Price_Matrix__c(
            AR_Account_Name__c = 'ACME',
            AR_Consultant_Name__c = 'Jean DUPONT',
            AR_Negotiation_Version__c = 1,
            AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
        ));

        System.assertEquals('ACME - Jean DUPONT, V1 (13/10/2026)', name);
        System.assert(!name.contains('…'));
    }

    // ---------- Idempotence, interrupteur, erreur ----------

    @isTest
    static void testReplayNeverDuplicates() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c v1 = validated(position);
        AR_Price_Matrix__c v2 = newMatrix(position, 'Validée', v1.Id, 2);
        Id entryId = entryOf(v2.Id).Id;

        AR_Validated_Matrix__c unchanged = entryOf(v2.Id);
        Integer rebuilt = AR_ValidatedMatrixSyncService.resyncAll();
        AR_ValidatedMatrixSyncService.resyncAll();

        System.assert(rebuilt >= 1, 'Au moins une chaîne rejouée');
        List<AR_Validated_Matrix__c> entries = entriesForPosition(position.Id);
        System.assertEquals(1, entries.size(), 'Rejouer la synchro ne crée jamais de doublon');
        System.assertEquals(entryId, entries[0].Id, 'Même entrée après rejeu');
        System.assertEquals(unchanged.Name, entries[0].Name, 'Libellé identique après rejeu');
    }

    @isTest
    static void testResyncAllRepairsMissingAndStaleEntries() {
        cxsrec__cxsPosition__c position = openPosition('A');
        setSync(false);
        AR_Price_Matrix__c matrix = validated(position);
        System.assertEquals(null, entryOf(matrix.Id), 'Interrupteur coupé : aucune entrée créée par le trigger');

        // Entrée orpheline : sa matrice est refusée pendant que la synchro est coupée.
        AR_Price_Matrix__c refused = validated(position);
        insert new AR_Validated_Matrix__c(
            Name = 'orpheline', AR_Price_Matrix__c = refused.Id, AR_Position__c = position.Id,
            AR_Root_Key__c = String.valueOf(refused.Id), AR_Matrix_Key__c = String.valueOf(refused.Id)
        );
        setStatus(refused, 'Refusée');
        System.assertNotEquals(null, entryOf(refused.Id), 'Interrupteur coupé : l\'entrée périmée n\'est pas retirée');

        AR_ValidatedMatrixSyncService.resyncAll();

        System.assertNotEquals(null, entryOf(matrix.Id), 'Reprise : l\'entrée manquante est créée');
        System.assertEquals(null, entryOf(refused.Id), 'Reprise : l\'entrée périmée est retirée');
    }

    @isTest
    static void testSwitchOffDoesNothing() {
        cxsrec__cxsPosition__c position = openPosition('A');
        setSync(false);

        AR_Price_Matrix__c matrix = validated(position);

        System.assertEquals(null, entryOf(matrix.Id), 'Interrupteur coupé : aucune écriture');
        setSync(true);
        setStatus(matrix, 'Validée par dérogation');
        System.assertNotEquals(null, entryOf(matrix.Id), 'Interrupteur rallumé : la synchro reprend');
    }

    @isTest
    static void testNoSettingsRecordDoesNothing() {
        cxsrec__cxsPosition__c position = openPosition('A');
        delete [SELECT Id FROM AR_General_Setting__c];

        AR_Price_Matrix__c matrix = validated(position);

        System.assertNotEquals(null, matrix.Id, 'La matrice est enregistrée');
        System.assertEquals(null, entryOf(matrix.Id), 'Sans réglages : synchro désactivée');
    }

    @isTest
    static void testTechnicalErrorDoesNotBlockMatrixSave() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c witness = validated(position);
        System.assertNotEquals(null, entryOf(witness.Id), 'Témoin : sans erreur simulée, l\'entrée est créée');

        AR_ValidatedMatrixSyncService.throwExceptionForTest = true;
        AR_Price_Matrix__c matrix;
        try {
            matrix = validated(position);
        } finally {
            AR_ValidatedMatrixSyncService.throwExceptionForTest = false;
        }

        System.assertNotEquals(null, matrix.Id, 'Erreur technique de la synchro : la matrice est enregistrée quand même');
        System.assertEquals(null, entryOf(matrix.Id), 'Erreur technique : aucune entrée, aucun refus');
        System.assertNotEquals(null, entryOf(witness.Id), 'Les entrées existantes ne sont pas touchées');
    }

    @isTest
    static void testUnrelatedUpdateOnDraftDoesNotTouchList() {
        cxsrec__cxsPosition__c position = openPosition('A');
        AR_Price_Matrix__c validatedMatrix = validated(position);
        Id entryId = entryOf(validatedMatrix.Id).Id;
        AR_Price_Matrix__c draft = newMatrix(position, 'Brouillon', null, 1);

        Integer queriesBefore = Limits.getQueries();
        update new AR_Price_Matrix__c(Id = draft.Id, AR_Proposed_TJM__c = 650);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;

        System.assertEquals(entryId, entryOf(validatedMatrix.Id).Id, 'Entrée existante intacte');
        System.assertEquals(1, entriesForPosition(position.Id).size());
        // Le test lui-même interroge (entryOf, entriesForPosition) après la mesure : la mesure se limite à l'update.
        System.assert(queriesUsed <= 1, 'Mise à jour sans rapport : aucune recomposition de chaîne (' + queriesUsed + ' requêtes)');
    }

    // ---------- Lot ----------

    @isTest
    static void testBulkOf200Matrices() {
        cxsrec__cxsPosition__c position = openPosition('A');
        // Session 200 : propriétaire = persona sans DA/DD/Directeur. Au nom de l'utilisateur qui exécute les tests, le nombre de
        // DML dépendait de sa fiche dans l'org : le partage de la chaîne (session 199) ajoute un DML dès qu'il a une chaîne
        // (renseignée en production, vide en sandbox). Avec ce propriétaire, le seul partage est celui du créateur : un DML groupé.
        Id ownerId = AR_TestPersona.sansHabilitation().Id;
        List<AR_Price_Matrix__c> matrices = new List<AR_Price_Matrix__c>();
        for (Integer i = 0; i < 200; i++) {
            matrices.add(new AR_Price_Matrix__c(
                OwnerId = ownerId,
                AR_Position__c = position.Id, AR_Status__c = 'Validée', AR_Contract_Type__c = 'CDI', AR_Proposed_TJM__c = 500,
                AR_Account_Name__c = 'ACME ' + i, AR_Consultant_Name__c = 'Jean DUPONT', AR_Negotiation_Version__c = 1,
                AR_Version_Number__c = 1, AR_Validated_At__c = Datetime.newInstance(2026, 10, 13, 12, 0, 0)
            ));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        insert matrices;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c = :position.Id], '200 matrices : 200 entrées');
        System.assertEquals(
            200, [SELECT COUNT() FROM AR_Validated_Matrix__c WHERE AR_Position__c = :position.Id AND Name LIKE 'ACME %'],
            'Chaque entrée porte le libellé de SA matrice'
        );
        System.assert(queriesUsed <= 10, 'Pas de requête par matrice (' + queriesUsed + ')');
        System.assertEquals(
            3, dmlUsed,
            'Un insert de matrices + un upsert d\'entrées + un partage du créateur groupé, quel que soit le lot (' + dmlUsed + ')'
        );
    }
}