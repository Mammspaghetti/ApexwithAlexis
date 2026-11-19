/**
 * Lien matrice validée ↔ étape Connexys « 2. Qualification » (RT Step `Interview2`), docs/171 §5-6, session 174.
 * Trigger before insert / before update sur cxsrec__cxsStep__c.
 *
 * Le champ de la popup est `AR_Validated_Matrix__c` (lookup vers l'objet « Matrice validée », qui ne contient que
 * les matrices validées utiles : une entrée par chaîne, dernière version, besoin Open — cf.
 * AR_ValidatedMatrixSyncService). Le sélecteur Connexys ignore les filtres de lookup : le filtrage est obtenu par
 * construction de la liste.
 *
 * - Copie (toujours, indépendante des interrupteurs C/D) : la vraie matrice de l'entrée choisie est recopiée dans
 *   `AR_Price_Matrix__c` du Step. C'est la source de vérité durable : quand l'entrée est purgée, le champ de la
 *   popup se vide mais le Step garde sa matrice. Jamais effacée ici.
 * - C (AR_StepMatrixLink_Auto_Link_Enabled__c) : champ vide → renseigné si le besoin n'a qu'une entrée.
 *   Jamais de choix entre plusieurs (sauf affinage par candidature non ambigu), jamais d'écrasement d'un choix.
 * - D (AR_StepMatrixLink_Check_Enabled__c) : entrée choisie qui n'appartient pas au besoin de la candidature → refus.
 *   D' (AR_StepMatrixLink_Require_Empty_Enabled__c, sous D) : champ vide avec 0 ou ≥ 2 entrées → refus.
 * - Session 183 : les trois lectures (paramètres, candidatures, entrées) sont en SYSTEM_MODE. Un utilisateur Connexys qui ne
 *   porte que AR_Connexys_Matrix_Picker n'a aucun droit sur AR_General_Setting__c : la lecture en mode utilisateur levait
 *   une QueryException, avalée ci-dessous, et la vraie matrice n'était jamais recopiée. Lectures seules, aucune écriture élargie.
 * - Une erreur technique est journalisée et l'étape s'enregistre normalement ; seuls les refus métier D/D' bloquent.
 */
public class AR_StepMatrixLinkHandler {
    private static final String INTERVIEW2_RT_DEV_NAME = 'Interview2';

    public class StepMatrixLinkException extends Exception {
    }

    // Point d'injection de test : provoque une erreur technique à l'intérieur du bloc protégé.
    @testVisible
    private static Boolean throwExceptionForTest = false;

    // Dernière erreur technique avalée par le catch (lecture en test uniquement).
    @testVisible
    private static String lastTechnicalErrorForTest;

    private static Id INTERVIEW2_RT_ID;

    static {
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.cxsrec__cxsStep__c
            .getRecordTypeInfosByDeveloperName()
            .get(INTERVIEW2_RT_DEV_NAME);
        INTERVIEW2_RT_ID = rtInfo != null ? rtInfo.getRecordTypeId() : null;
    }

