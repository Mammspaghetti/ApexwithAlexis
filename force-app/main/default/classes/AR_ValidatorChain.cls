/**
 * Source unique de la chaîne de valideurs d'une matrice — DA (`TP_DA__c`), DD
 * (`TP_DD__c`), Directeur (`TP_Directeur__c`) du PROPRIÉTAIRE de la matrice (décision du 30/09/2026),
 * plus, en phase de test, les utilisateurs listés dans `AR_General_Setting__c.AR_Test_Validator_Ids__c`
 * (décision du 24/09/2026 : Matthieu toujours proposé ; réglage à vider avant la production,
 * cf. docs/deploiement-production.md §8). Aucun Id en dur dans le code.
 *
 * Liste proposée à l'écran : RA, DA, DD, Directeur, Directeur commercial et Directeur commercial groupe
 * du propriétaire (`proposalLevels`), puis les valideurs actifs de l'entité PTF de la matrice
 * (`AR_PTF_Entity_Validator__c`, rôle « Valideur entité »), une seule ligne par personne, rôles cumulés. L'escalade des relances
 * ne retient que DA → DD → Directeur (`levels`) : elle ne change pas avec la liste proposée.
 *
 * Consommateurs : `AR_PricingMatrixService` (liste proposée à l'écran + garde serveur de la demande de
 * dérogation) et `AR_DerogationReminderBatch` (ordre des niveaux de l'escalade, via `levels`) — une seule
 * définition de « la chaîne », jamais une copie par appelant.
 *
 * L'application ne vérifie ni ne compense les permissions des autres utilisateurs : aucun filtre par
 * permission ici. Un niveau vide ou inactif est sauté ; si plus rien ne reste, `blockedReason` dit
 * quels champs sont vides sur la fiche de qui — jamais un message générique.
 */
