/**
 * Fabrique partagée de personas réels (session 41, docs/41-parcours-utilisateur-reel.md) — extraite
 * de la machinerie de AR_DerogationServiceTest (session 40) pour ne pas la recopier dans chaque
 * classe de test qui a besoin d'un utilisateur non-administrateur sous System.runAs.
 *
 * Profil "Recruiter" (pas "Utilisateur standard") : c'est le profil réel des valideurs constatés en
 * sandbox (Alexandre Lerbet, Francois Lefebvre) — "Utilisateur standard" a readable=false sur
 * User.TP_Job_Title__c, ce qui casse tout appel qui en dépend une fois sous System.runAs, cf.
 * AR_DerogationServiceTest (session 33).
 *
 * MIXED_DML_OPERATION : toute DML sur User/PermissionSetAssignment (objets de configuration) est
 * isolée dans un System.runAs(utilisateur courant) — sinon une DML métier plus loin dans la même
 * transaction (AR_Price_Matrix__c, AR_Derogation__c...) échoue.
 *
 * Session 43 : personas étendus aux trois domaines d'administration (session 42) et à
 * AR_Pricing_Manager (successeur non-administratif de l'ancien permission set d'administration
 * unique, supprimé cette session). newUser accepte désormais plusieurs permission sets, tous
 * additifs à AR_Pricing_User — un persona de domaine porte donc toujours le socle applicatif,
 * jamais un set d'administration seul.
 * sansHabilitation() remplace la fabrication d'un « non-habilité » par retrait de permission sur
 * l'utilisateur exécutant les tests (cf. docs/43-purge-pricing-admin-et-tests-independants.md §4) :
 * un utilisateur sans aucune habilitation se crée, il ne se simule pas en déshabillant l'admin qui
 * lance la suite.
 */
@IsTest
public class AR_TestPersona {

    private static Integer counter = 0;

    /**
     * Session 132 : fiche d'entité de la liste d'administration (AR_PTF_Entity_Referential__c) par Nom,
     * créée (active, sans coordonnées) si le test ne l'a pas déjà insérée. Comparaison `equals`
     * (sensible à la casse), jamais le `=` de SOQL qui confond « Abylsen GAMMA » et « ABYLSEN GAMMA ».
     */
    public static Id entityRefId(String name) {
        for (AR_PTF_Entity_Referential__c fiche : [
            SELECT Id, Name FROM AR_PTF_Entity_Referential__c WHERE Name = :name
        ]) {
            if (fiche.Name.equals(name)) {
                return fiche.Id;
            }
        }
        AR_PTF_Entity_Referential__c created = new AR_PTF_Entity_Referential__c(Name = name, AR_Active__c = true);
        insert created;
        return created.Id;
    }

    /**
     * Session 184c3 : fiche d'entité complète pour la génération PTF (RIB renseigné — seule condition
     * bancaire du gabarit Abylsen depuis la session 63). Même résolution que entityRefId (par Nom,
     * sensible à la casse) ; le RIB n'est posé que s'il manque, jamais écrasé.
     */
    public static Id entityRefIdWithBank(String name) {
        Id ficheId = entityRefId(name);
        update new AR_PTF_Entity_Referential__c(
            Id = ficheId,
            AR_Rib__c = '00000 00000 00000000000 00 (FICTIF test)'
        );
        return ficheId;
    }

    private static Id ownerWithDaId;