    public static void handleStepMatrixLink(
        List<cxsrec__cxsStep__c> newSteps,
        Map<Id, cxsrec__cxsStep__c> oldMap
    ) {
        if (INTERVIEW2_RT_ID == null) {
            return;
        }

        List<cxsrec__cxsStep__c> interview2Steps = filterToInterview2(newSteps);
        if (interview2Steps.isEmpty()) {
            return;
        }

        try {
            List<AR_General_Setting__c> settingsList = [
                SELECT AR_StepMatrixLink_Auto_Link_Enabled__c, AR_StepMatrixLink_Check_Enabled__c,
                       AR_StepMatrixLink_Require_Empty_Enabled__c
                FROM AR_General_Setting__c
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            processSteps(interview2Steps, oldMap, settingsList.isEmpty() ? null : settingsList[0]);
        } catch (Exception e) {
            lastTechnicalErrorForTest = e.getTypeName() + ' — ' + e.getMessage() + ' — ' + e.getStackTraceString();
            // Journaliser : une erreur technique ne doit jamais empêcher l'enregistrement de l'étape
            // (repli fail-open voulu, le seul refus possible est le refus métier D/D' posé par addError).
            System.debug(LoggingLevel.ERROR, 'AR_StepMatrixLinkHandler : ' + e.getTypeName() + ' — ' + e.getMessage()
                + ' — ' + e.getStackTraceString());
        }
    }

    private static List<cxsrec__cxsStep__c> filterToInterview2(List<cxsrec__cxsStep__c> steps) {
        List<cxsrec__cxsStep__c> filtered = new List<cxsrec__cxsStep__c>();
        for (cxsrec__cxsStep__c step : steps) {
            if (step.RecordTypeId == INTERVIEW2_RT_ID) {
                filtered.add(step);
            }
        }
        return filtered;
    }

    private static void processSteps(
        List<cxsrec__cxsStep__c> interview2Steps,
        Map<Id, cxsrec__cxsStep__c> oldMap,
        AR_General_Setting__c settings
    ) {
        if (throwExceptionForTest) {
            throw new StepMatrixLinkException('Erreur technique simulée (test)');
        }

        Boolean autoLinkOn = settings != null && settings.AR_StepMatrixLink_Auto_Link_Enabled__c == true;
        Boolean checkOn = settings != null && settings.AR_StepMatrixLink_Check_Enabled__c == true;
        Boolean requireEmptyOn = settings != null && settings.AR_StepMatrixLink_Require_Empty_Enabled__c == true;
        Boolean linkOrCheck = autoLinkOn || checkOn;

        // Entrées choisies à copier : à la création, ou quand le champ de la popup change.
        Set<Id> chosenIds = new Set<Id>();
        for (cxsrec__cxsStep__c step : interview2Steps) {
            if (step.AR_Validated_Matrix__c != null && isInsertOrMatrixChanged(step, oldMap)) {
                chosenIds.add(step.AR_Validated_Matrix__c);
            }
        }

        // Une requête pour toutes les candidatures du lot, une pour toutes les entrées utiles du lot.
        // Chaque étape lit SA candidature par l'Id de sa candidature (jamais par l'Id de l'étape, nul à l'insert).
        Map<Id, cxsrec__cxsJob_application__c> jobAppsMap = new Map<Id, cxsrec__cxsJob_application__c>();
        Set<Id> positionIds = new Set<Id>();
        if (linkOrCheck) {
            Set<Id> jobAppIds = new Set<Id>();
            for (cxsrec__cxsStep__c step : interview2Steps) {
                if (step.cxsrec__Job_application__c != null) {
                    jobAppIds.add(step.cxsrec__Job_application__c);
                }
            }
            if (!jobAppIds.isEmpty()) {
                jobAppsMap = queryJobApplications(jobAppIds);
                for (cxsrec__cxsJob_application__c jobApp : jobAppsMap.values()) {
                    if (jobApp.cxsrec__Position__c != null) {
                        positionIds.add(jobApp.cxsrec__Position__c);
                    }
                }
            }
        }
        if (chosenIds.isEmpty() && positionIds.isEmpty()) {
            return;
        }

        Map<Id, AR_Validated_Matrix__c> entriesById = new Map<Id, AR_Validated_Matrix__c>();
        Map<Id, List<AR_Validated_Matrix__c>> entriesByPosition = new Map<Id, List<AR_Validated_Matrix__c>>();
        for (AR_Validated_Matrix__c entry : queryEntries(positionIds, chosenIds)) {
            entriesById.put(entry.Id, entry);
            if (entry.AR_Position__c != null) {
                if (!entriesByPosition.containsKey(entry.AR_Position__c)) {
                    entriesByPosition.put(entry.AR_Position__c, new List<AR_Validated_Matrix__c>());
                }
                entriesByPosition.get(entry.AR_Position__c).add(entry);
            }
        }

        for (cxsrec__cxsStep__c step : interview2Steps) {
            cxsrec__cxsStep__c oldStep = oldMap?.get(step.Id);
            Boolean isInsert = oldStep == null;
            Boolean matrixChanged = !isInsert && oldStep.AR_Validated_Matrix__c != step.AR_Validated_Matrix__c;
            Boolean matrixCleared = matrixChanged && step.AR_Validated_Matrix__c == null;

            if (linkOrCheck) {
                cxsrec__cxsJob_application__c jobApp = jobAppsMap.get(step.cxsrec__Job_application__c);
                if (jobApp != null && jobApp.cxsrec__Position__c != null) {
                    List<AR_Validated_Matrix__c> positionEntries = entriesByPosition.get(jobApp.cxsrec__Position__c);
                    if (positionEntries == null) {
                        positionEntries = new List<AR_Validated_Matrix__c>();
                    }

                    if (autoLinkOn && step.AR_Validated_Matrix__c == null && (isInsert || matrixCleared)) {
                        autoLink(step, positionEntries, jobApp);
                    }

                    // Une étape existante modifiée sur un autre champ n'est jamais contrôlée : seul l'enregistrement
                    // d'une nouvelle valeur du champ (ou la création) l'est.
                    if (checkOn && (isInsert || matrixChanged)) {
                        validate(step, positionEntries, requireEmptyOn);
                    }
                }
            }

            copyRealMatrix(step, entriesById, isInsert || matrixChanged);
        }
    }

    private static Boolean isInsertOrMatrixChanged(cxsrec__cxsStep__c step, Map<Id, cxsrec__cxsStep__c> oldMap) {
        cxsrec__cxsStep__c oldStep = oldMap?.get(step.Id);
        return oldStep == null || oldStep.AR_Validated_Matrix__c != step.AR_Validated_Matrix__c;
    }

    // Recopie la vraie matrice de l'entrée choisie. Seulement si une entrée est posée : on n'efface jamais
    // AR_Price_Matrix__c (la purge d'une entrée vide le champ de la popup, pas la référence durable).
    // L'entrée posée par C est lue dans la même requête que les entrées du besoin.
    private static void copyRealMatrix(
        cxsrec__cxsStep__c step,
        Map<Id, AR_Validated_Matrix__c> entriesById,
        Boolean applicable
    ) {
        if (!applicable || step.AR_Validated_Matrix__c == null) {
            return;
        }
        AR_Validated_Matrix__c entry = entriesById.get(step.AR_Validated_Matrix__c);
        if (entry != null && entry.AR_Price_Matrix__c != null) {
            step.AR_Price_Matrix__c = entry.AR_Price_Matrix__c;
        }
    }

    private static Map<Id, cxsrec__cxsJob_application__c> queryJobApplications(Set<Id> jobAppIds) {
        return new Map<Id, cxsrec__cxsJob_application__c>(
            [SELECT Id, cxsrec__Position__c, cxsrec__Candidate__c FROM cxsrec__cxsJob_application__c WHERE Id IN :jobAppIds WITH SYSTEM_MODE]
        );
    }

    // Entrées des besoins du lot + entrées choisies par les étapes (une seule requête).
    private static List<AR_Validated_Matrix__c> queryEntries(Set<Id> positionIds, Set<Id> chosenIds) {
        return [
            SELECT Id, Name, AR_Position__c, AR_Price_Matrix__c, AR_Price_Matrix__r.AR_Job_Application__c
            FROM AR_Validated_Matrix__c
            WHERE AR_Position__c IN :positionIds OR Id IN :chosenIds
            WITH SYSTEM_MODE
            ORDER BY Name, Id
        ];
    }

    private static void autoLink(
        cxsrec__cxsStep__c step,
        List<AR_Validated_Matrix__c> positionEntries,
        cxsrec__cxsJob_application__c jobApp
    ) {
        if (positionEntries.size() == 1) {
            step.AR_Validated_Matrix__c = positionEntries[0].Id;
        } else if (positionEntries.size() > 1) {
            AR_Validated_Matrix__c byCandidate = findEntryByCandidate(positionEntries, jobApp);
            if (byCandidate != null) {
                step.AR_Validated_Matrix__c = byCandidate.Id;
            }
        }
    }

    // Affinage secondaire, jamais bloquant : une seule entrée dont la matrice porte cette candidature, sinon aucun choix.
    private static AR_Validated_Matrix__c findEntryByCandidate(
        List<AR_Validated_Matrix__c> entries,
        cxsrec__cxsJob_application__c jobApp
    ) {
        AR_Validated_Matrix__c found = null;
        for (AR_Validated_Matrix__c entry : entries) {
            if (entry.AR_Price_Matrix__r != null && entry.AR_Price_Matrix__r.AR_Job_Application__c == jobApp.Id) {
                if (found != null) {
                    return null;
                }
                found = entry;
            }
        }
        return found;
    }

    private static void validate(
        cxsrec__cxsStep__c step,
        List<AR_Validated_Matrix__c> positionEntries,
        Boolean requireEmptyOn
    ) {
        if (step.AR_Validated_Matrix__c == null) {
            if (requireEmptyOn) {
                if (positionEntries.isEmpty()) {
                    step.addError('AR_Validated_Matrix__c', messageNoMatrix());
                } else if (positionEntries.size() >= 2) {
                    step.addError(
                        'AR_Validated_Matrix__c',
                        AR_I18n.format(Label.AR_Msg_STP_SeveralValidated, new List<Object>{ namesOf(positionEntries) })
                    );
                }
            }
            return;
        }

        for (AR_Validated_Matrix__c entry : positionEntries) {
            if (entry.Id == step.AR_Validated_Matrix__c) {
                return;
            }
        }

        if (positionEntries.isEmpty()) {
            step.addError('AR_Validated_Matrix__c', messageNoMatrix());
        } else {
            step.addError(
                'AR_Validated_Matrix__c',
                AR_I18n.format(Label.AR_Msg_STP_MatrixMismatch, new List<Object>{ namesOf(positionEntries) })
            );
        }
    }

    private static String messageNoMatrix() {
        return Label.AR_Msg_STP_NoValidatedMatrix;
    }

    // Les libellés d'entrée contiennent déjà une virgule (« ACME - Jean, V2 (…) ») : séparateur « ; ».
    private static String namesOf(List<AR_Validated_Matrix__c> entries) {
        List<String> names = new List<String>();
        for (AR_Validated_Matrix__c entry : entries) {
            names.add(entry.Name);
        }
        names.sort();
        return String.join(names, ' ; ');
    }
}