public with sharing class AR_ValidatorChain {
    /** Résultat : valideurs proposés (Id + Name renseignés, actifs, dédoublonnés) ou motif de blocage. */
    public class Resolution {
        public List<User> validators = new List<User>();
        /** Rôles affichés par valideur proposé, rôles cumulés (« RA, DA ») ; absent pour le valideur de test. */
        public Map<Id, String> roleByUserId = new Map<Id, String>();
        public String blockedReason;
    }

    /** Un niveau de la liste proposée : la personne (null si vide) et le libellé de son rôle. */
    public class Level {
        public User person;
        public String role;
    }

    /** Niveaux de l'escalade dans l'ordre DA → DD → Directeur (null pour un niveau vide). */
    public static List<User> levels(User owner) {
        return new List<User>{ owner.TP_DA__r, owner.TP_DD__r, owner.TP_Directeur__r };
    }

    /** Niveaux de la liste proposée, dans l'ordre RA, DA, DD, Directeur, Directeur commercial, Directeur commercial groupe. */
    public static List<Level> proposalLevels(User owner) {
        List<Level> levels = documentLevels(owner);
        levels.add(level(owner.TP_Directeur_commercial__r, Label.AR_Msg_VAL_LevelSalesDirector));
        levels.add(level(owner.TP_Directeur_commercial_groupe__r, Label.AR_Msg_VAL_LevelGroupSalesDirector));
        return levels;
    }

    /** Niveaux proposés pour le valideur d'un PTF : RA, DA, DD, Directeur (sans les directeurs commerciaux). */
    public static List<Level> documentLevels(User owner) {
        return new List<Level>{
            level(owner.TP_RA__r, Label.AR_Msg_VAL_LevelRA),
            level(owner.TP_DA__r, Label.AR_Msg_VAL_LevelDA),
            level(owner.TP_DD__r, Label.AR_Msg_VAL_LevelDD),
            level(owner.TP_Directeur__r, Label.AR_Msg_VAL_LevelDirector)
        };
    }

    /** Valideurs actifs de l'entité PTF, ordonnés par nom, avec le rôle « Valideur entité » (liste vide si pas d'entité). */
    public static List<Level> entityLevels(Id entityId) {
        List<Level> out = new List<Level>();
        if (entityId == null) {
            return out;
        }
        List<User> users = activeEntityValidators(new Set<Id>{ entityId }).get(entityId);
        if (users != null) {
            for (User u : users) {
                out.add(level(u, Label.AR_Msg_VAL_LevelEntityValidator));
            }
        }
        return out;
    }

    /** Valideurs actifs par entité (ensemble d'entités, pour le partage en masse) ; lignes sans utilisateur ignorées. */
    public static Map<Id, List<User>> activeEntityValidators(Set<Id> entityIds) {
        Map<Id, List<User>> byEntity = new Map<Id, List<User>>();
        if (entityIds == null || entityIds.isEmpty()) {
            return byEntity;
        }
        for (AR_PTF_Entity_Validator__c row : [
            SELECT AR_Entity_Ref__c, AR_User__c, AR_User__r.Name, AR_User__r.Title, AR_User__r.IsActive
            FROM AR_PTF_Entity_Validator__c
            WHERE AR_Entity_Ref__c IN :entityIds AND AR_User__c != NULL AND AR_User__r.IsActive = true
            WITH SYSTEM_MODE
            ORDER BY AR_User__r.Name
        ]) {
            if (!byEntity.containsKey(row.AR_Entity_Ref__c)) {
                byEntity.put(row.AR_Entity_Ref__c, new List<User>());
            }
            byEntity.get(row.AR_Entity_Ref__c).add(row.AR_User__r);
        }
        return byEntity;
    }

    private static Level level(User person, String role) {
        Level l = new Level();
        l.person = person;
        l.role = role;
        return l;
    }

    public static Resolution resolveForMatrix(Id matrixId) {
        Resolution res = new Resolution();
        List<AR_Price_Matrix__c> matrices = [SELECT OwnerId, AR_Entity_Ref__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
        if (matrices.isEmpty()) {
            res.blockedReason = Label.AR_Msg_PM_MatrixNotFound;
            return res;
        }
        // Le demandeur (utilisateur courant) et le propriétaire ne valident jamais leur propre demande.
        return resolveForOwner(matrices[0].OwnerId, new Set<Id>{ matrices[0].OwnerId, UserInfo.getUserId() }, matrices[0].AR_Entity_Ref__c);
    }

    public static Resolution resolveForOwner(Id ownerId) {
        return resolveForOwner(ownerId, new Set<Id>());
    }

    /** `excluded` : personnes jamais proposées (demandeur, propriétaire), même présentes dans la chaîne. */
    public static Resolution resolveForOwner(Id ownerId, Set<Id> excluded) {
        return resolveForOwner(ownerId, excluded, null);
    }

    /** `entityId` : entité PTF de la matrice ; ses valideurs actifs suivent la hiérarchie, avant les valideurs de test. */
    public static Resolution resolveForOwner(Id ownerId, Set<Id> excluded, Id entityId) {
        Resolution res = new Resolution();
        List<User> owners = [
            SELECT Id, Name,
                   TP_RA__c, TP_RA__r.Name, TP_RA__r.IsActive,
                   TP_DA__c, TP_DA__r.Name, TP_DA__r.IsActive,
                   TP_DD__c, TP_DD__r.Name, TP_DD__r.IsActive,
                   TP_Directeur__c, TP_Directeur__r.Name, TP_Directeur__r.IsActive,
                   TP_Directeur_commercial__c, TP_Directeur_commercial__r.Name, TP_Directeur_commercial__r.IsActive,
                   TP_Directeur_commercial_groupe__c, TP_Directeur_commercial_groupe__r.Name, TP_Directeur_commercial_groupe__r.IsActive
            FROM User
            WHERE Id = :ownerId
            LIMIT 1
        ];
        if (owners.isEmpty()) {
            res.blockedReason = Label.AR_Msg_PM_MatrixNotFound;
            return res;
        }
        User owner = owners[0];

        Set<Id> seen = new Set<Id>();
        // Vrai si un valideur actif a été écarté parce qu'il est le demandeur ou le propriétaire.
        Boolean skippedExcluded = false;
        List<Level> proposed = proposalLevels(owner);
        proposed.addAll(entityLevels(entityId));
        for (Level l : proposed) {
            User person = l.person;
            if (person == null || person.IsActive != true) {
                continue;
            }
            if (excluded.contains(person.Id)) {
                skippedExcluded = true;
                continue;
            }
            if (seen.add(person.Id)) {
                res.validators.add(person);
                res.roleByUserId.put(person.Id, l.role);
            } else {
                res.roleByUserId.put(person.Id, res.roleByUserId.get(person.Id) + ', ' + l.role);
            }
        }

        Set<Id> testIds = testValidatorIds();
        Integer testFound = 0;
        if (!testIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :testIds AND IsActive = true ORDER BY Name]) {
                testFound++;
                if (excluded.contains(u.Id)) {
                    skippedExcluded = true;
                } else if (seen.add(u.Id)) {
                    res.validators.add(u);
                }
            }
        }

        if (res.validators.isEmpty()) {
            res.blockedReason = skippedExcluded
                ? Label.AR_Msg_VAL_OnlyExcludedValidators
                : emptyChainMessage(owner, testIds.size(), testFound);
        }
        return res;
    }

    /** Ids du réglage de phase de test (virgules, points-virgules ou espaces) ; valeur absente → vide. */
    public static Set<Id> testValidatorIds() {
        Set<Id> ids = new Set<Id>();
        List<AR_General_Setting__c> settings = [SELECT AR_Test_Validator_Ids__c FROM AR_General_Setting__c LIMIT 1];
        if (settings.isEmpty() || String.isBlank(settings[0].AR_Test_Validator_Ids__c)) {
            return ids;
        }
        for (String token : settings[0].AR_Test_Validator_Ids__c.split('[,;\\s]+')) {
            if (String.isBlank(token)) {
                continue;
            }
            // Avalé délibérément : un jeton qui n'est pas un Id Salesforce valide ne peut désigner
            // personne ; il est journalisé et le reste de la liste reste utilisable.
            if (Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', token) && token.startsWith('005')) {
                ids.add(Id.valueOf(token));
            } else {
                System.debug(LoggingLevel.WARN, 'AR_Test_Validator_Ids__c : jeton ignoré (pas un Id utilisateur) : ' + token);
            }
        }
        return ids;
    }

    private static String emptyChainMessage(User owner, Integer testConfigured, Integer testActive) {
        List<String> states = new List<String>{
            levelState(Label.AR_Msg_VAL_LevelRA, 'TP_RA__c', owner.TP_RA__c, owner.TP_RA__r),
            levelState(Label.AR_Msg_VAL_LevelDA, 'TP_DA__c', owner.TP_DA__c, owner.TP_DA__r),
            levelState(Label.AR_Msg_VAL_LevelDD, 'TP_DD__c', owner.TP_DD__c, owner.TP_DD__r),
            levelState(Label.AR_Msg_VAL_LevelDirector, 'TP_Directeur__c', owner.TP_Directeur__c, owner.TP_Directeur__r),
            levelState(Label.AR_Msg_VAL_LevelSalesDirector, 'TP_Directeur_commercial__c', owner.TP_Directeur_commercial__c, owner.TP_Directeur_commercial__r),
            levelState(Label.AR_Msg_VAL_LevelGroupSalesDirector, 'TP_Directeur_commercial_groupe__c', owner.TP_Directeur_commercial_groupe__c, owner.TP_Directeur_commercial_groupe__r)
        };
        String msg =
            AR_I18n.format(Label.AR_Msg_VAL_NoValidatorFound, new List<Object>{ owner.Name, String.join(states, ' ; ') });
        if (testConfigured > 0 && testActive == 0) {
            msg += ' ' + AR_I18n.format(Label.AR_Msg_VAL_TestValidatorsInactive, new List<Object>{ testConfigured });
        }
        return msg + ' ' + Label.AR_Msg_VAL_FillOneField;
    }

    private static String levelState(String label, String apiName, Id levelId, User level) {
        if (levelId == null) {
            return AR_I18n.format(System.Label.AR_Msg_VAL_LevelEmpty, new List<Object>{ label, apiName });
        }
        String name = level != null && String.isNotBlank(level.Name) ? level.Name : String.valueOf(levelId);
        return AR_I18n.format(System.Label.AR_Msg_VAL_LevelInactive, new List<Object>{ label, apiName, name });
    }
}