    /**
     * Session 184c3 : propriétaire de test dont le directeur d'agence (User.TP_DA__c) est renseigné.
     * Depuis la session 184c le valideur d'une PTF est le DA du propriétaire de la matrice : sans DA,
     * toute génération est refusée. Pour les matrices insérées par DML directe (OwnerId posé à
     * l'INSERT). Jamais le DA posé sur l'utilisateur qui exécute les tests : cette ligne User serait
     * verrouillée en parallèle par chaque classe (UNABLE_TO_LOCK_ROW). Réutilisé d'un appel à
     * l'autre dans la transaction, retrouvé par son nom quand il a été créé dans un @TestSetup.
     */
    public static Id ownerWithDa() {
        if (ownerWithDaId != null) {
            return ownerWithDaId;
        }
        List<User> existing = [SELECT Id FROM User WHERE LastName = 'Session184c3 OwnerDa' AND IsActive = true LIMIT 1];
        if (!existing.isEmpty()) {
            ownerWithDaId = existing[0].Id;
            return ownerWithDaId;
        }
        User da = valideur();
        User owner = newUser('OwnerDa', new List<String>{ 'AR_Pricing_User' });
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = owner.Id, TP_DA__c = da.Id, LastName = 'Session184c3 OwnerDa');
        }
        ownerWithDaId = owner.Id;
        return ownerWithDaId;
    }

    /** Business Manager : AR_Pricing_User seul — crée/enregistre des matrices, demande une dérogation, génère une PTF. */
    public static User bm() {
        return newUser('BM', new List<String>{ 'AR_Pricing_User' });
    }

    /** Valideur : AR_Pricing_Validator — décide les dossiers d'un autre utilisateur. */
    public static User valideur() {
        return newUser('Valideur', new List<String>{ 'AR_Pricing_Validator' });
    }

    /** Manager Pricing : AR_Pricing_Manager — successeur non-administratif de l'ancien permission
     * set d'administration unique (matrices, dérogations, AR_Approve_Derogation), sans aucun des
     * trois domaines d'admin. */
    public static User manager() {
        return newUser('Manager', new List<String>{ 'AR_Pricing_Manager' });
    }

    /** Administrateur du domaine « Paramètres généraux » (AR_Admin_General_Settings) — n'administre
     * ni les devises ni les référentiels. */
    public static User adminGeneral() {
        return newUser('AdminGeneral', new List<String>{ 'AR_Admin_General_Settings' });
    }

    /** Administrateur du domaine « Devises » (AR_Admin_Currency) — n'administre ni les paramètres
     * généraux ni les référentiels. */
    public static User adminDevises() {
        return newUser('AdminDevises', new List<String>{ 'AR_Admin_Currency' });
    }

    /** Administrateur du domaine « Référentiels » (AR_Admin_Referentials) — n'administre ni les
     * paramètres généraux ni les devises. */
    public static User adminReferentiels() {
        return newUser('AdminReferentiels', new List<String>{ 'AR_Admin_Referentials' });
    }

    /** Administrateur du domaine « Entités PTF » (AR_Admin_PTF_Entities, session 46) — domaine séparé
     * de AR_Admin_Referentials à la demande du client : n'administre ni les autres référentiels ni
     * les paramètres généraux ni les devises. */
    public static User adminPtfEntities() {
        return newUser('AdminPtfEntities', new List<String>{ 'AR_Admin_PTF_Entities' });
    }

    /** Aucune habilitation d'administration ni de validation : AR_Pricing_User seul. Le persona le
     * plus important de cette fabrique — remplace toute simulation d'un « non-habilité » par retrait
     * de permission sur l'utilisateur exécutant les tests. */
    public static User sansHabilitation() {
        return newUser('SansHabilitation', new List<String>{ 'AR_Pricing_User' });
    }

    /** Session 183 : AR_Connexys_Matrix_Picker seul, sans AR_Pricing_User — choisit une matrice validée dans l'étape Connexys. */
    public static User matrixPicker() {
        return newUser('MatrixPicker', new List<String>{ 'AR_Connexys_Matrix_Picker' });
    }

    /** Session 183 : comme matrixPicker, plus le permission set Connexys existant Custom_Step (modification d'une étape — le profil Recruiter seul ne peut que lire et créer). */
    public static User matrixPickerWithStepEdit() {
        return newUser('MatrixPickerEdit', new List<String>{ 'AR_Connexys_Matrix_Picker', 'Custom_Step' });
    }

    /** Session 183 : aucun permission set AR_ (profil Recruiter nu) — l'utilisateur Connexys ordinaire. */
    public static User sansPermissionSetAR() {
        return newUser('SansPermAR', new List<String>());
    }

    /** Id du profil "Utilisateur standard" indépendant de la langue. Recherche d'abord par
     * UserLicense (Salesforce) + PermissionsCustomizeApplication false, puis par nom (français/anglais). */
    public static Id standardProfileId() {
        // « Recruiter » = profil réel des Business Managers (propriétaires de 28 972 besoins Connexys,
        // relevé session 135) : seul à porter la lecture de cxsrec__cxsPosition__c. Le repli générique
        // seul (session 134) tombait sur « Webservice Profile V2 » (profil d'API, sans accès Connexys →
        // TRANSFER_REQUIRES_READ). Le nom est stable ici ; le repli couvre une org où il serait absent.
        List<Profile> recruiter = [SELECT Id FROM Profile WHERE Name = 'Recruiter' LIMIT 1];
        if (!recruiter.isEmpty()) {
            return recruiter[0].Id;
        }
        List<Profile> profiles = [
            SELECT Id FROM Profile
            WHERE UserLicense.Name = 'Salesforce' AND PermissionsCustomizeApplication = false
            LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            return profiles[0].Id;
        }
        return [SELECT Id FROM Profile WHERE Name IN ('Utilisateur standard', 'Standard User') LIMIT 1].Id;
    }

    private static User newUser(String key, List<String> permissionSetNames) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            counter++;
            String uniqueToken = key + counter + Datetime.now().getTime();
            u = new User(
                LastName = 'Session41 ' + key,
                Email = key.toLowerCase() + counter + '@example.com.invalid',
                Username = 'ar.session41.' + uniqueToken + '@example.com.invalid',
                Alias = (key + counter).left(8),
                IsActive = true,
                TimeZoneSidKey = 'Europe/Paris',
                LocaleSidKey = 'fr_FR',
                LanguageLocaleKey = 'fr',
                EmailEncodingKey = 'UTF-8',
                ProfileId = standardProfileId(),
                FederationIdentifier = 'ar.session41.' + uniqueToken
            );
            insert u;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames]) {
                assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
        }
        return u;
    }

    /**
     * Administrateur système dont la langue est le français, avec tous les permission sets AR_ :
     * les droits de l'utilisateur qui exécute la suite, libellés FR. Réservé aux assertions qui
     * comparent un message au texte français : la langue des libellés suit l'utilisateur sous
     * System.runAs, pas celui qui lance les tests (en_US).
     */
    public static User francais() {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            counter++;
            String uniqueToken = 'FR' + counter + Datetime.now().getTime();
            u = new User(
                LastName = 'AR Test FR',
                Email = 'ar.test.fr' + counter + '@example.com.invalid',
                Username = 'ar.test.fr.' + uniqueToken + '@example.com.invalid',
                Alias = ('fr' + counter).left(8),
                IsActive = true,
                TimeZoneSidKey = 'Europe/Paris',
                LocaleSidKey = 'fr_FR',
                LanguageLocaleKey = 'fr',
                EmailEncodingKey = 'UTF-8',
                // Session 252 : l'org porte le profil sous son libellé français (« Administrateur système »).
                ProfileId = [SELECT Id FROM Profile WHERE Name IN ('System Administrator', 'Administrateur système') LIMIT 1].Id,
                FederationIdentifier = 'ar.test.fr.' + uniqueToken
            );
            insert u;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name LIKE 'AR_%']) {
                assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
        }
        return u;
    }

    /**
     * Transfère la propriété d'un compte/besoin Connexys créés par l'utilisateur exécutant les tests
     * vers un persona : un utilisateur voit toujours ses propres enregistrements, quel que soit le
     * modèle de partage (Private compris) — évite de dépendre de règles de partage/rôles non montées
     * pour ces tests, qui ne sont pas l'objet de cette session (le partage Compte/Contact existant est
     * une contrainte documentée, cf. CLAUDE.md, pas un sujet de la session 41).
     */
    public static void makeOwner(Id recordId, Id ownerId) {
        update new Account(Id = recordId, OwnerId = ownerId);
    }

    public static void makePositionOwner(Id positionId, Id ownerId) {
        update new cxsrec__cxsPosition__c(Id = positionId, OwnerId = ownerId);
    }

    /** Business Manager avec DA assigné. Utile pour les tests qui exigent TP_DA__c renseigné. */
    public static User bmWithDa() {
        User da = bm();
        User creator = bm();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = creator.Id, TP_DA__c = da.Id);
        }
        return creator;
    }
}