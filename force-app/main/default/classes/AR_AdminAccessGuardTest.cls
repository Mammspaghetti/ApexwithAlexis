/**
 * Tests AR_AdminAccessGuard : les quatre gardes de domaine (session 42, quatrième domaine « Entités
 * PTF » ajouté en session 46), vérifiées avec des utilisateurs réels (System.runAs) porteurs d'une
 * seule permission à la fois — jamais une simple assertion de façade sur la méthode isolée. Cinq
 * personas couverts (prompts/session-42-administration-par-domaine.md, « Vérification exigée » §3,
 * étendu) : un porteur de chaque domaine, et un porteur d'aucun — chacun vérifié à la fois sur
 * getAdminAccess() (le quadruplet complet) et sur les quatre méthodes require*() (son propre domaine
 * ne bloque pas, les trois autres bloquent).
 */
@IsTest
private class AR_AdminAccessGuardTest {

    private static Integer userCounter = 0;

    private static User newUserWithoutPermissions() {
        userCounter++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'AdminGuardTest' + userCounter,
            FirstName = 'AR',
            Alias = 'aragt' + userCounter,
            Email = 'ar.admin.guard.test' + userCounter + '@abylsengroup.com.invalid',
            Username = 'ar.admin.guard.test' + userCounter + '@abylsengroup.com.invalid.' + Datetime.now().getTime(),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            LanguageLocaleKey = 'fr',
            EmailEncodingKey = 'UTF-8',
            FederationIdentifier = 'ar.admin.guard.test.' + userCounter + '.' + Datetime.now().getTime()
        );
        insert u;
        return u;
    }

    private static User newUserWithPermissionSet(String permissionSetName) {
        User u = newUserWithoutPermissions();
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
        return u;
    }

    private class DomainResult {
        AR_AdminAccessGuard.AdminAccessDto access;
        Boolean generalThrew = false;
        Boolean currencyThrew = false;
        Boolean referentialsThrew = false;
        Boolean ptfEntitiesThrew = false;
    }

    private static DomainResult probe(User u) {
        DomainResult r = new DomainResult();
        System.runAs(u) {
            r.access = AR_AdminAccessGuard.getAdminAccess();
            try {
                AR_AdminAccessGuard.requireGeneralSettings();
            } catch (AuraHandledException e) {
                r.generalThrew = true;
            }
            try {
                AR_AdminAccessGuard.requireCurrency();
            } catch (AuraHandledException e) {
                r.currencyThrew = true;
            }
            try {
                AR_AdminAccessGuard.requireReferentials();
            } catch (AuraHandledException e) {
                r.referentialsThrew = true;
            }
            try {
                AR_AdminAccessGuard.requirePtfEntities();
            } catch (AuraHandledException e) {
                r.ptfEntitiesThrew = true;
            }
        }
        return r;
    }

    // ------------------------------------------------------------------
    // Persona 1 : porteur d'AR_Admin_General_Settings uniquement.
    // ------------------------------------------------------------------
    @IsTest
    static void testPersona_generalSettingsOnly() {
        User u = newUserWithPermissionSet('AR_Admin_General_Settings');

        Test.startTest();
        DomainResult r = probe(u);
        Test.stopTest();

        System.assertEquals(true, r.access.generalSettings, 'Le porteur de AR_Admin_General_Settings doit voir generalSettings=true');
        System.assertEquals(false, r.access.currencyAccess, 'Le porteur de AR_Admin_General_Settings ne doit pas voir currency=true');
        System.assertEquals(false, r.access.referentials, 'Le porteur de AR_Admin_General_Settings ne doit pas voir referentials=true');
        System.assertEquals(false, r.access.ptfEntities, 'Le porteur de AR_Admin_General_Settings ne doit pas voir ptfEntities=true');
        System.assertEquals(false, r.generalThrew, 'requireGeneralSettings() ne doit pas bloquer ce porteur');
        System.assert(r.currencyThrew, 'requireCurrency() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.referentialsThrew, 'requireReferentials() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.ptfEntitiesThrew, 'requirePtfEntities() doit bloquer un porteur qui ne détient pas ce domaine');
    }

    // ------------------------------------------------------------------
    // Persona 2 : porteur d'AR_Admin_Currency uniquement.
    // ------------------------------------------------------------------
    @IsTest
    static void testPersona_currencyOnly() {
        User u = newUserWithPermissionSet('AR_Admin_Currency');

        Test.startTest();
        DomainResult r = probe(u);
        Test.stopTest();

        System.assertEquals(false, r.access.generalSettings, 'Le porteur de AR_Admin_Currency ne doit pas voir generalSettings=true');
        System.assertEquals(true, r.access.currencyAccess, 'Le porteur de AR_Admin_Currency doit voir currency=true');
        System.assertEquals(false, r.access.referentials, 'Le porteur de AR_Admin_Currency ne doit pas voir referentials=true');
        System.assertEquals(false, r.access.ptfEntities, 'Le porteur de AR_Admin_Currency ne doit pas voir ptfEntities=true');
        System.assert(r.generalThrew, 'requireGeneralSettings() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assertEquals(false, r.currencyThrew, 'requireCurrency() ne doit pas bloquer ce porteur');
        System.assert(r.referentialsThrew, 'requireReferentials() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.ptfEntitiesThrew, 'requirePtfEntities() doit bloquer un porteur qui ne détient pas ce domaine');
    }

    // ------------------------------------------------------------------
    // Persona 3 : porteur d'AR_Admin_Referentials uniquement.
    // ------------------------------------------------------------------
    @IsTest
    static void testPersona_referentialsOnly() {
        User u = newUserWithPermissionSet('AR_Admin_Referentials');

        Test.startTest();
        DomainResult r = probe(u);
        Test.stopTest();

        System.assertEquals(false, r.access.generalSettings, 'Le porteur de AR_Admin_Referentials ne doit pas voir generalSettings=true');
        System.assertEquals(false, r.access.currencyAccess, 'Le porteur de AR_Admin_Referentials ne doit pas voir currency=true');
        System.assertEquals(true, r.access.referentials, 'Le porteur de AR_Admin_Referentials doit voir referentials=true');
        System.assertEquals(false, r.access.ptfEntities, 'Le porteur de AR_Admin_Referentials ne doit pas voir ptfEntities=true (domaine séparé depuis la session 46)');
        System.assert(r.generalThrew, 'requireGeneralSettings() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.currencyThrew, 'requireCurrency() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assertEquals(false, r.referentialsThrew, 'requireReferentials() ne doit pas bloquer ce porteur');
        System.assert(r.ptfEntitiesThrew, 'requirePtfEntities() doit bloquer un porteur d\'AR_Admin_Referentials, domaine séparé depuis la session 46');
    }

    // ------------------------------------------------------------------
    // Persona 4 : porteur d'AR_Admin_PTF_Entities uniquement (session 46).
    // ------------------------------------------------------------------
    @IsTest
    static void testPersona_ptfEntitiesOnly() {
        User u = newUserWithPermissionSet('AR_Admin_PTF_Entities');

        Test.startTest();
        DomainResult r = probe(u);
        Test.stopTest();

        System.assertEquals(false, r.access.generalSettings, 'Le porteur de AR_Admin_PTF_Entities ne doit pas voir generalSettings=true');
        System.assertEquals(false, r.access.currencyAccess, 'Le porteur de AR_Admin_PTF_Entities ne doit pas voir currency=true');
        System.assertEquals(false, r.access.referentials, 'Le porteur de AR_Admin_PTF_Entities ne doit pas voir referentials=true (domaine séparé)');
        System.assertEquals(true, r.access.ptfEntities, 'Le porteur de AR_Admin_PTF_Entities doit voir ptfEntities=true');
        System.assert(r.generalThrew, 'requireGeneralSettings() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.currencyThrew, 'requireCurrency() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assert(r.referentialsThrew, 'requireReferentials() doit bloquer un porteur qui ne détient pas ce domaine');
        System.assertEquals(false, r.ptfEntitiesThrew, 'requirePtfEntities() ne doit pas bloquer ce porteur');
    }

    // ------------------------------------------------------------------
    // Persona 5 : porteur d'aucune des quatre permissions — le cas fail-closed.
    // ------------------------------------------------------------------
    @IsTest
    static void testPersona_none() {
        User u = newUserWithoutPermissions();

        Test.startTest();
        DomainResult r = probe(u);
        Test.stopTest();

        System.assertEquals(false, r.access.generalSettings, 'Un utilisateur sans aucune permission ne doit voir aucun domaine à true');
        System.assertEquals(false, r.access.currencyAccess, 'Un utilisateur sans aucune permission ne doit voir aucun domaine à true');
        System.assertEquals(false, r.access.referentials, 'Un utilisateur sans aucune permission ne doit voir aucun domaine à true');
        System.assertEquals(false, r.access.ptfEntities, 'Un utilisateur sans aucune permission ne doit voir aucun domaine à true');
        System.assert(r.generalThrew, 'requireGeneralSettings() doit bloquer un utilisateur sans permission');
        System.assert(r.currencyThrew, 'requireCurrency() doit bloquer un utilisateur sans permission');
        System.assert(r.referentialsThrew, 'requireReferentials() doit bloquer un utilisateur sans permission');
        System.assert(r.ptfEntitiesThrew, 'requirePtfEntities() doit bloquer un utilisateur sans permission');
    }
}