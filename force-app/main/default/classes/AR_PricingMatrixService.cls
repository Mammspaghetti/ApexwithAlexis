/**
 * Service de calcul et de cycle de vie sur AR_Price_Matrix__c. Orchestration + accès données autour
 * du moteur pur AR_PricingCalculator. `with sharing` : respecte le modèle de partage Private de la
 * matrice.
 *
 * Le top10 comparables (moteur de scoring algorithmique, cf. CLAUDE.md périmètre Lot 1) n'est pas
 * encore disponible : le pipeline l'initialise à 0 (AR_PricingCalculator.calcThresholds prend alors
 * uniquement idéal×1.10 pour le seuil Top 10 %). À brancher sur le futur service de comparables.
 */
public with sharing class AR_PricingMatrixService {
  /** Valeur technique de la séniorité « Défaut » du référentiel Nearshore, indépendante de la langue. */
  public static final String NEARSHORE_DEFAULT_SENIORITY = 'DEFAULT';

  // Session 88 : statuts clos à exclure de la recherche (searchPositions)
  private static final Set<String> EXCLUDED_STATUSES = new Set<String>{
    'Gagné',
    'Perdu',
    'Supprimé'
  };

  /**
   * Payload de simulation serveur, sans DML — pour un calcul avant création de la matrice
   * ou une vérification serveur ponctuelle. Le temps réel côté LWC (arPricingEngine, session 4)
   * est calculé en JS ; seul le clic « Valider » repasse par recalculate()/validate().
   */
  public class SimulateRequest {
    @AuraEnabled
    public String contractType;
    @AuraEnabled
    public Decimal annualSalary;
    @AuraEnabled
    public Decimal cjmBeforeMarkup;
    @AuraEnabled
    public Decimal markupApplied;
    @AuraEnabled
    public Decimal cjmVie;
    @AuraEnabled
    public Decimal cjmNearshore;
    @AuraEnabled
    public Decimal feeIk;
    @AuraEnabled
    public Decimal feeMeals;
    @AuraEnabled
    public Decimal feeLodging;
    @AuraEnabled
    public Decimal feeOmOther;
    @AuraEnabled
    public Decimal gratuityDays;
    @AuraEnabled
    public Decimal feeComputer;
    @AuraEnabled
    public Decimal feePhone;
    @AuraEnabled
    public Decimal feeMonthlyOther;
    @AuraEnabled
    public Decimal feeTraining;
    @AuraEnabled
    public Decimal feeEpi;
    @AuraEnabled
    public Decimal feeOfiiTax;
    @AuraEnabled
    public Decimal feeOther;
    @AuraEnabled
    public Decimal numberOfDays; // session 121b : diviseur des frais ponctuels
    @AuraEnabled
    public Decimal plannedLeaveDays;
    @AuraEnabled
    public Decimal rfaPercent;
    @AuraEnabled
    public Decimal proposedTjm;
    @AuraEnabled
    public Decimal top10Comparables;
    @AuraEnabled
    public Id accountIdForCorridor;
    @AuraEnabled
    public Id entityIdForCorridor;
  }

  /** Zone 1 — contexte affaire en lecture seule, mappé depuis le besoin Connexys (docs/01-decouverte-org.md §1.1). */
  public class PositionContext {
    // Session 167 : false quand le besoin n'est pas visible de l'utilisateur courant (partage) — le
    // contexte est alors vide ; l'écran affiche un bandeau et bloque toute écriture.
    @AuraEnabled
    public Boolean accessible = true;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String accountCountry;
    // Session 141 : ville de facturation du compte résolu (même chaîne que accountId), source du
    // pré-remplissage « Site client » de la matrice. Volontairement absent de la requête
    // searchPositions (cacheable, une ligne par frappe) : lu ici, à la sélection du besoin.
    @AuraEnabled
    public String accountCity;
    @AuraEnabled
    public String positionName;
    // Bandeau récapitulatif "{profil} — {région} — {secteur}" (session 17, maquette pricing-tool.html:1877-1880).
    // Aucun champ Connexys ne s'appelle littéralement "région" ou "secteur" : TP_Secteur_d_activit__c
    // (nom le plus proche) est vide sur 100% des besoins de l'org (cf. docs/17-contexte-affaire.md) ;
    // TP_P_rim_tre__c (Périmètre, ~99,99% peuplé) et TP_Business_Line__c (~60% peuplé) sont retenus à
    // la place, choix data-driven documenté plutôt qu'un simple appariement de libellé.
    @AuraEnabled
    public String perimetre;
    @AuraEnabled
    public String businessLine;
    // Session 81 : date de création du besoin pour le panneau de détail
    @AuraEnabled
    public DateTime createdDate;
    // Session 85 : type de contrat du besoin (CDD/CDI/VIE/Stage/Alternance)
    @AuraEnabled
    public String contractType;
    // Session 88 : statut réel du besoin pour badge coloré et filtrage
    @AuraEnabled
    public String status;
    // Manager du besoin : lookup Contact depuis TP_Manager__c (pré-remplissage matrice)
    @AuraEnabled
    public Id managerContactId;
    @AuraEnabled
    public String managerName;
    // Contact du besoin : lookup Contact depuis AB_Contact__c
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String contactName;
    // Dates mission : pré-remplissage matrice
    @AuraEnabled
    public Date startDate;
    // Session 141 : plus de endDate ici. Elle reprenait cxsrec__Channel_Internet_end_date__c, date de
    // fin de DIFFUSION de l'annonce et non de la mission ; la date de fin proposée par l'écran est
    // désormais le 31/12 de l'année de début (cf. arPriceMatrixSimulator.defaultEndDateFor).
    // Session 184b : « Estimated End Date » du besoin (AB_Estimated_End_Date__c) — prioritaire sur
    // le 31/12 quand elle est renseignée, uniquement à la création simple d'une matrice.
    @AuraEnabled
    public Date estimatedEndDate;
  }

  /** Contexte consultant pré-remplissage (session 65) : valeurs extraites de la fiche consultant à
   * la sélection explicite. Trois listes sans duplication :
   * - `filled` : noms des champs effectivement remplis (source non vide, valeur retenue)
   * - `sourceEmpty` : noms des champs dont la source existe sur le consultant mais est vide
   * - `unreadable` : noms des champs non lisibles (FLS refusant l'accès) — le narratif du bandeau les
   *   reconnaîtra comme « N informations non lisibles avec vos droits » plutôt que silencieusement
   *   absentes. Cf. session 65 §2, doctrine de session 34 (afficher / journaliser / avaler, jamais
   *   le quatrième cas muet).
   */
  public class ConsultantContext {
    @AuraEnabled
    public String contractType;
    @AuraEnabled
    public String seniorityLevel;
    @AuraEnabled
    public List<String> filled = new List<String>();
    @AuraEnabled
    public List<String> sourceEmpty = new List<String>();
    @AuraEnabled
    public List<String> unreadable = new List<String>();
  }

  /** Entrée Zone 2 / Zone 3 du simulateur — brouillon, validation et demande de dérogation partagent ce payload. */
  public class MatrixInput {
    // Périodes de frais ajoutées (docs/239) : JSON en String — Aura n'alimente pas une classe Apex
    // définie par l'utilisateur, cf. CLAUDE.md. Désérialisé par parseFeePeriods.
    @AuraEnabled
    public String feePeriods;
    // Périodes de TJM ajoutées (docs/254) : même forme que feePeriods, JSON en String, désérialisé par parseTjmPeriods.
    @AuraEnabled
    public String tjmPeriods;
    // Périodes de salaire ajoutées (CDI/CDD) : même forme, JSON en String, désérialisé par parseSalaryPeriods.
    @AuraEnabled
    public String salaryPeriods;
    // Régie sans régule (docs/265) : le client envoie l'interrupteur, la base de jours facturés et les jours produits
    // par mois (JSON {"2027-02": 9, ...}) ; le serveur reconstruit ouvrés et vendus. rplsrPlan = plan complet, en sortie.
    @AuraEnabled
    public Boolean rplsrEnabled;
    @AuraEnabled
    public Decimal rplsrDaysPerMonth;
    @AuraEnabled
    public String rplsrProduced;
    @AuraEnabled
    public String rplsrPlan;
    @AuraEnabled
    public Id matrixId;
    @AuraEnabled
    public Id positionId;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String contractType;
    @AuraEnabled
    public Decimal annualSalary;
    @AuraEnabled
    public Decimal cjmBeforeMarkup;
    @AuraEnabled
    public Decimal markupApplied;
    @AuraEnabled
    public Decimal cjmVie;
    @AuraEnabled
    public Decimal cjmNearshore;
    @AuraEnabled
    public Decimal feeIk;
    @AuraEnabled
    public Decimal feeMeals;
    @AuraEnabled
    public Decimal feeLodging;
    @AuraEnabled
    public Decimal feeOmOther;
    @AuraEnabled
    public Decimal gratuityDays;
    @AuraEnabled
    public Decimal feeComputer;
    @AuraEnabled
    public Decimal feePhone;
    @AuraEnabled
    public Decimal feeMonthlyOther;
    @AuraEnabled
    public Decimal feeTraining;
    @AuraEnabled
    public Decimal feeEpi;
    @AuraEnabled
    public Decimal feeOfiiTax;
    @AuraEnabled
    public Decimal feeOther;
    @AuraEnabled
    public Decimal rfaPercent;
    @AuraEnabled
    public Decimal proposedTjm;
    // Prix de négociation 2 et 3 : indicatifs, hors calcul serveur et hors workflow.
    @AuraEnabled
    public Decimal negoPrice2;
    @AuraEnabled
    public Decimal negoPrice3;
    // Grille client : le tarif est imposé, prix intermédiaire et plancher non demandés.
    @AuraEnabled
    public Boolean clientGrid;
    // Zone 1 — champs mission (session 17) : entité/consultant/site saisis librement, dates et jours
    // ouvrés dérivés côté LWC (arPricingEngine n'en a pas besoin, cf. docs/17-contexte-affaire.md).
    @AuraEnabled
    public String entity;
    // Session 132 : Nom de la fiche d'entité (lecture seule, affichage) — `entity` porte l'Id de la fiche.
    @AuraEnabled
    public String entityName;
    // Session 54 : AR_Consultant_Name__c (texte libre) est remplacé par un lookup vers
    // cxsrec__cxsCandidate__c. consultantName reste un champ de SORTIE uniquement — écho en lecture
    // seule de la valeur historique de AR_Consultant_Name__c (6 matrices sur 47 au 05/09/2026,
    // cf. docs/53-sources-ptf.md §2) — buildMatrixFromInput ne l'écrit plus jamais. consultantId est
    // le seul champ éditable désormais ; consultantLabel est son affichage résolu (sortie uniquement,
    // évite un aller-retour serveur supplémentaire pour ne connaître que le Name du lookup courant).
    @AuraEnabled
    public String consultantName;
    @AuraEnabled
    public Id consultantId;
    @AuraEnabled
    public String consultantLabel;
    // Suggestion de pré-remplissage (sortie uniquement, jamais appliquée automatiquement) depuis
    // AR_Job_Application__c.cxsrec__Candidate__c quand ce champ est renseigné et qu'aucun consultant
    // n'est encore sélectionné sur la matrice — cf. docs/54-lookup-consultant.md §0bis.
    @AuraEnabled
    public Id suggestedConsultantId;
    @AuraEnabled
    public String suggestedConsultantLabel;
    @AuraEnabled
    public String clientSite;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Decimal numberOfDays;
    // Congés prévus : retranchés des jours de mission (jours facturables).
    @AuraEnabled
    public Decimal plannedLeaveDays;
    // Pays retenus dans les référentiels VIE/Nearshore (session 18) : conservés même si l'utilisateur
    // surcharge ensuite cjmVie/cjmNearshore à la main — sans ce lookup, on perd la traçabilité du pays
    // dès qu'une surcharge a lieu, et le snapshot de version devient inexploitable pour un audit.
    @AuraEnabled
    public Id vieCountryId;
    @AuraEnabled
    public Id nearshoreCountryId;
    // Palier de séniorité : optionnel, resserre les repères marché (AR_ComparablesService).
    // Valeur du picklist cxsrec__cxsCandidate__c.TP_Seniority__c (record type Consultant) — le LWC
    // n'envoie ici que des valeurs déjà filtrées par record type, cf. arPriceMatrixSimulator.
    @AuraEnabled
    public String seniorityLevel;
    @AuraEnabled
    public String status; // sortie uniquement (getMatrixInput) ; ignoré en entrée de saveDraft/validate
    @AuraEnabled
    public String creatorName; // sortie uniquement — Zone 1 "Propriétaire" = créateur de la matrice, pas le owner du besoin
    // Sortie uniquement (getMatrixInput) : dernier calcul persisté sur l'enregistrement (session
    // 23b). Sur une matrice décidée (non Brouillon), le LWC doit afficher CES valeurs plutôt que de
    // recalculer avec le corridor/référentiel courant — sinon un changement d'administration fait
    // dériver rétroactivement l'affichage d'une décision déjà prise. cjm/feeOmPerDay/
    // feePonctuelsPerDay/markupCalcule/markupMismatch restent null : non stockés sur la matrice,
    // hors périmètre de ce correctif (cf. docs/23b, seuls seuils/segment/MC2 sont concernés).
    @AuraEnabled
    public AR_PricingResult storedResult;
    // Sortie uniquement (getMatrixInput, session 24) : date d'effet de la ligne AR_Currency_Rate__c
    // dont le taux a été figé dans storedResult.currencyRateApplied. Hors de AR_PricingResult
    // (donnée de résolution, pas un résultat de calcul) — null pour une matrice EUR.
    @AuraEnabled
    public Date currencyRateEffectiveDate;
    // Sortie uniquement (getMatrixInput) : MC2 % de la matrice amendée, renseignée pour un avenant en
    // Brouillon seulement. Sert à l'écran à choisir entre Valider et la demande de dérogation (la règle de
    // l'avenant compare à cette MC2, pas au plancher) ; null pour toute autre matrice.
    @AuraEnabled
    public Decimal avenantMc2Before;
    // Sortie uniquement (getMatrixInput, session 282) : droit de modification réel de l'utilisateur
    // (UserRecordAccess.HasEditAccess). false = matrice vue par partage d'agence (lecture seule à l'écran).
    @AuraEnabled
    public Boolean canEdit;
    // Sortie uniquement (getMatrixInput, session 282) : nom du propriétaire, pour le bandeau de lecture seule.
    @AuraEnabled
    public String ownerName;
  }

  /** Option de liste générique (Zone 1 « Entité » : value = Id de la fiche AR_PTF_Entity_Referential__c). */
  public class PicklistOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    // Session 141 : renseigné uniquement par getEntityOptionsWithPtfReadiness (pays de la fiche
    // d'entité, null si non saisi) ; toujours null pour les autres consommateurs de ce DTO.
    @AuraEnabled
    public String country;
  }

  /**
   * Niveau entité de la cascade coefficient/jours travaillés (session 48), pour le miroir JS
   * temps réel côté arPriceMatrixSimulator — sans lui, changer l'entité dans le formulaire ne
   * mettrait à jour l'aperçu qu'au prochain aller-retour serveur (saveDraftInput), en désaccord
   * silencieux avec ce qui est réellement enregistré. coefficient/workingDays null = pas de
   * surcharge pour cette entité, le client retombe alors sur le niveau paramètre général/constante
   * déjà porté par PricingSettingsDto.
   */
  public class EntityPricingDefaultDto {
    @AuraEnabled
    public Id entityId;
    @AuraEnabled
    public String entityName;
    @AuraEnabled
    public Decimal coefficient;
    @AuraEnabled
    public Decimal workingDays;
    // Session 141 : pays de la fiche, y compris pour une entité désactivée (absente des options de
    // sélection) — sert à l'affichage d'une matrice existante qui référence une telle entité.
    @AuraEnabled
    public String country;
  }

  /**
   * Option de pays des référentiels VIE/Nearshore (session 18) : ni drapeau ni note, ces champs
   * n'existent pas sur AR_VIE_Referential__c/AR_Nearshore_Referential__c (seuls Name et le montant
   * journalier existent, cf. session 2) — contrairement à la maquette qui les a en dur dans son mock.
   * Documenté dans docs/18-referentiels-statuts.md plutôt qu'ajouté sans base réelle.
   */
  public class ReferentialCountryOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public Decimal cjm;
    // Devise du montant journalier (session 24) — le référentiel n'est plus implicitement en euros.
    @AuraEnabled
    public String currencyCode;
    // Séniorité de la ligne Nearshore ; DEFAULT = tarif du pays à défaut de ligne exacte.
    @AuraEnabled
    public String seniority;
  }

  /** Résultat de resolveRecordContext : distingue ouverture depuis un besoin (nouvelle matrice) ou une matrice existante. */
  public class RecordContext {
    @AuraEnabled
    public Id positionId;
    @AuraEnabled
    public Id matrixId;
  }

  public class MatrixSaveResult {
    @AuraEnabled
    public Id matrixId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public AR_PricingResult calculation;
    // Plan de la régie sans régule tel qu'écrit par le serveur (JSON versionné), null hors mode.
    @AuraEnabled
    public String rplsrPlan;
    // Renseigné quand un e-mail ou une notification n'est pas parti ; l'action métier reste faite.
    @AuraEnabled
    public String notificationWarningDetail;
  }

  public class DerogationRequest {
    @AuraEnabled
    public MatrixInput matrixInput;
    // Commentaire obligatoire (session 220) : texte libre complémentaire aux motifs, jamais un
    // substitut à derogationReasonIds (décision client du 10/08/2026 : fin de la saisie libre
    // comme seul motif, cf. CLAUDE.md).
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public Id selectedValidatorId;
    // Motifs standardisés sélectionnés (AR_Reason__c), au moins un obligatoire — remplace
    // l'ancien contrôle sur `reason` non vide.
    @AuraEnabled
    public List<Id> derogationReasonIds;
  }

  public class ValidatorOption {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String userName;
    /** Rôles de la personne dans la chaîne du propriétaire (« RA, DA ») ; null pour le valideur de test. */
    @AuraEnabled
    public String role;
  }

  /** Seuils corridor (grand compte ou défaut), exposés pour le miroir JS arPricingEngine côté LWC. */
  public class ThresholdPercentsDto {
    @AuraEnabled
    public Decimal floorPercent;
    @AuraEnabled
    public Decimal targetPercent;
    @AuraEnabled
    public Decimal idealPercent;
    // Session 252 : ACCOUNT ou ENTITY (jamais null dans ce cas), entityName renseigné pour ENTITY.
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String entityName;
  }

  /** Paramètres AR_Settings__mdt + défauts du moteur, exposés pour que le miroir JS reste synchronisé. */
  public class PricingSettingsDto {
    // Session 237 : montant de dispense (€) lu tel quel ; null = règle désactivée, jamais substitué.
    @AuraEnabled
    public Decimal derogationWaiverAmount;
    @AuraEnabled
    public Decimal workingDaysPerYear;
    @AuraEnabled
    public Decimal markupPercent;
    @AuraEnabled
    public Decimal markupMax;
    @AuraEnabled
    public Decimal floorPercentDefault;
    @AuraEnabled
    public Decimal targetPercentDefault;
    @AuraEnabled
    public Decimal idealPercentDefault;
    // Coefficients CDI/CDD (session 28) : nulls interprétés par le miroir JS comme
    // AR_PricingCalculator.CONTRACT_COEFFICIENT_DEFAULT (2,02), même défaut que côté Apex.
    @AuraEnabled
    public Decimal cdiCoefficient;
    @AuraEnabled
    public Decimal cddCoefficient;
    // Taxe OFII (Paramètres généraux) : taux en % du salaire mensuel brut et plafond en euros. Un des deux
    // null = calcul indisponible, la liste de la matrice ne propose que N/A.
    @AuraEnabled
    public Decimal ofiiTaxRate;
    @AuraEnabled
    public Decimal ofiiTaxCapEur;
  }

  @AuraEnabled
  public static AR_PricingResult simulate(SimulateRequest req) {
    try {
      AR_PricingCalculator.Context ctx = toContext(req);
      AR_PricingCalculator.ThresholdPercents customPcts = resolveCorridorPercents(
        req.accountIdForCorridor,
        req.entityIdForCorridor
      );
      return AR_PricingCalculator.compute(
        ctx,
        req.rfaPercent,
        req.proposedTjm,
        req.top10Comparables,
        customPcts
      );
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_SimulationAction);
    }
  }

  @AuraEnabled
  public static AR_PricingResult recalculate(Id matrixId) {
    try {
      List<AR_Price_Matrix__c> mRows = [
        SELECT
          Id,
          AR_Contract_Type__c,
          AR_Annual_Salary__c,
          AR_CJM_Before_Markup__c,
          AR_Markup_Applied__c,
          AR_CJM_VIE__c,
          AR_CJM_Nearshore__c,
          AR_Fee_IK__c,
          AR_Fee_Meals__c,
          AR_Fee_Lodging__c,
          AR_Fee_OM_Other__c,
          AR_Fee_Periods__c,
          AR_TJM_Periods__c,
          AR_Salary_Periods__c,
          AR_RPLSR_Enabled__c,
          AR_RPLSR_Days_Sold__c,
          AR_RPLSR_Days_Produced__c,
          AR_Gratuity_Days__c,
          AR_Fee_Computer__c,
          AR_Fee_Phone__c,
          AR_Fee_Monthly_Other__c,
          AR_Fee_Training__c,
          AR_Fee_EPI__c,
          AR_Fee_OFII_Tax__c,
          AR_Fee_Other__c,
          AR_RFA_Percent__c,
          AR_Proposed_TJM__c,
          AR_Account_Country__c,
          AR_Currency__c,
          AR_Seniority__c,
          AR_Entity_Ref__c,
          AR_Number_Of_Days__c,
          AR_Planned_Leave_Days__c,
          AR_Position__r.cxsrec__Account__c
        FROM AR_Price_Matrix__c
        WHERE Id = :matrixId
        LIMIT 1
      ];
      AR_Price_Matrix__c m = requireMatrix(mRows);
      AR_PricingResult result = calculateAndPopulate(m, resolveAccountId(m.AR_Position__c));
      Database.update(m, AccessLevel.SYSTEM_MODE);
      return result;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_RecalcAction);
    }
  }

  /**
   * Point d'entrée du LWC : recordId peut être un besoin (quick action, nouvelle matrice) ou une
   * matrice existante (record page, édition d'un Brouillon). Distingue les deux sans supposer le
   * préfixe d'Id côté client.
   */
  @AuraEnabled(cacheable=true)
  public static RecordContext resolveRecordContext(Id anyId) {
    RecordContext ctx = new RecordContext();
    if (anyId.getSObjectType() == AR_Price_Matrix__c.SObjectType) {
      List<AR_Price_Matrix__c> mRows = [
        SELECT AR_Position__c
        FROM AR_Price_Matrix__c
        WHERE Id = :anyId
        LIMIT 1
      ];
      AR_Price_Matrix__c m = requireMatrix(mRows);
      ctx.matrixId = anyId;
      ctx.positionId = m.AR_Position__c;
    } else {
      ctx.positionId = anyId;
    }
    return ctx;
  }

  /**
   * Session 184a : nombre de matrices déjà portées par un besoin, visibles de l'utilisateur
   * (partage respecté). Sert à prévenir, à l'arrivée depuis le bouton du besoin, qu'une nouvelle
   * matrice va s'ajouter aux existantes (jamais de doublon silencieux). Non `cacheable` : la
   * réponse doit refléter l'état réel à chaque arrivée.
   */
  @AuraEnabled
  public static Integer countMatricesForPosition(Id positionId) {
    try {
      return [
        SELECT COUNT()
        FROM AR_Price_Matrix__c
        WHERE AR_Position__c = :positionId
        WITH USER_MODE
      ];
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_CountMatricesAction);
    }
  }

  /**
   * Matrice introuvable (supprimée) ou non accessible (partage retiré) pour un Id venu de l'écran : message métier
   * unique, jamais « List has no rows for assignment to SObject » (session 291c).
   */
  private static AR_Price_Matrix__c requireMatrix(List<AR_Price_Matrix__c> rows) {
    if (rows == null || rows.isEmpty()) {
      throw newAuraException(Label.AR_Msg_PM_MatrixGone);
    }
    return rows[0];
  }

  private static Id requireMatrixOwner(Id matrixId) {
    return requireMatrix([SELECT OwnerId FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1]).OwnerId;
  }

  /** Recharge les champs saisissables d'une matrice existante (édition d'un Brouillon). */
  @AuraEnabled(cacheable=true)
  public static MatrixInput getMatrixInput(Id matrixId) {
    MatrixInput input = loadMatrixInput(matrixId, true);
    applyAccess(input, matrixId);
    return input;
  }

  /**
   * Session 282 : droit de modification réel de l'utilisateur courant sur la matrice (partage : chaîne,
   * agence, viewAll/modifyAll) et nom du propriétaire. Jamais déduit côté client.
   */
  @TestVisible
  private static void applyAccess(MatrixInput input, Id matrixId) {
    input.canEdit = false;
    for (UserRecordAccess ura : [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :matrixId
      LIMIT 1
    ]) {
      input.canEdit = ura.HasEditAccess;
    }
    Id ownerId = requireMatrixOwner(matrixId);
    for (User u : [SELECT Name FROM User WHERE Id = :ownerId LIMIT 1]) {
      input.ownerName = u.Name;
    }
  }

  /**
   * `withAvenantBaseline` : joindre la MC2 de la matrice amendée (avenant en Brouillon). AR_AvenantService
   * la passe à false quand il vient de la calculer lui-même (un calcul complet coûte des dizaines de requêtes).
   */
  public static MatrixInput loadMatrixInput(Id matrixId, Boolean withAvenantBaseline) {
    List<AR_Price_Matrix__c> mRows = [
      SELECT
        Id,
        AR_Position__c,
        AR_Currency__c,
        AR_Contract_Type__c,
        AR_Annual_Salary__c,
        AR_CJM_Before_Markup__c,
        AR_Markup_Applied__c,
        AR_CJM_VIE__c,
        AR_CJM_Nearshore__c,
        AR_Fee_IK__c,
        AR_Fee_Meals__c,
        AR_Fee_Lodging__c,
        AR_Fee_OM_Other__c,
        AR_Fee_Periods__c,
        AR_TJM_Periods__c,
        AR_Salary_Periods__c,
        AR_RPLSR_Enabled__c,
        AR_RPLSR_Days_Per_Month__c,
        AR_RPLSR_Plan__c,
        AR_RPLSR_Days_Sold__c,
        AR_RPLSR_Days_Produced__c,
        AR_TJM_Weighted__c,
        AR_Gratuity_Days__c,
        AR_Fee_Computer__c,
        AR_Fee_Phone__c,
        AR_Fee_Monthly_Other__c,
        AR_Fee_Training__c,
        AR_Fee_EPI__c,
        AR_Fee_OFII_Tax__c,
        AR_Fee_Other__c,
        AR_RFA_Percent__c,
        AR_Proposed_TJM__c,
        AR_Nego_Price_2__c,
        AR_Nego_Price_3__c,
        AR_Client_Grid__c,
        AR_Entity_Ref__c,
        AR_Entity_Ref__r.Name,
        AR_Consultant_Name__c,
        AR_Consultant__c,
        AR_Consultant__r.Name,
        AR_Job_Application__c,
        AR_Job_Application__r.cxsrec__Candidate__c,
        AR_Job_Application__r.cxsrec__Candidate__r.Name,
        AR_Client_Site__c,
        AR_Start_Date__c,
        AR_End_Date__c,
        AR_Number_Of_Days__c,
        AR_Planned_Leave_Days__c,
        AR_VIE_Country__c,
        AR_Nearshore_Country__c,
        AR_Seniority__c,
        AR_Manager_Contact__c,
        AR_Status__c,
        AR_Version_Type__c,
        CreatedBy.Name,
        AR_Total_Daily_Cost__c,
        AR_TJM_Floor__c,
        AR_TJM_Target__c,
        AR_TJM_Ideal__c,
        AR_TJM_Top10__c,
        AR_MC2_Per_Day__c,
        AR_MC2_Percent__c,
        AR_Corridor_Segment__c,
        AR_Floor_Percent_Applied__c,
        AR_Target_Percent_Applied__c,
        AR_Ideal_Percent_Applied__c,
        AR_Corridor_Source__c,
        AR_Corridor_Entity_Name__c,
        AR_Contract_Coefficient_Applied__c,
        AR_Working_Days_Applied__c,
        AR_Currency_Rate_Applied__c,
        AR_Currency_Rate_Effective_Date__c,
        AR_TJM_EUR_Equivalent__c,
        AR_Total_Daily_Cost_EUR_Equivalent__c,
        AR_MC2_Per_Day_EUR_Equivalent__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    AR_Price_Matrix__c m = requireMatrix(mRows);
    MatrixInput input = new MatrixInput();
    input.matrixId = m.Id;
    input.positionId = m.AR_Position__c;
    input.currencyCode = m.AR_Currency__c;
    input.contractType = m.AR_Contract_Type__c;
    input.annualSalary = m.AR_Annual_Salary__c;
    input.cjmBeforeMarkup = m.AR_CJM_Before_Markup__c;
    input.markupApplied = m.AR_Markup_Applied__c;
    input.cjmVie = m.AR_CJM_VIE__c;
    input.cjmNearshore = m.AR_CJM_Nearshore__c;
    input.feeIk = m.AR_Fee_IK__c;
    input.feeMeals = m.AR_Fee_Meals__c;
    input.feeLodging = m.AR_Fee_Lodging__c;
    input.feeOmOther = m.AR_Fee_OM_Other__c;
    input.feePeriods = m.AR_Fee_Periods__c;
    input.tjmPeriods = m.AR_TJM_Periods__c;
    input.salaryPeriods = m.AR_Salary_Periods__c;
    input.rplsrEnabled = m.AR_RPLSR_Enabled__c;
    input.rplsrDaysPerMonth = m.AR_RPLSR_Days_Per_Month__c;
    input.rplsrPlan = m.AR_RPLSR_Plan__c;
    input.gratuityDays = m.AR_Gratuity_Days__c;
    input.feeComputer = m.AR_Fee_Computer__c;
    input.feePhone = m.AR_Fee_Phone__c;
    input.feeMonthlyOther = m.AR_Fee_Monthly_Other__c;
    input.feeTraining = m.AR_Fee_Training__c;
    input.feeEpi = m.AR_Fee_EPI__c;
    input.feeOfiiTax = m.AR_Fee_OFII_Tax__c;
    input.feeOther = m.AR_Fee_Other__c;
    input.rfaPercent = m.AR_RFA_Percent__c;
    input.proposedTjm = m.AR_Proposed_TJM__c;
    input.negoPrice2 = m.AR_Nego_Price_2__c;
    input.negoPrice3 = m.AR_Nego_Price_3__c;
    input.clientGrid = m.AR_Client_Grid__c == true;
    input.entity = m.AR_Entity_Ref__c;
    input.entityName = m.AR_Entity_Ref__r != null ? m.AR_Entity_Ref__r.Name : null;
    // Session 54 : consultantName reste la valeur historique lue seule (jamais réécrite) ;
    // consultantId/consultantLabel sont la paire éditable désormais sauvegardée.
    input.consultantName = m.AR_Consultant_Name__c;
    input.consultantId = m.AR_Consultant__c;
    input.consultantLabel = m.AR_Consultant__r != null ? m.AR_Consultant__r.Name : null;
    // Suggestion jamais automatique : uniquement quand aucun consultant n'est encore sélectionné et
    // que la candidature pressentie porte un candidat (0/47 matrices au 05/09/2026, cf. docs/53).
    if (
      m.AR_Consultant__c == null &&
      m.AR_Job_Application__r != null &&
      m.AR_Job_Application__r.cxsrec__Candidate__c != null
    ) {
      input.suggestedConsultantId = m.AR_Job_Application__r.cxsrec__Candidate__c;
      input.suggestedConsultantLabel = m.AR_Job_Application__r.cxsrec__Candidate__r.Name;
    }
    input.clientSite = m.AR_Client_Site__c;
    input.startDate = m.AR_Start_Date__c;
    input.endDate = m.AR_End_Date__c;
    input.numberOfDays = m.AR_Number_Of_Days__c;
    input.plannedLeaveDays = m.AR_Planned_Leave_Days__c;
    input.vieCountryId = m.AR_VIE_Country__c;
    input.nearshoreCountryId = m.AR_Nearshore_Country__c;
    input.seniorityLevel = m.AR_Seniority__c;
    input.status = m.AR_Status__c;
    input.creatorName = m.CreatedBy.Name;
    if (withAvenantBaseline && m.AR_Version_Type__c == 'Avenant' && m.AR_Status__c == 'Brouillon') {
      input.avenantMc2Before = AR_AvenantService.baselineMc2Percent(m.Id);
    }

    AR_PricingResult stored = new AR_PricingResult();
    stored.totalDailyCost = m.AR_Total_Daily_Cost__c;
    stored.tjmFloor = m.AR_TJM_Floor__c;
    stored.tjmTarget = m.AR_TJM_Target__c;
    stored.tjmIdeal = m.AR_TJM_Ideal__c;
    stored.tjmTop10 = m.AR_TJM_Top10__c;
    stored.mc2PerDay = m.AR_MC2_Per_Day__c;
    stored.mc2PercentHuman = m.AR_MC2_Percent__c;
    stored.corridorSegment = m.AR_Corridor_Segment__c;
    stored.floorPercentApplied = m.AR_Floor_Percent_Applied__c;
    stored.targetPercentApplied = m.AR_Target_Percent_Applied__c;
    stored.idealPercentApplied = m.AR_Ideal_Percent_Applied__c;
    stored.corridorSource = m.AR_Corridor_Source__c;
    stored.corridorEntityName = m.AR_Corridor_Entity_Name__c;
    stored.contractCoefficientApplied = m.AR_Contract_Coefficient_Applied__c;
    stored.workingDaysPerYearApplied = m.AR_Working_Days_Applied__c;
    stored.currencyRateApplied = m.AR_Currency_Rate_Applied__c;
    stored.tjmEurEquivalent = m.AR_TJM_EUR_Equivalent__c;
    stored.totalDailyCostEurEquivalent = m.AR_Total_Daily_Cost_EUR_Equivalent__c;
    stored.mc2PerDayEurEquivalent = m.AR_MC2_Per_Day_EUR_Equivalent__c;
    // Régie sans régule : ratio et coût piloté relus des résultats figés ; le « mode éteint » est recalculé du TJM et du coût unitaire.
    Decimal storedRatio = rplsrRatioOf(m);
    if (storedRatio != null) {
      stored.rplsrRatio = storedRatio;
      stored.totalDailyCostPiloted = m.AR_Total_Daily_Cost__c != null ? m.AR_Total_Daily_Cost__c * storedRatio : null;
      AR_PricingCalculator.MC2Result theoretical = AR_PricingCalculator.calcMC2(
        effectiveTjm(m), m.AR_Total_Daily_Cost__c, m.AR_RFA_Percent__c
      );
      stored.mc2PerDayTheoretical = theoretical.mc2PerDay;
      stored.mc2PercentTheoretical = (theoretical.mc2PercentFraction * 100).setScale(2, RoundingMode.HALF_UP);
    }
    input.storedResult = stored;
    input.currencyRateEffectiveDate = m.AR_Currency_Rate_Effective_Date__c;

    return input;
  }

  /**
   * Zone 1 "Entité House of ABY" : options bornées aux entités configurées et actives dans le
   * référentiel PTF (AR_PTF_Entity_Referential__c.AR_Active__c = true, administrable depuis le
   * panneau d'administration — session 46, remplace AR_PTF_Entity__mdt). Session 132 : cette liste
   * est la SEULE référence d'entité de l'application, aucun filtre par picklist ; value = Id de la
   * fiche. Une fiche désactivée n'est plus proposable à la création d'une matrice — la
   * désactivation ne bloque pas la génération PTF des matrices existantes qui la référencent déjà.
   *
   * Générique : consommée aussi par un écran SANS rapport avec la PTF (arAdminGeneralSettings,
   * exceptions de jours travaillés par entité) — ne rien y ajouter de spécifique à la PTF, cf.
   * getEntityOptionsWithPtfReadiness ci-dessous pour ça.
   */
  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getEntityOptions() {
    List<PicklistOption> options = new List<PicklistOption>();
    for (AR_PTF_Entity_Referential__c entity : [
      SELECT Id, Name
      FROM AR_PTF_Entity_Referential__c
      WHERE Name != NULL AND AR_Active__c = TRUE
      ORDER BY Name
    ]) {
      PicklistOption opt = new PicklistOption();
      opt.label = entity.Name;
      opt.value = entity.Id;
      options.add(opt);
    }
    return options;
  }

  /**
   * Entités actives proposées par le sélecteur de la matrice (arPriceMatrixSimulator, Zone 1),
   * avec leur pays. Le libellé est le nom de l'entité seul ; le blocage réel se fait à la
   * génération de la PTF (AR_PTFDataService.validationPrerequisites).
   */
  @AuraEnabled(cacheable=true)
  public static List<PicklistOption> getEntityOptionsWithPtfReadiness() {
    List<PicklistOption> options = new List<PicklistOption>();
    for (AR_PTF_Entity_Referential__c entity : [
      SELECT Id, Name, AR_Country__c
      FROM AR_PTF_Entity_Referential__c
      WHERE Name != NULL AND AR_Active__c = TRUE
      ORDER BY Name
    ]) {
      PicklistOption opt = new PicklistOption();
      opt.label = entity.Name;
      opt.value = entity.Id;
      opt.country = String.isBlank(entity.AR_Country__c) ? null : entity.AR_Country__c;
      options.add(opt);
    }
    return options;
  }

  /**
   * Coefficient/jours travaillés par entité (session 48), servis en une fois pour que le miroir JS
   * (arPriceMatrixSimulator.recompute) applique la même cascade entité → paramètre général →
   * constante que calculateAndPopulate côté Apex, sans aller-retour serveur à chaque changement
   * d'entité. Pas de filtre AR_Active__c/picklist actif (contrairement à getEntityOptions*) : une
   * matrice existante peut référencer une entité depuis désactivée, et son recalcul doit rester
   * juste — même principe que AR_PTFDataService.loadEntityReferential.
   */
  @AuraEnabled(cacheable=true)
  public static List<EntityPricingDefaultDto> getEntityPricingDefaults() {
    List<EntityPricingDefaultDto> defaults = new List<EntityPricingDefaultDto>();
    for (AR_PTF_Entity_Referential__c entity : [
      SELECT Id, Name, AR_Coefficient__c, AR_Working_Days__c, AR_Country__c
      FROM AR_PTF_Entity_Referential__c
      WHERE Name != NULL
    ]) {
      EntityPricingDefaultDto dto = new EntityPricingDefaultDto();
      dto.entityId = entity.Id;
      dto.entityName = entity.Name;
      dto.coefficient = entity.AR_Coefficient__c;
      dto.workingDays = entity.AR_Working_Days__c;
      dto.country = String.isBlank(entity.AR_Country__c) ? null : entity.AR_Country__c;
      defaults.add(dto);
    }
    return defaults;
  }

  /** Zone 2 statut VIE : options du référentiel pays, pour pré-remplir l'indemnité au choix d'un pays. */
  @AuraEnabled(cacheable=true)
  public static List<ReferentialCountryOption> getVieReferentialOptions() {
    List<ReferentialCountryOption> options = new List<ReferentialCountryOption>();
    for (AR_VIE_Referential__c ref : [
      SELECT Id, Name, AR_Daily_Allowance__c, AR_Currency__c
      FROM AR_VIE_Referential__c
      ORDER BY Name
    ]) {
      ReferentialCountryOption opt = new ReferentialCountryOption();
      opt.id = ref.Id;
      opt.country = ref.Name;
      opt.cjm = ref.AR_Daily_Allowance__c;
      opt.currencyCode = String.isNotBlank(ref.AR_Currency__c) ? ref.AR_Currency__c : 'EUR';
      options.add(opt);
    }
    return options;
  }

  /** Zone 2 statut Nearshore : options du référentiel pays, pour pré-remplir le CJM au choix d'un pays. */
  @AuraEnabled(cacheable=true)
  public static List<ReferentialCountryOption> getNearshoreReferentialOptions() {
    List<ReferentialCountryOption> options = new List<ReferentialCountryOption>();
    for (AR_Nearshore_Referential__c ref : [
      SELECT Id, Name, AR_Daily_Rate__c, AR_Currency__c, AR_Seniority__c
      FROM AR_Nearshore_Referential__c
      ORDER BY Name, AR_Seniority__c
    ]) {
      ReferentialCountryOption opt = new ReferentialCountryOption();
      opt.id = ref.Id;
      opt.country = ref.Name;
      opt.cjm = ref.AR_Daily_Rate__c;
      opt.currencyCode = String.isNotBlank(ref.AR_Currency__c) ? ref.AR_Currency__c : 'EUR';
      opt.seniority = ref.AR_Seniority__c;
      options.add(opt);
    }
    return options;
  }

  /** Zone 1 "Propriétaire" (nouvelle matrice, pas encore créée) = utilisateur courant. */
  @AuraEnabled(cacheable=true)
  public static String getCurrentUserName() {
    return UserInfo.getName();
  }

  /** Bandeau de reprise de brouillon (session 13) : brouillon de l'utilisateur courant, modifié il y a moins de 24h. */
  public class DraftResumeInfo {
    @AuraEnabled
    public Id matrixId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Datetime lastModifiedDate;
  }

  /**
   * Utilisée à l'arrivée sur la vue « Matrice AT » sans aucun contexte (ni besoin, ni matrice) : le
   * plus récent Brouillon appartenant à l'utilisateur courant, modifié il y a moins de 24h, ou null.
   */
  @AuraEnabled(cacheable=true)
  public static DraftResumeInfo getRecentDraftForCurrentUser() {
    Datetime cutoff = System.now().addHours(-24);
    List<AR_Price_Matrix__c> drafts = [
      SELECT Id, Name, AR_Account_Name__c, LastModifiedDate
      FROM AR_Price_Matrix__c
      WHERE
        OwnerId = :UserInfo.getUserId()
        AND AR_Status__c = 'Brouillon'
        AND LastModifiedDate >= :cutoff
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    if (drafts.isEmpty()) {
      return null;
    }
    DraftResumeInfo info = new DraftResumeInfo();
    info.matrixId = drafts[0].Id;
    info.name = drafts[0].Name;
    info.accountName = drafts[0].AR_Account_Name__c;
    info.lastModifiedDate = drafts[0].LastModifiedDate;
    return info;
  }

  /**
   * Seuils corridor servis au simulateur : grand compte, sinon entité PTF (si ses trois seuils sont
   * renseignés), sinon null = paramètres généraux (lus par le LWC dans getPricingSettings).
   * Session 252 : volontairement NON cacheable — un seuil d'entité modifié dans l'administration doit
   * se voir sans purge du cache client (piège session 51 et session 155).
   */
  @AuraEnabled
  public static ThresholdPercentsDto getAccountCorridorPercents(Id accountId, Id entityId) {
    try {
      CorridorResolution corridor = resolveCorridor(accountId, loadEntityReferentialForPricing(entityId));
      if (corridor.source == CORRIDOR_DEFAULT) {
        return null;
      }
      ThresholdPercentsDto dto = new ThresholdPercentsDto();
      dto.floorPercent = corridor.pcts.floorPercent;
      dto.targetPercent = corridor.pcts.targetPercent;
      dto.idealPercent = corridor.pcts.idealPercent;
      dto.source = corridor.source;
      dto.entityName = corridor.entityName;
      return dto;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_ReadSettingsAction);
    }
  }

  /**
   * Paramètres de calcul pour que le miroir JS (arPricingEngine) reste synchronisé avec AR_General_Setting__c.
   * Session 155 : volontairement NON cacheable — appelée en impératif par le simulateur, un appel
   * cacheable serait servi par le cache client (piège session 51) et un corridor de base modifié dans
   * Paramètres généraux ne se verrait qu'après purge du cache.
   */
  @AuraEnabled
  public static PricingSettingsDto getPricingSettings() {
    try {
      AR_General_Setting__c settings = loadGeneralSettings();
      PricingSettingsDto dto = new PricingSettingsDto();
      dto.workingDaysPerYear = (settings != null &&
        settings.AR_Working_Days_Per_Year__c != null)
        ? settings.AR_Working_Days_Per_Year__c
        : AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT;
      dto.markupPercent = (settings != null &&
        settings.AR_Markup_Percent__c != null)
        ? settings.AR_Markup_Percent__c
        : AR_PricingCalculator.MARKUP_PERCENT_DEFAULT;
      dto.markupMax = (settings != null &&
        settings.AR_Markup_Max__c != null)
        ? settings.AR_Markup_Max__c
        : AR_PricingCalculator.MARKUP_MAX_DEFAULT;
      // Session 155 : valeurs EFFECTIVES (base sinon constante), les mêmes que celles appliquées par
      // resolveCorridorPercents — jamais les constantes brutes, sinon le simulateur afficherait 20/25/30
      // pendant que Paramètres généraux dit autre chose.
      AR_PricingCalculator.ThresholdPercents defaultPcts = thresholdPercentsFrom(settings);
      dto.floorPercentDefault = defaultPcts.floorPercent;
      dto.targetPercentDefault = defaultPcts.targetPercent;
      dto.idealPercentDefault = defaultPcts.idealPercent;
      dto.ofiiTaxRate = settings != null ? settings.AR_Ofii_Tax_Rate__c : null;
      dto.ofiiTaxCapEur = settings != null ? settings.AR_Ofii_Tax_Cap__c : null;
      dto.derogationWaiverAmount = settings != null ? settings.AR_Derogation_Waiver_Amount__c : null;
      // Coefficient CDI/CDD administrable : découplé temporairement, cf. applySettingsDefaults()
      // ci-dessus. dto.cdiCoefficient/cddCoefficient restent toujours null (défaut moteur 2,02 côté JS).
      return dto;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_ReadSettingsAction);
    }
  }

  /** Option de sélection du besoin (combobox recherche, vue « Matrice AT » sans contexte préexistant). */
  public class PositionOption {
    @AuraEnabled
    public Id positionId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String positionName;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public DateTime createdDate;
  }

  /**
   * Recherche de besoins pour le sélecteur de la vue « Matrice AT » (session 8) : nom du besoin
   * ou du compte, 1 caractère minimum (session 83), 20 résultats max. `with sharing` : ne remonte
   * que les besoins visibles de l'utilisateur courant.
   * Session 81 : utilise le chaînage AB_Need_details__c.AB_Account__c comme source fiable de compte,
   * avec fallback au champ legacy cxsrec__Account__c pour couverture des besoins non liés.
   * Session 88 : filtre les besoins clos (Gagné/Perdu/Supprimé) hors de la recherche.
   * Session 117 : tri par date de création (plus récent en premier). Décision Alexis 25/09 : un seul
   * critère, celui de la requête, pour la traçabilité (cf. docs/117-plan-retours-matthieu.md §1).
   */
  @AuraEnabled(cacheable=true)
  public static List<PositionOption> searchPositions(String searchTerm) {
    List<PositionOption> options = new List<PositionOption>();
    if (String.isBlank(searchTerm) || searchTerm.length() < 1) {
      return options;
    }
    String likeTerm = '%' + String.escapeSingleQuotes(searchTerm) + '%';
    for (cxsrec__cxsPosition__c p : [
      SELECT Id, Name, CreatedDate, cxsrec__Account__r.Name, AB_Need_details__r.AB_Account__r.Name
      FROM cxsrec__cxsPosition__c
      WHERE (Name LIKE :likeTerm
        OR cxsrec__Account__r.Name LIKE :likeTerm
        OR AB_Need_details__r.AB_Account__r.Name LIKE :likeTerm)
        AND (cxsrec__Status__c = NULL OR cxsrec__Status__c NOT IN :EXCLUDED_STATUSES)
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 20
    ]) {
      PositionOption opt = new PositionOption();
      opt.positionId = p.Id;
      String accountName = p.AB_Need_details__r?.AB_Account__r?.Name != null
        ? p.AB_Need_details__r.AB_Account__r.Name
        : (p.cxsrec__Account__r != null ? p.cxsrec__Account__r.Name : null);
      opt.label =
        p.Name +
        ' — ' +
        (accountName != null ? accountName : Label.AR_Msg_PM_NoAccount);
      opt.positionName = p.Name;
      opt.accountName = accountName;
      opt.createdDate = p.CreatedDate;
      options.add(opt);
    }

    return options;
  }


  /** Option de sélection du consultant (recherche Zone 1, session 54) — porte la séniorité pour que
   * le LWC puisse la pré-remplir à la sélection sans appel serveur supplémentaire. */
  public class ConsultantOption {
    @AuraEnabled
    public Id consultantId;
    @AuraEnabled
    public String label;
    // Valeur de cxsrec__cxsCandidate__c.TP_Seniority__c au moment de la recherche — suggestion,
    // jamais appliquée par le serveur lui-même (cf. AR_Seniority__c.field-meta.xml).
    @AuraEnabled
    public String seniority;
  }

  /**
   * Recherche de consultants pour le lookup Zone 1 (session 54, remplace la saisie libre de
   * AR_Consultant_Name__c) : nom, 1 caractère minimum (session 99, alignement sur searchPositions),
   * 20 résultats max, filtrée au record type Consultant — jamais le picklist/l'objet complet,
   * même principe que le filtre de séniorité déjà en place côté LWC
   * (arPriceMatrixSimulator.wiredSeniorityPicklist). `with sharing` : ne remonte que les candidats
   * visibles de l'utilisateur courant.
   */
  @AuraEnabled(cacheable=true)
  public static List<ConsultantOption> searchConsultants(String searchTerm) {
    List<ConsultantOption> options = new List<ConsultantOption>();
    if (String.isBlank(searchTerm) || searchTerm.length() < 1) {
      return options;
    }
    Set<Id> selectableRecordTypeIds = selectableCandidateRecordTypeIds();
    String likeTerm = '%' + String.escapeSingleQuotes(searchTerm) + '%';
    for (cxsrec__cxsCandidate__c c : [
      SELECT Id, Name, TP_Seniority__c
      FROM cxsrec__cxsCandidate__c
      WHERE RecordTypeId IN :selectableRecordTypeIds AND Name LIKE :likeTerm
      ORDER BY LastModifiedDate DESC
      LIMIT 20
    ]) {
      ConsultantOption opt = new ConsultantOption();
      opt.consultantId = c.Id;
      opt.label = c.Name;
      opt.seniority = c.TP_Seniority__c;
      options.add(opt);
    }
    return options;
  }

  /** Record types de candidat sélectionnables comme consultant : Consultant et External_candidate
   * (demande du 16/10/2026). Partagé par la recherche et par le pré-remplissage à la création. */
  private static Set<Id> selectableCandidateRecordTypeIds() {
    Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.cxsrec__cxsCandidate__c.getRecordTypeInfosByDeveloperName();
    Set<Id> ids = new Set<Id>();
    for (String developerName : new List<String>{ 'Consultant', 'External_candidate' }) {
      Schema.RecordTypeInfo info = recordTypes.get(developerName);
      if (info != null) {
        ids.add(info.getRecordTypeId());
      }
    }
    return ids;
  }

  /** Valeurs proposées à la création d'une matrice depuis un besoin (sorties uniquement). */
  public class CreationPrefill {
    @AuraEnabled
    public Decimal proposedTjm;
    // Devise du montant proposedTjm (devise de l'organisation) : l'écran ne l'applique que si la
    // matrice est dans cette devise.
    @AuraEnabled
    public String tjmCurrency;
    @AuraEnabled
    public Id consultantId;
    @AuraEnabled
    public String consultantLabel;
    // Entité pré-sélectionnée depuis l'utilisateur qui crée la matrice (User.TP_Abylsen_Company__c).
    @AuraEnabled
    public Id entityId;
  }

  private static final Decimal PLAUSIBLE_DAILY_RATE_MIN = 50;
  private static final Decimal PLAUSIBLE_DAILY_RATE_MAX = 5000;

  /** Tarif journalier du besoin retenu comme TJM proposé : hors de la plage plausible, rien. */
  @TestVisible
  private static Decimal plausibleDailyRate(Decimal rate) {
    if (rate == null || rate < PLAUSIBLE_DAILY_RATE_MIN || rate > PLAUSIBLE_DAILY_RATE_MAX) {
      return null;
    }
    return rate;
  }

  /**
   * Pré-remplissages de la CRÉATION d'une matrice depuis un besoin (jamais appelé pour une
   * duplication, un avenant ou la réouverture d'une matrice) :
   * - TJM proposé = « Average daily rate » du besoin (TP_TJM__c) quand il est plausible ;
   * - consultant = le candidat du besoin quand il n'y en a qu'un (candidats distincts de ses
   *   candidatures) et que son type d'enregistrement est sélectionnable comme consultant ;
   * - entité = la fiche active du référentiel qui correspond à « Abylsen Company » de l'utilisateur
   *   courant (cf. creatorDefaultEntityId).
   * Source vide, ambiguë ou illisible : rien n'est proposé. Non cacheable : une candidature ajoutée
   * entre deux ouvertures doit être vue.
   */
  @AuraEnabled
  public static CreationPrefill getCreationPrefill(Id positionId) {
    try {
      return buildCreationPrefill(positionId);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_PrefillAction);
    }
  }

  /**
   * Entité de la matrice proposée au créateur : la fiche active du référentiel dont le nom égale la
   * valeur « Abylsen Company » de l'utilisateur courant, ou son libellé de liste, sans tenir compte
   * de la casse ni des espaces en bord. Aucune correspondance, ou plusieurs fiches : rien, l'utilisateur
   * choisit. Pas de rapprochement approximatif.
   */
  @TestVisible
  private static Id creatorDefaultEntityId() {
    String company = [SELECT TP_Abylsen_Company__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]
      .TP_Abylsen_Company__c;
    if (String.isBlank(company)) {
      return null;
    }
    Set<String> wantedNames = new Set<String>{ normalizeEntityName(company) };
    for (Schema.PicklistEntry entry : User.TP_Abylsen_Company__c.getDescribe().getPicklistValues()) {
      if (entry.getValue() == company) {
        wantedNames.add(normalizeEntityName(entry.getLabel()));
      }
    }
    Set<Id> matches = new Set<Id>();
    for (AR_PTF_Entity_Referential__c entity : [
      SELECT Id, Name
      FROM AR_PTF_Entity_Referential__c
      WHERE Name != NULL AND AR_Active__c = TRUE
    ]) {
      if (wantedNames.contains(normalizeEntityName(entity.Name))) {
        matches.add(entity.Id);
      }
    }
    return matches.size() == 1 ? new List<Id>(matches)[0] : null;
  }

  private static String normalizeEntityName(String name) {
    return name.trim().toLowerCase();
  }

  private static CreationPrefill buildCreationPrefill(Id positionId) {
    CreationPrefill prefill = new CreationPrefill();
    if (positionId == null) {
      return prefill;
    }
    prefill.entityId = creatorDefaultEntityId();
    List<cxsrec__cxsPosition__c> positions = [SELECT TP_TJM__c FROM cxsrec__cxsPosition__c WHERE Id = :positionId LIMIT 1];
    if (positions.isEmpty()) {
      return prefill;
    }
    if (Schema.SObjectType.cxsrec__cxsPosition__c.fields.TP_TJM__c.isAccessible()) {
      prefill.proposedTjm = plausibleDailyRate(positions[0].TP_TJM__c);
      if (prefill.proposedTjm != null) {
        prefill.tjmCurrency = UserInfo.getDefaultCurrency();
      }
    }

    List<AggregateResult> distinctCandidates = [
      SELECT cxsrec__Candidate__c candidateId
      FROM cxsrec__cxsJob_application__c
      WHERE cxsrec__Position__c = :positionId AND cxsrec__Candidate__c != NULL
      GROUP BY cxsrec__Candidate__c
      LIMIT 2
    ];
    if (distinctCandidates.size() == 1) {
      Id candidateId = (Id) distinctCandidates[0].get('candidateId');
      Set<Id> selectable = selectableCandidateRecordTypeIds();
      for (cxsrec__cxsCandidate__c c : [
        SELECT Id, Name
        FROM cxsrec__cxsCandidate__c
        WHERE Id = :candidateId AND RecordTypeId IN :selectable
        LIMIT 1
      ]) {
        prefill.consultantId = c.Id;
        prefill.consultantLabel = c.Name;
      }
    }
    return prefill;
  }

  /** Zone 1 : pré-remplissage lecture seule depuis le besoin Connexys (nouvelle matrice ou matrice existante).
   * Session 81 : utilise le chaînage AB_Need_details__c.AB_Account__c comme source fiable de compte,
   * avec fallback au champ legacy cxsrec__Account__c pour couverture des besoins non liés.
   * Ajoute CreatedDate pour le panneau de détail de sélection en deux temps (session 81).
   * Session 88 : ajoute le statut du besoin pour le badge coloré.
   */
  @AuraEnabled(cacheable=true)
  public static PositionContext getPositionContext(Id positionId) {
    List<cxsrec__cxsPosition__c> positions = [
      SELECT
        Name,
        CreatedDate,
        cxsrec__Account__c,
        cxsrec__Account__r.Name,
        cxsrec__Account__r.BillingCity,
        cxsrec__Account__r.ShippingCity,
        cxsrec__Country__c,
        TP_P_rim_tre__c,
        TP_Business_Line__c,
        cxsrec__Contract_type__c,
        cxsrec__Status__c,
        AB_Need_details__r.AB_Account__c,
        AB_Need_details__r.AB_Account__r.Name,
        AB_Need_details__r.AB_Account__r.BillingCity,
        AB_Need_details__r.AB_Account__r.ShippingCity,
        AB_Need_details__r.AB_Contact__c,
        AB_Need_details__r.AB_Contact__r.Name,
        TP_Manager__c,
        TP_Manager__r.Name,
        TP_Date_de_d_marrage_attendue__c,
        AB_Estimated_End_Date__c
      FROM cxsrec__cxsPosition__c
      WHERE Id = :positionId
      LIMIT 1
    ];
    PositionContext ctx = new PositionContext();
    // Session 167 : besoin non visible sous partage (with sharing, inchangé) → contexte vide signalé,
    // jamais d'exception brute « List has no rows ».
    if (positions.isEmpty()) {
      ctx.accessible = false;
      return ctx;
    }
    cxsrec__cxsPosition__c position = positions[0];
    // Session 81 : prefer the new chain (AB_Need_details__c → AB_Account__c), fall back to legacy field
    Id accountIdFromNewChain = position.AB_Need_details__r?.AB_Account__c;
    ctx.accountId = accountIdFromNewChain != null ? accountIdFromNewChain : position.cxsrec__Account__c;
    String accountNameFromNewChain = position.AB_Need_details__r?.AB_Account__r?.Name;
    ctx.accountName = accountNameFromNewChain != null
      ? accountNameFromNewChain
      : (position.cxsrec__Account__r != null ? position.cxsrec__Account__r.Name : null);
    // Session 142b : ville de livraison en repli — BillingCity en priorité, puis ShippingCity si
    // BillingCity est vide. Mesure session 142 : 13 matrices sur 16 n'ont que l'adresse de livraison.
    // Session 141 : ville du compte RÉSOLU ci-dessus — si la nouvelle chaîne désigne un compte, c'est
    // sa ville (même vide) qui compte, jamais celle du compte legacy, pour ne pas mélanger deux comptes.
    String billingCity = accountIdFromNewChain != null
      ? position.AB_Need_details__r.AB_Account__r?.BillingCity
      : position.cxsrec__Account__r?.BillingCity;
    String shippingCity = accountIdFromNewChain != null
      ? position.AB_Need_details__r.AB_Account__r?.ShippingCity
      : position.cxsrec__Account__r?.ShippingCity;
    ctx.accountCity = String.isNotBlank(billingCity) ? billingCity : shippingCity;
    ctx.accountCountry = position.cxsrec__Country__c;
    ctx.positionName = position.Name;
    ctx.perimetre = position.TP_P_rim_tre__c;
    ctx.businessLine = position.TP_Business_Line__c;
    ctx.contractType = position.cxsrec__Contract_type__c;
    ctx.status = position.cxsrec__Status__c;
    ctx.createdDate = position.CreatedDate;
    ctx.managerContactId = position.TP_Manager__c;
    ctx.managerName = position.TP_Manager__r != null ? position.TP_Manager__r.Name : null;
    ctx.contactId = position.AB_Need_details__r?.AB_Contact__c;
    ctx.contactName = position.AB_Need_details__r?.AB_Contact__r != null ? position.AB_Need_details__r.AB_Contact__r.Name : null;
    ctx.startDate = position.TP_Date_de_d_marrage_attendue__c;
    ctx.estimatedEndDate = position.AB_Estimated_End_Date__c;
    return ctx;
  }

  /**
   * Session 167 : contexte du besoin pour un chemin d'ÉCRITURE (sauvegarde, duplication) — lève une
   * AuraHandledException claire si le besoin n'est pas visible de l'utilisateur courant.
   */
  public static PositionContext requireAccessiblePositionContext(Id positionId) {
    // Contexte déjà lu dans la transaction pour cet utilisateur (session 291c : un enregistrement + validation +
    // copie relisaient 5 fois le même besoin). Seuls les besoins accessibles sont mémorisés.
    String key = UserInfo.getUserId() + '|' + positionId;
    PositionContext cached = accessiblePositionContexts.get(key);
    if (cached != null) {
      return cached;
    }
    PositionContext ctx = getPositionContext(positionId);
    if (!ctx.accessible) {
      throw newAuraException(System.Label.AR_PMS_PositionAccessDeniedSaveError);
    }
    accessiblePositionContexts.put(key, ctx);
    return ctx;
  }

  private static Map<String, PositionContext> accessiblePositionContexts = new Map<String, PositionContext>();

  /**
   * Session 136, décision d'Alexis du 02/10/2026 : le salaire du consultant n'est PAS repris par
   * l'application (aucune lecture d'un champ salaire Connexys, ni pré-remplissage, ni mention
   * « non lisible ») ; le salaire reste une saisie manuelle de la matrice.
   *
   * Contexte consultant pré-remplissage (session 65) : appelé à la sélection explicite d'un
   * consultant depuis le dropdown de recherche. Retourne les valeurs lues, filtrées en trois listes :
   * - `filled` : champs extraits et non vides
   * - `sourceEmpty` : champs existants sur le consultant mais vides
   * - `unreadable` : champs non lisibles à cause des FLS de l'utilisateur courant
   *
   * SOQL USER_MODE : respecte le FLS de l'utilisateur. Retour typé (pas de Map opaque).
   */
  @AuraEnabled
  public static ConsultantContext getConsultantContext(Id consultantId) {
    if (consultantId == null) {
      throw newAuraException(Label.AR_Msg_PM_ConsultantNotSelected);
    }
    try {
      ConsultantContext ctx = new ConsultantContext();

      // FLS champ par champ AVANT la requête : une seule SOQL USER_MODE listant un champ illisible
      // échoue en bloc (« No such column »), ce qui ferait tomber tout le pré-remplissage au lieu de
      // n'en retirer que la part non lisible. Un champ illisible est rapporté dans `unreadable`
      // (doc 65 §6, doctrine session 34 : afficher, jamais muet), jamais confondu avec « vide ».
      Set<String> readable = new Set<String>();
      for (Schema.SObjectField f : new List<Schema.SObjectField>{
        cxsrec__cxsCandidate__c.TP_Type_de_contrat__c,
        cxsrec__cxsCandidate__c.TP_Seniority__c
      }) {
        if (f.getDescribe().isAccessible()) {
          readable.add(String.valueOf(f));
        }
      }
      List<String> selectFields = new List<String>{ 'Id', 'Name' };
      selectFields.addAll(readable);
      List<cxsrec__cxsCandidate__c> rows = Database.queryWithBinds(
        'SELECT ' + String.join(selectFields, ', ') + ' FROM cxsrec__cxsCandidate__c WHERE Id = :consultantId LIMIT 1',
        new Map<String, Object>{ 'consultantId' => consultantId },
        AccessLevel.USER_MODE
      );
      if (rows.isEmpty()) {
        throw newAuraException(Label.AR_Msg_PM_ConsultantNotFound);
      }
      cxsrec__cxsCandidate__c consultant = rows[0];

      // Contrat : traduction TP_Type_de_contrat__c → contractType (session 65, tableau de la 64)
      String contractTypeSource = readable.contains('TP_Type_de_contrat__c') ? consultant.TP_Type_de_contrat__c : null;
      String contractTypeTranslated = translateContractType(contractTypeSource);
      if (!readable.contains('TP_Type_de_contrat__c')) {
        ctx.unreadable.add('contractType');
      } else if (contractTypeTranslated != null) {
        ctx.contractType = contractTypeTranslated;
        ctx.filled.add('contractType');
      } else if (contractTypeSource != null) {
        // Source non traduisible → ne pas remplir, mais signaler
        ctx.sourceEmpty.add('contractType');
      }

      // Entité : JAMAIS pré-remplie (session 132, décision d'Alexis) — l'utilisateur la choisit
      // dans la liste d'administration, ni la société du consultant ni celle de l'utilisateur
      // ne servent à la déterminer.

      // Séniorité : déjà câblée en session 54, tester la présence
      if (!readable.contains('TP_Seniority__c')) {
        ctx.unreadable.add('seniorityLevel');
      } else if (consultant.TP_Seniority__c != null) {
        ctx.seniorityLevel = consultant.TP_Seniority__c;
        ctx.filled.add('seniorityLevel');
      }

      // Dates : JAMAIS reprises de la fiche consultant (session 146c, décision d'Alexis du 06/10/2026) —
      // les dates des fiches sont périmées (ex. 2012 → 2017). Début = date du besoin, fin = 31/12.

      return ctx;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_ConsultantContextAction);
    }
  }

  /**
   * Traduction des statuts de contrat depuis la fiche consultant (TP_Type_de_contrat__c) vers les
   * statuts matrice (AR_Contract_Type__c). Session 64 : mesure du périmètre B établit CDI/CDD/VIE et
   * Indépendant comme seuls candidats traductibles ; Sous-traitant reste non traduit (arbitrage client
   * requis). Aucune source ne couvre NEARSHORE.
   */
  @TestVisible
  private static String translateContractType(String sourceValue) {
    if (sourceValue == null) {
      return null;
    }
    switch on sourceValue {
      when 'CDI' {
        return 'CDI';
      }
      when 'CDD' {
        return 'CDD';
      }
      when 'VIE' {
        return 'VIE';
      }
      when 'Indépendant' {
        return 'INDEP';
      }
    }
    return null;
  }

  /** DTO de retour pour getValidatorOptionsForMatrix : options proposées, ou état bloquant explicite
   * (motif nommant les champs vides et la fiche concernée) quand la chaîne est vide.
   */
  public class ValidatorOptionsResult {
    @AuraEnabled
    public List<ValidatorOption> options;
    @AuraEnabled
    public Boolean blocked;
    @AuraEnabled
    public String blockedReason;
  }

  /** Résout les options de valideur d'une matrice. Session 79 : hiérarchie du propriétaire (OwnerId),
   * pas l'entité. Session 179 : DA, DD et Directeur dédoublonnés, inactifs exclus, plus les valideurs
   * de test du réglage général — tout le calcul est dans AR_ValidatorChain (partagé avec l'escalade
   * des relances). Chaîne vide → blocage explicite avec le détail des champs, jamais une liste vide
   * silencieuse.
   */
  @AuraEnabled(cacheable=true)
  public static ValidatorOptionsResult getValidatorOptionsForMatrix(Id matrixId) {
    ValidatorOptionsResult result = new ValidatorOptionsResult();
    result.options = new List<ValidatorOption>();
    result.blocked = false;

    if (matrixId == null) {
      result.blocked = true;
      result.blockedReason = Label.AR_Msg_PM_MatrixNotFound;
      return result;
    }

    AR_ValidatorChain.Resolution resolution = AR_ValidatorChain.resolveForMatrix(matrixId);
    if (resolution.blockedReason != null) {
      result.blocked = true;
      result.blockedReason = resolution.blockedReason;
      return result;
    }
    for (User u : resolution.validators) {
      ValidatorOption opt = new ValidatorOption();
      opt.userId = u.Id;
      opt.userName = u.Name;
      opt.role = resolution.roleByUserId.get(u.Id);
      result.options.add(opt);
    }
    return result;
  }

  /**
   * Payload transmis en String JSON, pas en classe wrapper (constat du 10/08/2026, cf.
   * docs/19-payload-json.md). Dans la sandbox `abylsengroup--full`, Aura n'alimente AUCUN champ
   * d'un paramètre de type classe Apex définie par l'utilisateur : l'objet arrive instancié mais
   * entièrement à null, sans erreur. Vérifié sur une classe témoin minimale (AR_TmpWrapperProbe) :
   * `String` scalaire, `Map<String,Object>` et `List<String>` passent normalement, la classe
   * wrapper non — qu'elle soit interne ou top-level. Symptôme côté utilisateur : `input.positionId`
   * null → `getPositionContext` lève `List has no rows for assignment to SObject` sur un besoin
   * pourtant bien sélectionné à l'écran.
   *
   * Les méthodes typées (`saveDraftInput`, `validateInput`, `requestDerogationInput`) restent le
   * point d'entrée interne et testable ; seules les façades @AuraEnabled changent de signature.
   * À reverter si Salesforce corrige le comportement plateforme (case à ouvrir).
   */
  private static MatrixInput parseMatrixInput(String inputJson) {
    if (String.isBlank(inputJson)) {
      throw newAuraException(
        Label.AR_Msg_PM_EmptyMatrixPayload
      );
    }
    return (MatrixInput) JSON.deserialize(inputJson, MatrixInput.class);
  }

  /**
   * Périodes de frais ajoutées (docs/239), stockées en JSON sur AR_Fee_Periods__c. JSON illisible →
   * erreur explicite à la sauvegarde, jamais une liste vide silencieuse. Valeurs négatives ramenées à
   * 0, jours arrondis à l'entier ; une clé absente vaut 0.
   */
  public static List<AR_PricingCalculator.FeePeriod> parseFeePeriods(String periodsJson) {
    List<AR_PricingCalculator.FeePeriod> periods = new List<AR_PricingCalculator.FeePeriod>();
    if (String.isBlank(periodsJson)) {
      return periods;
    }
    try {
      for (Object raw : (List<Object>) JSON.deserializeUntyped(periodsJson)) {
        Map<String, Object> row = (Map<String, Object>) raw;
        AR_PricingCalculator.FeePeriod p = new AR_PricingCalculator.FeePeriod();
        p.days = amountOf(row.get('days')).setScale(0, RoundingMode.HALF_UP);
        p.feeIk = amountOf(row.get('feeIk'));
        p.feeMeals = amountOf(row.get('feeMeals'));
        p.feeLodging = amountOf(row.get('feeLodging'));
        p.feeOmOther = amountOf(row.get('feeOmOther'));
        periods.add(p);
      }
    } catch (Exception e) {
      throw newAuraException(Label.AR_Msg_PM_FeePeriodsInvalidJson);
    }
    return periods;
  }

  private static Decimal amountOf(Object value) {
    Decimal amount = value == null ? 0 : Decimal.valueOf(String.valueOf(value));
    return amount < 0 ? 0 : amount;
  }

  // Liste vide = aucune période : null, comme un champ jamais renseigné.
  private static String serializeFeePeriods(List<AR_PricingCalculator.FeePeriod> periods) {
    if (periods.isEmpty()) {
      return null;
    }
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (AR_PricingCalculator.FeePeriod p : periods) {
      rows.add(new Map<String, Object>{
        'days' => p.days,
        'feeIk' => p.feeIk,
        'feeMeals' => p.feeMeals,
        'feeLodging' => p.feeLodging,
        'feeOmOther' => p.feeOmOther
      });
    }
    return JSON.serialize(rows);
  }

  /**
   * Périodes de TJM ajoutées (docs/254), stockées en JSON sur AR_TJM_Periods__c. JSON illisible ou valeur
   * négative → erreur explicite, jamais une liste vide silencieuse ni une valeur ramenée à 0 (un prix à 0
   * serait plausible mais faux). Jours arrondis à l'entier ; une clé absente vaut null (période incomplète,
   * refusée à la validation). Liste vide ou nulle = aucune évolution de TJM.
   */
  public static List<AR_PricingCalculator.TjmPeriod> parseTjmPeriods(String periodsJson) {
    List<AR_PricingCalculator.TjmPeriod> periods = new List<AR_PricingCalculator.TjmPeriod>();
    if (String.isBlank(periodsJson)) {
      return periods;
    }
    try {
      for (Object raw : (List<Object>) JSON.deserializeUntyped(periodsJson)) {
        Map<String, Object> row = (Map<String, Object>) raw;
        AR_PricingCalculator.TjmPeriod p = new AR_PricingCalculator.TjmPeriod();
        p.days = row.get('days') == null
          ? null
          : Decimal.valueOf(String.valueOf(row.get('days'))).setScale(0, RoundingMode.HALF_UP);
        p.tjm = row.get('tjm') == null ? null : Decimal.valueOf(String.valueOf(row.get('tjm')));
        if ((p.days != null && p.days < 0) || (p.tjm != null && p.tjm < 0)) {
          throw new IllegalArgumentException('valeur négative');
        }
        periods.add(p);
      }
    } catch (Exception e) {
      throw newAuraException(Label.AR_Msg_PM_TjmPeriodsInvalid);
    }
    return periods;
  }

  // Liste vide = aucune période : null, comme un champ jamais renseigné.
  private static String serializeTjmPeriods(List<AR_PricingCalculator.TjmPeriod> periods) {
    if (periods.isEmpty()) {
      return null;
    }
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (AR_PricingCalculator.TjmPeriod p : periods) {
      rows.add(new Map<String, Object>{ 'days' => p.days, 'tjm' => p.tjm });
    }
    return JSON.serialize(rows);
  }

  /**
   * Périodes de salaire ajoutées (CDI/CDD), stockées en JSON sur AR_Salary_Periods__c. Mêmes règles que
   * les périodes de TJM : JSON illisible ou valeur négative → erreur explicite ; clé absente = null
   * (période incomplète, refusée à la validation) ; jours arrondis à l'entier.
   */
  public static List<AR_PricingCalculator.SalaryPeriod> parseSalaryPeriods(String periodsJson) {
    List<AR_PricingCalculator.SalaryPeriod> periods = new List<AR_PricingCalculator.SalaryPeriod>();
    if (String.isBlank(periodsJson)) {
      return periods;
    }
    try {
      for (Object raw : (List<Object>) JSON.deserializeUntyped(periodsJson)) {
        Map<String, Object> row = (Map<String, Object>) raw;
        AR_PricingCalculator.SalaryPeriod p = new AR_PricingCalculator.SalaryPeriod();
        p.days = row.get('days') == null
          ? null
          : Decimal.valueOf(String.valueOf(row.get('days'))).setScale(0, RoundingMode.HALF_UP);
        p.salary = row.get('salary') == null ? null : Decimal.valueOf(String.valueOf(row.get('salary')));
        if ((p.days != null && p.days < 0) || (p.salary != null && p.salary < 0)) {
          throw new IllegalArgumentException('valeur négative');
        }
        periods.add(p);
      }
    } catch (Exception e) {
      throw newAuraException(Label.AR_Msg_PM_SalaryPeriodsInvalid);
    }
    return periods;
  }

  // Liste vide = aucune période : null, comme un champ jamais renseigné.
  private static String serializeSalaryPeriods(List<AR_PricingCalculator.SalaryPeriod> periods) {
    if (periods.isEmpty()) {
      return null;
    }
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (AR_PricingCalculator.SalaryPeriod p : periods) {
      rows.add(new Map<String, Object>{ 'days' => p.days, 'salary' => p.salary });
    }
    return JSON.serialize(rows);
  }

  /**
   * Gardes des périodes de salaire (CDI/CDD seulement ; ignorées pour les autres statuts) : période
   * incomplète, plus de 4 salaires, durée absente ou dépassée bloquent la validation et la dérogation.
   */
  private static List<AR_PTFDataService.Prerequisite> salaryPeriodsPrerequisites(AR_Price_Matrix__c m) {
    List<AR_PTFDataService.Prerequisite> missing = new List<AR_PTFDataService.Prerequisite>();
    if (m.AR_Contract_Type__c != 'CDI' && m.AR_Contract_Type__c != 'CDD') {
      return missing;
    }
    List<AR_PricingCalculator.SalaryPeriod> periods = parseSalaryPeriods(m.AR_Salary_Periods__c);
    if (periods.isEmpty()) {
      return missing;
    }
    for (AR_PricingCalculator.SalaryPeriod p : periods) {
      if (p.days == null || p.days < 1 || p.salary == null || p.salary <= 0) {
        missing.add(
          new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_SalaryPeriodIncomplete, Label.AR_Msg_PM_SalaryPeriodIncompleteWhere)
        );
        break;
      }
    }
    if (periods.size() > 3) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_SalaryPeriodsTooMany, Label.AR_Msg_PM_SalaryPeriodsTooManyWhere));
    }
    if (m.AR_Number_Of_Days__c == null || m.AR_Number_Of_Days__c <= 0) {
      missing.add(
        new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_SalaryPeriodsMissionUnknown, Label.AR_Msg_PM_TjmPeriodsMissionUnknownWhere)
      );
    } else if (AR_PricingCalculator.calcSalaryPeriods(toContext(m)).exceedMission) {
      missing.add(
        new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_SalaryPeriodsExceedMission, Label.AR_Msg_PM_TjmPeriodsExceedMissionWhere)
      );
    }
    return missing;
  }

  /**
   * Prix de la mission (docs/254 §1) : le TJM moyen pondéré s'il est calculé, sinon le TJM saisi (période 1).
   * Seul point de lecture Apex d'un « prix de la mission » : AR_TJM_Weighted__c doit être dans la requête
   * de la matrice. Aucun appelant ne refait ce repli à la main.
   */
  public static Decimal effectiveTjm(AR_Price_Matrix__c m) {
    return m.AR_TJM_Weighted__c != null ? m.AR_TJM_Weighted__c : m.AR_Proposed_TJM__c;
  }

  /**
   * Périodes de TJM affichées (docs/254 §11.2) : vide sans évolution, sinon la période 1 (jours restants)
   * puis les périodes ajoutées. Calcul pur, sans requête : la matrice doit porter AR_TJM_Periods__c,
   * AR_Proposed_TJM__c et les champs des jours facturables (cf. billableDaysOf).
   */
  public static List<AR_PricingResult.TjmPeriod> tjmPeriodsOf(AR_Price_Matrix__c m) {
    AR_PricingCalculator.Context ctx = billableDaysContext(m);
    ctx.tjmPeriods = parseTjmPeriods(m.AR_TJM_Periods__c);
    return AR_PricingCalculator.calcTjmPeriods(ctx, m.AR_Proposed_TJM__c).periods;
  }

  /**
   * Jours facturables d'une matrice (jours de mission − congés prévus, congés ignorés en régie sans
   * régule), 0 si la durée est inconnue. La matrice doit porter AR_Number_Of_Days__c,
   * AR_Planned_Leave_Days__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c et AR_RPLSR_Days_Produced__c.
   */
  public static Decimal billableDaysOf(AR_Price_Matrix__c m) {
    return AR_PricingCalculator.calcBillableDays(billableDaysContext(m));
  }

  private static AR_PricingCalculator.Context billableDaysContext(AR_Price_Matrix__c m) {
    AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
    ctx.missionDays = m.AR_Number_Of_Days__c;
    ctx.plannedLeaveDays = m.AR_Planned_Leave_Days__c;
    ctx.rplsrRatio = rplsrRatioOf(m);
    return ctx;
  }

  /** Congés prévus supérieurs aux jours de mission (hors régie sans régule) : bloque la validation. */
  private static List<AR_PTFDataService.Prerequisite> plannedLeavePrerequisites(AR_Price_Matrix__c m) {
    List<AR_PTFDataService.Prerequisite> missing = new List<AR_PTFDataService.Prerequisite>();
    Decimal leave = m.AR_Planned_Leave_Days__c == null ? 0 : m.AR_Planned_Leave_Days__c;
    Decimal days = m.AR_Number_Of_Days__c == null ? 0 : m.AR_Number_Of_Days__c;
    if (m.AR_RPLSR_Enabled__c != true && leave > 0 && leave > days) {
      missing.add(
        new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_LeaveExceedsMission, Label.AR_Msg_PM_LeaveExceedsMissionWhere)
      );
    }
    return missing;
  }

  /**
   * Gardes des périodes de TJM (docs/254 §3.4 et §11.1) : une période incomplète, la durée de mission
   * absente alors que le TJM évolue, un dépassement de la mission, ou plus de 4 TJM au total bloquent la
   * validation et la dérogation. Le brouillon reste libre.
   */
  private static List<AR_PTFDataService.Prerequisite> tjmPeriodsPrerequisites(AR_Price_Matrix__c m) {
    List<AR_PTFDataService.Prerequisite> missing = new List<AR_PTFDataService.Prerequisite>();
    List<AR_PricingCalculator.TjmPeriod> periods = parseTjmPeriods(m.AR_TJM_Periods__c);
    if (periods.isEmpty()) {
      return missing;
    }
    for (AR_PricingCalculator.TjmPeriod p : periods) {
      if (p.days == null || p.days < 1 || p.tjm == null || p.tjm <= 0) {
        missing.add(
          new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_TjmPeriodIncomplete, Label.AR_Msg_PM_TjmPeriodIncompleteWhere)
        );
        break;
      }
    }
    if (periods.size() > 3) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_TjmPeriodsTooMany, Label.AR_Msg_PM_TjmPeriodsTooManyWhere));
    }
    if (m.AR_Number_Of_Days__c == null || m.AR_Number_Of_Days__c <= 0) {
      missing.add(
        new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_TjmPeriodsMissionUnknown, Label.AR_Msg_PM_TjmPeriodsMissionUnknownWhere)
      );
    } else if (AR_PricingCalculator.calcTjmPeriods(toContext(m), m.AR_Proposed_TJM__c).exceedMission) {
      missing.add(
        new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_TjmPeriodsExceedMission, Label.AR_Msg_PM_TjmPeriodsExceedMissionWhere)
      );
    }
    return missing;
  }

  // --- Régie sans régule (docs/265) -------------------------------------------------------------------

  private static final Decimal RPLSR_MAX_DAYS_PER_MONTH = 23;
  private static final Integer RPLSR_PLAN_VERSION = 1;

  /**
   * Rapport jours produits ÷ jours vendus du plan enregistré, null hors mode (ou sans jour vendu).
   * La matrice doit porter AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c et AR_RPLSR_Days_Produced__c.
   */
  public static Decimal rplsrRatioOf(AR_Price_Matrix__c m) {
    if (m.AR_RPLSR_Enabled__c != true || m.AR_RPLSR_Days_Sold__c == null || m.AR_RPLSR_Days_Sold__c <= 0) {
      return null;
    }
    Decimal produced = m.AR_RPLSR_Days_Produced__c == null ? 0 : m.AR_RPLSR_Days_Produced__c;
    return produced.divide(m.AR_RPLSR_Days_Sold__c, 18, RoundingMode.HALF_UP);
  }

  /** Jours facturés par mois proposés à l'activation : jours travaillés/an ÷ 12, 2 décimales HALF_UP. */
  public static Decimal defaultRplsrDaysPerMonth(Decimal workingDaysPerYear) {
    return (workingDaysPerYear / 12).setScale(2, RoundingMode.HALF_UP);
  }

  /** Plan lu du JSON versionné ; JSON illisible → erreur explicite, jamais un plan vide. */
  public static List<AR_WorkingCalendar.PlanMonth> parseRplsrPlan(String planJson) {
    List<AR_WorkingCalendar.PlanMonth> months = new List<AR_WorkingCalendar.PlanMonth>();
    if (String.isBlank(planJson)) {
      return months;
    }
    try {
      Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(planJson);
      for (Object raw : (List<Object>) root.get('mois')) {
        Map<String, Object> row = (Map<String, Object>) raw;
        AR_WorkingCalendar.PlanMonth pm = new AR_WorkingCalendar.PlanMonth();
        pm.m = (String) row.get('m');
        pm.ouvres = Integer.valueOf(row.get('ouvres'));
        pm.vendus = Decimal.valueOf(String.valueOf(row.get('vendus')));
        pm.produits = row.get('produits') == null ? null : Decimal.valueOf(String.valueOf(row.get('produits')));
        if (String.isBlank(pm.m)) {
          throw new IllegalArgumentException('mois');
        }
        months.add(pm);
      }
    } catch (Exception e) {
      throw newAuraException(Label.AR_Msg_PM_RplsrPlanInvalid);
    }
    return months;
  }

  private static String serializeRplsrPlan(List<AR_WorkingCalendar.PlanMonth> months) {
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (AR_WorkingCalendar.PlanMonth pm : months) {
      rows.add(new Map<String, Object>{ 'm' => pm.m, 'ouvres' => pm.ouvres, 'vendus' => pm.vendus, 'produits' => pm.produits });
    }
    return JSON.serialize(new Map<String, Object>{ 'v' => RPLSR_PLAN_VERSION, 'mois' => rows });
  }

  /** Jours produits envoyés par le client ({"2027-02": 9}) ; JSON illisible → erreur explicite. */
  private static Map<String, Decimal> parseRplsrProduced(String producedJson) {
    Map<String, Decimal> produced = new Map<String, Decimal>();
    if (String.isBlank(producedJson)) {
      return produced;
    }
    try {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(producedJson);
      for (String key : raw.keySet()) {
        produced.put(key, Decimal.valueOf(String.valueOf(raw.get(key))));
      }
    } catch (Exception e) {
      throw newAuraException(Label.AR_Msg_PM_RplsrPlanInvalid);
    }
    return produced;
  }

  /**
   * Écrit sur `m` le mode, la base, le plan (ouvrés et vendus recalculés ici depuis les dates, la base et le pays
   * de l'entité ; seuls les jours produits viennent du client) et les deux synthèses. Le plan est reconstruit
   * (répartition équilibrée) quand les dates ou la base ont changé depuis l'enregistrement, ou quand les mois
   * envoyés ne sont pas ceux de la mission. Aucun DML ; le brouillon reste libre, les gardes sont à la validation.
   */
  private static void applyRplsrPlan(AR_Price_Matrix__c m, MatrixInput input) {
    m.AR_RPLSR_Plan__c = null;
    m.AR_RPLSR_Days_Sold__c = null;
    m.AR_RPLSR_Days_Produced__c = null;
    if (input.rplsrEnabled != true) {
      m.AR_RPLSR_Enabled__c = false;
      m.AR_RPLSR_Days_Per_Month__c = input.rplsrDaysPerMonth;
      return;
    }
    m.AR_RPLSR_Enabled__c = true;
    AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
    AR_PTF_Entity_Referential__c entityRef = applySettingsDefaults(ctx, m.AR_Entity_Ref__c);
    Decimal base = input.rplsrDaysPerMonth != null
      ? input.rplsrDaysPerMonth.setScale(2, RoundingMode.HALF_UP)
      : defaultRplsrDaysPerMonth(ctx.workingDaysPerYear);
    m.AR_RPLSR_Days_Per_Month__c = base;
    if (base <= 0 || base > RPLSR_MAX_DAYS_PER_MONTH) {
      return;
    }
    String country = entityRef != null ? entityRef.AR_Country__c : null;
    List<AR_WorkingCalendar.PlanMonth> months = AR_WorkingCalendar.monthsOf(
      m.AR_Start_Date__c, m.AR_End_Date__c, country, base
    );
    if (months.isEmpty()) {
      return;
    }
    Map<String, Decimal> produced = parseRplsrProduced(input.rplsrProduced);
    Set<String> expectedKeys = new Set<String>();
    for (AR_WorkingCalendar.PlanMonth pm : months) {
      expectedKeys.add(pm.m);
    }
    Boolean rebuild = !produced.keySet().equals(expectedKeys) || rplsrChangedSinceSave(m, base);
    if (rebuild) {
      AR_WorkingCalendar.balance(months);
    } else {
      for (AR_WorkingCalendar.PlanMonth pm : months) {
        pm.produits = produced.get(pm.m);
      }
    }
    m.AR_RPLSR_Plan__c = serializeRplsrPlan(months);
    m.AR_RPLSR_Days_Sold__c = AR_WorkingCalendar.totalSold(months);
    m.AR_RPLSR_Days_Produced__c = AR_WorkingCalendar.totalProduced(months).setScale(0, RoundingMode.HALF_UP);
  }

  /** Dates de mission ou base différentes de celles d'un plan déjà enregistré : les jours produits envoyés sont périmés. */
  private static Boolean rplsrChangedSinceSave(AR_Price_Matrix__c m, Decimal base) {
    if (m.Id == null) {
      return false;
    }
    List<AR_Price_Matrix__c> stored = [
      SELECT AR_Start_Date__c, AR_End_Date__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Per_Month__c, AR_RPLSR_Plan__c
      FROM AR_Price_Matrix__c
      WHERE Id = :m.Id
      LIMIT 1
    ];
    if (stored.isEmpty() || stored[0].AR_RPLSR_Enabled__c != true || stored[0].AR_RPLSR_Plan__c == null) {
      return false;
    }
    return stored[0].AR_Start_Date__c != m.AR_Start_Date__c
      || stored[0].AR_End_Date__c != m.AR_End_Date__c
      || stored[0].AR_RPLSR_Days_Per_Month__c != base;
  }

  /**
   * Régie sans régule (docs/265c §7) : mention secondaire des e-mails et des écrans de dérogation,
   * « N j produits pour M j vendus · MC2 régie classique x % ». Null hors mode actif. Les jours sont les
   * totaux figés de la matrice ; la MC2 classique (mode éteint) est recalculée du TJM et du coût unitaire.
   */
  public static String rplsrMention(AR_Price_Matrix__c m) {
    if (m.AR_RPLSR_Enabled__c != true || m.AR_RPLSR_Days_Sold__c == null) {
      return null;
    }
    Decimal tjm = effectiveTjm(m);
    String classique = '–';
    if (tjm != null && tjm > 0 && m.AR_Total_Daily_Cost__c != null) {
      AR_PricingCalculator.MC2Result mc2 = AR_PricingCalculator.calcMC2(tjm, m.AR_Total_Daily_Cost__c, m.AR_RFA_Percent__c);
      classique = AR_PTFFormatUtil.formatNumberFr((mc2.mc2PercentFraction * 100).setScale(1, RoundingMode.HALF_UP), 1);
      classique = classique.contains(',') ? classique : classique + ',0';
    }
    Decimal produits = m.AR_RPLSR_Days_Produced__c == null ? 0 : m.AR_RPLSR_Days_Produced__c;
    return String.format(
      Label.AR_RPLSR_Mention,
      new List<String>{
        AR_PTFFormatUtil.formatNumberFr(produits, 0),
        AR_PTFFormatUtil.formatNumberFr(m.AR_RPLSR_Days_Sold__c, 2),
        classique
      }
    );
  }

  /**
   * Gardes de la régie sans régule (docs/265 §4.5) : dates de mission, base entre 0 (exclu) et 23, plan présent et couvrant
   * exactement les mois de la mission, jours produits entiers, positifs ou nuls et au plus égaux aux jours ouvrés du mois.
   * Bloquent la validation et la dérogation ; le brouillon reste libre. Vide hors mode.
   */
  public static List<AR_PTFDataService.Prerequisite> rplsrPrerequisites(AR_Price_Matrix__c m) {
    List<AR_PTFDataService.Prerequisite> missing = new List<AR_PTFDataService.Prerequisite>();
    if (m.AR_RPLSR_Enabled__c != true) {
      return missing;
    }
    if (m.AR_Start_Date__c == null || m.AR_End_Date__c == null || m.AR_End_Date__c < m.AR_Start_Date__c) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_RplsrDatesMissing, Label.AR_Msg_PM_RplsrDatesMissingWhere));
      return missing;
    }
    Decimal base = m.AR_RPLSR_Days_Per_Month__c;
    if (base == null || base <= 0 || base > RPLSR_MAX_DAYS_PER_MONTH) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_RplsrBaseInvalid, Label.AR_Msg_PM_RplsrBaseInvalidWhere));
      return missing;
    }
    List<AR_WorkingCalendar.PlanMonth> plan = parseRplsrPlan(m.AR_RPLSR_Plan__c);
    Set<String> planKeys = new Set<String>();
    for (AR_WorkingCalendar.PlanMonth pm : plan) {
      planKeys.add(pm.m);
    }
    Set<String> missionKeys = new Set<String>();
    for (AR_WorkingCalendar.PlanMonth pm : AR_WorkingCalendar.monthsOf(m.AR_Start_Date__c, m.AR_End_Date__c, null, base)) {
      missionKeys.add(pm.m);
    }
    if (plan.isEmpty() || plan.size() != planKeys.size() || !planKeys.equals(missionKeys)) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_RplsrPlanMissing, Label.AR_Msg_PM_RplsrPlanMissingWhere));
      return missing;
    }
    Decimal totalProduced = 0;
    for (AR_WorkingCalendar.PlanMonth pm : plan) {
      if (pm.produits == null || pm.produits < 0 || pm.produits != pm.produits.setScale(0) || pm.produits > pm.ouvres) {
        missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_RplsrProducedInvalid, Label.AR_Msg_PM_RplsrProducedInvalidWhere));
        return missing;
      }
      totalProduced += pm.produits;
    }
    // Ratio 0 : calculé tel quel par le moteur (MC2 = TJM), mais un plan sans aucun jour produit ne se valide pas.
    if (totalProduced == 0) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_RplsrNoProduced, Label.AR_Msg_PM_RplsrNoProducedWhere));
    }
    return missing;
  }

  @AuraEnabled
  public static MatrixSaveResult saveDraft(String inputJson) {
    try {
      return saveDraftInput(parseMatrixInput(inputJson));
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_SaveDraftAction);
    }
  }

  /**
   * Seule modification permise sur une matrice validée : l'entité (coordonnées de la prochaine PTF).
   * Aucun recalcul, aucun autre champ ; le verrou du trigger n'est franchi que pour ce DML.
   */
  @AuraEnabled
  public static void changeValidatedMatrixEntity(Id matrixId, Id entityRefId) {
    try {
      changeEntityOfValidatedMatrix(matrixId, entityRefId);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_ChangeEntityAction);
    }
  }

  public static void changeEntityOfValidatedMatrix(Id matrixId, Id entityRefId) {
    if (matrixId == null || entityRefId == null) {
      throw newAuraException(Label.AR_Msg_PM_ChangeEntityRequired);
    }
    // Lecture « with sharing » : une matrice que l'utilisateur ne voit pas est indiscernable d'une
    // matrice inexistante, même règle que pour la modification d'un brouillon.
    List<AR_Price_Matrix__c> rows = [SELECT Id, AR_Status__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
    if (rows.isEmpty()) {
      throw newAuraException(Label.AR_Msg_PM_ChangeEntityNoAccess);
    }
    if (rows[0].AR_Status__c != 'Validée' && rows[0].AR_Status__c != 'Validée par dérogation') {
      throw newAuraException(AR_I18n.format(Label.AR_Msg_PM_ChangeEntityStatus, new List<Object>{ rows[0].AR_Status__c }));
    }
    Integer activeCount = [SELECT COUNT() FROM AR_PTF_Entity_Referential__c WHERE Id = :entityRefId AND AR_Active__c = TRUE];
    if (activeCount == 0) {
      throw newAuraException(Label.AR_Msg_PM_ChangeEntityInactive);
    }
    Boolean previousBypass = AR_TriggerBypass.serviceContext;
    AR_TriggerBypass.serviceContext = true;
    try {
      Database.update(new AR_Price_Matrix__c(Id = matrixId, AR_Entity_Ref__c = entityRefId), AccessLevel.SYSTEM_MODE);
    } catch (DmlException e) {
      if (e.getDmlType(0) == StatusCode.INSUFFICIENT_ACCESS_OR_READONLY || e.getDmlType(0) == StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY) {
        throw newAuraException(Label.AR_Msg_PM_ChangeEntityNoAccess);
      }
      throw e;
    } finally {
      AR_TriggerBypass.serviceContext = previousBypass;
    }
  }

  /** Sauvegarde Brouillon (bouton dédié, ou étape interne à validate()/requestDerogation()). */
  public static MatrixSaveResult saveDraftInput(MatrixInput input) {
    AR_Price_Matrix__c m = buildMatrixFromInput(input);
    Id accountId = resolveAccountId(input.positionId);
    Boolean isNew = m.Id == null;
    if (isNew) {
      m.AR_Status__c = 'Brouillon';
    }
    AR_PricingResult result = calculateAndPopulate(m, accountId);
    // Session 41 : la quasi-totalité des champs écrits ici sont des champs calculés/dénormalisés
    // (Zone 1 lecture seule — AR_Account_Name__c, AR_Position_Name__c... — et les résultats du
    // moteur — AR_MC2_Percent__c, AR_Corridor_Segment__c, AR_TJM_Floor__c...), délibérément
    // AR_Pricing_User.editable=false : l'utilisateur ne doit jamais pouvoir les poser directement
    // (Data Loader, API), seul ce pipeline le peut. `upsert m;` en mode utilisateur échouait donc
    // pour TOUT BM réel avec « Operation failed due to fields being inaccessible » — jamais vu avant
    // cette session, aucun test antérieur n'exerçait saveDraftInput sous System.runAs pour un
    // non-administrateur. Même motif que AR_MatrixVersionService.createSnapshot (session 40) :
    // AccessLevel.SYSTEM_MODE bypass CRUD/FLS, le partage (with sharing, classe entière) reste lui
    // pleinement appliqué — un BM ne peut toujours écrire QUE sur une matrice qu'il peut voir.
    Database.upsert(m, AccessLevel.SYSTEM_MODE);

    MatrixSaveResult out = new MatrixSaveResult();
    out.matrixId = m.Id;
    // Le statut réel doit toujours venir de la source de vérité, jamais d'une supposition (session
    // 28b §1) : pour un enregistrement existant, `m` est un sObject PARTIEL construit par
    // buildMatrixFromInput (Id + champs saisis seulement) — AR_Status__c n'y est jamais réassigné
    // ici (seules validateInput/requestDerogationInput transitionnent le statut, et elles écrasent
    // déjà `out.status` après coup), donc `m.AR_Status__c` valait `null` pour toute resauvegarde d'un
    // Brouillon existant (bouton Sauvegarder, autosave) — le DTO ne portait pas le statut, et
    // `arPriceMatrixSimulator` verrouillait le formulaire sur un statut « undefined ». Une nouvelle
    // matrice reste bon marché (pas de requête, `m.AR_Status__c` vient d'être fixé ci-dessus) ; un
    // Brouillon existant est requêté pour rester correct quelle que soit l'évolution future du code.
    out.status = isNew
      ? m.AR_Status__c
      : requireMatrix([SELECT AR_Status__c FROM AR_Price_Matrix__c WHERE Id = :m.Id LIMIT 1]).AR_Status__c;
    out.calculation = result;
    out.rplsrPlan = m.AR_RPLSR_Plan__c;
    return out;
  }

  /**
   * MC2 ≥ plancher (segment ≠ below_floor) → statut Validée + snapshot immuable.
   * Sinon rejeté : le serveur fait foi, la dérogation est le seul chemin possible (cf. requestDerogation).
   */
  @AuraEnabled
  public static MatrixSaveResult validate(String inputJson) {
    try {
      return validateInput(parseMatrixInput(inputJson));
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_ValidateAction);
    }
  }

  public static MatrixSaveResult validateInput(MatrixInput input) {
    return validateInput(input, null);
  }

  /** `avenantBaseline` : MC2 de la matrice amendée déjà calculée par l'appelant (sinon recalculée pour un avenant). */
  public static MatrixSaveResult validateInput(MatrixInput input, AR_PricingResult avenantBaseline) {
    MatrixSaveResult saved = saveDraftInput(input);

    // Un avenant n'est pas jugé sur le plancher mais sur la MC2 de la matrice amendée (AR_AvenantService).
    if (avenantBaseline != null || AR_AvenantService.isAvenant(saved.matrixId)) {
      AR_PricingResult before = avenantBaseline != null ? avenantBaseline : AR_AvenantService.baselineResult(saved.matrixId);
      if (AR_AvenantService.requiresHumanValidation(before, saved.calculation) && !isDispensedFromDerogation(saved.calculation)) {
        throw newAuraException(
          Label.AR_Msg_PM_AvenantProfitabilityDown
        );
      }
    } else if (saved.calculation.corridorSegment == 'below_floor' && !isDispensedFromDerogation(saved.calculation)) {
      throw newAuraException(
        Label.AR_Msg_PM_BelowFloorNeedsDerogation
      );
    }

    // Session 108 : seules les données de la MATRICE bloquent (dates). Besoin/entité = avertissements
    // affichés par l'écran, jamais un refus ici. Levée après saveDraftInput : l'exception annule
    // toute la transaction, brouillon compris.
    // Un avenant reprend le prix d'une matrice déjà négociée : pas de prix indicatifs à ressaisir.
    requireMatrixPrerequisites(
      input,
      Label.AR_Msg_PM_VerbValidateMatrix,
      avenantBaseline == null && !AR_AvenantService.isAvenant(saved.matrixId)
    );

    AR_Price_Matrix__c mUpdate = new AR_Price_Matrix__c(
      Id = saved.matrixId,
      AR_Status__c = 'Validée',
      AR_Validated_At__c = System.now()
    );
    // AR_Validated_At__c est aussi un champ système (editable=false, cf. commentaire de
    // saveDraftInput ci-dessus) : même bypass nécessaire.
    Database.update(mUpdate, AccessLevel.SYSTEM_MODE);
    AR_MatrixVersionService.createSnapshot(saved.matrixId, 'validation');
    AR_NotificationService.sendAutoValidationEmail(saved.matrixId);
    AR_NotificationService.sendAutoValidationHierarchyNotificationIfImmediate(saved.matrixId);
    applyNotificationWarning(saved);

    saved.status = 'Validée';
    return saved;
  }

  /** Motif obligatoire + valideur sélectionné ; refuse une seconde dérogation En attente sur la même matrice. */
  @AuraEnabled
  public static MatrixSaveResult requestDerogation(String reqJson) {
    if (String.isBlank(reqJson)) {
      throw newAuraException(
        Label.AR_Msg_PM_EmptyDerogationPayload
      );
    }
    try {
      return requestDerogationInput(
        (DerogationRequest) JSON.deserialize(reqJson, DerogationRequest.class)
      );
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_DerogationRequestAction);
    }
  }

  public static MatrixSaveResult requestDerogationInput(DerogationRequest req) {
    if (req.derogationReasonIds == null || req.derogationReasonIds.isEmpty()) {
      throw newAuraException(
        Label.AR_Msg_PM_AtLeastOneReason
      );
    }
    if (req.selectedValidatorId == null) {
      throw newAuraException(Label.AR_Msg_PM_ValidatorRequired);
    }
    // Session 220 : le commentaire est obligatoire ; des espaces seuls ne comptent pas.
    if (String.isBlank(req.reason)) {
      throw newAuraException(Label.AR_Msg_PM_DerogationCommentRequired);
    }

    // Session 108 : une dérogation sur une matrice sans dates serait le même piège, en pire.
    requireMatrixPrerequisites(
      req.matrixInput,
      Label.AR_Msg_PM_VerbRequestDerogation,
      !AR_AvenantService.isAvenant(req.matrixInput.matrixId)
    );

    // Session 79 : vérifier que le créateur a DA et/ou DD renseignés. Si aucun des deux,
    // le blocage est explicite, pas silencieux.
    MatrixSaveResult saved = saveDraftInput(req.matrixInput);

    // Session 237 : même règle que la validation directe — la décision serveur et le bouton affiché concordent.
    if (isDispensedFromDerogation(saved.calculation)) {
      throw newAuraException(Label.AR_Msg_PM_DerogationNotNeeded);
    }

    verifyCreatorHasValidatorChain(saved.matrixId);
    requireSelectableValidator(saved.matrixId, req.selectedValidatorId);

    List<AR_Derogation__c> pending = [
      SELECT Id
      FROM AR_Derogation__c
      WHERE
        AR_Price_Matrix__c = :saved.matrixId
        AND AR_Decision__c = 'En attente'
      LIMIT 1
    ];
    if (!pending.isEmpty()) {
      throw newAuraException(
        Label.AR_Msg_PM_DerogationAlreadyPending
      );
    }

    AR_Derogation__c derogation = new AR_Derogation__c(
      AR_Price_Matrix__c = saved.matrixId,
      AR_Selected_Validator__c = req.selectedValidatorId,
      AR_Requester_Reason__c = req.reason,
      AR_Decision__c = 'En attente',
      AR_Requested_At__c = System.now()
    );
    // Session 41 : AR_Decision__c/AR_Selected_Validator__c sont editable=false pour AR_Pricing_User
    // (état de workflow, pas une saisie libre) — même motif que saveDraftInput ci-dessus, jamais
    // exercé sous System.runAs avant cette session.
    Database.insert(derogation, AccessLevel.SYSTEM_MODE);
    AR_ReasonService.insertSelections(null, derogation.Id, req.derogationReasonIds);

    update new AR_Price_Matrix__c(
      Id = saved.matrixId,
      AR_Status__c = 'En dérogation',
      AR_Derogation_Reason__c = req.reason,
      AR_Selected_Validator__c = req.selectedValidatorId
    );

    AR_NotificationService.sendDerogationRequestEmail(derogation.Id);
    applyNotificationWarning(saved);

    saved.status = 'En dérogation';
    return saved;
  }

  /**
   * Session 237 — dispense de dérogation : MC2/jour (convertie en EUR au taux de la matrice) égale ou
   * supérieure au montant administré dans Paramètres généraux. Montant vide = règle désactivée.
   * Le montant est lu une fois par transaction (une requête de plus par appel dépassait la limite de
   * SOQL des transactions qui enchaînent plusieurs avenants) ; AR_AdminSettingsService le remet à zéro.
   */
  public static Boolean isDispensedFromDerogation(AR_PricingResult calc) {
    if (!dispenseAmountLoaded) {
      AR_General_Setting__c settings = loadGeneralSettings();
      dispenseAmountCache = settings != null ? settings.AR_Derogation_Waiver_Amount__c : null;
      dispenseAmountLoaded = true;
    }
    if (calc == null || calc.mc2PerDayEurEquivalent == null || dispenseAmountCache == null) {
      return false;
    }
    return calc.mc2PerDayEurEquivalent >= dispenseAmountCache;
  }

  public static void resetDispenseAmountCache() {
    dispenseAmountLoaded = false;
    dispenseAmountCache = null;
  }

  private static Boolean dispenseAmountLoaded = false;
  private static Decimal dispenseAmountCache;

  private static void applyNotificationWarning(MatrixSaveResult saved) {
    AR_NotificationService.DeliveryWarning warning = AR_NotificationService.consumeWarning();
    if (warning != null) {
      saved.notificationWarningDetail = warning.detail;
    }
  }

  private static AR_Price_Matrix__c buildMatrixFromInput(MatrixInput input) {
    AR_Price_Matrix__c m = input.matrixId != null
      ? new AR_Price_Matrix__c(Id = input.matrixId)
      : new AR_Price_Matrix__c();
    m.AR_Position__c = input.positionId;
    m.AR_Currency__c = input.currencyCode;
    m.AR_Contract_Type__c = input.contractType;
    m.AR_Annual_Salary__c = input.annualSalary;
    m.AR_CJM_Before_Markup__c = input.cjmBeforeMarkup;
    m.AR_Markup_Applied__c = input.markupApplied;
    m.AR_CJM_VIE__c = input.cjmVie;
    m.AR_CJM_Nearshore__c = input.cjmNearshore;
    m.AR_Fee_IK__c = input.feeIk;
    m.AR_Fee_Meals__c = input.feeMeals;
    m.AR_Fee_Lodging__c = input.feeLodging;
    m.AR_Fee_OM_Other__c = input.feeOmOther;
    m.AR_Fee_Periods__c = serializeFeePeriods(parseFeePeriods(input.feePeriods));
    m.AR_Gratuity_Days__c = input.gratuityDays;
    m.AR_Fee_Computer__c = input.feeComputer;
    m.AR_Fee_Phone__c = input.feePhone;
    m.AR_Fee_Monthly_Other__c = input.feeMonthlyOther;
    m.AR_Fee_Training__c = input.feeTraining;
    m.AR_Fee_EPI__c = input.feeEpi;
    m.AR_Fee_OFII_Tax__c = input.feeOfiiTax;
    m.AR_Fee_Other__c = input.feeOther;
    m.AR_RFA_Percent__c = input.rfaPercent;
    m.AR_Proposed_TJM__c = input.proposedTjm;
    // Périodes de TJM (docs/254) : stockage du JSON ; le pondéré (AR_TJM_Weighted__c) est écrit par le moteur.
    m.AR_TJM_Periods__c = serializeTjmPeriods(parseTjmPeriods(input.tjmPeriods));
    m.AR_Salary_Periods__c = serializeSalaryPeriods(parseSalaryPeriods(input.salaryPeriods));
    m.AR_Nego_Price_2__c = input.negoPrice2;
    m.AR_Client_Grid__c = input.clientGrid == true;
    // Grille cochée : les prix indicatifs sont vidés, jamais conservés en silence.
    if (m.AR_Client_Grid__c) {
      m.AR_Nego_Price_2__c = null;
      m.AR_Nego_Price_3__c = null;
    } else {
      m.AR_Nego_Price_3__c = input.negoPrice3;
    }
    m.AR_Entity_Ref__c = String.isBlank(input.entity) ? null : (Id) input.entity;
    // Session 54 : AR_Consultant_Name__c n'est plus écrit par aucune sauvegarde — seul le lookup
    // AR_Consultant__c l'est désormais. Le texte historique (6 matrices sur 47) n'est ni recopié ni
    // effacé : une sauvegarde ultérieure d'une de ces 6 matrices laisse ce champ intact (simplement
    // absent de ce DML partiel), cf. AR_Consultant_Name__c.field-meta.xml.
    m.AR_Consultant__c = input.consultantId;
    m.AR_Client_Site__c = input.clientSite;
    m.AR_Start_Date__c = input.startDate;
    m.AR_End_Date__c = input.endDate;
    m.AR_Number_Of_Days__c = input.numberOfDays;
    m.AR_Planned_Leave_Days__c = input.plannedLeaveDays;
    m.AR_VIE_Country__c = input.vieCountryId;
    m.AR_Nearshore_Country__c = input.nearshoreCountryId;
    m.AR_Seniority__c = input.seniorityLevel;

    PositionContext posCtx = requireAccessiblePositionContext(input.positionId);
    m.AR_Account_Name__c = posCtx.accountName;
    m.AR_Account_Country__c = posCtx.accountCountry;
    // Périmètre du besoin : figé avec les autres valeurs de la Zone 1 ; une matrice validée n'est plus réenregistrée.
    m.AR_Perimeter__c = posCtx.perimetre == null ? null : posCtx.perimetre.left(255);
    m.AR_Position_Name__c = posCtx.positionName;
    m.AR_Manager_Contact__c = posCtx.managerContactId;
    // Pré-remplissage des dates mission depuis le besoin si non fournies en input
    if (m.AR_Start_Date__c == null && posCtx.startDate != null) {
      m.AR_Start_Date__c = posCtx.startDate;
    }
    applyRplsrPlan(m, input);
    // Mode RPLSR : missionDays = total vendu.
    if (m.AR_RPLSR_Enabled__c == true && m.AR_RPLSR_Days_Sold__c != null) {
      m.AR_Number_Of_Days__c = m.AR_RPLSR_Days_Sold__c;
    }
    return m;
  }

  // AuraHandledException.getMessage() ne restitue le message que si setMessage() est appelé
  // explicitement avant le throw (comportement Apex documenté).
  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  private static Id resolveAccountId(Id positionId) {
    return AR_AccountHierarchy.accountOfPosition(positionId);
  }

  /**
   * Pipeline complet sur une matrice EN MÉMOIRE, sans aucune écriture : sert à mesurer ce que donnerait une
   * matrice existante (la matrice amendée d'un avenant) avec les réglages d'aujourd'hui. `m` est modifié.
   */
  public static AR_PricingResult evaluateWithoutSaving(AR_Price_Matrix__c m) {
    return calculateAndPopulate(m, resolveAccountId(m.AR_Position__c));
  }

  /** Calcule le pipeline complet et écrit les champs résultats sur le sObject (non sauvegardé ici). */
  private static AR_PricingResult calculateAndPopulate(
    AR_Price_Matrix__c m,
    Id accountIdForCorridor
  ) {
    AR_PricingCalculator.Context ctx = toContext(m);
    AR_General_Setting__c generalSettings = loadGeneralSettings();
    AR_PTF_Entity_Referential__c entityRef = applySettingsDefaults(ctx, m.AR_Entity_Ref__c, generalSettings);
    if (ctx.contractType == 'VIE' && ctx.cjmVie == null) {
      ctx.cjmVie = loadVieAllowance(m.AR_Account_Country__c, m.AR_Currency__c);
    }
    if (ctx.contractType == 'NEARSHORE' && ctx.cjmNearshore == null) {
      ctx.cjmNearshore = loadNearshoreRate(m);
      m.AR_CJM_Nearshore__c = ctx.cjmNearshore;
    }
    // Défense en profondeur (session 28) : couvre le cas où AUCUN pays n'est connu du tout (ni
    // sélectionné dans le référentiel, ni déduit de AR_Account_Country__c) — loadVieAllowance/
    // loadNearshoreRate ci-dessus ne s'exécutent même pas dans ce cas (country blank), donc ne
    // peuvent pas lever leur propre exception nommée. Sans cette garde, AR_PricingCalculator.
    // calcTotalDailyCost lèverait une NullPointerException technique plus bas dans le pipeline.
    if (ctx.contractType == 'VIE' && ctx.cjmVie == null) {
      throw newAuraException(
        Label.AR_Msg_PM_VieAllowanceMissing
      );
    }
    if (ctx.contractType == 'NEARSHORE' && ctx.cjmNearshore == null) {
      throw newAuraException(
        Label.AR_Msg_PM_NearshoreCostMissing
      );
    }

    CorridorResolution corridor = resolveCorridor(accountIdForCorridor, entityRef, generalSettings);
    AR_PricingCalculator.ThresholdPercents customPcts = corridor.pcts;

    // Résolution + gel du taux (session 24) : date de résolution = aujourd'hui tant que la matrice
    // reste éditable (Brouillon/En dérogation) — même principe que le corridor, cf. en-tête
    // AR_CurrencyRateService. Absence de taux = blocage explicite du calcul, jamais un repli sur 1
    // (CLAUDE.md : erreur de facteur invisible sinon). Résolu AVANT les comparables (ci-dessous) :
    // le taux leur est nécessaire pour convertir p90Tjm dans la devise de la matrice (session 24b).
    AR_CurrencyRateService.RateResolution rateResolution;
    try {
      rateResolution = AR_CurrencyRateService.resolveRate(m.AR_Currency__c, Date.today());
    } catch (AR_CurrencyRateService.NoRateAvailableException e) {
      throw newAuraException(e.getMessage());
    }

    // Top 10 % réel (session 9) : AR_ComparablesService.getMarketReference remonte le p90 des
    // comparables gagnés ; calcThresholds ne le retient que s'il dépasse idéal×1.10 (repli déjà
    // géré côté AR_PricingCalculator, inchangé). Converti dans la devise de la matrice (session 24b)
    // — l'historique de comparables est en EUR (org mono-devise avant ce lot), mais top10Comparables
    // est ensuite comparé à des seuils en devise de la matrice : sans conversion, une matrice non-EUR
    // mélangerait un p90 EUR dans un calcul GBP/MAD, contamination invisible du seuil Top 10 %.
    // Resserrement par séniorité (session 28) : approximatif, cf. AR_ComparablesService
    // (correspondance de sous-chaîne sur l'intitulé du besoin, aucun champ fiable côté Connexys).
    String seniorityLevelName = m.AR_Seniority__c;
    AR_ComparablesService.MarketReference marketRef = AR_ComparablesService.getMarketReference(
      m.AR_Position__c,
      m.AR_Contract_Type__c,
      m.AR_Currency__c,
      rateResolution.rateToEur,
      seniorityLevelName
    );
    Decimal top10Comparables = marketRef.hasEnoughData ? marketRef.p90Tjm : 0;

    AR_PricingResult result = AR_PricingCalculator.compute(
      ctx,
      m.AR_RFA_Percent__c,
      m.AR_Proposed_TJM__c,
      top10Comparables,
      customPcts,
      rateResolution.rateToEur
    );

    m.AR_Total_Daily_Cost__c = result.totalDailyCost;
    m.AR_TJM_Floor__c = result.tjmFloor;
    m.AR_TJM_Target__c = result.tjmTarget;
    m.AR_TJM_Ideal__c = result.tjmIdeal;
    m.AR_TJM_Top10__c = result.tjmTop10;
    m.AR_MC2_Per_Day__c = result.mc2PerDay;
    m.AR_MC2_Percent__c = result.mc2PercentHuman;
    m.AR_Corridor_Segment__c = result.corridorSegment;
    m.AR_Floor_Percent_Applied__c = result.floorPercentApplied;
    m.AR_Target_Percent_Applied__c = result.targetPercentApplied;
    m.AR_Ideal_Percent_Applied__c = result.idealPercentApplied;
    m.AR_Corridor_Source__c = corridor.source;
    m.AR_Corridor_Entity_Name__c = corridor.entityName;
    result.corridorSource = corridor.source;
    result.corridorEntityName = corridor.entityName;
    m.AR_Contract_Coefficient_Applied__c = result.contractCoefficientApplied;
    m.AR_Working_Days_Applied__c = result.workingDaysPerYearApplied;
    m.AR_Currency_Rate_Applied__c = result.currencyRateApplied;
    m.AR_Currency_Rate_Effective_Date__c = rateResolution.effectiveDate;
    m.AR_TJM_EUR_Equivalent__c = result.tjmEurEquivalent;
    m.AR_TJM_Weighted__c = result.tjmWeighted != null ? result.tjmWeighted.setScale(2, RoundingMode.HALF_UP) : null;
    m.AR_Total_Daily_Cost_EUR_Equivalent__c = result.totalDailyCostEurEquivalent;
    m.AR_MC2_Per_Day_EUR_Equivalent__c = result.mc2PerDayEurEquivalent;
    return result;
  }

  /**
   * Contexte de calcul d'une matrice déjà enregistrée, tel que le moteur l'a figé (jours travaillés et
   * coefficient appliqués). Sert au tableau de bord pour ramener les frais au jour avec les fonctions du
   * moteur, sans les recalculer à côté (session 285).
   */
  public static AR_PricingCalculator.Context costContextOf(AR_Price_Matrix__c m) {
    AR_PricingCalculator.Context ctx = toContext(m);
    if (m.AR_Working_Days_Applied__c != null && m.AR_Working_Days_Applied__c > 0) {
      ctx.workingDaysPerYear = m.AR_Working_Days_Applied__c;
    }
    if (m.AR_Contract_Coefficient_Applied__c != null) {
      ctx.contractCoefficient = m.AR_Contract_Coefficient_Applied__c;
    }
    return ctx;
  }

  private static AR_PricingCalculator.Context toContext(AR_Price_Matrix__c m) {
    AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
    ctx.contractType = m.AR_Contract_Type__c;
    ctx.annualSalary = m.AR_Annual_Salary__c;
    ctx.cjmBeforeMarkup = m.AR_CJM_Before_Markup__c;
    ctx.markupApplied = m.AR_Markup_Applied__c;
    ctx.cjmVie = m.AR_CJM_VIE__c;
    ctx.cjmNearshore = m.AR_CJM_Nearshore__c;
    ctx.feeIk = m.AR_Fee_IK__c;
    ctx.feeMeals = m.AR_Fee_Meals__c;
    ctx.feeLodging = m.AR_Fee_Lodging__c;
    ctx.feeOmOther = m.AR_Fee_OM_Other__c;
    ctx.feePeriods = parseFeePeriods(m.AR_Fee_Periods__c);
    ctx.tjmPeriods = parseTjmPeriods(m.AR_TJM_Periods__c);
    ctx.salaryPeriods = parseSalaryPeriods(m.AR_Salary_Periods__c);
    ctx.gratuityDays = m.AR_Gratuity_Days__c;
    ctx.feeComputer = m.AR_Fee_Computer__c;
    ctx.feePhone = m.AR_Fee_Phone__c;
    ctx.feeMonthlyOther = m.AR_Fee_Monthly_Other__c;
    ctx.feeTraining = m.AR_Fee_Training__c;
    ctx.feeEpi = m.AR_Fee_EPI__c;
    ctx.feeOfiiTax = m.AR_Fee_OFII_Tax__c;
    ctx.feeOther = m.AR_Fee_Other__c;
    ctx.missionDays = m.AR_Number_Of_Days__c;
    ctx.plannedLeaveDays = m.AR_Planned_Leave_Days__c;
    ctx.rplsrRatio = rplsrRatioOf(m);
    return ctx;
  }

  private static AR_PricingCalculator.Context toContext(SimulateRequest req) {
    AR_PricingCalculator.Context ctx = new AR_PricingCalculator.Context();
    ctx.contractType = req.contractType;
    ctx.annualSalary = req.annualSalary;
    ctx.cjmBeforeMarkup = req.cjmBeforeMarkup;
    ctx.markupApplied = req.markupApplied;
    ctx.cjmVie = req.cjmVie;
    ctx.cjmNearshore = req.cjmNearshore;
    ctx.feeIk = req.feeIk;
    ctx.feeMeals = req.feeMeals;
    ctx.feeLodging = req.feeLodging;
    ctx.feeOmOther = req.feeOmOther;
    ctx.gratuityDays = req.gratuityDays;
    ctx.feeComputer = req.feeComputer;
    ctx.feePhone = req.feePhone;
    ctx.feeMonthlyOther = req.feeMonthlyOther;
    ctx.feeTraining = req.feeTraining;
    ctx.feeEpi = req.feeEpi;
    ctx.feeOfiiTax = req.feeOfiiTax;
    ctx.feeOther = req.feeOther;
    ctx.missionDays = req.numberOfDays;
    ctx.plannedLeaveDays = req.plannedLeaveDays;
    // SimulateRequest n'a pas de champ entité — ce point d'entrée reste non exposé au LWC (bug
    // wrapper Aura, cf. CLAUDE.md), pas de cascade entité pour lui.
    applySettingsDefaults(ctx, null);
    return ctx;
  }

  /**
   * Cascade entité → paramètre global → constante moteur (session 48, réunion client du
   * 03/09/2026), dans cet ordre de priorité décroissante : une valeur d'entité l'emporte sur le
   * paramètre général, qui l'emporte sur la constante d'AR_PricingCalculator. entityId = Id de la
   * fiche AR_Price_Matrix__c.AR_Entity_Ref__c (ou SimulateRequest.entity, absent aujourd'hui) — null si
   * aucune entité sélectionnée, auquel cas seuls les deux derniers niveaux s'appliquent.
   */
  private static AR_PTF_Entity_Referential__c applySettingsDefaults(AR_PricingCalculator.Context ctx, Id entityId) {
    return applySettingsDefaults(ctx, entityId, loadGeneralSettings());
  }

  /** Même cascade avec les réglages déjà lus : une seule lecture par calcul (session 291c, limite SOQL). */
  private static AR_PTF_Entity_Referential__c applySettingsDefaults(
    AR_PricingCalculator.Context ctx,
    Id entityId,
    AR_General_Setting__c settings
  ) {
    if (settings != null) {
      if (settings.AR_Working_Days_Per_Year__c != null) {
        ctx.workingDaysPerYear = settings.AR_Working_Days_Per_Year__c;
      }
      if (settings.AR_Markup_Percent__c != null) {
        ctx.markupPercentSetting = settings.AR_Markup_Percent__c;
      }
      if (settings.AR_Markup_Max__c != null) {
        ctx.markupMaxSetting = settings.AR_Markup_Max__c;
      }
    }
    // Coefficient CDI/CDD administrable au niveau global (session 28) : TEMPORAIREMENT découplé
    // (session 28, incident post-livraison) — AR_General_Setting__c.AR_CDI_Coefficient__c /
    // AR_CDD_Coefficient__c existent en métadonnées (Tooling API) mais restent invisibles en
    // SOQL/DML/Apex anonyme, y compris après suppression/redéploiement. ctx.contractCoefficient
    // reste donc toujours null à ce stade, et AR_PricingCalculator retombe sur son défaut moteur
    // 2,02 (CONTRACT_COEFFICIENT_DEFAULT) pour CDI comme CDD, SAUF si l'entité ci-dessous porte son
    // propre coefficient — comportement identique à avant la tentative d'administrabilité globale,
    // pas une régression fonctionnelle. À rebrancher une fois l'org débloquée : cf.
    // docs/28-ecarts-contractuels.md.
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferentialForPricing(entityId);
    if (entityRef != null) {
      if (entityRef.AR_Coefficient__c != null) {
        ctx.contractCoefficient = entityRef.AR_Coefficient__c;
      }
      if (entityRef.AR_Working_Days__c != null) {
        ctx.workingDaysPerYear = entityRef.AR_Working_Days__c;
      }
    }
    return entityRef;
  }

  /** Remplace AR_Settings__mdt.getInstance('Default') (session 23 : migration __mdt → objet
   * custom pour permettre l'écriture DML synchrone depuis la page d'administration). */
  private static AR_General_Setting__c loadGeneralSettings() {
    List<AR_General_Setting__c> rows = [
      SELECT AR_Working_Days_Per_Year__c, AR_Markup_Percent__c, AR_Markup_Max__c, AR_Ofii_Tax_Rate__c, AR_Ofii_Tax_Cap__c,
        AR_Floor_Percent_Default__c, AR_Target_Percent_Default__c, AR_Ideal_Percent_Default__c,
        AR_Derogation_Waiver_Amount__c
      FROM AR_General_Setting__c
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** Niveau entité de la cascade (session 48). Même principe que AR_PTFDataService.
   * loadEntityReferential : un champ lu ailleurs sur cette variable doit figurer dans ce SELECT. Ne
   * filtre pas sur AR_Active__c — une entité désactivée à la sélection reste valide pour recalculer
   * une matrice qui la référence déjà (même raisonnement que la génération PTF). */
  private static AR_PTF_Entity_Referential__c loadEntityReferentialForPricing(Id entityId) {
    if (entityId == null) {
      return null;
    }
    List<AR_PTF_Entity_Referential__c> refs = [
      SELECT Name, AR_Country__c, AR_Coefficient__c, AR_Working_Days__c, AR_Floor_Percent__c, AR_Target_Percent__c, AR_Ideal_Percent__c
      FROM AR_PTF_Entity_Referential__c
      WHERE Id = :entityId
      LIMIT 1
    ];
    return refs.isEmpty() ? null : refs[0];
  }

  /** Origines possibles des seuils appliqués (figées sur la matrice dans AR_Corridor_Source__c). */
  public static final String CORRIDOR_ACCOUNT = 'ACCOUNT';
  public static final String CORRIDOR_ENTITY = 'ENTITY';
  public static final String CORRIDOR_DEFAULT = 'DEFAULT';

  /** Seuils appliqués, avec leur origine et le nom de l'entité quand elle les fournit. */
  public class CorridorResolution {
    public AR_PricingCalculator.ThresholdPercents pcts;
    public String source;
    public String entityName;

    public CorridorResolution(AR_PricingCalculator.ThresholdPercents pcts, String source, String entityName) {
      this.pcts = pcts;
      this.source = source;
      this.entityName = entityName;
    }
  }

  /**
   * Corridor effectivement appliqué, dans cet ordre (session 252) : grand compte (avec héritage parent →
   * enfant, session 146b) ; sinon entité PTF de la matrice si ses TROIS seuils sont renseignés ; sinon
   * paramètres généraux. Une entité partielle est ignorée (défauts), jamais complétée.
   */
  @TestVisible
  private static CorridorResolution resolveCorridor(Id accountId, AR_PTF_Entity_Referential__c entity) {
    return resolveCorridor(accountId, entity, null, false);
  }

  /** Réglages déjà lus par l'appelant (null = singleton absent) : pas de relecture (session 291c). */
  private static CorridorResolution resolveCorridor(
    Id accountId,
    AR_PTF_Entity_Referential__c entity,
    AR_General_Setting__c settings
  ) {
    return resolveCorridor(accountId, entity, settings, true);
  }

  private static CorridorResolution resolveCorridor(
    Id accountId,
    AR_PTF_Entity_Referential__c entity,
    AR_General_Setting__c settings,
    Boolean settingsProvided
  ) {
    AR_PricingCalculator.ThresholdPercents accountPcts = loadCorridorPercents(accountId);
    if (accountPcts != null) {
      return new CorridorResolution(accountPcts, CORRIDOR_ACCOUNT, null);
    }
    if (entity != null && hasCompleteThresholds(entity)) {
      return new CorridorResolution(
        new AR_PricingCalculator.ThresholdPercents(
          entity.AR_Floor_Percent__c,
          entity.AR_Target_Percent__c,
          entity.AR_Ideal_Percent__c
        ),
        CORRIDOR_ENTITY,
        entity.Name
      );
    }
    return new CorridorResolution(thresholdPercentsFrom(settingsProvided ? settings : loadGeneralSettings()), CORRIDOR_DEFAULT, null);
  }

  @TestVisible
  private static AR_PricingCalculator.ThresholdPercents resolveCorridorPercents(Id accountId, Id entityId) {
    return resolveCorridor(accountId, loadEntityReferentialForPricing(entityId)).pcts;
  }

  /** Une entité ne surcharge le corridor que si ses TROIS seuils sont renseignés. */
  private static Boolean hasCompleteThresholds(AR_PTF_Entity_Referential__c entity) {
    return entity.AR_Floor_Percent__c != null && entity.AR_Target_Percent__c != null && entity.AR_Ideal_Percent__c != null;
  }

  /**
   * Seuils par défaut du singleton, champ par champ : valeur en base sinon constante du moteur (même
   * logique que AR_GeneralSettingDefaults). `settings` null (singleton absent) → les trois constantes.
   */
  @TestVisible
  private static AR_PricingCalculator.ThresholdPercents thresholdPercentsFrom(
    AR_General_Setting__c settings
  ) {
    return new AR_PricingCalculator.ThresholdPercents(
      settings != null && settings.AR_Floor_Percent_Default__c != null
        ? settings.AR_Floor_Percent_Default__c
        : AR_PricingCalculator.FLOOR_PERCENT_DEFAULT,
      settings != null && settings.AR_Target_Percent_Default__c != null
        ? settings.AR_Target_Percent_Default__c
        : AR_PricingCalculator.TARGET_PERCENT_DEFAULT,
      settings != null && settings.AR_Ideal_Percent_Default__c != null
        ? settings.AR_Ideal_Percent_Default__c
        : AR_PricingCalculator.IDEAL_PERCENT_DEFAULT
    );
  }

  private static AR_PricingCalculator.ThresholdPercents loadCorridorPercents(
    Id accountId
  ) {
    if (accountId == null) {
      return null;
    }

    // Session 146b : réutiliser le helper partagé de remontée de hiérarchie
    List<Id> chain = AR_AccountHierarchy.chainFrom(accountId);
    if (chain == null || chain.isEmpty()) {
      return null;
    }

    Map<Id, AR_Account_Corridor__c> corridorByAccountId = new Map<Id, AR_Account_Corridor__c>();
    for (AR_Account_Corridor__c c : [
      SELECT AR_Account__c, AR_Floor_Percent__c, AR_Target_Percent__c, AR_Ideal_Percent__c
      FROM AR_Account_Corridor__c
      WHERE AR_Account__c IN :chain
    ]) {
      if (!corridorByAccountId.containsKey(c.AR_Account__c)) {
        corridorByAccountId.put(c.AR_Account__c, c);
      }
    }

    for (Id id : chain) {
      if (corridorByAccountId.containsKey(id)) {
        AR_Account_Corridor__c c = corridorByAccountId.get(id);
        return new AR_PricingCalculator.ThresholdPercents(
          c.AR_Floor_Percent__c,
          c.AR_Target_Percent__c,
          c.AR_Ideal_Percent__c
        );
      }
    }

    return null;
  }

  /**
   * Le référentiel VIE porte sa propre devise depuis la session 24 (CLAUDE.md : le moteur ne
   * convertit jamais). Un référentiel dans une devise différente de celle de la matrice n'est pas
   * silencieusement converti ni ignoré — bloqué bruyamment, même logique que l'absence de taux.
   */
  /**
   * Un pays VIE sans indemnité au référentiel n'est jamais traité comme un coût nul (session 28,
   * même règle que l'absence de taux de change, cf. AR_CurrencyRateService.NoRateAvailableException
   * et docs/24-multidevise.md §2) : sans ce blocage explicite, ctx.cjmVie reste null et
   * AR_PricingCalculator.calcTotalDailyCost lève une NullPointerException technique plus bas dans le
   * pipeline — ou pire, si un appelant s'écartait de ce chemin, un coût nul ferait passer MC2 à 100 %
   * (« Excellence ») sur une mission dont le coût réel est inconnu.
   */
  private static Decimal loadVieAllowance(String country, String matrixCurrency) {
    if (String.isBlank(country)) {
      return null;
    }
    List<AR_VIE_Referential__c> refs = [
      SELECT AR_Daily_Allowance__c, AR_Currency__c
      FROM AR_VIE_Referential__c
      WHERE Name = :country
      LIMIT 1
    ];
    if (refs.isEmpty()) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PM_NoVieAllowanceForCountry, new List<Object>{ country })
      );
    }
    assertReferentialCurrencyMatches('VIE', country, refs[0].AR_Currency__c, matrixCurrency);
    return refs[0].AR_Daily_Allowance__c;
  }

  /**
   * Même règle que loadVieAllowance ci-dessus, pour le référentiel Nearshore : ligne pays + séniorité de
   * la matrice, à défaut ligne pays + DEFAULT, sinon blocage nommé. La ligne retenue est inscrite dans
   * AR_Nearshore_Country__c. Une séniorité vide au référentiel n'est jamais lue comme DEFAULT.
   */
  private static Decimal loadNearshoreRate(AR_Price_Matrix__c m) {
    String country = m.AR_Account_Country__c;
    if (m.AR_Nearshore_Country__c != null) {
      List<AR_Nearshore_Referential__c> chosen = [
        SELECT Name
        FROM AR_Nearshore_Referential__c
        WHERE Id = :m.AR_Nearshore_Country__c
        LIMIT 1
      ];
      if (!chosen.isEmpty()) {
        country = chosen[0].Name;
      }
    }
    if (String.isBlank(country)) {
      return null;
    }
    AR_Nearshore_Referential__c ref = resolveNearshoreRow(country, m.AR_Seniority__c);
    assertReferentialCurrencyMatches('Nearshore', country, ref.AR_Currency__c, m.AR_Currency__c);
    m.AR_Nearshore_Country__c = ref.Id;
    return ref.AR_Daily_Rate__c;
  }

  @TestVisible
  private static AR_Nearshore_Referential__c resolveNearshoreRow(String country, String seniority) {
    Boolean noSeniority = String.isBlank(seniority);
    List<String> wanted = new List<String>{ NEARSHORE_DEFAULT_SENIORITY };
    if (!noSeniority) {
      wanted.add(seniority);
    }
    AR_Nearshore_Referential__c exact;
    AR_Nearshore_Referential__c fallback;
    for (AR_Nearshore_Referential__c r : [
      SELECT Id, AR_Daily_Rate__c, AR_Currency__c, AR_Seniority__c
      FROM AR_Nearshore_Referential__c
      WHERE Name = :country AND AR_Seniority__c IN :wanted
    ]) {
      if (r.AR_Seniority__c == NEARSHORE_DEFAULT_SENIORITY) {
        fallback = r;
      } else {
        exact = r;
      }
    }
    AR_Nearshore_Referential__c found = exact != null ? exact : fallback;
    if (found == null) {
      throw newAuraException(
        AR_I18n.format(
          Label.AR_Msg_PM_NoNearshoreRateForSeniority,
          new List<Object>{ country, noSeniority ? Label.AR_ANR_SeniorityDefault : seniority }
        )
      );
    }
    return found;
  }

  private static void assertReferentialCurrencyMatches(
    String referentialLabel,
    String country,
    String referentialCurrency,
    String matrixCurrency
  ) {
    String refCode = String.isNotBlank(referentialCurrency) ? referentialCurrency : 'EUR';
    String matrixCode = String.isNotBlank(matrixCurrency) ? matrixCurrency : 'EUR';
    if (refCode != matrixCode) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PM_ReferentialCurrencyMismatch, new List<Object>{ referentialLabel, country, refCode, matrixCode })
      );
    }
  }

  /** Vérifie qu'au moins un valideur est résolvable pour la matrice (même calcul que la liste proposée
   * à l'écran : AR_ValidatorChain). Session 79 : défense en profondeur — un appel direct à
   * requestDerogationInput ne peut pas contourner cette règle. Session 179 : le message nomme les
   * champs vides et la fiche concernée.
   */
  /** Le valideur choisi n'est ni le demandeur ni le propriétaire de la matrice (appel direct compris). */
  @TestVisible
  private static void requireSelectableValidator(Id matrixId, Id validatorId) {
    Id owner = requireMatrixOwner(matrixId);
    if (validatorId == UserInfo.getUserId() || validatorId == owner) {
      throw newAuraException(Label.AR_Msg_DRG_OwnRequest);
    }
    // Même résolution que la liste proposée : hiérarchie du propriétaire, valideurs de l'entité, valideurs de test.
    AR_ValidatorChain.Resolution resolution = AR_ValidatorChain.resolveForMatrix(matrixId);
    Boolean proposed = false;
    for (User u : resolution.validators) {
      proposed = proposed || u.Id == validatorId;
    }
    if (!proposed) {
      throw newAuraException(Label.AR_Msg_DRG_ValidatorNotProposed);
    }
  }

  @TestVisible
  private static void verifyCreatorHasValidatorChain(Id matrixId) {
    AR_ValidatorChain.Resolution resolution = AR_ValidatorChain.resolveForMatrix(matrixId);
    if (resolution.blockedReason != null) {
      throw newAuraException(resolution.blockedReason);
    }
  }

  /**
   * Session 107 : vérification des prérequis avant validation PTF — API qui évalue l'état SAISI
   * d'une matrice (reçue en JSON, non sauvegardée) pour que la liste reflète ce que l'utilisateur voit
   * à l'écran. Retourne la liste des champs à compléter avant validation, vide si tout est présent.
   *
   * Le LWC appelle cette méthode avant de lancer la validation ; si la liste n'est pas vide, un
   * panneau de blocage s'affiche avec la liste complète et les lieux de correction (whereToFix).
   */
  @AuraEnabled
  public static List<AR_PTFDataService.Prerequisite> getValidationPrerequisites(String inputJson) {
    try {
      return validationPrerequisitesForInput(parseMatrixInput(inputJson));
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PM_PrerequisitesCheckAction);
    }
  }

  /**
   * Session 108 : même construction que la sauvegarde (parseMatrixInput + buildMatrixFromInput,
   * y compris le pré-remplissage des dates depuis le besoin) — la 107 relisait des clés
   * `AR_*__c` que l'écran n'envoie jamais (il envoie startDate, endDate, positionId).
   * Aucun DML : buildMatrixFromInput ne fait que des lectures.
   */
  public static List<AR_PTFDataService.Prerequisite> validationPrerequisitesForInput(MatrixInput input) {
    return validationPrerequisitesForInput(input, true);
  }

  private static List<AR_PTFDataService.Prerequisite> validationPrerequisitesForInput(MatrixInput input, Boolean negoPricesRequired) {
    AR_Price_Matrix__c m = buildMatrixFromInput(input);
    List<AR_PTFDataService.Prerequisite> missing = AR_PTFDataService.validationPrerequisites(m);
    // Périodes de frais (docs/239) : leur somme ne peut pas dépasser la durée de la mission. Bloque la
    // validation et la dérogation (requireMatrixPrerequisites) ; le brouillon reste accepté.
    if (AR_PricingCalculator.calcFeePeriods(toContext(m)).exceedMission) {
      missing.add(
        new AR_PTFDataService.Prerequisite(
          Label.AR_Msg_PM_FeePeriodsExceedMission,
          Label.AR_Msg_PM_FeePeriodsExceedMissionWhere
        )
      );
    }
    missing.addAll(tjmPeriodsPrerequisites(m));
    missing.addAll(salaryPeriodsPrerequisites(m));
    missing.addAll(rplsrPrerequisites(m));
    missing.addAll(plannedLeavePrerequisites(m));
    // Prix intermédiaire et plancher : obligatoires à la validation et à la dérogation, sauf grille client.
    if (negoPricesRequired && m.AR_Client_Grid__c != true && (m.AR_Nego_Price_2__c == null || m.AR_Nego_Price_3__c == null)) {
      missing.add(new AR_PTFDataService.Prerequisite(Label.AR_Msg_PM_NegoPricesMissing, Label.AR_Msg_PM_NegoPricesMissingWhere));
    }
    return missing;
  }

  private static void requireMatrixPrerequisites(MatrixInput input, String action) {
    requireMatrixPrerequisites(input, action, true);
  }

  private static void requireMatrixPrerequisites(MatrixInput input, String action, Boolean negoPricesRequired) {
    List<AR_PTFDataService.Prerequisite> blocking = AR_PTFDataService.blockingOnly(
      validationPrerequisitesForInput(input, negoPricesRequired)
    );
    if (blocking.isEmpty()) {
      return;
    }
    List<String> labels = new List<String>();
    for (AR_PTFDataService.Prerequisite p : blocking) {
      labels.add(p.label + ' (' + p.whereToFix + ')');
    }
    throw newAuraException(
      AR_I18n.format(Label.AR_Msg_PM_CompleteFieldsBefore, new List<Object>{ action, String.join(labels, ' ; ') })
    );
  }
}