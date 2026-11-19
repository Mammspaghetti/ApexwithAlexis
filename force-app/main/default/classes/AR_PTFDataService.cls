/**
 * Collecte des données consommées par le gabarit PTF (pricing-tool.html:3035 buildPTFHTML /
 * pricing-tool.html:2808 computePTFSchedule), séparée strictement de leur mise en forme
 * (AR_PTFTemplate.page / AR_PTFTemplateController). Le jour où le gabarit de Matthieu arrive, seul
 * le rendu change — cette classe et la structure PTFData restent la source de vérité.
 *
 * Trois catégories de champs, documentées dans docs/20-generation-ptf.md :
 * A. Issus de la donnée Salesforce (matrice, besoin, compte, contact).
 * B. Issus d'un référentiel administrable (AR_PTF_Setting__mdt, AR_PTF_Entity_Referential__c) — jamais de
 *    constante en dur, ce qui est provisoire aujourd'hui devient paramétrable au jalon 1B sans
 *    déploiement.
 * C. Saisis par l'utilisateur au moment de la génération (GenerationInput) — surchargent, quand
 *    renseignés, les valeurs par défaut des catégories A/B.
 *
 * `with sharing` : ne doit exposer que des matrices visibles de l'utilisateur courant.
 */
public with sharing class AR_PTFDataService {
  private static final Set<String> GENERATABLE_STATUSES = new Set<String>{
    'Validée',
    'Validée par dérogation'
  };

  // Type de prestation figé à 'AT' (Assistance Technique, mono-consultant) : le multi-consultant CDS
  // est hors périmètre lot 1 (cf. CLAUDE.md). Ce n'est pas une valeur administrable à "corriger" plus
  // tard : c'est la définition même de ce que cette session sait produire.
  private static final String PTF_TYPE = 'AT';
  private static final Integer NB_CONSULTANTS = 1;

  // Session 30 : gabarit par défaut tant qu'aucun gabarit spécifique grand compte n'est arrivé
  // (livrable 1.2, cf. docs/30-ptf-previsualisation-et-gabarits.md §3). Ce n'est pas une valeur à
  // administrer : c'est le repli garanti de la résolution, symétrique de PTF_TYPE ci-dessus.
  public static final String GENERIC_TEMPLATE_CODE = 'GENERIQUE';

  /**
   * Les codes de gabarit connus, avec leur libellé d'affichage (session 35). Chaque code a une page
   * Visualforce dédiée, résolue par AR_PTFGenerationService.resolveTemplatePage — architecture
   * retenue : une page par gabarit, duplication de CSS assumée, pas de moteur paramétré par blocs
   * conditionnels (ces documents sont contractuels : une régression de mise en page sur l'un parce
   * qu'on a touché l'autre coûte plus cher que du CSS répété).
   *
   * Cette carte est la SEULE liste de codes valides de l'application : le sélecteur du LWC la lit
   * depuis le serveur, la résolution la contrôle, le rendu la contrôle à nouveau. Aucune liste en
   * dur côté client.
   */
  public static final Map<String, String> TEMPLATE_LABELS = new Map<String, String>{
    'ABYLSEN_AT_V11' => 'House of ABY — PTF AT v11',
    'AVENANT_AT_V11' => 'House of ABY — Avenant à une PTF AT v11',
    'ABMI_DQ012' => 'ABMI — Offre commerciale et technique (DQ012_G)'
  };

  /**
   * Gabarits qui impriment l'article « Conditions de règlement » avec les coordonnées bancaires de
   * l'entité (C48). Pour ceux-là, une entité sans coordonnées bancaires BLOQUE la génération —
   * doctrine du projet : donnée de référence absente → bloquer avec un message explicite, jamais
   * substituer. Le gabarit générique n'en imprime aucune : l'y soumettre bloquerait des PTF qui se
   * génèrent correctement aujourd'hui, ce serait une régression, pas une sécurité.
   */
  // Session 37 : le .docx de l'avenant (docs/gabarits/Avenant_PTF_AT_v11.docx) ne comporte ni article
  // "Conditions de règlement" ni bloc RIB/IBAN/BIC — seulement une éventuelle table Lots/Montant/
  // Échéancier dans son bloc de révision de prix. Retiré de cet ensemble (ajouté par anticipation en
  // session 35, avant que le contenu réel de l'avenant ne soit connu) : l'y soumettre bloquerait des
  // avenants sans aucune raison contractuelle.
  private static final Set<String> TEMPLATES_REQUIRING_BANK_DETAILS = new Set<String>{
    'ABYLSEN_AT_V11'
  };

  // Session 38 : ABMI_DQ012 (docs/gabarits/DQ012_G_...docx) n'imprime ni RIB ni IBAN — "Réception
  // des commandes et facturation" cite une adresse ADV et une adresse mail, pas de coordonnées
  // bancaires. Il imprime en revanche l'adresse, le téléphone, le fax et le site web de l'entité
  // (page "Vos contacts") : bloqué séparément (cf. TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS
  // ci-dessous), jamais soumis à requireBankDetails.
  private static final String ABMI_TEMPLATE_CODE = 'ABMI_DQ012';

  /**
   * Gabarits qui impriment les coordonnées générales de l'entité (adresse/téléphone/fax/site web)
   * sans en imprimer les coordonnées bancaires — même doctrine que TEMPLATES_REQUIRING_BANK_DETAILS
   * (donnée de référence absente → bloquer, jamais substituer), sur un ensemble de champs différent.
   * Le SIRET et l'email commercial ne sont PAS requis : ni l'un ni l'autre n'est imprimé par ce
   * gabarit (le .docx source ne porte pas de SIRET ABMI, l'email commercial est saisi par
   * signataire, pas au niveau de l'entité).
   */
  private static final Set<String> TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS = new Set<String>{
    ABMI_TEMPLATE_CODE
  };

  /**
   * Gabarits qui impriment le tribunal de commerce (article 17 des conditions générales, pour les
   * PTF qui les incluent) — même doctrine que TEMPLATES_REQUIRING_BANK_DETAILS (donnée de référence
   * absente → bloquer, jamais substituer). L'avenant et ABMI ne l'impriment pas (avenant = pas de
   * section II ; ABMI = tribunal fixe en dur à Nanterre sans paramètre). Session 152.
   */
  private static final Set<String> TEMPLATES_REQUIRING_TRIBUNAL = new Set<String>{
    'ABYLSEN_AT_V11'
  };

  // ------------------------------------------------------------------------------------------
  // Session 36 — gabarit Abylsen AT v11. Trois comportements changent de SOURCE de donnée pour ce
  // seul gabarit (le générique doit continuer de rendre à l'identique, cf. non-régression) : le
  // rédacteur/valideur (C0/C1/C7/C29/C97/C99), le périmètre de l'historique (C4/C6) et le
  // pré-remplissage du contexte (C24). Des SETS nommés génériquement (pas "ABYLSEN_ONLY") plutôt
  // qu'un simple `== ABYLSEN_TEMPLATE_CODE` : la session 37 (avenant) aura besoin des deux premiers
  // (cf. docs/33-gabarits-ptf-annotations-matthieu.md §2, "idem PTF") sans réécrire cette logique,
  // il suffira d'ajouter 'AVENANT_AT_V11' à l'ensemble concerné — non fait ici, volontairement hors
  // périmètre de cette session (le gabarit avenant est encore une coquille, invérifiable en réel).
  private static final String ABYLSEN_TEMPLATE_CODE = 'ABYLSEN_AT_V11';
  // Session 37 : comme annoncé en session 36, l'avenant rejoint les trois ensembles ci-dessous —
  // « idem PTF » pour C0/C1/C4/C5/C7/C97/C99, cf. docs/33-gabarits-ptf-annotations-matthieu.md §2.
  private static final String AVENANT_TEMPLATE_CODE = 'AVENANT_AT_V11';

  /**
   * Session 49 (cause B, prompts/session-49-alignement-gabarits.md) : le gabarit Abylsen imprime un
   * tableau Lots/Montant/Échéancier (I.4.1/4.3) — sans dates de mission, ce tableau est vide et le
   * gabarit affichait jusqu'ici un texte de remplacement ("... lots à définir conjointement"). Une
   * proposition commerciale sans prix est l'un des deux cas les plus graves relevés : bloquer,
   * jamais dégrader (même doctrine que requireBankDetails).
   *
   * Le gabarit GÉNÉRIQUE n'est PAS soumis à ce blocage, volontairement — asymétrie assumée, pas un
   * oubli : session 20c a délibérément choisi d'y laisser `totalHT`/le tableau à null plutôt que de
   * bloquer (testCollect_noMissionDates_totalHTIsNullNotZero, AR_PTFDataServiceTest), et le relevé
   * de session 49 ne cite que le gabarit Abylsen pour cette cause, jamais le générique. Le
   * générique reste donc le gabarit "toujours généré, avec ses trous visibles" — Abylsen (repris
   * mot à mot d'un .docx contractuel réel, sévérité différente) devient "jamais généré incomplet".
   * Avenant et ABMI exclus pour une autre raison : l'avenant n'imprime ce tableau que dans son bloc
   * de révision de prix, déjà conditionnel (ptf.revisionPrix, jamais affiché vide) ; ABMI ne dépend
   * jamais de hasSchedule pour son prix (proposition financière en texte libre, arbitrage 2 de
   * docs/38-gabarit-abmi-dq012.md).
   */
  private static final Set<String> TEMPLATES_REQUIRING_SCHEDULE = new Set<String>{
    ABYLSEN_TEMPLATE_CODE
  };

  /**
   * Session 176b : gabarits qui impriment le champ SIRET de l'entité (`entiteInfo.siret`) en plus du
   * bloc adresse. Pour ceux-là, les fragments SIREN / NIC / SIRET du bloc adresse sont retirés au
   * rendu (cf. dedupeSirenNic) : chaque information n'apparaît qu'une fois. ABMI n'imprime pas le
   * SIRET (cf. TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS) : son bloc reste intact.
   */
  private static final Set<String> TEMPLATES_PRINTING_SIRET = new Set<String>{
    ABYLSEN_TEMPLATE_CODE,
    AVENANT_TEMPLATE_CODE
  };

  /** C0/C7/C29 : rédacteur = BM de l'affaire (Owner de la matrice), pas l'utilisateur courant. */
  private static final Set<String> TEMPLATES_USING_BM_REDACTEUR = new Set<String>{
    ABYLSEN_TEMPLATE_CODE,
    AVENANT_TEMPLATE_CODE
  };

  /** C4/C6 : historique relu au périmètre du BESOIN (plusieurs matrices), pas de la seule matrice. */
  public static final Set<String> TEMPLATES_USING_BESOIN_HISTORY_SCOPE = new Set<String>{
    ABYLSEN_TEMPLATE_CODE,
    AVENANT_TEMPLATE_CODE
  };

  /**
   * C2/C3 de l'AVENANT (session 37) : l'interlocuteur CLIENT de l'avenant est l'interlocuteur
   * TECHNIQUE du besoin (cxsrec__Contact_for_questions__c), pas le client signataire de la PTF
   * (cxsrec__Hiringmanager__c, utilisé partout ailleurs pour interNom/interFonction). Deux
   * propriétés Connexys distinctes, jamais la même réutilisée — annotation explicite de Matthieu.
   */
  private static final Set<String> TEMPLATES_USING_TECHNICAL_CONTACT_AS_INTERLOCUTEUR = new Set<String>{
    AVENANT_TEMPLATE_CODE
  };

  private static final String GENERIC_TEMPLATE_KEY = 'GENERIQUE';
  private static final String LEGACY_OBJET_PREFIX = 'La présente Proposition Technique et Financière a pour objet';
  private static final String LEGACY_EVOLUTION_FALLBACK = 'Les prix sont fermes et non révisables pour la durée de la présente PTF.';
  private static final String ABYLSEN_EVOLUTION_DEFAULT = 'Le Prix de Prestations pourra être réévalué par accord des parties ou lors de la prolongation du Contrat.';

  /** Texte d'objet imprimé par le modèle Abylsen v11 tant que l'utilisateur ne le modifie pas. */
  private static String abylsenObjetDefault(AR_PTFData d) {
    String text = 'Ce document présente les conditions d’intervention de la société '
      + (String.isBlank(d.entite) ? '' : d.entite.toUpperCase())
      + ' (ci-après « le Prestataire »), dans le cadre d’une prestation d’assistance technique, pour le compte de '
      + (d.client == null ? '' : d.client) + ' (ci-après « le Client »)';
    if (String.isNotBlank(d.lieuPrestation)) {
      text += ' sur le site de ' + d.lieuPrestation;
    }
    return text + '.';
  }

  private static Boolean sameText(String a, String b) {
    return a != null && b != null && a.trim() == b.trim();
  }

  /**
   * Pré-remplissage propre à chaque gabarit, et séparation « saisie » / « texte du modèle » pour le
   * gabarit Abylsen. Une valeur égale à un défaut connu (celui du gabarit, l'ancien défaut générique ou
   * le réglage global) compte comme non modifiée : le modèle s'imprime alors tel quel.
   */
  private static void applyTemplateTexts(AR_PTFData d, GenerationInput input, String templateCode, String genericObjet, String genericEvolution) {
    String abylsenObjet = abylsenObjetDefault(d);
    d.objetParGabarit = new Map<String, String>{ GENERIC_TEMPLATE_KEY => genericObjet, ABYLSEN_TEMPLATE_CODE => abylsenObjet };
    d.evolutionPrixParGabarit = new Map<String, String>{
      GENERIC_TEMPLATE_KEY => genericEvolution,
      ABYLSEN_TEMPLATE_CODE => ABYLSEN_EVOLUTION_DEFAULT
    };
    if (templateCode != ABYLSEN_TEMPLATE_CODE) {
      return;
    }
    Boolean objetModified = String.isNotBlank(input.objet)
      && !sameText(input.objet, abylsenObjet)
      && !sameText(input.objet, genericObjet)
      && !input.objet.trim().startsWith(LEGACY_OBJET_PREFIX);
    Boolean evolutionModified = String.isNotBlank(input.evolutionPrix)
      && !sameText(input.evolutionPrix, ABYLSEN_EVOLUTION_DEFAULT)
      && !sameText(input.evolutionPrix, genericEvolution)
      && !sameText(input.evolutionPrix, LEGACY_EVOLUTION_FALLBACK);
    d.objetSaisi = objetModified ? input.objet : null;
    d.evolutionPrixSaisie = evolutionModified ? input.evolutionPrix : null;
    d.objet = objetModified ? input.objet : abylsenObjet;
    d.evolutionPrix = evolutionModified ? input.evolutionPrix : ABYLSEN_EVOLUTION_DEFAULT;
  }

  /** Catégorie C : saisie utilisateur au moment de la génération, en surcharge des défauts A/B. */
  public class GenerationInput {
    @AuraEnabled
    public Id matrixId;
    @AuraEnabled
    public String objet;
    @AuraEnabled
    public String contexte;
    @AuraEnabled
    public String livrables;
    @AuraEnabled
    public String redacteurNom;
    @AuraEnabled
    public String redacteurFonction;
    @AuraEnabled
    public String valideurNom;
    @AuraEnabled
    public String valideurFonction;
    // Id du valideur choisi parmi valideurOptions ; hors liste ou vide, le valideur par défaut s'applique.
    @AuraEnabled
    public String valideurId;
    @AuraEnabled
    public String freqReunions;
    @AuraEnabled
    public Boolean materielClient;
    @AuraEnabled
    public Boolean fraisDepl;
    @AuraEnabled
    public String conditionsReglement;
    @AuraEnabled
    public String tribunalCompetent;
    @AuraEnabled
    public String evolutionPrix;
    @AuraEnabled
    public String consultantExperience;
    @AuraEnabled
    public String consultantCompetences;
    @AuraEnabled
    public String interTel;
    @AuraEnabled
    public String interEmail;
    // Surcharge manuelle du gabarit (session 30) — vide = résolution automatique (compte > entité >
    // générique, cf. resolveTemplateCode). Depuis la session 35, la valeur vient d'une liste de
    // valeurs alimentée par le serveur (TEMPLATE_LABELS) et non plus d'une saisie libre : une faute
    // de frappe donnait un code inconnu, qui retombait silencieusement sur le générique.
    @AuraEnabled
    public String templateCode;
    // C27 (session 35) : items de matériel mis à disposition, un par ligne ou séparés par des
    // virgules. Vide → « Mis à disposition par <NOM CLIENT> » sur les gabarits qui l'impriment.
    @AuraEnabled
    public String materielItems;
    // C44 (session 35) : surcharges de montant par lot. Un lot absent de cette liste reste calculé,
    // et le reste même si les données de la matrice changent ensuite.
    @AuraEnabled
    public List<LotOverride> lotOverrides;
    // C8/C9 de l'avenant (session 35) : la PTF initiale citée par l'avenant. Aucun gabarit ne la
    // consomme encore (les pages 36-38 sont des coquilles) — la donnée est collectée et figée dès
    // maintenant pour que le modèle soit complet quand elles arrivent.
    @AuraEnabled
    public Id ptfInitialeDocumentId;
    // I.2 « Contexte du projet » (gabarit Abylsen, session 37) : domaine d'expertise mis en avant,
    // saisie pure — aucune source Connexys identifiée (cf. AR_PTFData.domaineExpertise).
    @AuraEnabled
    public String domaineExpertise;
    // Session 138 : type/détail de la modification apportée par cette version (liste de valeurs de
    // AR_PTF_Document__c.AR_Modification_Type__c). Exigés à partir du rang 2 (AR_PTFGenerationService),
    // ignorés au rang 1.
    @AuraEnabled
    public String modificationType;
    @AuraEnabled
    public String modificationDetail;
    // Facturation mensuelle lissée (case décochée par défaut). Vrai : chaque mois complet
    // = TJM × jours travaillés annuels / 12 ; premier et dernier mois au prorata. Faux : échéancier réel.
    @AuraEnabled
    public Boolean facturationMensuelleLissee;
    // TJM par périodes (docs/254d) : dates de début saisies (ISO AAAA-MM-JJ) des périodes 2, 3, 4 dans
    // l'ordre. Ignorées sans période de TJM sur la matrice ; obligatoires à la génération sinon.
    @AuraEnabled
    public List<String> tjmPeriodStarts;

    // --- Session 38 : gabarit ABMI DQ012 — miroir des AR_PTFData.abmi* (cf. ce fichier). Tous
    // optionnels, tous transmis tels quels par collect() : ce gabarit n'a aucune règle de calcul de
    // repli, seulement des textes libres et deux couples signataire préremplis (voir collect()).
    @AuraEnabled
    public String abmiNosReferences;
    @AuraEnabled
    public String abmiAttentionDe;
    @AuraEnabled
    public String abmiSignataire1Nom;
    @AuraEnabled
    public String abmiSignataire1Fonction;
    @AuraEnabled
    public String abmiSignataire1Tel;
    @AuraEnabled
    public String abmiSignataire1Mobile;
    @AuraEnabled
    public String abmiSignataire1Email;
    @AuraEnabled
    public String abmiSignataire2Nom;
    @AuraEnabled
    public String abmiSignataire2Fonction;
    @AuraEnabled
    public String abmiSignataire2Tel;
    @AuraEnabled
    public String abmiSignataire2Email;
    @AuraEnabled
    public String abmiDescriptionTravaux;
    @AuraEnabled
    public String abmiDonneesEntree;
    @AuraEnabled
    public String abmiDescriptionSolution;
    @AuraEnabled
    public String abmiAvantages;
    @AuraEnabled
    public String abmiRessources;
    @AuraEnabled
    public String abmiOrganisationProjet;
    @AuraEnabled
    public String abmiHabilitations;
    @AuraEnabled
    public String abmiAnalyseRisques;
    @AuraEnabled
    public String abmiPropositionFinanciereTexte;
    // Session 279 : adresse client saisie dans le formulaire (vide = adresse du compte).
    @AuraEnabled
    public String adresseClient;
  }

  /** Surcharge du montant d'un lot, identifiée par son rang dans l'échéancier (0 = premier lot). */
  public class LotOverride {
    @AuraEnabled
    public Integer index;
    @AuraEnabled
    public Decimal montant;
  }

  /** Prérequis manquant pour la validation PTF (session 107). */
  public class Prerequisite {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String whereToFix;
    /** true = donnée de la MATRICE, bloque la validation ; false = donnée externe (besoin,
     * entité) : simple avertissement « la génération PTF pourrait être bloquée » (décision
     * d'Alexis, 23/09/2026 — seule la matrice peut bloquer la validation de la matrice). */
    @AuraEnabled
    public Boolean blocking;

    public Prerequisite(String label, String whereToFix) {
      this(label, whereToFix, true);
    }

    public Prerequisite(String label, String whereToFix, Boolean blocking) {
      this.label = label;
      this.whereToFix = whereToFix;
      this.blocking = blocking;
    }
  }

  /** Sous-ensemble bloquant (données de la matrice) — seul critère de refus de la validation. */
  public static List<Prerequisite> blockingOnly(List<Prerequisite> all) {
    List<Prerequisite> out = new List<Prerequisite>();
    for (Prerequisite p : all) {
      if (p.blocking == true) {
        out.add(p);
      }
    }
    return out;
  }

  /**
   * Défauts pré-remplis (catégories A + B) pour le formulaire de génération : la matrice doit être
   * validée, sinon la génération n'a pas de sens (contrôle dupliqué dans generatePTF — le serveur
   * fait foi aux deux points d'entrée).
   */
  // Valideur par défaut = DA du propriétaire de la matrice (User.TP_DA__c), modifiable via listValideurOptions.
  // Appel impératif uniquement (arPtfPanel), aucun @wire.
  @AuraEnabled
  public static AR_PTFData getGenerationDefaults(Id matrixId) {
    try {
      GenerationInput emptyInput = new GenerationInput();
      emptyInput.matrixId = matrixId;
      // Session 110 : un pré-remplissage ne bloque jamais. Les blocages de génération (valideur vide,
      // coordonnées bancaires/contact de l'entité, échéancier) s'appliquent à generatePTF et à
      // l'aperçu, pas ici : une exception levée ici faisait échouer tout le chargement du panneau PTF
      // et masquait l'historique des PTF déjà générées (matrice validée sans dérogation, donc sans
      // valideur effectif ni sélectionné — constaté le 24/09/2026). La préparation de l'entité est
      // signalée à part par getEntityReadinessByTemplate ; le gating par statut reste appliqué.
      AR_PTFData defaults = collect(matrixId, emptyInput, 1, false);
      attachFormDraft(defaults, matrixId);
      return defaults;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_ResolveDefaultsAction);
    }
  }

  // ------------------------------------------------------------------------------------------
  // Session 148 — brouillon du formulaire PTF / avenant. Stockage : AR_Price_Matrix__c.AR_PTF_Form_Draft__c,
  // JSON { version: 1, ptf: {templateCode, input, savedAt, savedById, savedByName},
  //                    avenant: {parentDocumentId, input, savedAt, savedById, savedByName} }.
  // `input` est exactement l'inputJson envoyé à generatePTF / generateAvenant / createPreview.
  // ------------------------------------------------------------------------------------------
  public static final String DRAFT_MODE_PTF = 'ptf';
  public static final String DRAFT_MODE_AVENANT = 'avenant';
  private static final Integer DRAFT_VERSION = 1;
  private static final Integer DRAFT_MAX_LENGTH = 131072;

  /**
   * Enregistre la saisie courante d'un formulaire. DML en mode utilisateur (CRUD/FLS) dans une classe
   * `with sharing` : pas de contournement. Seul le verrouillage de AR_PriceMatrixTrigger est suspendu
   * (AR_TriggerBypass.serviceContext) — une PTF n'existe que sur une matrice déjà décidée, que ce
   * trigger refuserait sinon de modifier ; l'enregistrement ne porte que ce champ.
   */
  @AuraEnabled
  public static String savePtfFormDraft(Id matrixId, String mode, String inputJson) {
    try {
      if (mode != DRAFT_MODE_PTF && mode != DRAFT_MODE_AVENANT) {
        throw draftException(AR_I18n.format(Label.AR_Msg_PTF_DraftUnknownMode, new List<Object>{ mode }));
      }
      Object parsedInput;
      try {
        parsedInput = JSON.deserializeUntyped(inputJson);
      } catch (Exception e) {
        throw draftException(AR_I18n.format(Label.AR_Msg_PTF_DraftUnreadableInput, new List<Object>{ e.getMessage() }));
      }
      if (!(parsedInput instanceof Map<String, Object>)) {
        throw draftException(Label.AR_Msg_PTF_DraftNotJson);
      }
      requireDraftWriteAccess(matrixId);

      AR_Price_Matrix__c matrix = [
        SELECT Id, AR_PTF_Form_Draft__c
        FROM AR_Price_Matrix__c
        WHERE Id = :matrixId
        WITH USER_MODE
        LIMIT 1
      ];
      // Entrée de l'autre mode conservée telle quelle ; un brouillon existant illisible est remplacé
      // (il n'était déjà plus utilisable), seule l'entrée qu'on écrit compte.
      Map<String, Object> doc = new Map<String, Object>();
      if (String.isNotBlank(matrix.AR_PTF_Form_Draft__c)) {
        try {
          Object existing = JSON.deserializeUntyped(matrix.AR_PTF_Form_Draft__c);
          if (existing instanceof Map<String, Object>) {
            doc = (Map<String, Object>) existing;
          }
        } catch (Exception e) {
          System.debug(LoggingLevel.WARN, 'AR_PTFDataService.savePtfFormDraft : brouillon existant illisible, remplacé : ' + e.getMessage());
        }
      }
      Map<String, Object> input = (Map<String, Object>) parsedInput;
      Map<String, Object> entry = new Map<String, Object>{
        'input' => input,
        'savedAt' => Datetime.now(),
        'savedById' => UserInfo.getUserId(),
        'savedByName' => UserInfo.getName()
      };
      if (mode == DRAFT_MODE_PTF) {
        entry.put('templateCode', input.get('templateCode'));
      } else {
        entry.put('parentDocumentId', input.get('ptfDocumentId'));
      }
      doc.put('version', DRAFT_VERSION);
      doc.put(mode, entry);
      writeDraft(matrixId, JSON.serialize(doc));
      // Entrée telle qu'écrite (date et auteur réels) : le bandeau du LWC l'affiche sans rien deviner.
      return JSON.serialize(entry);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_DraftSaveAction);
    }
  }

  /** « Revenir aux valeurs par défaut » : efface l'entrée du mode donné, garde l'autre. */
  @AuraEnabled
  public static void clearPtfFormDraft(Id matrixId, String mode) {
    try {
      if (mode != DRAFT_MODE_PTF && mode != DRAFT_MODE_AVENANT) {
        throw draftException(AR_I18n.format(Label.AR_Msg_PTF_DraftNotClearedUnknownMode, new List<Object>{ mode }));
      }
      requireDraftWriteAccess(matrixId);
      AR_Price_Matrix__c matrix = [
        SELECT Id, AR_PTF_Form_Draft__c
        FROM AR_Price_Matrix__c
        WHERE Id = :matrixId
        WITH USER_MODE
        LIMIT 1
      ];
      if (String.isBlank(matrix.AR_PTF_Form_Draft__c)) {
        return;
      }
      Map<String, Object> doc = null;
      try {
        Object existing = JSON.deserializeUntyped(matrix.AR_PTF_Form_Draft__c);
        if (existing instanceof Map<String, Object>) {
          doc = (Map<String, Object>) existing;
        }
      } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'AR_PTFDataService.clearPtfFormDraft : brouillon illisible, vidé : ' + e.getMessage());
      }
      if (doc == null) {
        writeDraft(matrixId, null);
        return;
      }
      doc.remove(mode);
      Boolean empty = !doc.containsKey(DRAFT_MODE_PTF) && !doc.containsKey(DRAFT_MODE_AVENANT);
      writeDraft(matrixId, empty ? null : JSON.serialize(doc));
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_DraftClearAction);
    }
  }

  private static AuraHandledException draftException(String message) {
    AuraHandledException ahe = new AuraHandledException(message);
    ahe.setMessage(message);
    return ahe;
  }

  /** Droit d'écriture réel de l'utilisateur sur CETTE matrice (partage) et sur le champ (FLS). */
  private static void requireDraftWriteAccess(Id matrixId) {
    Boolean canEditRecord = false;
    for (UserRecordAccess ura : [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :matrixId
      LIMIT 1
    ]) {
      canEditRecord = ura.HasEditAccess;
    }
    Boolean canWriteField = Schema.SObjectType.AR_Price_Matrix__c.fields.AR_PTF_Form_Draft__c.isUpdateable();
    if (!canEditRecord || !canWriteField) {
      throw draftException(Label.AR_Msg_PTF_DraftNoWriteAccess);
    }
  }

  private static void writeDraft(Id matrixId, String draftJson) {
    if (draftJson != null && draftJson.length() > DRAFT_MAX_LENGTH) {
      throw draftException(
        AR_I18n.format(Label.AR_Msg_PTF_DraftTooLarge, new List<Object>{ draftJson.length(), DRAFT_MAX_LENGTH })
      );
    }
    AR_Price_Matrix__c toUpdate = new AR_Price_Matrix__c(Id = matrixId, AR_PTF_Form_Draft__c = draftJson);
    Boolean previous = AR_TriggerBypass.serviceContext;
    AR_TriggerBypass.serviceContext = true;
    try {
      Database.update(toUpdate, AccessLevel.USER_MODE);
    } finally {
      AR_TriggerBypass.serviceContext = previous;
    }
  }

  /**
   * Lit le brouillon et le joint aux défauts. Une lecture qui échoue (JSON illisible, entrée mal
   * formée) n'interrompt jamais le chargement du panneau : l'entrée concernée est écartée et le
   * motif est renvoyé dans formDraftWarning (affiché, règle session 34).
   */
  private static void attachFormDraft(AR_PTFData data, Id matrixId) {
    List<AR_Price_Matrix__c> rows = [
      SELECT AR_PTF_Form_Draft__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1
    ];
    if (rows.isEmpty() || String.isBlank(rows[0].AR_PTF_Form_Draft__c)) {
      return;
    }
    List<String> problems = new List<String>();
    Map<String, Object> clean = new Map<String, Object>{ 'version' => DRAFT_VERSION };
    try {
      Object parsed = JSON.deserializeUntyped(rows[0].AR_PTF_Form_Draft__c);
      if (!(parsed instanceof Map<String, Object>)) {
        problems.add(Label.AR_Msg_PTF_DraftProblemNotJson);
      } else {
        Map<String, Object> doc = (Map<String, Object>) parsed;
        if (doc.get('version') != DRAFT_VERSION) {
          problems.add(AR_I18n.format(Label.AR_Msg_PTF_DraftProblemUnknownVersion, new List<Object>{ doc.get('version') }));
        } else {
          for (String mode : new List<String>{ DRAFT_MODE_PTF, DRAFT_MODE_AVENANT }) {
            if (!doc.containsKey(mode)) {
              continue;
            }
            Object entry = doc.get(mode);
            if (entry instanceof Map<String, Object> && ((Map<String, Object>) entry).get('input') instanceof Map<String, Object>) {
              clean.put(mode, entry);
            } else {
              problems.add(AR_I18n.format(Label.AR_Msg_PTF_DraftProblemMalformedEntry, new List<Object>{ mode }));
            }
          }
        }
      }
    } catch (Exception e) {
      problems.add(e.getMessage());
    }
    if (!problems.isEmpty()) {
      data.formDraftWarning = AR_I18n.format(Label.AR_Msg_PTF_DraftIgnored, new List<Object>{ String.join(problems, ' ; ') });
    }
    if (clean.size() > 1) {
      data.formDraft = JSON.serialize(clean);
    }
  }

  /** Construit la structure complète pour une génération donnée ; versionNumber = version du document PTF (pas de la matrice). */
  public static AR_PTFData collect(
    Id matrixId,
    GenerationInput input,
    Integer versionNumber
  ) {
    return collect(matrixId, input, versionNumber, true);
  }

  /**
   * enforceGenerationBlocks = false réservé au pré-remplissage du formulaire (getGenerationDefaults) :
   * mêmes valeurs résolues, sans les quatre blocages propres à la génération.
   */
  @TestVisible
  private static AR_PTFData collect(
    Id matrixId,
    GenerationInput input,
    Integer versionNumber,
    Boolean enforceGenerationBlocks
  ) {
    AR_Price_Matrix__c m = [
      SELECT
        Id,
        Name,
        AR_Status__c,
        AR_Position__c,
        AR_Position__r.cxsrec__Account__c,
        AR_Position__r.AB_Need_details__r.AB_Account__c,
        AR_Position__r.AB_Need_details__r.AB_Contact__c,
        AR_Position__r.AB_Need_details__r.AB_Contact__r.Name,
        AR_Position__r.AB_Need_details__r.AB_Contact__r.Title,
        AR_Position__r.AB_Need_details__r.AB_Contact__r.Phone,
        AR_Position__r.AB_Need_details__r.AB_Contact__r.MobilePhone,
        AR_Position__r.AB_Need_details__r.AB_Contact__r.Email,
        AR_Position_Name__c,
        AR_Account_Name__c,
        AR_Entity_Ref__c,
        AR_Consultant_Name__c,
        AR_Consultant__c,
        AR_Consultant__r.Name,
        AR_Client_Site__c,
        AR_Start_Date__c,
        AR_End_Date__c,
        AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
        AR_Working_Days_Applied__c,
        AR_Currency__c,
        AR_Proposed_TJM__c,
        AR_TJM_Periods__c,
        AR_Total_Daily_Cost__c,
        AR_RFA_Percent__c,
        AR_Floor_Percent_Applied__c,
        AR_RPLSR_Enabled__c,
        AR_RPLSR_Plan__c,
        AR_Selected_Validator__r.Name,
        AR_Selected_Validator__r.Title,
        AR_Effective_Validator__r.Name,
        AR_Effective_Validator__r.Title,
        OwnerId,
        AR_Previous_Version__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    if (!GENERATABLE_STATUSES.contains(m.AR_Status__c)) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_OnlyValidatedCanGenerate, new List<Object>{ m.AR_Status__c })
      );
    }

    // Session 122 : Account from junction object first (AB_Need_details__r.AB_Account__c), fallback to Position
    Id accountId = (m.AR_Position__r.AB_Need_details__r != null &&
                    m.AR_Position__r.AB_Need_details__r.AB_Account__c != null)
      ? m.AR_Position__r.AB_Need_details__r.AB_Account__c
      : m.AR_Position__r.cxsrec__Account__c;

    Account acc = accountId != null
      ? [
          SELECT
            Name,
            BillingStreet,
            BillingPostalCode,
            BillingCity,
            ShippingStreet,
            ShippingPostalCode,
            ShippingCity,
            SIRET__c
          FROM Account
          WHERE Id = :accountId
          LIMIT 1
        ]
      : null;

    Contact hiringManager = null;
    // Interlocuteur *technique* du besoin (C2/C3 de l'avenant), distinct de l'interlocuteur client
    // (cxsrec__Hiringmanager__c, libellé « Interlocuteur Client » dans cette org). Aucun champ
    // Connexys ne s'appelle « interlocuteur technique » : cxsrec__Contact_for_questions__c
    // (« Personne à contacter en cas de questions ») est le plus proche, à CONFIRMER avec Matthieu
    // avant que l'avenant (session 37) ne l'imprime — cf. docs/35-socle-multi-gabarits.md §6.
    Contact technicalContact = null;
    Integer connexysDurationMonths = null;
    String positionTitle = null;
    // C24 (gabarit Abylsen uniquement) : descriptif du besoin, repris comme défaut de I.3.1 « Besoins
    // du Client » — jamais imprimé tel quel par le gabarit générique, qui garde son propre défaut
    // (aucun) pour son I.2 « Contexte du projet ».
    String besoinDescription = null;
    for (cxsrec__cxsPosition__c pos : [
      SELECT Name,
             cxsrec__Hiringmanager__r.Name, cxsrec__Hiringmanager__r.Title,
             cxsrec__Hiringmanager__r.Phone, cxsrec__Hiringmanager__r.MobilePhone, cxsrec__Hiringmanager__r.Email,
             cxsrec__Contact_for_questions__r.Name, cxsrec__Contact_for_questions__r.Title,
             cxsrec__Contact_for_questions__r.Phone, cxsrec__Contact_for_questions__r.MobilePhone, cxsrec__Contact_for_questions__r.Email,
             cxsrec__Duration_number_of_units__c, cxsrec__Duration_unit__c,
             cxsrec__Job_description__c, TP_Information_complementaire__c
      FROM cxsrec__cxsPosition__c
      WHERE Id = :m.AR_Position__c
      LIMIT 1
    ]) {
      // Session 122 : Hiring manager from junction object first (AB_Need_details__r.AB_Contact__r),
      // fallback to Position's hiring manager
      hiringManager = (m.AR_Position__r.AB_Need_details__r != null &&
                       m.AR_Position__r.AB_Need_details__r.AB_Contact__r != null)
        ? m.AR_Position__r.AB_Need_details__r.AB_Contact__r
        : pos.cxsrec__Hiringmanager__r;
      technicalContact = pos.cxsrec__Contact_for_questions__r;
      positionTitle = pos.Name;
      // Session 129 : prioritize TP_Information_complementaire__c (46% filled) over Job_description (9% filled)
      besoinDescription = String.isNotBlank(pos.TP_Information_complementaire__c)
        ? cleanHtmlPreservingLinebreaks(pos.TP_Information_complementaire__c)
        : String.isNotBlank(pos.cxsrec__Job_description__c)
          ? cleanHtmlPreservingLinebreaks(pos.cxsrec__Job_description__c)
          : null;
      // Seule l'unité « Month(s) » est reprise telle quelle : convertir des heures ou des semaines
      // en mois demanderait une hypothèse (combien d'heures dans un mois ?) que personne n'a
      // arbitrée. Sinon on retombe sur les dates de mission, qui sont une donnée, pas une règle.
      if (
        pos.cxsrec__Duration_number_of_units__c != null &&
        pos.cxsrec__Duration_unit__c == 'Month(s)'
      ) {
        connexysDurationMonths = Integer.valueOf(pos.cxsrec__Duration_number_of_units__c);
      }
    }

    AR_PTF_Setting__mdt settings = AR_PTF_Setting__mdt.getInstance('Default');
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
    Decimal joursParMoisDefault = defaultJoursParMois();

    // Résolution du gabarit déplacée ICI (session 36, était après la construction de `d` jusqu'à la
    // session 35) : le rédacteur, le valideur, le contexte par défaut et l'historique dépendent
    // désormais du gabarit résolu, pas seulement son rendu final — cf. les trois TEMPLATES_USING_*
    // ci-dessus. Le blocage bancaire reste juste après la résolution, avant tout le reste : un
    // gabarit qui imprime l'article 4.5 sans coordonnées bancaires ne doit produire aucun document,
    // même vide, même avec un « À COMPLÉTER ».
    TemplateResolution resolution = resolveTemplate(input, m, entityRef);
    if (enforceGenerationBlocks) {
      requireBankDetails(resolution.code, entityRef == null ? null : entityRef.Name, entityRef);
      requireEntityContactDetails(resolution.code, entityRef == null ? null : entityRef.Name, entityRef);
    }

    AR_PTFData d = new AR_PTFData();
    d.client = m.AR_Account_Name__c;
    d.warnings = new List<String>();
    // Session 142b : avertissement si l'adresse client n'a pu être renseignée (ni ville de facturation
    // ni ville de livraison disponibles sur le compte résolu). Session 279 : adresse saisie prioritaire.
    applyClientAddress(d, acc, input == null ? null : input.adresseClient);
    d.entite = entityRef == null ? null : entityRef.Name;
    d.entiteInfo = toEntiteInfo(entityRef, resolution.code);
    // Session 138 : la version affichée (`version`, « Version n° » du PDF) suit le RANG dans
    // l'historique (versions cochées du périmètre). Session 176e : la RÉFÉRENCE, elle, suit le compteur
    // technique `versionNumber` (AR_Version_Number__c, MAX + 1 par matrice) — sur le rang, elle se
    // répétait dès qu'une version était décochée ou en échec (deux documents « PTF-MAT-x-V3 »).
    List<AR_PTF_Document__c> priorDocs = AR_PTFHistoryService.listEligibleDocuments(m.Id, resolution.code);
    Integer displayRank = priorDocs.size() + 1;
    d.displayRank = displayRank;
    d.reference = 'PTF-' + m.Name + '-V' + (versionNumber == null ? displayRank : versionNumber);
    d.version = 'V' + displayRank;
    d.missionType = PTF_TYPE;
    // Session 49 : String.valueOf(null) vaut littéralement "null" en Apex — sans garde, un compte
    // ou un besoin dénormalisé absent imprimait "...dans le cadre du besoin null." dans un document
    // contractuel (trouvé en régénérant réellement ce gabarit, cause A/B généralisée). La clause
    // correspondante disparaît à la place, jamais la valeur brute "null".
    String objetSentence = 'La présente Proposition Technique et Financière a pour objet de définir les modalités d\'intervention';
    if (String.isNotBlank(m.AR_Account_Name__c)) {
      objetSentence += ' auprès de ' + m.AR_Account_Name__c;
    }
    if (String.isNotBlank(m.AR_Position_Name__c)) {
      objetSentence += ' dans le cadre du besoin ' + m.AR_Position_Name__c;
    }
    d.objet = String.isNotBlank(input.objet) ? input.objet : objetSentence + '.';
    // C24 (session 142) : pré-remplissage du contexte depuis le descriptif Connexys (besoinDescription)
    // pour tout gabarit qui imprime une section « Besoins du client » ou « Contexte » (Abylsen, Générique,
    // ABMI). Session 129 : besoinDescription lit TP_Information_complementaire__c en priorité (46% remplissage)
    // avant de repli sur Job_description (9%). Saisie utilisateur toujours prioritaire.
    d.contexte = String.isNotBlank(input.contexte)
      ? input.contexte
      : besoinDescription;
    d.dateDebut = m.AR_Start_Date__c;
    d.dateFin = m.AR_End_Date__c;
    d.lieuPrestation = m.AR_Client_Site__c;
    d.currencyCode = String.isNotBlank(m.AR_Currency__c) ? m.AR_Currency__c : 'EUR';
    d.tjm = m.AR_Proposed_TJM__c;
    d.nbConsultants = NB_CONSULTANTS;
    // Session 122 : pass totalDays for proportional redistribution if manually overridden
    // En mode lissé, l'échéancier ignore totalDays (la somme des lignes fait foi).
    // Régie sans régule active sur la matrice : la case est imposée, l'échéancier reprend les jours vendus du plan.
    Boolean rplsr = m.AR_RPLSR_Enabled__c == true;
    Boolean lissee = rplsr || input.facturationMensuelleLissee == true;
    Map<String, Decimal> vendusDuPlan = vendusParMoisDuPlan(m);
    if (rplsr && enforceGenerationBlocks && vendusDuPlan.isEmpty()) {
      throw newAuraException(Label.AR_Msg_PM_RplsrPlanInvalid);
    }
    d.rplsrActive = rplsr;
    d.mensualisationLissee = lissee;
    Decimal joursParMoisEcheancier = joursParMoisPourEcheancier(
      m.AR_Working_Days_Applied__c, entityRef, lissee, joursParMoisDefault
    );
    d.joursParMois = joursParMoisEcheancier;
    // TJM par périodes (docs/254d) : null sans évolution de TJM, l'échéancier reste alors le code actuel.
    d.tjmPeriodes = buildTjmPeriodRows(m, input.tjmPeriodStarts, enforceGenerationBlocks);
    d.schedule = buildSchedule(
      m.AR_Start_Date__c,
      m.AR_End_Date__c,
      m.AR_Proposed_TJM__c,
      joursParMoisEcheancier,
      NB_CONSULTANTS,
      scheduleTotalDays(m),
      lissee,
      d.tjmPeriodes,
      vendusDuPlan,
      entityRef == null ? null : entityRef.AR_Country__c
    );
    if (enforceGenerationBlocks) {
      requireSchedule(resolution.code, d.schedule);
    }
    // null (pas 0) quand l'échéancier est vide : un montant total à zéro sur une proposition
    // commerciale est faux et ne doit jamais être inventé faute de dates de mission — le gabarit
    // affiche "À définir" sur null, un vrai 0 calculé (cas théorique) reste un 0 affiché.
    d.totalHT = d.schedule.isEmpty() ? null : sumMontants(d.schedule);
    d.livrables = input.livrables;
    // Session 58 (A16) : le gabarit Abylsen imprime "Trimestrielle" en dur dans son .docx source —
    // valeur du MODÈLE, pas le défaut général AR_PTF_Setting__mdt.AR_Default_Freq_Reunions__c
    // ("Mensuelle ou sur demande", partagé avec le gabarit générique, qui reste inchangé). Repli
    // spécifique à ce gabarit, surchargeable par la saisie comme les autres défauts — question 5 de
    // docs/53-plan-ptf-iso-et-sources.md (valeur par défaut ou texte contractuel figé ?) non
    // tranchée par Matthieu à ce jour.
    d.freqReunions = String.isNotBlank(input.freqReunions)
      ? input.freqReunions
      : (resolution.code == ABYLSEN_TEMPLATE_CODE
          ? 'Trimestrielle'
          : (settings != null ? settings.AR_Default_Freq_Reunions__c : null));
    d.fraisDepl = input.fraisDepl != null
      ? input.fraisDepl
      : (settings != null ? settings.AR_Default_Frais_Deplacement__c : false);
    d.materielClient = input.materielClient != null
      ? input.materielClient
      : (settings != null ? settings.AR_Default_Materiel_Client__c : false);
    d.conditionsReglement = String.isNotBlank(input.conditionsReglement)
      ? input.conditionsReglement
      : (settings != null ? settings.AR_Default_Conditions_Reglement__c : null);
    d.tribunalCompetent = String.isNotBlank(input.tribunalCompetent)
      ? input.tribunalCompetent
      : (entityRef != null && String.isNotBlank(entityRef.AR_Tribunal_Competent__c)
        ? entityRef.AR_Tribunal_Competent__c
        : (settings != null ? settings.AR_Default_Tribunal_Competent__c : null));
    // Session 152c : le blocage porte sur le tribunal RÉSOLU (formulaire > entité > réglage global),
    // jamais sur l'entité seule — sinon une saisie de l'utilisateur ou le réglage global étaient ignorés.
    if (enforceGenerationBlocks) {
      String tribunalBlock = tribunalBlockError(resolution.code, d.tribunalCompetent);
      if (tribunalBlock != null) {
        throw newAuraException(tribunalBlock);
      }
    }
    d.evolutionPrix = String.isNotBlank(input.evolutionPrix)
      ? input.evolutionPrix
      : (settings != null ? settings.AR_Default_Evolution_Prix__c : null);
    applyTemplateTexts(d, input, resolution.code, objetSentence + '.', settings != null ? settings.AR_Default_Evolution_Prix__c : null);
    // Session 177 : managerName = nom du propriétaire de la matrice (BM), utilisé pour le trigramme
    // du manager dans la nomenclature PTF.
    User bm = loadUser(m.OwnerId);
    d.managerName = bm != null ? bm.Name : null;

    // C0/C7/C29 : rédacteur = BM de l'affaire (Owner de la matrice) pour le gabarit Abylsen ;
    // comportement historique (utilisateur courant) inchangé pour tous les autres, générique compris.
    if (TEMPLATES_USING_BM_REDACTEUR.contains(resolution.code)) {
      d.redacteurNom = String.isNotBlank(input.redacteurNom)
        ? input.redacteurNom
        : (bm != null ? bm.Name : null);
      d.redacteurFonction = String.isNotBlank(input.redacteurFonction)
        ? input.redacteurFonction
        : (bm != null ? bm.Title : null);
    } else {
      d.redacteurNom = String.isNotBlank(input.redacteurNom)
        ? input.redacteurNom
        : UserInfo.getName();
      d.redacteurFonction = String.isNotBlank(input.redacteurFonction)
        ? input.redacteurFonction
        : currentUserTitle();
    }
    // Valideur : choisi parmi RA/DA/DD/Directeur du propriétaire (input.valideurId), à défaut
    // valideurDe. Un id hors liste est ignoré. Fonction : saisie, à défaut le Title de la personne.
    // Blocage si personne n'est renseigné.
    ValideurChoice choix = resolveValideur(bm, m.AR_Entity_Ref__c, input.valideurId, input.valideurFonction);
    d.valideurNom = choix.nom;
    d.valideurFonction = choix.fonction;
    d.valideurBlocage = valideurError(d.valideurNom, bm);
    if (enforceGenerationBlocks && d.valideurBlocage != null) {
      throw newAuraException(d.valideurBlocage);
    }
    // C2/C3 : l'interlocuteur CLIENT est l'interlocuteur technique du besoin pour l'avenant, le
    // client signataire (hiringManager) partout ailleurs — cf. TEMPLATES_USING_TECHNICAL_CONTACT_*.
    Contact interlocuteurClient = TEMPLATES_USING_TECHNICAL_CONTACT_AS_INTERLOCUTEUR.contains(resolution.code)
      ? technicalContact
      : hiringManager;
    d.interNom = interlocuteurClient != null ? interlocuteurClient.Name : null;
    d.interFonction = interlocuteurClient != null ? interlocuteurClient.Title : null;
    // Session 142 : fallback to MobilePhone if Phone is empty (hypothesis 2a)
    String contactPhone = interlocuteurClient != null ? interlocuteurClient.Phone : null;
    String contactMobile = interlocuteurClient != null ? interlocuteurClient.MobilePhone : null;
    d.interTel = String.isNotBlank(input.interTel)
      ? input.interTel
      : (String.isNotBlank(contactPhone) ? contactPhone : contactMobile);
    d.interEmail = String.isNotBlank(input.interEmail)
      ? input.interEmail
      : (interlocuteurClient != null ? interlocuteurClient.Email : null);
    // Session 54 : le lookup AR_Consultant__c, quand renseigné, est une DONNÉE (Name du candidat),
    // préférée au texte libre historique AR_Consultant_Name__c (heuristique de saisie, jamais
    // réécrit depuis cette session) — consommé par consultantTrigramme (AR_PTFGenerationService)
    // pour les initiales de la référence PTF.
    d.consultantNom = m.AR_Consultant__r != null ? m.AR_Consultant__r.Name : m.AR_Consultant_Name__c;
    applyNomenclatureReference(d);
    // Session 66 : pré-remplissage PTF depuis la fiche consultant — mêmes bornes que session 65
    // (source vide ne remplace pas saisie existante, pré-remplissage GET-TIME, pas rejoué).
    applyConsultantData(d, m.AR_Consultant__c, input);
    d.generatedAt = System.now();
    d.isPreview = false;

    // --- Session 35 : socle multi-gabarits (résolution elle-même déplacée en amont, session 36) --
    d.templateCode = resolution.code;
    d.templateCodeSource = resolution.source;

    d.siretClient = formatSiret(acc);
    // C17 : le titre du besoin lu sur le besoin lui-même, pas sur la copie dénormalisée de la
    // matrice — celle-ci date de la création de la matrice et peut avoir divergé. Repli sur la
    // copie si le besoin n'est plus lisible.
    d.titreBesoin = String.isNotBlank(positionTitle) ? positionTitle : m.AR_Position_Name__c;
    // Session 122b : les dates de la matrice font foi (même source que l'échéancier) ; la durée
    // Connexys n'est plus qu'un repli quand la matrice n'a pas de dates.
    Integer matrixDurationMonths = monthsBetween(m.AR_Start_Date__c, m.AR_End_Date__c);
    d.dureeMois = matrixDurationMonths != null ? matrixDurationMonths : connexysDurationMonths;
    d.materielItems = parseMaterielItems(input.materielItems);
    d.interlocuteurTechniqueNom = technicalContact != null ? technicalContact.Name : null;
    d.interlocuteurTechniqueFonction = technicalContact != null ? technicalContact.Title : null;
    d.coutTotalJour = m.AR_Total_Daily_Cost__c;
    d.plancherPercent = m.AR_Floor_Percent_Applied__c; // session 123b : plancher figé de la matrice (grand compte compris)
    d.rfaPercent = m.AR_RFA_Percent__c;
    d.lots = buildLots(d.schedule, m.AR_Start_Date__c, input.lotOverrides);
    d.lotsTotal = d.lots.isEmpty() ? null : sumLots(d.lots);
    applyPtfInitiale(d, input.ptfInitialeDocumentId);
    d.domaineExpertise = input.domaineExpertise;
    applyAbmiFields(d, input);

    d.historique = buildHistoriquePtf(priorDocs, d, input);
    d.showHistorique = priorDocs.size() > 0;
    return d;
  }

  /**
   * Session 184d : la référence affichée (page de garde, pied de page, AR_Reference__c) est exactement
   * le nom produit par AR_PTFGenerationService.buildNomenclatureFileName — une seule fonction pour la
   * référence et le nom de fichier. À appeler une fois managerName, consultantNom, dates, version et
   * templateCode posés. Sans nom de client la nomenclature est impossible : la référence technique
   * posée plus haut est conservée (repli identique à celui du nom de fichier). Tronquée à 255, taille
   * du champ AR_Reference__c.
   */
  private static void applyNomenclatureReference(AR_PTFData d) {
    String nomenclature = AR_PTFGenerationService.buildNomenclatureFileName(d);
    if (String.isNotBlank(nomenclature)) {
      d.reference = nomenclature.length() > 255 ? nomenclature.substring(0, 255) : nomenclature;
    }
  }

  /**
   * Session 38 (gabarit ABMI_DQ012) : copie directe des saisies GenerationInput.abmi*, sans règle de
   * repli sauf pour trois champs qui ont un défaut sûr — jamais le texte d'exemple du .docx source
   * (cf. AR_PTFData, région "Session 38").
   *
   * - abmiNosReferences : reprend la référence interne (arbitrage 1, "garde la référence interne")
   *   quand rien n'est saisi, jamais un faux format de devis fabriqué.
   * - abmiSignataire{1,2}{Nom,Fonction} : préremplis avec rédacteur/valideur (arbitrage 4), déjà
   *   résolus plus haut dans collect() — jamais recalculés depuis une hiérarchie Connexys que
   *   Matthieu n'a pas confirmée pour ce gabarit.
   * - abmiPropositionFinanciereTexte : paragraphe calculé depuis le TJM/l'échéancier de la matrice
   *   (arbitrage 2, "texte libre amendable"), sur le modèle de la phrase du .docx source
   *   ("Ce montant est basé sur un tarif journalier de XXX € HT/jour... estimé à xxx jours"),
   *   jamais le tableau de lots des gabarits Abylsen/avenant.
   */
  private static void applyAbmiFields(AR_PTFData d, GenerationInput input) {
    d.abmiNosReferences = String.isNotBlank(input.abmiNosReferences)
      ? input.abmiNosReferences
      : d.reference;
    d.abmiAttentionDe = input.abmiAttentionDe;

    d.abmiSignataire1Nom = String.isNotBlank(input.abmiSignataire1Nom)
      ? input.abmiSignataire1Nom
      : d.redacteurNom;
    d.abmiSignataire1Fonction = String.isNotBlank(input.abmiSignataire1Fonction)
      ? input.abmiSignataire1Fonction
      : d.redacteurFonction;
    d.abmiSignataire1Tel = input.abmiSignataire1Tel;
    d.abmiSignataire1Mobile = input.abmiSignataire1Mobile;
    d.abmiSignataire1Email = input.abmiSignataire1Email;

    d.abmiSignataire2Nom = String.isNotBlank(input.abmiSignataire2Nom)
      ? input.abmiSignataire2Nom
      : d.valideurNom;
    d.abmiSignataire2Fonction = String.isNotBlank(input.abmiSignataire2Fonction)
      ? input.abmiSignataire2Fonction
      : d.valideurFonction;
    d.abmiSignataire2Tel = input.abmiSignataire2Tel;
    d.abmiSignataire2Email = input.abmiSignataire2Email;

    // Arbitrage 3 : saisie libre pure, jamais un texte d'exemple du .docx en repli.
    d.abmiDescriptionTravaux = input.abmiDescriptionTravaux;
    d.abmiDonneesEntree = input.abmiDonneesEntree;
    d.abmiDescriptionSolution = input.abmiDescriptionSolution;
    d.abmiAvantages = input.abmiAvantages;
    d.abmiRessources = input.abmiRessources;
    d.abmiOrganisationProjet = input.abmiOrganisationProjet;
    d.abmiHabilitations = input.abmiHabilitations;
    d.abmiAnalyseRisques = input.abmiAnalyseRisques;

    if (String.isNotBlank(input.abmiPropositionFinanciereTexte)) {
      d.abmiPropositionFinanciereTexte = input.abmiPropositionFinanciereTexte;
    } else if (d.tjm != null && !d.schedule.isEmpty()) {
      Decimal totalJoursCalc = 0;
      for (AR_PTFData.ScheduleRow row : d.schedule) {
        totalJoursCalc += row.jours;
      }
      String tarifTexte = AR_PTFFormatUtil.tjmPeriodesLabel(d.tjmPeriodes, d.currencyCode);
      if (tarifTexte == null) {
        tarifTexte = AR_PTFFormatUtil.formatNumberFr(d.tjm, 0, AR_PTFFormatUtil.currencySymbol(d.currencyCode)) +
          ' HT/jour';
      }
      d.abmiPropositionFinanciereTexte = 'Ce montant est basé sur un tarif journalier de ' +
        tarifTexte +
        ' sur site du Client et estimé à ' +
        AR_PTFFormatUtil.formatNumberFr(totalJoursCalc, 2, 'j') + '.';
    } else {
      d.abmiPropositionFinanciereTexte = null;
    }
  }

  /**
   * Session 184c : TP_Experience__c et TP_Competences_techniques_et_transverses__c ne servent
   * qu'au gabarit générique, retiré en session 184c. Pré-remplissage serveur supprimé.
   * Les propriétés restent dans AR_PTFData (forme du snapshot inchangée, cf. piège resetEmpty()).
   */
  private static void applyConsultantData(
    AR_PTFData d,
    Id consultantId,
    GenerationInput input
  ) {
    d.consultantExperience = input.consultantExperience;
    d.consultantCompetences = input.consultantCompetences;
  }

  /**
   * Collecte pour un AVENANT (session 37) — se rattache à un AR_PTF_Document__c existant (la « PTF
   * initiale »), ne le remplace pas, ne consomme pas son AR_Version_Number__c (numérotation propre,
   * cf. AR_PTFGenerationService.nextAvenantNumber). Ce n'est NI une nouvelle PTF NI une nouvelle
   * version de la PTF (cf. tête de section « Ce qu'est un avenant » du prompt de session) : méthode
   * séparée de collect() plutôt qu'un paramètre supplémentaire — collect() reste inchangée et sa
   * couverture de tests existante n'est pas mise en jeu par cette fonctionnalité.
   *
   * Réutilise directement les briques privées déjà éprouvées par collect() (résolution d'entité,
   * adresse, SIRET, rédacteur/valideur, historique, lots) plutôt que de les dupliquer.
   */
  public static AR_PTFData collectAvenant(
    AR_PTF_Document__c parentDoc,
    AvenantGenerationInput input,
    Integer avenantNumber
  ) {
    // Session 180d : avenant piloté par la matrice — `input.matrixId` désigne la matrice avenant
    // (AR_Version_Type__c = 'Avenant'), qui porte tarif, dates et échéancier ; sans lui (avenants
    // antérieurs à la 180, formulaire historique), la matrice lue reste celle de la PTF d'origine.
    Boolean matrixDriven = input != null && input.matrixId != null;
    Id avenantMatrixId = matrixDriven ? input.matrixId : parentDoc.AR_Price_Matrix__c;
    AR_Price_Matrix__c m = [
      SELECT
        Id,
        Name,
        AR_Status__c,
        AR_Position__c,
        AR_Position__r.cxsrec__Account__c,
        AR_Position__r.AB_Need_details__r.AB_Account__c,
        AR_Position_Name__c,
        AR_Account_Name__c,
        AR_Entity_Ref__c,
        AR_Consultant_Name__c,
        AR_Consultant__c,
        AR_Consultant__r.Name,
        AR_Client_Site__c,
        AR_Start_Date__c,
        AR_End_Date__c,
        AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Enabled__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c,
        AR_Currency__c,
        AR_Proposed_TJM__c,
        AR_Total_Daily_Cost__c,
        AR_RFA_Percent__c,
        AR_Floor_Percent_Applied__c,
        AR_Selected_Validator__r.Name,
        AR_Selected_Validator__r.Title,
        AR_Effective_Validator__r.Name,
        AR_Effective_Validator__r.Title,
        OwnerId,
        AR_Previous_Version__c,
        AR_Version_Type__c,
        AR_Amended_PTF__c,
        AR_Avenant_Changes__c
      FROM AR_Price_Matrix__c
      WHERE Id = :avenantMatrixId
      LIMIT 1
    ];
    if (!GENERATABLE_STATUSES.contains(m.AR_Status__c)) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_OnlyValidatedCanAmend, new List<Object>{ m.AR_Status__c })
      );
    }

    if (matrixDriven && (m.AR_Version_Type__c != 'Avenant' || m.AR_Amended_PTF__c != parentDoc.Id)) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_NotAnAvenantOf, new List<Object>{ parentDoc.AR_Reference__c })
      );
    }

    // Session 122 : Account from junction object first (AB_Need_details__r.AB_Account__c), fallback to Position
    Id accountId = (m.AR_Position__r.AB_Need_details__r != null &&
                    m.AR_Position__r.AB_Need_details__r.AB_Account__c != null)
      ? m.AR_Position__r.AB_Need_details__r.AB_Account__c
      : m.AR_Position__r.cxsrec__Account__c;

    Account acc = accountId != null
      ? [
          SELECT Name, BillingStreet, BillingPostalCode, BillingCity, ShippingStreet, ShippingPostalCode,
                 ShippingCity, SIRET__c
          FROM Account
          WHERE Id = :accountId
          LIMIT 1
        ]
      : null;

    Contact technicalContact = null;
    // C17 (session 57) : titre du besoin, même source que collect() — pour la ligne « Projet » du
    // tableau d'identification de la page de garde, partagée entre PTF et avenant.
    String positionTitle = null;
    for (cxsrec__cxsPosition__c pos : [
      SELECT Name, cxsrec__Contact_for_questions__r.Name, cxsrec__Contact_for_questions__r.Title,
             cxsrec__Contact_for_questions__r.Phone, cxsrec__Contact_for_questions__r.MobilePhone,
             cxsrec__Contact_for_questions__r.Email
      FROM cxsrec__cxsPosition__c
      WHERE Id = :m.AR_Position__c
      LIMIT 1
    ]) {
      technicalContact = pos.cxsrec__Contact_for_questions__r;
      positionTitle = pos.Name;
    }

    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
    Decimal joursParMoisDefault = defaultJoursParMois();
    // L'avenant reprend le choix de facturation de la PTF qu'il modifie (snapshot d'origine),
    // y compris ses jours facturés par mois en mode lissé. Snapshot absent ou sans le champ : décoché.
    AR_PTFData parentEcheancier = null;
    Boolean echeancierIllisible = false;
    try {
      parentEcheancier = readParentSnapshot(parentDoc.Id);
    } catch (Exception e) {
      // Afficher (doctrine session 34) : le repli est signalé dans les avertissements, jamais silencieux.
      System.debug(LoggingLevel.ERROR, 'Snapshot de la PTF d\'origine illisible (échéancier) : ' + e.getMessage());
      echeancierIllisible = true;
    }
    Boolean lissee = parentEcheancier != null && parentEcheancier.mensualisationLissee == true;
    Decimal joursParMoisAvenant = lissee && parentEcheancier.joursParMois != null
      ? parentEcheancier.joursParMois
      : joursParMoisDefault;

    AR_PTFData d = new AR_PTFData();
    d.client = m.AR_Account_Name__c;
    d.warnings = new List<String>();
    // Session 142b : avertissement si l'adresse client n'a pu être renseignée. Session 279 : adresse
    // saisie dans le formulaire d'avenant prioritaire.
    applyClientAddress(d, acc, input == null ? null : input.adresseClient);
    d.entite = entityRef == null ? null : entityRef.Name;
    d.entiteInfo = toEntiteInfo(entityRef, AVENANT_TEMPLATE_CODE);
    d.currencyCode = String.isNotBlank(m.AR_Currency__c) ? m.AR_Currency__c : 'EUR';
    d.tjm = m.AR_Proposed_TJM__c;
    d.nbConsultants = NB_CONSULTANTS;
    d.dateDebut = m.AR_Start_Date__c;
    d.dateFin = m.AR_End_Date__c;
    // Session 54 : même préférence lookup > texte libre que collect() ci-dessus.
    d.consultantNom = m.AR_Consultant__r != null ? m.AR_Consultant__r.Name : m.AR_Consultant_Name__c;
    d.siretClient = formatSiret(acc);
    d.titreBesoin = String.isNotBlank(positionTitle) ? positionTitle : m.AR_Position_Name__c;

    d.templateCode = AVENANT_TEMPLATE_CODE;
    d.templateCodeSource = 'Avenant';
    d.isPreview = false;
    d.generatedAt = System.now();
    d.reference = 'AV' + avenantNumber + '-' + parentDoc.AR_Reference__c;
    d.version = 'AV' + avenantNumber;

    // Session 145 : rédacteur, valideur et interlocuteur CLIENT résolus par résolveAvenantContacts
    // (formulaire > PTF d'origine > source actuelle). Avant, ils étaient reconstruits depuis Connexys
    // et la matrice sans jamais regarder la PTF d'origine : l'interlocuteur qu'elle portait était
    // perdu dès que le contact technique du besoin était vide (relevé 06/10/2026, docs/145).
    // C0/C7 : rédacteur = BM de l'affaire (AVENANT_TEMPLATE_CODE est dans
    // TEMPLATES_USING_BM_REDACTEUR). C1 : valideur obligatoire, jamais un DA recalculé.
    // C2/C3 : à défaut de PTF d'origine lisible, interlocuteur = contact technique du besoin.
    User bm = loadUser(m.OwnerId);
    // Session 177 : managerName = nom du propriétaire de la matrice (BM), utilisé pour le trigramme
    // du manager dans la nomenclature PTF.
    d.managerName = bm != null ? bm.Name : null;
    applyNomenclatureReference(d);
    AvenantContacts contacts = resolveAvenantContacts(m, parentDoc.Id, input, technicalContact, bm);
    if (String.isNotBlank(contacts.warning)) {
      d.warnings.add(contacts.warning);
    }
    d.redacteurNom = contacts.redacteurNom;
    d.redacteurFonction = contacts.redacteurFonction;
    d.valideurNom = contacts.valideurNom;
    d.valideurFonction = contacts.valideurFonction;
    d.valideurBlocage = contacts.valideurBlocage;
    if (d.valideurBlocage != null) {
      throw newAuraException(d.valideurBlocage);
    }
    d.interNom = contacts.interNom;
    d.interFonction = contacts.interFonction;
    d.interTel = contacts.interTel;
    d.interEmail = contacts.interEmail;

    // C8/C9 : référence et date de la PTF initiale, jamais ressaisies.
    d.ptfInitialeDocumentId = parentDoc.Id;
    d.ptfInitialeReference = parentDoc.AR_Reference__c;
    d.ptfInitialeDate = parentDoc.AR_Generated_At__c == null ? null : parentDoc.AR_Generated_At__c.date();
    // Session 49 (cause B) : un avenant qui ne cite pas la référence/date de la PTF qu'il modifie
    // est juridiquement vide — le cas le plus grave relevé avec le prix (§ci-dessus). Ne devrait
    // jamais se produire (parentDoc vient d'une PTF déjà générée, donc déjà pourvue des deux), mais
    // bloquer plutôt que d'imprimer "(référence non renseignée)" si un document parent incomplet
    // devait un jour exister.
    if (String.isBlank(d.ptfInitialeReference) || d.ptfInitialeDate == null) {
      throw newAuraException(
        Label.AR_Msg_PTF_OriginRefMissing
      );
    }

    d.mensualisationLissee = lissee;
    d.joursParMois = joursParMoisAvenant;
    if (echeancierIllisible) {
      d.warnings.add(Label.AR_Msg_PTF_OriginEcheancierUnreadable);
    }
    if (matrixDriven) {
      applyMatrixDrivenAvenantBody(d, m, input, joursParMoisAvenant, lissee);
    } else {
      applyFormDrivenAvenantBody(d, m, input, joursParMoisAvenant, lissee);
    }

    d.coutTotalJour = m.AR_Total_Daily_Cost__c;
    d.plancherPercent = m.AR_Floor_Percent_Applied__c; // session 123b : plancher figé de la matrice (grand compte compris)
    d.rfaPercent = m.AR_RFA_Percent__c;

    // Historique : même règle que la PTF Abylsen (périmètre besoin), avec un libellé propre plutôt
    // que Création/Régénération — un avenant n'est ni l'un ni l'autre.
    d.historique = buildHistorique(
      m.Id, m.AR_Position__c, AVENANT_TEMPLATE_CODE, null, d.version, d.reference, d.generatedAt,
      d.redacteurNom, d.valideurNom, false, 'Avenant'
    );
    // Session 151 : pour les avenants, toujours afficher l'historique (session 37 : « aucun changement »)
    d.showHistorique = true;
    return d;
  }

  /**
   * Corps d'un avenant historique (formulaire, avant la session 180) : prolongation, bloc de révision
   * de prix, nouveau TJM et dates viennent de l'entrée du formulaire. Code déplacé tel quel depuis
   * collectAvenant (session 180d), comportement inchangé.
   */
  private static void applyFormDrivenAvenantBody(
    AR_PTFData d,
    AR_Price_Matrix__c m,
    AvenantGenerationInput input,
    Decimal joursParMois,
    Boolean lissee
  ) {
    String country = entityCountryOf(m.AR_Entity_Ref__c);
    // Corps de l'avenant — variables 2/3 (docs/33 §2). La prolongation est toujours renseignée ;
    // le bloc de révision de prix est conditionnel (`revisionPrix`), jamais affiché avec un tableau
    // vide sur un avenant de simple prolongation.
    // Session 49 (cause B) : "toujours renseignée" était une intention non vérifiée — le gabarit
    // imprimait "(date non renseignée)" faute de garde. Bloqué ici comme le reste de cette famille
    // de défauts, plutôt que dégradé à l'affichage.
    if (input.prolongationJusquAu == null) {
      throw newAuraException(
        Label.AR_Msg_PTF_ExtensionDateRequired
      );
    }
    d.prolongationJusquAu = input.prolongationJusquAu;
    d.revisionPrix = input.revisionPrix == true;
    if (d.revisionPrix) {
      if (input.revisionPrixADateDu == null) {
        throw newAuraException(
          Label.AR_Msg_PTF_PriceRevisionDateRequired
        );
      }
      // Session 123 : nouveau TJM obligatoire quand la case révision de prix est cochée.
      if (input.nouveauTjm == null || input.nouveauTjm <= 0) {
        throw newAuraException(
          Label.AR_Msg_PTF_NewRateRequired
        );
      }
      d.revisionPrixADateDu = input.revisionPrixADateDu;
      d.nouveauTjm = input.nouveauTjm;
      // Le tableau Lots/Montant/Échéancier est réutilisé TEL QUEL (session 35), ré-ancré sur la date
      // d'effet de la révision plutôt que sur la date de début de mission, en conservant le même
      // nombre de lots que l'échéancier d'origine (repli documenté, cf. docs/37-avenant.md — question
      // ouverte sur la sémantique d'un lot, déjà signalée en docs/34 §"Questions").
      // Session 123 : échéancier calculé avec le NOUVEAU TJM au lieu de l'ancien
      // Session 122 : pass totalDays for proportional redistribution
      List<AR_PTFData.ScheduleRow> originalSchedule = buildSchedule(
        m.AR_Start_Date__c, m.AR_End_Date__c, m.AR_Proposed_TJM__c, joursParMois, NB_CONSULTANTS, scheduleTotalDays(m), lissee,
        null, null, country
      );
      // Session 123b : l'échéancier révisé court de la date d'effet à la date de prolongation (déjà
      // exigée plus haut), et non plus « autant de lots que l'origine ».
      Date revisedEnd = input.prolongationJusquAu;
      List<AR_PTFData.ScheduleRow> revisedSchedule = buildSchedule(
        input.revisionPrixADateDu, revisedEnd, input.nouveauTjm, joursParMois, NB_CONSULTANTS, null /* jours ouvrés réels : le nombre de jours de la mission d'origine ne s'applique pas à l'avenant */, lissee,
        null, null, country
      );
      d.schedule = revisedSchedule;
      d.lots = buildLots(revisedSchedule, input.revisionPrixADateDu, input.lotOverrides);
      d.lotsTotal = d.lots.isEmpty() ? null : sumLots(d.lots);
      d.totalHT = d.lotsTotal;
    } else {
      d.schedule = new List<AR_PTFData.ScheduleRow>();
      d.lots = new List<AR_PTFData.LotRow>();
      d.nouveauTjm = null;
    }
  }

  /**
   * Corps d'un avenant piloté par la matrice (session 180d) : tout vient de la matrice avenant — date
   * d'effet = AR_Start_Date__c, fin = AR_End_Date__c, nouveau TJM = AR_Proposed_TJM__c, réponses aux
   * trois questions = AR_Avenant_Changes__c. Aucune saisie de prix ni de date dans le formulaire.
   *
   *  - Prolongation (Période = Oui) : paragraphe « prolongées jusqu'au » imprimé avec la fin de la
   *    matrice ; sinon `prolongationJusquAu` reste null et la page ne l'imprime pas.
   *  - Bloc de prix (`revisionPrix`) : imprimé si le Tarif OU la Période change (Q5 B, 14/10/2026 :
   *    une prolongation au même tarif imprime l'échéancier de la période prolongée). Le nom de la
   *    propriété est historique ; il vaut ici « le bloc tarif/échéancier est imprimé ».
   *  - Seul le coût change (Q4 B) : avenant généré quand même, sans paragraphe de prolongation ni bloc
   *    de prix — aucun texte contractuel inventé.
   * Échéancier : buildSchedule(date d'effet, fin, TJM, …, jours ouvrés de la matrice avenant).
   */
  private static void applyMatrixDrivenAvenantBody(
    AR_PTFData d,
    AR_Price_Matrix__c m,
    AvenantGenerationInput input,
    Decimal joursParMois,
    Boolean lissee
  ) {
    String country = entityCountryOf(m.AR_Entity_Ref__c);
    Set<String> changes = new Set<String>(
      String.isBlank(m.AR_Avenant_Changes__c) ? new List<String>() : m.AR_Avenant_Changes__c.split(';')
    );
    Boolean periode = changes.contains('Période');
    Boolean printPriceBlock = changes.contains('Tarif') || periode;
    if (m.AR_Start_Date__c == null || m.AR_End_Date__c == null) {
      throw newAuraException(
        Label.AR_Msg_PTF_AvenantDatesMissing
      );
    }
    d.prolongationJusquAu = periode ? m.AR_End_Date__c : null;
    d.revisionPrix = printPriceBlock;
    if (printPriceBlock) {
      if (m.AR_Proposed_TJM__c == null || m.AR_Proposed_TJM__c <= 0) {
        throw newAuraException(Label.AR_Msg_PTF_AvenantRateMissing);
      }
      d.revisionPrixADateDu = m.AR_Start_Date__c;
      d.nouveauTjm = m.AR_Proposed_TJM__c;
      List<AR_PTFData.ScheduleRow> schedule = buildSchedule(
        m.AR_Start_Date__c, m.AR_End_Date__c, m.AR_Proposed_TJM__c, joursParMois, NB_CONSULTANTS,
        scheduleTotalDays(m), lissee, null, null, country
      );
      d.schedule = schedule;
      d.lots = buildLots(schedule, m.AR_Start_Date__c, input.lotOverrides);
      d.lotsTotal = d.lots.isEmpty() ? null : sumLots(d.lots);
      d.totalHT = d.lotsTotal;
    } else {
      d.schedule = new List<AR_PTFData.ScheduleRow>();
      d.lots = new List<AR_PTFData.LotRow>();
      d.nouveauTjm = null;
    }
  }

  private static final String AVENANT_PARENT_CONTACTS_UNREADABLE =
    Label.AR_Msg_PTF_OriginContactsUnreadable;

  /**
   * Session 145 — contacts d'un avenant : formulaire (si non vide) > valeur figée dans le snapshot de
   * la PTF d'origine > source actuelle (comportement d'avant la session). Lecture du snapshot dans un
   * try/catch qui ne masque rien : snapshot absent ou illisible → repli sur la source actuelle ET
   * message dans `warning` (relayé dans AR_PTFData.warnings par collectAvenant).
   *
   * Interlocuteur CLIENT : la priorité s'applique par BLOC, pas champ par champ — si la PTF d'origine
   * porte un interlocuteur (n'importe lequel des quatre champs), l'avenant reprend ce bloc, sinon le
   * contact technique du besoin ; un téléphone de l'un ne se retrouve jamais accolé au nom de l'autre.
   * Le formulaire surcharge ensuite champ par champ (saisie explicite). Même logique par paire
   * nom/fonction pour rédacteur et valideur.
   */
  private static AvenantContacts resolveAvenantContacts(
    AR_Price_Matrix__c m,
    Id parentDocId,
    AvenantGenerationInput input,
    Contact technicalContact,
    User bm
  ) {
    AvenantContacts c = new AvenantContacts();
    AR_PTFData parent = null;
    try {
      parent = readParentSnapshot(parentDocId);
      if (parent == null) {
        c.warning = AVENANT_PARENT_CONTACTS_UNREADABLE;
      }
    } catch (Exception e) {
      // Afficher (doctrine session 34) : le repli est signalé à l'utilisateur, jamais silencieux.
      System.debug(LoggingLevel.ERROR, 'Snapshot de la PTF d\'origine illisible : ' + e.getMessage());
      c.warning = AVENANT_PARENT_CONTACTS_UNREADABLE;
    }

    Boolean parentHasInter = parent != null &&
      (String.isNotBlank(parent.interNom) || String.isNotBlank(parent.interFonction) ||
       String.isNotBlank(parent.interTel) || String.isNotBlank(parent.interEmail));
    String baseNom;
    String baseFonction;
    String baseTel;
    String baseEmail;
    if (parentHasInter) {
      baseNom = parent.interNom;
      baseFonction = parent.interFonction;
      baseTel = parent.interTel;
      baseEmail = parent.interEmail;
    } else if (technicalContact != null) {
      baseNom = technicalContact.Name;
      baseFonction = technicalContact.Title;
      baseTel = String.isNotBlank(technicalContact.Phone) ? technicalContact.Phone : technicalContact.MobilePhone;
      baseEmail = technicalContact.Email;
    }
    c.interNom = String.isNotBlank(input.interNom) ? input.interNom : baseNom;
    c.interFonction = String.isNotBlank(input.interFonction) ? input.interFonction : baseFonction;
    c.interTel = String.isNotBlank(input.interTel) ? input.interTel : baseTel;
    c.interEmail = String.isNotBlank(input.interEmail) ? input.interEmail : baseEmail;

    Boolean redacteurFromParent = String.isBlank(input.redacteurNom) && parent != null &&
      String.isNotBlank(parent.redacteurNom);
    c.redacteurNom = String.isNotBlank(input.redacteurNom)
      ? input.redacteurNom
      : (redacteurFromParent ? parent.redacteurNom : (bm != null ? bm.Name : null));
    c.redacteurFonction = String.isNotBlank(input.redacteurFonction)
      ? input.redacteurFonction
      : (redacteurFromParent ? parent.redacteurFonction : (bm != null ? bm.Title : null));

    // Valideur : choix du formulaire s'il est proposable ; sinon celui de la PTF d'origine s'il l'est
    // encore (même nom, fonction reprise) ; sinon valideurDe.
    ValideurChoice choix = resolveValideur(bm, m.AR_Entity_Ref__c, input.valideurId, input.valideurFonction);
    if (!choix.fromInput && parent != null && String.isNotBlank(parent.valideurNom)) {
      for (ValideurOption opt : valideurOptions(bm, m.AR_Entity_Ref__c)) {
        if (opt.name == parent.valideurNom) {
          choix = resolveValideur(bm, m.AR_Entity_Ref__c, opt.id, parent.valideurFonction);
          break;
        }
      }
    }
    c.valideurId = choix.id;
    c.valideurNom = choix.nom;
    c.valideurFonction = choix.fonction;
    c.valideurBlocage = valideurError(c.valideurNom, bm);
    return c;
  }

  /** Snapshot figé de la PTF d'origine ; null si absent. JSONException propagée si illisible. */
  private static AR_PTFData readParentSnapshot(Id parentDocId) {
    if (parentDocId == null) {
      return null;
    }
    List<AR_PTF_Document__c> docs = [
      SELECT AR_Snapshot__c FROM AR_PTF_Document__c WHERE Id = :parentDocId LIMIT 1
    ];
    if (docs.isEmpty() || String.isBlank(docs[0].AR_Snapshot__c)) {
      return null;
    }
    return (AR_PTFData) JSON.deserialize(docs[0].AR_Snapshot__c, AR_PTFData.class);
  }

  /**
   * Session 145 — valeurs par défaut du formulaire d'avenant (interlocuteur CLIENT, rédacteur,
   * valideur), calculées par la même règle que la génération (resolveAvenantContacts) : ce que le
   * formulaire affiche est exactement ce que le serveur figerait en l'absence de saisie. Non
   * cacheable : appel impératif à l'ouverture du formulaire (cf. piège session 51).
   */
  @AuraEnabled(cacheable=false)
  public static AvenantContacts getAvenantDefaults(Id parentDocId) {
    try {
      AR_PTF_Document__c parentDoc = [
        SELECT Id, AR_Price_Matrix__c FROM AR_PTF_Document__c WHERE Id = :parentDocId LIMIT 1
      ];
      AR_Price_Matrix__c m = [
        SELECT Id, OwnerId, AR_Position__c, AR_Entity_Ref__c,
               AR_Selected_Validator__r.Name, AR_Selected_Validator__r.Title,
               AR_Effective_Validator__r.Name, AR_Effective_Validator__r.Title
        FROM AR_Price_Matrix__c
        WHERE Id = :parentDoc.AR_Price_Matrix__c
        LIMIT 1
      ];
      Contact technicalContact = null;
      for (cxsrec__cxsPosition__c pos : [
        SELECT cxsrec__Contact_for_questions__r.Name, cxsrec__Contact_for_questions__r.Title,
               cxsrec__Contact_for_questions__r.Phone, cxsrec__Contact_for_questions__r.MobilePhone,
               cxsrec__Contact_for_questions__r.Email
        FROM cxsrec__cxsPosition__c
        WHERE Id = :m.AR_Position__c
        LIMIT 1
      ]) {
        technicalContact = pos.cxsrec__Contact_for_questions__r;
      }
      AvenantContacts contacts = resolveAvenantContacts(
        m, parentDoc.Id, new AvenantGenerationInput(), technicalContact, loadUser(m.OwnerId)
      );
      contacts.adresseClient = accountAddressForMatrix(m.Id);
      return contacts;
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_AvenantDefaultsAction);
    }
  }

  /**
   * Session 126b : aperçu des lots révisés d'un avenant. Réutilise exactement le même code que
   * collectAvenant (buildSchedule + buildLots), sans DML. Paramètres tous optionnels (sauf
   * considération métier — voir ci-dessous) ; renvoie liste vide si l'un manque ou si prolongation
   * antérieure à date d'effet. Le LWC appelle cette méthode avec debounce 300 ms dès que les trois
   * paramètres changent.
   *
   * @param dateEffet date de début de la révision (revisionPrixADateDu)
   * @param prolongation date de fin (prolongationJusquAu)
   * @param nouveauTjm nouveau TJM avec lequel calculer les lots
   * @return liste des lots révisés, chacun avec mois/jours/montant
   */
  @AuraEnabled(cacheable=false)
  public static List<AR_PTFData.LotRow> previewAvenantLots(
    Date dateEffet,
    Date prolongation,
    Decimal nouveauTjm,
    Id parentDocId
  ) {
    if (dateEffet == null || prolongation == null || nouveauTjm == null) {
      return new List<AR_PTFData.LotRow>();
    }
    if (prolongation < dateEffet) {
      return new List<AR_PTFData.LotRow>();
    }

    // Réutilise les mêmes helpers que collectAvenant (doctrine : pas de réimplémentation en JS).
    Decimal joursParMoisDefault = 21; // AR_GeneralSettingDefaults.JOURS_PAR_MOIS
    // Même choix de facturation que la PTF d'origine (cf. collectAvenant).
    AR_PTFData parentEcheancier = readParentSnapshot(parentDocId);
    Boolean lissee = parentEcheancier != null && parentEcheancier.mensualisationLissee == true;
    Decimal joursParMoisAvenant = lissee && parentEcheancier.joursParMois != null
      ? parentEcheancier.joursParMois
      : joursParMoisDefault;
    String parentCountry = null;
    for (AR_PTF_Document__c doc : [SELECT AR_Price_Matrix__r.AR_Entity_Ref__c FROM AR_PTF_Document__c WHERE Id = :parentDocId LIMIT 1]) {
      parentCountry = entityCountryOf(doc.AR_Price_Matrix__r == null ? null : doc.AR_Price_Matrix__r.AR_Entity_Ref__c);
    }
    List<AR_PTFData.ScheduleRow> revisedSchedule = buildSchedule(
      dateEffet, prolongation, nouveauTjm, joursParMoisAvenant, NB_CONSULTANTS, null, lissee, null, null,
      parentCountry
    );
    return buildLots(revisedSchedule, dateEffet, null);
  }

  /**
   * Lots de l'échéancier d'une PTF recalculés quand la case « Facturation mensuelle lissée »
   * change dans le formulaire, sans le reconstruire (les valeurs saisies restent). Même calcul que
   * collect() ; lecture seule, sans blocage de génération.
   */
  @AuraEnabled(cacheable=false)
  public static List<AR_PTFData.LotRow> previewPtfLots(
    Id matrixId,
    Boolean facturationMensuelleLissee,
    List<String> tjmPeriodStarts
  ) {
    AR_Price_Matrix__c m = [
      SELECT AR_Start_Date__c, AR_End_Date__c, AR_Proposed_TJM__c, AR_Working_Days_Applied__c,
             AR_Entity_Ref__c, AR_Number_Of_Days__c, AR_Planned_Leave_Days__c, AR_RPLSR_Days_Sold__c, AR_RPLSR_Days_Produced__c, AR_TJM_Periods__c,
             AR_RPLSR_Enabled__c, AR_RPLSR_Plan__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
    Boolean lissee = m.AR_RPLSR_Enabled__c == true || facturationMensuelleLissee == true;
    Decimal joursParMois = joursParMoisPourEcheancier(
      m.AR_Working_Days_Applied__c, entityRef, lissee, defaultJoursParMois()
    );
    // Aperçu : dates saisies si lisibles, sinon estimées (jamais de blocage ici, lecture seule).
    List<AR_PTFData.ScheduleRow> schedule = buildSchedule(
      m.AR_Start_Date__c, m.AR_End_Date__c, m.AR_Proposed_TJM__c, joursParMois, NB_CONSULTANTS,
      scheduleTotalDays(m), lissee, buildTjmPeriodRows(m, tjmPeriodStarts, false), vendusParMoisDuPlan(m),
      entityRef == null ? null : entityRef.AR_Country__c
    );
    return buildLots(schedule, m.AR_Start_Date__c, null);
  }

  /** Payload en String JSON pour la création d'un avenant — même contournement Aura que GenerationInput. */
  public class AvenantGenerationInput {
    // Session 180d : matrice avenant (AR_Version_Type__c = 'Avenant') dont le document est généré ;
    // absent = avenant historique (formulaire), rattaché à la matrice de la PTF d'origine.
    @AuraEnabled
    public Id matrixId;
    @AuraEnabled
    public Id ptfDocumentId;
    @AuraEnabled
    public Date prolongationJusquAu;
    @AuraEnabled
    public Boolean revisionPrix;
    @AuraEnabled
    public Date revisionPrixADateDu;
    @AuraEnabled
    public Decimal nouveauTjm;
    @AuraEnabled
    public List<LotOverride> lotOverrides;
    @AuraEnabled
    public String redacteurNom;
    @AuraEnabled
    public String redacteurFonction;
    @AuraEnabled
    public String valideurNom;
    @AuraEnabled
    public String valideurFonction;
    @AuraEnabled
    public String valideurId;
    // Session 145 : contacts de l'avenant, pré-remplis par getAvenantDefaults depuis la PTF d'origine.
    @AuraEnabled
    public String interNom;
    @AuraEnabled
    public String interFonction;
    @AuraEnabled
    public String interTel;
    @AuraEnabled
    public String interEmail;
    // Session 279 : adresse client saisie dans le formulaire d'avenant (vide = adresse du compte).
    @AuraEnabled
    public String adresseClient;
  }

  /**
   * Contacts d'un avenant après résolution formulaire > PTF d'origine > source actuelle (session
   * 145). Sert à la fois de défauts pour le formulaire (getAvenantDefaults) et de valeurs figées dans
   * le snapshot (collectAvenant) : une seule règle, jamais deux implémentations qui divergent.
   */
  public class AvenantContacts {
    @AuraEnabled
    public String interNom;
    @AuraEnabled
    public String interFonction;
    @AuraEnabled
    public String interTel;
    @AuraEnabled
    public String interEmail;
    @AuraEnabled
    public String redacteurNom;
    @AuraEnabled
    public String redacteurFonction;
    @AuraEnabled
    public String valideurNom;
    @AuraEnabled
    public String valideurFonction;
    // Id du valideur retenu, pour sélectionner l'option correspondante du formulaire.
    @AuraEnabled
    public String valideurId;
    // Texte de blocage calculé par valideurError, null si le valideur existe.
    @AuraEnabled
    public String valideurBlocage;
    @AuraEnabled
    public String warning;
    // Session 279 : adresse du compte client, pré-remplissage du champ « Adresse client » de l'avenant.
    @AuraEnabled
    public String adresseClient;
  }

  /** Code de gabarit résolu + provenance de la résolution, figés ensemble dans le snapshot. */
  public class TemplateResolution {
    public String code;
    public String source;
    private TemplateResolution(String code, String source) {
      this.code = code;
      this.source = source;
    }
  }

  /**
   * Couche de sélection du gabarit (session 30), sans moteur derrière : manuel (formulaire) > compte
   * (AR_Account_Commercial_Data__c, grands comptes) > entité (AR_PTF_Entity_Referential__c) > Abylsen par défaut.
   * Plusieurs gabarits existent (pages Visualforce dédiées, résolues par AR_PTFGenerationService.resolveTemplatePage) :
   * cette méthode détermine et fige le CODE pour chaque génération. Depuis la session 184c, plus de
   * gabarit générique : un code inconnu ou une absence de source lève une erreur.
   */
  private static TemplateResolution resolveTemplate(
    GenerationInput input,
    AR_Price_Matrix__c m,
    AR_PTF_Entity_Referential__c entityRef
  ) {
    if (String.isNotBlank(input.templateCode)) {
      return new TemplateResolution(requireKnownCode(input.templateCode, Label.AR_Msg_PTF_OriginManualOverride), 'Manuel');
    }
    Id templateAccountId = m.AR_Position__r.AB_Need_details__r?.AB_Account__c != null
      ? m.AR_Position__r.AB_Need_details__r.AB_Account__c
      : m.AR_Position__r.cxsrec__Account__c;
    String accountCode = accountTemplateCode(templateAccountId);
    if (accountCode != null) {
      return new TemplateResolution(requireKnownCode(accountCode, Label.AR_Msg_PTF_OriginAccountData), 'Compte');
    }
    if (entityRef != null && String.isNotBlank(entityRef.AR_Template_Code__c)) {
      return new TemplateResolution(
        requireKnownCode(entityRef.AR_Template_Code__c, Label.AR_Msg_PTF_OriginEntity),
        'Entité'
      );
    }
    return new TemplateResolution(ABYLSEN_TEMPLATE_CODE, 'Abylsen');
  }

  /** Code de gabarit posé sur les données commerciales du compte, null si aucun (grands comptes). */
  private static String accountTemplateCode(Id accountId) {
    if (accountId == null) {
      return null;
    }
    // Session 184f : le paramétrage d'un compte vaut pour ses comptes enfants ; le plus proche gagne.
    List<Id> chain = AR_AccountHierarchy.chainFrom(accountId);
    Map<Id, String> codeByAccount = new Map<Id, String>();
    for (AR_Account_Commercial_Data__c d : [
      SELECT AR_Account__c, AR_PTF_Template_Code__c
      FROM AR_Account_Commercial_Data__c
      WHERE AR_Account__c IN :chain
    ]) {
      if (String.isNotBlank(d.AR_PTF_Template_Code__c) && !codeByAccount.containsKey(d.AR_Account__c)) {
        codeByAccount.put(d.AR_Account__c, d.AR_PTF_Template_Code__c);
      }
    }
    for (Id id : chain) {
      if (codeByAccount.containsKey(id)) {
        return codeByAccount.get(id);
      }
    }
    return null;
  }

  /**
   * Session 182 : le code de gabarit qui SERA utilisé pour une matrice (compte > entité > générique),
   * sans la surcharge manuelle (choisie plus tard, au formulaire) et sans jamais lever — mêmes
   * priorités que resolveTemplate, qui reste la seule à bloquer sur un code inconnu. Sert aux
   * surfaces de préparation (avertissements, libellés), qui ne doivent parler que du gabarit réel.
   */
  public static String expectedTemplateCode(Id accountId, AR_PTF_Entity_Referential__c entityRef) {
    String accountCode = accountTemplateCode(accountId);
    return accountCode != null ? accountCode : templateCodeForEntity(entityRef);
  }

  /** Gabarit propre d'une entité (AR_Template_Code__c), Abylsen par défaut si elle n'en a pas. */
  public static String templateCodeForEntity(AR_PTF_Entity_Referential__c entityRef) {
    return entityRef != null && String.isNotBlank(entityRef.AR_Template_Code__c)
      ? entityRef.AR_Template_Code__c
      : ABYLSEN_TEMPLATE_CODE;
  }

  /**
   * Session 35 : un code inconnu ne retombe PLUS silencieusement sur le générique. Avec quatre
   * gabarits contractuels, ce repli muet est le meilleur moyen d'envoyer au client un document sur
   * le mauvais modèle sans que personne ne le voie. Le message nomme le code fautif, l'endroit d'où
   * il vient (surcharge manuelle, compte, entité) et les codes valides — sans quoi l'administrateur
   * cherche dans trois référentiels.
   */
  private static String requireKnownCode(String code, String origin) {
    String error = templateCodeError(code, origin);
    if (error != null) {
      throw newAuraException(error);
    }
    return code;
  }

  /**
   * Le message d'erreur d'un code inconnu, ou null si le code est valide — SANS le lever.
   *
   * Pourquoi séparer : `AuraHandledException` ne peut être levée que depuis un contexte Aura/LWC ou
   * un test Apex (cf. CLAUDE.md) ; un script Apex anonyme échoue sur
   * `System.LimitException: Can only throw this exception type from VisualForce or Aura context`
   * AVANT d'atteindre le message métier. Sans ce point d'entrée, la règle serait invérifiable en
   * réel, et ce bloc se livrerait « testé, non vérifié ».
   */
  public static String templateCodeError(String code, String origin) {
    if (TEMPLATE_LABELS.containsKey(code)) {
      return null;
    }
    List<String> valid = new List<String>(TEMPLATE_LABELS.keySet());
    valid.sort();
    return AR_I18n.format(Label.AR_Msg_PTF_UnknownTemplateCode, new List<Object>{ code, origin, String.join(valid, ', ') });
  }

  /**
   * Doctrine du projet appliquée aux coordonnées bancaires (C48) : donnée de référence absente →
   * bloquer avec un message explicite, jamais substituer une valeur plausible. Une PTF Abylsen dont
   * l'article 4.5 porterait un IBAN vide ou un « À COMPLÉTER » ferait payer un client au mauvais
   * compte, ou pas du tout — les deux sont pires qu'un document non produit.
   *
   * Ne s'applique qu'aux gabarits qui impriment ces coordonnées : le générique n'en imprime aucune,
   * l'y soumettre casserait des générations qui fonctionnent aujourd'hui.
   */
  private static void requireBankDetails(
    String templateCode,
    String entityName,
    AR_PTF_Entity_Referential__c entityRef
  ) {
    String error = bankDetailsError(templateCode, entityName, entityRef);
    if (error != null) {
      throw newAuraException(error);
    }
  }

  /** Point d'entrée vérifiable en Apex anonyme, cf. templateCodeError ci-dessus. */
  public static String bankDetailsError(String templateCode, Id entityId) {
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(entityId);
    return bankDetailsError(templateCode, entityRef == null ? null : entityRef.Name, entityRef);
  }

  private static String bankDetailsError(
    String templateCode,
    String entityName,
    AR_PTF_Entity_Referential__c entityRef
  ) {
    if (!TEMPLATES_REQUIRING_BANK_DETAILS.contains(templateCode)) {
      return null;
    }
    String entityLabel = String.isNotBlank(entityName) ? entityName : Label.AR_Msg_PTF_NoEntityOnMatrix;
    if (entityRef == null) {
      return AR_I18n.format(Label.AR_Msg_PTF_BankDetailsEntityMissing, new List<Object>{ TEMPLATE_LABELS.get(templateCode), entityLabel });
    }
    List<String> missing = missingBankDetailFields(entityRef);
    if (!missing.isEmpty()) {
      missing.sort();
      return AR_I18n.format(Label.AR_Msg_PTF_BankDetailsMissing, new List<Object>{ entityLabel, String.join(missing, ', '), TEMPLATE_LABELS.get(templateCode) });
    }
    return null;
  }

  /** Champs manquants (C48), sans le message d'accompagnement — réutilisé par le blocage
   * (bankDetailsError ci-dessus) et par les surfaces de préparation (session 47, cf.
   * missingFieldsForTemplate).
   * Session 176h : le fax est FACULTATIF (décision d'Alexis du 15/10/2026) — absent de cette liste ;
   * le gabarit ABMI n'imprime la ligne « Fax » que s'il est renseigné.
   * Session 63 : référentiel v6, les coordonnées bancaires tiennent dans le seul bloc AR_Rib__c
   * (banque + IBAN/BIC ou code banque/guichet/compte/clé selon l'entité) — AR_Bank_Name__c/
   * AR_Iban__c/AR_Bic__c ne sont plus alimentés par cet import et deviennent inertes (conservés,
   * non supprimés, cf. docs/63-blocs-adresse-et-banque.md §6). Le bloc devient la seule condition :
   * les tester encore produirait un blocage permanent pour les 33 entités qui ont un RIB complet
   * mais plus aucune de ces trois valeurs. */
  private static List<String> missingBankDetailFields(AR_PTF_Entity_Referential__c entityRef) {
    List<String> missing = new List<String>();
    if (String.isBlank(entityRef.AR_Rib__c)) {
      missing.add(Label.AR_Msg_PTF_FieldRib);
    }
    return missing;
  }

  /**
   * Session 38 (ABMI_DQ012) : mêmes principes que requireBankDetails ci-dessus, sur les coordonnées
   * générales de l'entité (adresse/CP/ville/téléphone/site web ; fax facultatif) plutôt que bancaires — ce gabarit
   * n'imprime pas de RIB. Doctrine inchangée : donnée de référence absente → bloquer avec un message
   * explicite, jamais un "À COMPLÉTER" imprimé sur un document envoyé à un client.
   */
  private static void requireEntityContactDetails(
    String templateCode,
    String entityName,
    AR_PTF_Entity_Referential__c entityRef
  ) {
    String error = entityContactDetailsError(templateCode, entityName, entityRef);
    if (error != null) {
      throw newAuraException(error);
    }
  }

  /** Point d'entrée vérifiable en Apex anonyme, cf. templateCodeError ci-dessus. */
  public static String entityContactDetailsError(String templateCode, Id entityId) {
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(entityId);
    return entityContactDetailsError(templateCode, entityRef == null ? null : entityRef.Name, entityRef);
  }

  private static String entityContactDetailsError(
    String templateCode,
    String entityName,
    AR_PTF_Entity_Referential__c entityRef
  ) {
    if (!TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS.contains(templateCode)) {
      return null;
    }
    String entityLabel = String.isNotBlank(entityName) ? entityName : Label.AR_Msg_PTF_NoEntityOnMatrix;
    if (entityRef == null) {
      return AR_I18n.format(Label.AR_Msg_PTF_ContactDetailsEntityMissing, new List<Object>{ TEMPLATE_LABELS.get(templateCode), entityLabel });
    }
    List<String> missing = missingEntityContactFields(entityRef);
    if (!missing.isEmpty()) {
      missing.sort();
      return AR_I18n.format(Label.AR_Msg_PTF_ContactDetailsMissing, new List<Object>{ entityLabel, String.join(missing, ', '), TEMPLATE_LABELS.get(templateCode) });
    }
    return null;
  }

  /** Champs manquants, sans le message d'accompagnement — même principe que
   * missingBankDetailFields ci-dessus.
   * Session 63 : référentiel v6, l'adresse tient dans le seul bloc AR_Address__c (voie, CP/ville,
   * pays, mention légale) — AR_Postal_Code__c/AR_City__c ne sont plus alimentés par cet import et
   * deviennent inertes (conservés, non supprimés, cf. docs/63-blocs-adresse-et-banque.md §6). Les
   * tester encore bloquerait en permanence les 34 entités qui ont une adresse complète mais plus de
   * CP/Ville renseignés séparément. */
  private static List<String> missingEntityContactFields(AR_PTF_Entity_Referential__c entityRef) {
    Map<String, String> required = new Map<String, String>{
      Label.AR_Msg_PTF_FieldAddressBlock => entityRef.AR_Address__c,
      Label.AR_Common_Phone => entityRef.AR_Phone__c,
      Label.AR_APE_Website => entityRef.AR_Website__c
    };
    List<String> missing = new List<String>();
    for (String label : required.keySet()) {
      if (String.isBlank(required.get(label))) {
        missing.add(label);
      }
    }
    return missing;
  }

  /**
   * Session 152c : règle de blocage du tribunal de commerce (article 17 des conditions générales),
   * pure — reçoit le tribunal DÉJÀ résolu (formulaire > entité > réglage global) pour rester testable
   * sans dépendre du custom metadata. Même doctrine que bankDetailsError : donnée absente → bloquer,
   * jamais substituer. Null si le gabarit n'imprime pas le tribunal ou si une valeur est résolue.
   */
  @TestVisible
  private static String tribunalBlockError(String templateCode, String resolvedTribunal) {
    if (!TEMPLATES_REQUIRING_TRIBUNAL.contains(templateCode) || String.isNotBlank(resolvedTribunal)) {
      return null;
    }
    return AR_I18n.format(Label.AR_Msg_PTF_TribunalMissing, new List<Object>{ TEMPLATE_LABELS.get(templateCode) });
  }

  /** Tribunal par défaut du réglage global (AR_PTF_Setting__mdt.Default), null si absent. */
  private static String globalTribunal() {
    AR_PTF_Setting__mdt settings = AR_PTF_Setting__mdt.getInstance('Default');
    return settings == null ? null : settings.AR_Default_Tribunal_Competent__c;
  }

  /**
   * Diagnostic de préparation d'une entité pour un gabarit donné (session 47), SANS bloquer :
   * réutilisé par les surfaces qui doivent signaler un manque avant la génération (sélecteur
   * d'entité à la création de matrice, écran d'administration des entités PTF), sur les mêmes
   * règles que le blocage réel (bankDetailsError/entityContactDetailsError ci-dessus) — un seul
   * calcul de complétude, jamais un second chemin qui pourrait diverger. Retourne null si le
   * gabarit ne réclame rien à cette entité ou si elle est déjà complète pour lui.
   */
  public static String missingFieldsForTemplate(String templateCode, AR_PTF_Entity_Referential__c entityRef) {
    return missingFieldsForTemplate(templateCode, entityRef, globalTribunal());
  }

  /**
   * Le tribunal n'est signalé manquant que si l'entité ET le réglage global sont vides (session 152c) :
   * entité vide + réglage global renseigné = le tribunal par défaut sera utilisé, pas d'avertissement.
   */
  @TestVisible
  private static String missingFieldsForTemplate(
    String templateCode,
    AR_PTF_Entity_Referential__c entityRef,
    String globalTribunal
  ) {
    Boolean requiresBank = TEMPLATES_REQUIRING_BANK_DETAILS.contains(templateCode);
    Boolean requiresContact = TEMPLATES_REQUIRING_ENTITY_CONTACT_DETAILS.contains(templateCode);
    Boolean requiresTribunal = TEMPLATES_REQUIRING_TRIBUNAL.contains(templateCode);
    if (!requiresBank && !requiresContact && !requiresTribunal) {
      return null;
    }
    if (entityRef == null) {
      return Label.AR_Msg_PTF_EntityNotInReferential;
    }
    List<String> missing = new List<String>();
    if (requiresBank) {
      missing.addAll(missingBankDetailFields(entityRef));
    }
    if (requiresContact) {
      missing.addAll(missingEntityContactFields(entityRef));
    }
    if (requiresTribunal && String.isBlank(entityRef.AR_Tribunal_Competent__c) && String.isBlank(globalTribunal)) {
      missing.add(Label.AR_Msg_PTF_FieldTribunal);
    }
    if (missing.isEmpty()) {
      return null;
    }
    missing.sort();
    return String.join(missing, ', ');
  }

  /**
   * Préparation de l'entité de la matrice, pour chacun des gabarits connus (session 47) — permet à
   * arPtfPanel de désactiver « Confirmer et générer » AVANT que l'utilisateur ne heurte le blocage
   * serveur, dès que le gabarit sélectionné réclame des données que l'entité n'a pas. Un seul appel
   * à la création du formulaire : le client réévalue localement à chaque changement de gabarit,
   * sans nouvel aller-retour serveur.
   */
  @AuraEnabled
  public static Map<String, String> getEntityReadinessByTemplate(Id matrixId) {
    AR_Price_Matrix__c m = [SELECT AR_Entity_Ref__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
    Map<String, String> issuesByTemplate = new Map<String, String>();
    for (String code : TEMPLATE_LABELS.keySet()) {
      String issue = missingFieldsForTemplate(code, entityRef);
      if (issue != null) {
        issuesByTemplate.put(code, issue);
      }
    }
    return issuesByTemplate;
  }

  /**
   * Gabarit propre à l'entité de la matrice (et non le gabarit attendu compte > entité), avec le nom
   * de l'entité : sert au panneau PTF à avertir quand le gabarit choisi n'est pas celui de l'entité.
   * Appel impératif, sans cache : il doit suivre un changement d'entité sur une matrice validée.
   */
  @AuraEnabled
  public static Map<String, String> getEntityTemplateInfo(Id matrixId) {
    AR_Price_Matrix__c m = [SELECT AR_Entity_Ref__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
    AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
    Map<String, String> info = new Map<String, String>();
    if (entityRef == null) {
      return info;
    }
    String code = templateCodeForEntity(entityRef);
    info.put('entityName', entityRef.Name);
    info.put('templateCode', code);
    info.put('templateLabel', TEMPLATE_LABELS.containsKey(code) ? TEMPLATE_LABELS.get(code) : code);
    return info;
  }

  /** Codes de gabarit valides, pour le sélecteur du LWC — jamais une liste en dur côté client. */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getTemplateOptions() {
    return buildTemplateOptions(true);
  }

  /**
   * Gabarits de PTF proposables à la saisie dans l'administration (code gabarit par défaut d'une
   * entité, d'un grand compte — session 176i) : la même carte TEMPLATE_LABELS que la résolution,
   * moins l'avenant, qui n'est jamais un gabarit de PTF résolu par entité ou par compte. Les
   * services d'administration l'exposent derrière leur propre garde (AR_AdminReferentialService,
   * AR_AdminCommercialService) : la liste vient d'ici, une seule fois.
   */
  public static List<Map<String, String>> getPtfTemplateOptions() {
    return buildTemplateOptions(false);
  }

  private static List<Map<String, String>> buildTemplateOptions(Boolean includeAvenant) {
    List<Map<String, String>> options = new List<Map<String, String>>();
    List<String> codes = new List<String>(TEMPLATE_LABELS.keySet());
    codes.sort();
    for (String code : codes) {
      if (!includeAvenant && code == AVENANT_TEMPLATE_CODE) {
        continue;
      }
      options.add(new Map<String, String>{ 'value' => code, 'label' => TEMPLATE_LABELS.get(code) });
    }
    return options;
  }

  /**
   * SIRET du client (C9) : Account.SIRET__c est un champ NUMÉRIQUE dans cette org. Rendu tel quel,
   * un Decimal produirait « 12345678901234.0 » sur un document contractuel — formaté ici en chaîne
   * de chiffres, sans séparateur ni décimale.
   */
  private static String formatSiret(Account acc) {
    if (acc == null || acc.SIRET__c == null) {
      return null;
    }
    return String.valueOf(acc.SIRET__c.setScale(0, System.RoundingMode.HALF_UP).longValue());
  }

  /** C57 : durée en mois, repli sur les dates de mission quand Connexys ne la donne pas en mois. */
  private static Integer monthsBetween(Date startDate, Date endDate) {
    if (startDate == null || endDate == null || startDate > endDate) {
      return null;
    }
    return startDate.monthsBetween(endDate) + 1;
  }

  /** C27 : items saisis un par ligne ou séparés par des virgules ; jamais d'entrée vide. */
  private static List<String> parseMaterielItems(String raw) {
    List<String> items = new List<String>();
    if (String.isBlank(raw)) {
      return items;
    }
    for (String part : raw.split('[\n,;]')) {
      if (String.isNotBlank(part)) {
        items.add(part.trim());
      }
    }
    return items;
  }

  /**
   * C40/C43/C44/C45 — l'échéancier vu en LOTS. Par défaut 1 lot = 1 mois, échéance = fin du mois du
   * lot, montant = TJM × jours ouvrés du mois. `schedule` (mensuel) n'est pas modifié : `lots` en
   * est une vue enrichie, seule à porter les surcharges, pour que le gabarit générique continue de
   * rendre exactement ce qu'il rendait avant cette session.
   *
   * Une surcharge est OPTIONNELLE et PAR LOT : un lot non surchargé reste calculé, et le reste même
   * si les données de la matrice changent ensuite. `montantCalcule` est conservé à côté de
   * `montant` dans tous les cas — c'est ce qui rend l'écart auditable après coup.
   */
  private static List<AR_PTFData.LotRow> buildLots(
    List<AR_PTFData.ScheduleRow> schedule,
    Date startDate,
    List<LotOverride> overrides
  ) {
    List<AR_PTFData.LotRow> lots = new List<AR_PTFData.LotRow>();
    if (schedule == null || schedule.isEmpty() || startDate == null) {
      return lots;
    }
    Map<Integer, Decimal> overrideByIndex = new Map<Integer, Decimal>();
    if (overrides != null) {
      for (LotOverride o : overrides) {
        if (o != null && o.index != null && o.montant != null) {
          overrideByIndex.put(o.index, o.montant);
        }
      }
    }

    Date firstOfMonth = Date.newInstance(startDate.year(), startDate.month(), 1);
    Decimal cumul = 0;
    for (Integer i = 0; i < schedule.size(); i++) {
      AR_PTFData.ScheduleRow row = schedule[i];
      Date lotMonth = firstOfMonth.addMonths(i);

      AR_PTFData.LotRow lot = new AR_PTFData.LotRow();
      lot.libelle = 'Lot ' + (i + 1);
      lot.mois = row.mois;
      lot.jours = row.jours;
      lot.montantCalcule = row.montant;
      lot.isOverridden = overrideByIndex.containsKey(i);
      lot.montant = lot.isOverridden ? overrideByIndex.get(i) : row.montant;
      // Fin du mois du lot (C45) : Date.daysInMonth gère les mois courts et les années bissextiles.
      lot.echeance = Date.newInstance(
        lotMonth.year(),
        lotMonth.month(),
        Date.daysInMonth(lotMonth.year(), lotMonth.month())
      );
      cumul += lot.montant;
      lot.cumul = cumul;
      lots.add(lot);
    }
    return lots;
  }

  private static Decimal sumLots(List<AR_PTFData.LotRow> lots) {
    Decimal total = 0;
    for (AR_PTFData.LotRow lot : lots) {
      total += lot.montant;
    }
    return total;
  }

  /**
   * C8/C9 de l'avenant : référence et date de la PTF initiale citée. Un identifiant fourni mais
   * introuvable BLOQUE — un avenant qui cite une PTF inexistante est un document faux, pas un
   * document incomplet.
   */
  private static void applyPtfInitiale(AR_PTFData d, Id ptfInitialeDocumentId) {
    if (ptfInitialeDocumentId == null) {
      return;
    }
    List<AR_PTF_Document__c> parents = [
      SELECT AR_Reference__c, AR_Generated_At__c
      FROM AR_PTF_Document__c
      WHERE Id = :ptfInitialeDocumentId
      LIMIT 1
    ];
    if (parents.isEmpty()) {
      throw newAuraException(
        AR_I18n.format(Label.AR_Msg_PTF_InitialPtfNotFound, new List<Object>{ ptfInitialeDocumentId })
      );
    }
    d.ptfInitialeReference = parents[0].AR_Reference__c;
    d.ptfInitialeDate = parents[0].AR_Generated_At__c == null
      ? null
      : parents[0].AR_Generated_At__c.date();
    // Session 49 (cause B) : même garde qu'en collectAvenant — un document parent trouvé mais dont
    // la référence/date sont elles-mêmes vides ne doit pas non plus laisser passer un avenant
    // juridiquement vide.
    if (String.isBlank(d.ptfInitialeReference) || d.ptfInitialeDate == null) {
      throw newAuraException(
        Label.AR_Msg_PTF_OriginRefMissing
      );
    }
  }

  /**
   * Historique figé d'une PTF (session 138) : les versions cochées du périmètre (via
   * AR_PTFHistoryService, dans l'ordre des rangs) puis la ligne en cours. Le PDF fige l'état des
   * cases au moment de SA génération ; décocher plus tard ne réécrit aucun PDF existant. Colonnes :
   * Version = 'V' + rang ; Date d'émission ; Modification = libellé central de AR_PTFHistoryService
   * (rang 1 vide, « Autre » → texte seul) ; Responsable = CreatedBy du document (utilisateur qui
   * génère, pour la ligne en cours). Plus aucun calcul Création/Régénération/Révision budgétaire.
   */
  private static List<AR_PTFData.HistoryRow> buildHistoriquePtf(
    List<AR_PTF_Document__c> priorDocs,
    AR_PTFData current,
    GenerationInput input
  ) {
    List<AR_PTFData.HistoryRow> rows = new List<AR_PTFData.HistoryRow>();
    Integer rank = 1;
    for (AR_PTF_Document__c doc : priorDocs) {
      AR_PTFData.HistoryRow row = new AR_PTFData.HistoryRow();
      row.version = 'V' + rank;
      row.reference = doc.AR_Reference__c;
      row.generatedAt = doc.AR_Generated_At__c;
      row.objetModification = AR_PTFHistoryService.getModificationLabel(doc, rank);
      row.responsable = doc.CreatedBy?.Name;
      rows.add(row);
      rank++;
    }

    AR_PTFData.HistoryRow currentRow = new AR_PTFData.HistoryRow();
    currentRow.version = current.version;
    currentRow.reference = current.reference;
    currentRow.generatedAt = current.generatedAt;
    currentRow.objetModification = AR_PTFHistoryService.getModificationLabel(
      new AR_PTF_Document__c(
        AR_Modification_Type__c = input?.modificationType,
        AR_Modification_Detail__c = input?.modificationDetail
      ),
      rank
    );
    currentRow.redacteurNom = current.redacteurNom;
    currentRow.valideurNom = current.valideurNom;
    currentRow.responsable = UserInfo.getName();
    rows.add(currentRow);
    return rows;
  }

  /**
   * NE SERT PLUS QU'À L'AVENANT (session 138) : la PTF passe par buildHistoriquePtf. L'avenant garde
   * volontairement son comportement d'avant (« Avenant », lignes sur le compteur technique), décision
   * de la session 138 — « avenants : aucun changement ».
   *
   * Historique multi-versions figé au moment de la génération (option (b), décision documentée
   * dans docs/30-ptf-previsualisation-et-gabarits.md §4) : chaque génération relit les documents
   * déjà générés pour cette matrice (redacteur/valideur extraits de LEUR PROPRE snapshot, jamais de
   * l'état courant) et ajoute la ligne en cours de génération (pas encore en base à cet instant).
   * Un document déjà généré ne requête donc plus jamais la base pour son historique : il reste
   * fidèle à ce qui existait au moment de SA génération, cohérent avec « la donnée fait foi ».
   */
  /**
   * C4/C6 (session 36, gabarit Abylsen uniquement, cf. TEMPLATES_USING_BESOIN_HISTORY_SCOPE) :
   * périmètre élargi au BESOIN (plusieurs matrices peuvent le partager) au lieu de la seule matrice,
   * et libellé « Révision budgétaire » pour la ligne en cours quand la matrice courante descend
   * elle-même d'une version antérieure (`AR_Previous_Version__c`, duplication de matrice). Le
   * gabarit générique garde exactement son comportement d'avant cette session (périmètre matrice,
   * libellés Création/Régénération) — c'est le paramètre `templateCode` qui fait la différence, pas
   * une nouvelle méthode dupliquée.
   */
  /**
   * `currentVersionNumber` reste un Integer (décision Création/Régénération, non pertinente pour un
   * avenant → null) tandis que `currentVersionLabel` porte le libellé déjà formaté à afficher
   * ('V1'/'AV1') : ce sont deux informations différentes depuis la session 37, qu'il ne faut pas
   * recomposer l'une depuis l'autre. `modificationLabelOverride` (non null pour un avenant, ex.
   * « Avenant ») prime sur le calcul Création/Régénération/Révision budgétaire — jamais les deux à
   * la fois. Filtre AR_Document_Type__c != 'Avenant' sur les DEUX requêtes (ajouté session 37) :
   * un avenant n'apparaît JAMAIS dans l'historique d'une PTF ni dans celui d'un autre avenant —
   * seule la lignée des PTF elles-mêmes y figure (cf. docs/37-avenant.md, décision documentée).
   */
  private static List<AR_PTFData.HistoryRow> buildHistorique(
    Id matrixId,
    Id positionId,
    String templateCode,
    Integer currentVersionNumber,
    String currentVersionLabel,
    String currentReference,
    Datetime currentGeneratedAt,
    String currentRedacteurNom,
    String currentValideurNom,
    Boolean matrixHasPreviousVersion,
    String modificationLabelOverride
  ) {
    Boolean besoinScope = TEMPLATES_USING_BESOIN_HISTORY_SCOPE.contains(templateCode) && positionId != null;
    List<AR_PTFData.HistoryRow> rows = new List<AR_PTFData.HistoryRow>();
    List<AR_PTF_Document__c> docs = besoinScope
      ? [
          SELECT AR_Version_Number__c, AR_Reference__c, AR_Generated_At__c, AR_Snapshot__c
          FROM AR_PTF_Document__c
          WHERE AR_Position__c = :positionId AND AR_Document_Type__c != 'Avenant'
          ORDER BY AR_Generated_At__c ASC
        ]
      : [
          SELECT AR_Version_Number__c, AR_Reference__c, AR_Generated_At__c, AR_Snapshot__c
          FROM AR_PTF_Document__c
          WHERE AR_Price_Matrix__c = :matrixId AND AR_Document_Type__c != 'Avenant'
          ORDER BY AR_Version_Number__c ASC
        ];
    for (AR_PTF_Document__c doc : docs) {
      rows.add(toHistoryRow(doc));
    }

    AR_PTFData.HistoryRow current = new AR_PTFData.HistoryRow();
    current.version = currentVersionLabel;
    current.reference = currentReference;
    current.generatedAt = currentGeneratedAt;
    current.objetModification = String.isNotBlank(modificationLabelOverride)
      ? modificationLabelOverride
      : ((besoinScope && matrixHasPreviousVersion == true)
          ? 'Révision budgétaire'
          : (currentVersionNumber == 1 ? 'Création' : 'Régénération'));
    current.redacteurNom = currentRedacteurNom;
    current.valideurNom = currentValideurNom;
    rows.add(current);
    return rows;
  }

  private static AR_PTFData.HistoryRow toHistoryRow(AR_PTF_Document__c doc) {
    AR_PTFData.HistoryRow row = new AR_PTFData.HistoryRow();
    row.version = 'V' + Integer.valueOf(doc.AR_Version_Number__c);
    row.reference = doc.AR_Reference__c;
    row.generatedAt = doc.AR_Generated_At__c;
    // Repli par défaut, recalculé par numéro de version — comportement identique à avant la session
    // 36 pour tout document dont le snapshot ne porte pas sa propre ligne d'historique figée.
    row.objetModification = doc.AR_Version_Number__c == 1 ? 'Création' : 'Régénération';
    if (String.isNotBlank(doc.AR_Snapshot__c)) {
      try {
        AR_PTFData previous = (AR_PTFData) JSON.deserialize(doc.AR_Snapshot__c, AR_PTFData.class);
        row.redacteurNom = previous.redacteurNom;
        row.valideurNom = previous.valideurNom;
        // Session 36 : le libellé figé sur CE document (dernière ligne de son propre historique, la
        // ligne qui était "current" au moment de SA génération) prime sur le recalcul par numéro de
        // version — c'est la seule façon de reproduire fidèlement « Révision budgétaire » (C6) pour
        // une ligne ancienne. Sans effet sur un document généré par le gabarit générique : sa propre
        // ligne "current" a été calculée avec la même règle Création/Régénération que le repli
        // ci-dessus, donc identique au caractère près (non-régression).
        if (previous.historique != null && !previous.historique.isEmpty()) {
          AR_PTFData.HistoryRow ownRow = previous.historique[previous.historique.size() - 1];
          if (String.isNotBlank(ownRow.objetModification)) {
            row.objetModification = ownRow.objetModification;
          }
        }
      } catch (Exception e) {
        // Snapshot antérieur corrompu : ligne d'historique dégradée (rédacteur/valideur vides),
        // jamais bloquante pour la génération en cours.
      }
    }
    return row;
  }

  // Session 274 : jours ouvrés = calendrier unique AR_WorkingCalendar (week-ends + fériés France selon le pays).
  private static Integer calcBusinessDaysBetween(Date startDate, Date endDate, String country) {
    return AR_WorkingCalendar.workingDays(startDate, endDate, country);
  }

  /**
   * Port Apex de computePTFSchedule (pricing-tool.html:2808) : un cumul mensuel entre dateDebut et
   * dateFin, du premier jour du mois de dateDebut jusqu'à dateFin inclus. Liste vide si les dates ne
   * sont pas renseignées ou incohérentes — le gabarit affiche alors "à définir conjointement", pas
   * une erreur (comportement fidèle à la maquette, cf. AR_PTFTemplate.page).
   *
   * Session 122 : jours de chaque mois calculés comme jours ouvrés réels du mois compris dans
   * [startDate, endDate]. Si totalDays est saisi à la main et diffère du total calculé, répartir
   * proportionnellement avec l'arrondi sur le dernier lot : Σ jours des lots = totalDays exactement.
   */
  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    Decimal totalDays
  ) {
    return buildSchedule(startDate, endDate, tjm, joursParMois, nbConsultants, totalDays, false);
  }

  /**
   * mensualisationLissee = true bascule sur la facturation lissée (cf. buildLisseSchedule) ;
   * false (ou null) garde l'échéancier au jour ouvré réel, strictement inchangé.
   */
  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    Decimal totalDays,
    Boolean mensualisationLissee
  ) {
    return buildSchedule(startDate, endDate, tjm, joursParMois, nbConsultants, totalDays, mensualisationLissee, null);
  }

  /**
   * TJM par périodes (docs/254d) : `periodes` = périodes 1..N avec leur date de début (saisie ou estimée).
   * Les jours ouvrés avant la date de début d'une période valent le TJM précédent, ceux à partir de cette
   * date le TJM de la période ; un mois à cheval donne un montant mixte sur une seule ligne. Le total HT
   * reste la somme des lignes. null ou une seule période : code historique, strictement inchangé.
   * Remplit aussi jours et montant de chaque période (répartition des lignes, pour le tableau Abylsen).
   */
  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    Decimal totalDays,
    Boolean mensualisationLissee,
    List<AR_PTFData.TjmPeriodRow> periodes
  ) {
    return buildSchedule(startDate, endDate, tjm, joursParMois, nbConsultants, totalDays, mensualisationLissee, periodes, null);
  }

  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    Decimal totalDays,
    Boolean mensualisationLissee,
    List<AR_PTFData.TjmPeriodRow> periodes,
    Map<String, Decimal> vendusParMois
  ) {
    return buildSchedule(
      startDate, endDate, tjm, joursParMois, nbConsultants, totalDays, mensualisationLissee, periodes, vendusParMois, null
    );
  }

  /**
   * Régie sans régule (docs/265c) : `vendusParMois` = jours vendus du plan de production, clé yyyy-MM.
   * Lissé et mois présent dans le plan : jours = vendus du mois, montant = TJM du mois × vendus. Mois
   * absent du plan, ou pas de plan (null) : calcul lissé habituel, strictement inchangé.
   * Session 274 : `country` = pays de l'entité PTF de la matrice ; jours ouvrés hors week-ends et, pour la
   * France, hors jours fériés (AR_WorkingCalendar). null ou autre pays : week-ends seuls.
   */
  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    Decimal totalDays,
    Boolean mensualisationLissee,
    List<AR_PTFData.TjmPeriodRow> periodes,
    Map<String, Decimal> vendusParMois,
    String country
  ) {
    Boolean multi = periodes != null && periodes.size() >= 2;
    if (multi) {
      for (AR_PTFData.TjmPeriodRow p : periodes) {
        p.jours = 0;
        p.montant = 0;
      }
    }
    List<AR_PTFData.ScheduleRow> rows = new List<AR_PTFData.ScheduleRow>();
    if (
      startDate == null ||
      endDate == null ||
      tjm == null ||
      startDate > endDate
    ) {
      return rows;
    }
    if (mensualisationLissee == true) {
      return buildLisseSchedule(
        startDate, endDate, tjm, joursParMois, nbConsultants, multi ? periodes : null, vendusParMois, country
      );
    }

    // Build list of months chronologically
    List<Date> monthStarts = new List<Date>();
    Date cur = Date.newInstance(startDate.year(), startDate.month(), 1);
    while (cur <= endDate) {
      monthStarts.add(cur);
      cur = cur.addMonths(1);
    }

    // Calculate actual working days for each month
    List<Integer> workingDaysPerMonthList = new List<Integer>();
    Integer totalCalculatedDays = 0;
    for (Date monthStart : monthStarts) {
      Date monthEnd = monthStart.addMonths(1).addDays(-1);
      Date rangeStart = monthStart < startDate ? startDate : monthStart;
      Date rangeEnd = monthEnd > endDate ? endDate : monthEnd;
      Integer days = calcBusinessDaysBetween(rangeStart, rangeEnd, country);
      workingDaysPerMonthList.add(days);
      totalCalculatedDays += days;
    }

    // Use manual totalDays if provided, otherwise use calculated
    Integer daysToUse = (totalDays != null && totalDays > 0)
      ? Integer.valueOf(totalDays)
      : totalCalculatedDays;

    // If manual override differs from calculated, proportionally redistribute
    Decimal scaleFactor = (daysToUse != totalCalculatedDays && totalCalculatedDays > 0)
      ? Decimal.valueOf(daysToUse) / Decimal.valueOf(totalCalculatedDays)
      : 1;

    Integer nb = nbConsultants == null ? 1 : nbConsultants;
    Decimal cumul = 0;
    Decimal joursCounter = 0;
    Decimal totalJours = Decimal.valueOf(daysToUse);

    for (Integer i = 0; i < monthStarts.size(); i++) {
      Date monthDate = monthStarts[i];
      Integer workingDays = workingDaysPerMonthList[i];
      Decimal scaledDays = Decimal.valueOf(workingDays) * scaleFactor;
      Decimal jours = scaledDays * nb;

      // Session 126 : round to 0.5 day precision; last lot gets remainder
      if (i < monthStarts.size() - 1) {
        jours = (jours * 2).setScale(0, System.RoundingMode.HALF_UP) / 2;
      } else {
        // Last row: ensure exact sum
        jours = totalJours - joursCounter;
      }

      joursCounter += jours;
      Decimal montant = (tjm * jours).setScale(0, System.RoundingMode.HALF_UP);
      if (multi) {
        Date monthEnd = monthDate.addMonths(1).addDays(-1);
        List<Integer> parPeriode = businessDaysByPeriod(
          monthDate < startDate ? startDate : monthDate,
          monthEnd > endDate ? endDate : monthEnd,
          periodes,
          country
        );
        montant = montantMixte(parPeriode, periodes, jours, tjm);
        repartirLigne(parPeriode, periodes, jours, montant);
      }
      cumul += montant;

      AR_PTFData.ScheduleRow row = new AR_PTFData.ScheduleRow();
      row.mois = AR_PTFFormatUtil.MONTHS_FR[monthDate.month() - 1] + ' ' + monthDate.year();
      row.jours = jours;
      row.montant = montant;
      row.cumul = cumul;
      rows.add(row);
    }

    if (multi) {
      ajusterMontantsPeriodes(periodes, rows);
    }
    return rows;
  }

  // ---- TJM par périodes (docs/254d) -------------------------------------------------------------

  private static Boolean isBusinessDay(Date d, String country) {
    return AR_WorkingCalendar.isWorkingDay(d, country);
  }

  /**
   * Date approximative de début d'une période : le (cumul + 1)ᵉ jour ouvré à partir du début de mission
   * (calendrier ouvré unique AR_WorkingCalendar, même que l'échéancier : jamais un week-end ni un férié du
   * pays ; les congés ne sont pas connus, d'où « à corriger si besoin » dans le formulaire).
   */
  @TestVisible
  private static Date estimatedPeriodStart(Date missionStart, Decimal cumulDays, String country) {
    if (missionStart == null || cumulDays == null) {
      return null;
    }
    Integer wanted = Integer.valueOf(cumulDays);
    Integer seen = 0;
    Date cur = missionStart;
    // Garde-fou : une mission ne dépasse pas quelques milliers de jours ouvrés.
    for (Integer guard = 0; guard < 20000; guard++) {
      if (isBusinessDay(cur, country)) {
        if (seen == wanted) {
          return cur;
        }
        seen++;
      }
      cur = cur.addDays(1);
    }
    return cur;
  }

  private static Date parseIsoDate(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return Date.valueOf(raw.trim());
    } catch (Exception e) {
      // Date illisible : traitée comme absente (obligatoire à la génération, message nommé).
      return null;
    }
  }

  /**
   * Périodes de TJM du PTF avec leur date de début. null sans évolution de TJM. strict = génération /
   * aperçu : chaque date de période 2+ est obligatoire, strictement croissante et comprise dans la mission
   * (message nommé sinon). Non strict = pré-remplissage du formulaire : date saisie si lisible, sinon estimée.
   */
  @TestVisible
  /**
   * Total de l'échéancier : jours facturables (jours de mission − congés prévus), répartis au prorata des
   * jours ouvrés de chaque mois par buildSchedule ; null (jours ouvrés calculés) si la durée est inconnue.
   */
  private static Decimal leaveDaysOf(AR_Price_Matrix__c m) {
    Decimal mission = m.AR_Number_Of_Days__c == null ? 0 : m.AR_Number_Of_Days__c;
    return mission > 0 ? mission - AR_PricingMatrixService.billableDaysOf(m) : 0;
  }

  private static Decimal scheduleTotalDays(AR_Price_Matrix__c m) {
    Decimal billable = AR_PricingMatrixService.billableDaysOf(m);
    return billable > 0 ? billable : null;
  }

  private static List<AR_PTFData.TjmPeriodRow> buildTjmPeriodRows(
    AR_Price_Matrix__c m,
    List<String> starts,
    Boolean strict
  ) {
    List<AR_PricingResult.TjmPeriod> engine = AR_PricingMatrixService.tjmPeriodsOf(m);
    if (engine == null || engine.size() < 2) {
      return null;
    }
    List<AR_PTFData.TjmPeriodRow> rows = new List<AR_PTFData.TjmPeriodRow>();
    Decimal cumul = 0;
    Date previous = m.AR_Start_Date__c;
    for (Integer i = 0; i < engine.size(); i++) {
      AR_PTFData.TjmPeriodRow row = new AR_PTFData.TjmPeriodRow();
      row.index = i + 1;
      row.tjm = engine[i].tjm;
      row.jours = engine[i].days;
      if (i == 0) {
        row.dateDebut = m.AR_Start_Date__c;
      } else {
        Date entered = (starts != null && i - 1 < starts.size()) ? parseIsoDate(starts[i - 1]) : null;
        if (strict == true) {
          List<Object> args = new List<Object>{ i + 1 };
          if (entered == null) {
            throw newAuraException(AR_I18n.format(Label.AR_Msg_PTF_TjmPeriodDateMissing, args));
          }
          if (previous != null && entered <= previous) {
            throw newAuraException(AR_I18n.format(Label.AR_Msg_PTF_TjmPeriodDateOrder, args));
          }
          if (m.AR_End_Date__c != null && entered > m.AR_End_Date__c) {
            throw newAuraException(AR_I18n.format(Label.AR_Msg_PTF_TjmPeriodDateOutside, args));
          }
          row.dateDebut = entered;
        } else {
          row.dateDebut = entered != null ? entered : estimatedPeriodStart(m.AR_Start_Date__c, cumul, entityCountryOf(m.AR_Entity_Ref__c));
        }
      }
      cumul += engine[i].days == null ? 0 : engine[i].days;
      // Dates estimées : durée calendaire — les congés, retranchés de la période 1, n'avancent pas la date.
      if (i == 0) {
        cumul += leaveDaysOf(m);
      }
      previous = row.dateDebut;
      rows.add(row);
    }
    for (Integer i = 0; i < rows.size(); i++) {
      rows[i].dateFin = i < rows.size() - 1
        ? (rows[i + 1].dateDebut == null ? null : rows[i + 1].dateDebut.addDays(-1))
        : m.AR_End_Date__c;
    }
    return rows;
  }

  /** Jours ouvrés de [a, b] par période : un jour appartient à la dernière période dont la date de début est ≤ à lui. */
  private static List<Integer> businessDaysByPeriod(
    Date a,
    Date b,
    List<AR_PTFData.TjmPeriodRow> periodes,
    String country
  ) {
    List<Integer> counts = new List<Integer>();
    for (Integer i = 0; i < periodes.size(); i++) {
      counts.add(0);
    }
    Date cur = a;
    while (cur <= b) {
      if (isBusinessDay(cur, country)) {
        Integer idx = 0;
        for (Integer p = 1; p < periodes.size(); p++) {
          if (periodes[p].dateDebut != null && periodes[p].dateDebut <= cur) {
            idx = p;
          }
        }
        counts[idx] = counts[idx] + 1;
      }
      cur = cur.addDays(1);
    }
    return counts;
  }

  /** Montant d'une ligne mensuelle : jours × TJM moyen des périodes traversées, pondéré par les jours ouvrés. */
  private static Decimal montantMixte(
    List<Integer> parPeriode,
    List<AR_PTFData.TjmPeriodRow> periodes,
    Decimal jours,
    Decimal tjmRepli
  ) {
    Decimal somme = 0;
    Integer total = 0;
    for (Integer p = 0; p < periodes.size(); p++) {
      somme += parPeriode[p] * periodes[p].tjm;
      total += parPeriode[p];
    }
    Decimal tjmMois = total == 0 ? tjmRepli : somme / total;
    return (tjmMois * jours).setScale(0, System.RoundingMode.HALF_UP);
  }

  /** Cumule dans chaque période sa part des jours et du montant d'une ligne (au prorata jours × TJM). */
  private static void repartirLigne(
    List<Integer> parPeriode,
    List<AR_PTFData.TjmPeriodRow> periodes,
    Decimal jours,
    Decimal montant
  ) {
    Decimal totalJours = 0;
    Decimal totalPoids = 0;
    for (Integer p = 0; p < periodes.size(); p++) {
      totalJours += parPeriode[p];
      totalPoids += parPeriode[p] * periodes[p].tjm;
    }
    if (totalJours == 0) {
      return;
    }
    for (Integer p = 0; p < periodes.size(); p++) {
      periodes[p].jours += jours * parPeriode[p] / totalJours;
      periodes[p].montant += totalPoids == 0 ? 0 : montant * parPeriode[p] * periodes[p].tjm / totalPoids;
    }
  }

  /** Arrondit les montants par période et fait porter l'écart d'arrondi à la dernière : Σ périodes = Σ lignes. */
  private static void ajusterMontantsPeriodes(List<AR_PTFData.TjmPeriodRow> periodes, List<AR_PTFData.ScheduleRow> rows) {
    Decimal total = rows.isEmpty() ? 0 : rows[rows.size() - 1].cumul;
    Decimal somme = 0;
    for (Integer p = 0; p < periodes.size(); p++) {
      periodes[p].jours = periodes[p].jours.setScale(2, System.RoundingMode.HALF_UP);
      periodes[p].montant = periodes[p].montant.setScale(0, System.RoundingMode.HALF_UP);
      if (p < periodes.size() - 1) {
        somme += periodes[p].montant;
      }
    }
    periodes[periodes.size() - 1].montant = total - somme;
  }

  /**
   * Facturation mensuelle lissée (case « Facturation mensuelle lissée » du formulaire) :
   * chaque mois complet est facturé joursParMois × nb (TJM × jours annuels / 12, quel que soit le nombre
   * de jours ouvrés réel du mois). Premier et dernier mois incomplets : montant mensuel au prorata des
   * jours ouvrés couverts par la mission dans le mois. Le total est la somme des lignes.
   * Un mois est « complet » quand la mission couvre tous ses jours ouvrés.
   */
  private static List<AR_PTFData.ScheduleRow> buildLisseSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants,
    List<AR_PTFData.TjmPeriodRow> periodes,
    Map<String, Decimal> vendusParMois,
    String country
  ) {
    List<AR_PTFData.ScheduleRow> rows = new List<AR_PTFData.ScheduleRow>();
    if (joursParMois == null) {
      return rows;
    }
    Integer nb = nbConsultants == null ? 1 : nbConsultants;
    Decimal joursMois = joursParMois * nb;
    Decimal cumul = 0;
    Date cur = Date.newInstance(startDate.year(), startDate.month(), 1);
    while (cur <= endDate) {
      Date monthEnd = cur.addMonths(1).addDays(-1);
      Integer joursOuvresMois = calcBusinessDaysBetween(cur, monthEnd, country);
      Date rangeStart = cur < startDate ? startDate : cur;
      Date rangeEnd = monthEnd > endDate ? endDate : monthEnd;
      Integer joursCouverts = calcBusinessDaysBetween(rangeStart, rangeEnd, country);
      Boolean complet = joursCouverts == joursOuvresMois;
      Decimal ratio = Decimal.valueOf(joursCouverts) / joursOuvresMois;

      // Plusieurs TJM : le TJM du mois est la moyenne, pondérée par les jours ouvrés couverts, des TJM des
      // périodes qu'il traverse (un mois entièrement dans une période garde exactement son TJM).
      Decimal tjmMoisCourant = tjm;
      List<Integer> parPeriode = null;
      if (periodes != null && joursCouverts > 0) {
        parPeriode = businessDaysByPeriod(rangeStart, rangeEnd, periodes, country);
        Decimal somme = 0;
        for (Integer p = 0; p < periodes.size(); p++) {
          somme += parPeriode[p] * periodes[p].tjm;
        }
        tjmMoisCourant = somme / joursCouverts;
      }
      Decimal montantMoisCourant = (tjmMoisCourant * joursMois).setScale(0, System.RoundingMode.HALF_UP);

      // Régie sans régule : jours vendus du plan pour ce mois (déjà au prorata), donc pas de ratio.
      String cle = cur.year() + '-' + String.valueOf(cur.month()).leftPad(2, '0');
      Boolean planifie = vendusParMois != null && vendusParMois.containsKey(cle);

      AR_PTFData.ScheduleRow row = new AR_PTFData.ScheduleRow();
      row.mois = AR_PTFFormatUtil.MONTHS_FR[cur.month() - 1] + ' ' + cur.year();
      if (planifie) {
        row.jours = vendusParMois.get(cle);
        row.montant = (tjmMoisCourant * row.jours).setScale(0, System.RoundingMode.HALF_UP);
      } else {
        row.jours = complet ? joursMois : (joursMois * ratio).setScale(2, System.RoundingMode.HALF_UP);
        row.montant = complet
          ? montantMoisCourant
          : (montantMoisCourant * ratio).setScale(0, System.RoundingMode.HALF_UP);
      }
      cumul += row.montant;
      row.cumul = cumul;
      rows.add(row);
      if (parPeriode != null) {
        repartirLigne(parPeriode, periodes, row.jours, row.montant);
      }
      cur = cur.addMonths(1);
    }
    if (periodes != null) {
      ajusterMontantsPeriodes(periodes, rows);
    }
    return rows;
  }

  /**
   * Jours vendus par mois (clé yyyy-MM) du plan de production de la régie sans régule. Vide si la matrice
   * n'est pas en mode actif. Le plan est écrit par le serveur (AR_PricingMatrixService) : un JSON illisible
   * lève l'erreur de lecture du plan, jamais un plan vide silencieux.
   */
  private static Map<String, Decimal> vendusParMoisDuPlan(AR_Price_Matrix__c m) {
    Map<String, Decimal> vendus = new Map<String, Decimal>();
    if (m.AR_RPLSR_Enabled__c != true) {
      return vendus;
    }
    for (AR_WorkingCalendar.PlanMonth pm : AR_PricingMatrixService.parseRplsrPlan(m.AR_RPLSR_Plan__c)) {
      vendus.put(pm.m, pm.vendus);
    }
    return vendus;
  }

  /**
   * Jours facturés par mois complet en mode lissé : jours travaillés annuels / 12, arrondi
   * à 2 décimales (18,17 j pour 218). Annuels = ceux de la matrice (figés à la validation), à défaut
   * l'exception jours travaillés de l'entité. Hors mode lissé, ou sans aucune valeur propre : le
   * paramètre général déjà calculé par l'appelant (joursParMoisDefault), inchangé.
   */
  private static Decimal joursParMoisPourEcheancier(
    Decimal joursAnnuelsMatrice,
    AR_PTF_Entity_Referential__c entityRef,
    Boolean lissee,
    Decimal joursParMoisDefault
  ) {
    if (lissee != true) {
      return joursParMoisDefault;
    }
    Decimal joursAnnuels = joursAnnuelsMatrice;
    if (joursAnnuels == null && entityRef != null) {
      joursAnnuels = entityRef.AR_Working_Days__c;
    }
    if (joursAnnuels == null) {
      return joursParMoisDefault;
    }
    return (joursAnnuels / 12).setScale(2, System.RoundingMode.HALF_UP);
  }

  // Backward compatibility: buildSchedule without totalDays parameter
  public static List<AR_PTFData.ScheduleRow> buildSchedule(
    Date startDate,
    Date endDate,
    Decimal tjm,
    Decimal joursParMois,
    Integer nbConsultants
  ) {
    return buildSchedule(startDate, endDate, tjm, joursParMois, nbConsultants, null);
  }

  private static Decimal sumMontants(List<AR_PTFData.ScheduleRow> schedule) {
    Decimal total = 0;
    for (AR_PTFData.ScheduleRow row : schedule) {
      total += row.montant;
    }
    return total;
  }

  // Session 23 : AR_Settings__mdt migré vers AR_General_Setting__c (objet custom).
  private static Decimal defaultJoursParMois() {
    List<AR_General_Setting__c> rows = [
      SELECT AR_Working_Days_Per_Year__c FROM AR_General_Setting__c LIMIT 1
    ];
    Decimal workingDaysPerYear = (!rows.isEmpty() &&
      rows[0].AR_Working_Days_Per_Year__c != null)
      ? rows[0].AR_Working_Days_Per_Year__c
      : AR_PricingCalculator.JOURS_TRAVAIL_DEFAULT;
    return (workingDaysPerYear / 12).setScale(2, System.RoundingMode.HALF_UP);
  }

  /**
   * Session 279 : adresse client imprimée = saisie du formulaire si non vide (espaces de début/fin et
   * fins de ligne Windows ignorés), sinon adresse du compte. `adresseClientModifiee` n'est vrai que si
   * la saisie diffère de l'adresse du compte. Avertissement « adresse manquante » si rien à imprimer.
   */
  @TestVisible
  private static void applyClientAddress(AR_PTFData d, Account acc, String saisie) {
    String compte = buildAddress(acc);
    d.adresseClientCompte = compte;
    String saisieNormalisee = normalizeAddress(saisie);
    if (String.isNotBlank(saisieNormalisee)) {
      d.adresseClient = saisieNormalisee;
      d.adresseClientModifiee = !saisieNormalisee.equals(normalizeAddress(compte));
    } else {
      d.adresseClient = compte;
      d.adresseClientModifiee = false;
    }
    if (String.isBlank(d.adresseClient)) {
      d.warnings.add(Label.AR_Msg_PTF_ClientAddressMissing);
    }
  }

  private static String normalizeAddress(String raw) {
    return raw == null ? '' : raw.replace('\r\n', '\n').replace('\r', '\n').trim();
  }

  /** Session 279 : adresse du compte client d'une matrice (même résolution que collect). */
  private static String accountAddressForMatrix(Id matrixId) {
    AR_Price_Matrix__c m = [
      SELECT AR_Position__r.cxsrec__Account__c, AR_Position__r.AB_Need_details__r.AB_Account__c
      FROM AR_Price_Matrix__c
      WHERE Id = :matrixId
      LIMIT 1
    ];
    Id accountId = (m.AR_Position__r != null && m.AR_Position__r.AB_Need_details__r != null &&
                    m.AR_Position__r.AB_Need_details__r.AB_Account__c != null)
      ? m.AR_Position__r.AB_Need_details__r.AB_Account__c
      : (m.AR_Position__r == null ? null : m.AR_Position__r.cxsrec__Account__c);
    if (accountId == null) {
      return null;
    }
    for (Account acc : [
      SELECT BillingStreet, BillingPostalCode, BillingCity, ShippingStreet, ShippingPostalCode, ShippingCity
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ]) {
      return buildAddress(acc);
    }
    return null;
  }

  private static String buildAddress(Account acc) {
    if (acc == null) {
      return null;
    }
    // Session 142 : hypothesis 3a — use Shipping address if Billing is empty (fallback as a block,
    // never mix street from one and city from the other)
    String street = acc.BillingStreet;
    String postalCode = acc.BillingPostalCode;
    String city = acc.BillingCity;

    if (String.isBlank(street) && String.isNotBlank(acc.ShippingStreet)) {
      street = acc.ShippingStreet;
      postalCode = acc.ShippingPostalCode;
      city = acc.ShippingCity;
    }

    List<String> lines = new List<String>();
    if (String.isNotBlank(street)) {
      lines.add(street);
    }
    String cityLine = String.join(
      new List<String>{ postalCode, city },
      ' '
    ).trim();
    if (String.isNotBlank(cityLine)) {
      lines.add(cityLine);
    }
    return lines.isEmpty() ? null : String.join(lines, '\n');
  }

  /** Session 132 : lecture par Id de la fiche (lookup AR_Price_Matrix__c.AR_Entity_Ref__c), plus par
   * nom — deux fiches ne différant que par la casse (« Abylsen GAMMA » / « ABYLSEN GAMMA ») se
   * confondaient dans un WHERE Name = :nom (SOQL insensible à la casse). */
  /** Pays de l'entité PTF (même source que la régie par lot) ; null sans entité : week-ends seuls. */
  private static String entityCountryOf(Id entityId) {
    AR_PTF_Entity_Referential__c ref = loadEntityReferential(entityId);
    return ref == null ? null : ref.AR_Country__c;
  }

  private static AR_PTF_Entity_Referential__c loadEntityReferential(Id entityId) {
    if (entityId == null) {
      return null;
    }
    // Piège déjà payé en session 30 : un champ absent de ce SELECT lève « SObject row was retrieved
    // via SOQL without querying the requested field » à l'exécution seulement — le déploiement, lui,
    // réussit. Tout champ lu ailleurs sur cette variable doit figurer ici.
    // Pas de filtre sur AR_Active__c : la désactivation d'une entité (session 46) empêche seulement
    // sa sélection à la création d'une nouvelle matrice, elle ne bloque pas la génération PTF des
    // matrices existantes qui la référencent déjà.
    List<AR_PTF_Entity_Referential__c> refs = [
      SELECT Name, AR_Address__c, AR_Postal_Code__c, AR_City__c, AR_Siret__c, AR_Phone__c, AR_Template_Code__c,
             AR_Bank_Name__c, AR_Rib__c, AR_Iban__c, AR_Bic__c, AR_Fax__c, AR_Website__c, AR_Commercial_Email__c,
             AR_Tribunal_Competent__c, AR_Working_Days__c, AR_Country__c
      FROM AR_PTF_Entity_Referential__c
      WHERE Id = :entityId
      LIMIT 1
    ];
    return refs.isEmpty() ? null : refs[0];
  }

  /**
   * Session 176b : retire du bloc adresse les fragments que la ligne « SIRET : » reimprime déjà.
   * Un fragment est un segment entre « – » ; il est retiré UNIQUEMENT s'il vaut exactement
   * « SIREN <9 premiers chiffres du SIRET> », « NIC <5 derniers> » ou « SIRET <le SIRET> » : un SIREN
   * différent, une P.IVA, une TVA, un REA ou un nom légal ne sont jamais touchés. Sans SIRET valide
   * (14 chiffres) sur la fiche, le bloc est rendu tel quel : aucune information ne disparaît sans
   * être reimprimée ailleurs. Une ligne vidée de tous ses segments est supprimée.
   */
  @TestVisible
  private static String dedupeSirenNic(String adresse, String siret) {
    if (String.isBlank(adresse) || String.isBlank(siret)) {
      return adresse;
    }
    String digits = siret.deleteWhitespace();
    if (!Pattern.matches('\\d{14}', digits)) {
      return adresse;
    }
    Set<String> duplicates = new Set<String>{
      'SIREN ' + digits.substring(0, 9),
      'NIC ' + digits.substring(9),
      'SIRET ' + digits
    };
    List<String> keptLines = new List<String>();
    for (String line : adresse.split('\n')) {
      List<String> keptSegments = new List<String>();
      for (String segment : line.split(' – ')) {
        if (!duplicates.contains(segment.trim())) {
          keptSegments.add(segment);
        }
      }
      if (!keptSegments.isEmpty()) {
        keptLines.add(String.join(keptSegments, ' – '));
      }
    }
    return String.join(keptLines, '\n');
  }

  private static AR_PTFData.EntiteInfo toEntiteInfo(AR_PTF_Entity_Referential__c ref, String templateCode) {
    AR_PTFData.EntiteInfo info = new AR_PTFData.EntiteInfo();
    if (ref != null) {
      // Session 176b : le bloc adresse reste tel que saisi en base (docs/63) ; le doublon avec la
      // ligne « SIRET : » n'est retiré qu'au rendu, et seulement par les gabarits qui l'impriment.
      info.adresse = TEMPLATES_PRINTING_SIRET.contains(templateCode)
        ? dedupeSirenNic(ref.AR_Address__c, ref.AR_Siret__c)
        : ref.AR_Address__c;
      info.cp = ref.AR_Postal_Code__c;
      info.ville = ref.AR_City__c;
      info.siret = ref.AR_Siret__c;
      info.tel = ref.AR_Phone__c;
      // Coordonnées bancaires (C48) : recopiées telles quelles, jamais complétées ni inventées.
      // Un gabarit qui les imprime a déjà bloqué en amont si elles manquent (requireBankDetails).
      info.banque = ref.AR_Bank_Name__c;
      info.rib = ref.AR_Rib__c;
      info.iban = ref.AR_Iban__c;
      info.bic = ref.AR_Bic__c;
      // Session 38 (gabarit ABMI DQ012) : champs que les entités Abylsen ne portent pas.
      info.fax = ref.AR_Fax__c;
      info.website = ref.AR_Website__c;
      info.commercialEmail = ref.AR_Commercial_Email__c;
    }
    return info;
  }

  private static String currentUserTitle() {
    List<User> users = [
      SELECT Title
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].Title;
  }

  /**
   * BM de l'affaire (C0/C7/C29) : Owner de la matrice — même source que la colonne « BM » de « Mes
   * matrices » (AR_MatrixListService). Requête séparée par Id plutôt que `m.Owner.Name` en
   * sous-sélection : cette relation polymorphe standard retourne null en contexte @IsTest sur cet
   * objet alors qu'OwnerId est correctement peuplé (même piège déjà documenté et contourné dans
   * AR_MatrixListService). OwnerId pointe toujours un User dans ce périmètre (jamais une Queue).
   */
  private static User loadUser(Id userId) {
    if (userId == null) {
      return null;
    }
    List<User> users = [
      SELECT Name, Title,
             TP_RA__c, TP_RA__r.Name, TP_RA__r.Title, TP_RA__r.IsActive,
             TP_DA__c, TP_DA__r.Name, TP_DA__r.Title, TP_DA__r.IsActive,
             TP_Directeur__c, TP_Directeur__r.Name, TP_Directeur__r.Title, TP_Directeur__r.IsActive,
             TP_DD__c, TP_DD__r.Name, TP_DD__r.Title, TP_DD__r.IsActive
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  /**
   * C1/C97/C99 (session 47) : le nom du valideur est un champ obligatoire du formulaire PTF — la
   * condition bloquante s'évalue ici, sur le champ lui-même, plutôt qu'en amont sur une source
   * théorique (DA recalculé par cercle, retiré en session 40, puis par résolution stricte
   * effectif/sélectionné, qui bloquait à tort le cas sain — cf.
   * prompts/session-47-blocages-en-amont.md §1). Message adressé à qui le lit dans le formulaire,
   * pas à un développeur : pas de nom d'objet ni de champ technique.
   */
  /**
   * Point d'entrée vérifiable en Apex anonyme, cf. templateCodeError ci-dessus. Nomme le propriétaire
   * de la matrice quand il est connu ; sinon la phrase reste compréhensible sans lui.
   */
  public static String valideurError(String valideurNom, User owner) {
    if (String.isNotBlank(valideurNom)) {
      return null;
    }
    String sujet = owner != null && String.isNotBlank(owner.Name)
      ? AR_I18n.format(Label.AR_Msg_PTF_OwnerNamedSubject, new List<Object>{ owner.Name })
      : Label.AR_Msg_PTF_OwnerGenericSubject;
    return AR_I18n.format(Label.AR_Msg_PTF_NoValidatorOnOwner, new List<Object>{ sujet });
  }

  /**
   * Session 49 (cause B) : même doctrine que requireBankDetails — un tableau de prix vide n'est
   * jamais imprimé avec un texte de remplacement, la génération est refusée à la place. Ne
   * s'applique qu'aux gabarits de TEMPLATES_REQUIRING_SCHEDULE (cf. commentaire de tête).
   */
  private static void requireSchedule(String templateCode, List<AR_PTFData.ScheduleRow> schedule) {
    String error = scheduleError(templateCode, schedule);
    if (error != null) {
      throw newAuraException(error);
    }
  }

  /** Point d'entrée vérifiable en Apex anonyme, cf. templateCodeError ci-dessus. */
  public static String scheduleError(String templateCode, List<AR_PTFData.ScheduleRow> schedule) {
    if (!TEMPLATES_REQUIRING_SCHEDULE.contains(templateCode)) {
      return null;
    }
    if (schedule != null && !schedule.isEmpty()) {
      return null;
    }
    return AR_I18n.format(Label.AR_Msg_PTF_ScheduleMissing, new List<Object>{ TEMPLATE_LABELS.get(templateCode) });
  }

  /** Valideur proposable dans le formulaire PTF / avenant. */
  public class ValideurOption {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    // Rôles cumulés dans la chaîne du propriétaire (« RA, DA »).
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean isDefault;
  }

  private class ValideurChoice {
    String id;
    String nom;
    String fonction;
    // Vrai si l'id reçu faisait partie des valideurs proposables.
    Boolean fromInput = false;
  }

  private static final Integer VALIDEUR_FONCTION_MAX = 255;

  /**
   * Valideurs proposables : RA, DA, DD, Directeur du propriétaire de la matrice, puis valideurs actifs de
   * l'entité PTF de la matrice, une ligne par personne avec ses rôles cumulés. Pas de directeurs
   * commerciaux ni de valideurs de test. Défaut = valideurDe (inchangé).
   */
  private static List<ValideurOption> valideurOptions(User owner, Id entityId) {
    List<ValideurOption> options = new List<ValideurOption>();
    if (owner == null) {
      return options;
    }
    User defaultUser = valideurDe(owner);
    Map<Id, ValideurOption> byId = new Map<Id, ValideurOption>();
    List<AR_ValidatorChain.Level> levels = AR_ValidatorChain.documentLevels(owner);
    levels.addAll(AR_ValidatorChain.entityLevels(entityId));
    for (AR_ValidatorChain.Level l : levels) {
      User person = l.person;
      if (person == null || person.IsActive != true) {
        continue;
      }
      ValideurOption opt = byId.get(person.Id);
      if (opt == null) {
        opt = new ValideurOption();
        opt.id = person.Id;
        opt.name = person.Name;
        opt.title = person.Title;
        opt.role = l.role;
        opt.isDefault = defaultUser != null && defaultUser.Id == person.Id;
        byId.put(person.Id, opt);
        options.add(opt);
      } else {
        opt.role = opt.role + ', ' + l.role;
      }
    }
    for (ValideurOption opt : options) {
      opt.label = opt.name + ' — ' + opt.role;
    }
    return options;
  }

  /** Options du sélecteur de valideur, pour le propriétaire de la matrice. */
  @AuraEnabled(cacheable=false)
  public static List<ValideurOption> listValideurOptions(Id matrixId) {
    try {
      List<AR_Price_Matrix__c> matrices = [SELECT OwnerId, AR_Entity_Ref__c FROM AR_Price_Matrix__c WHERE Id = :matrixId LIMIT 1];
      return matrices.isEmpty()
        ? new List<ValideurOption>()
        : valideurOptions(loadUser(matrices[0].OwnerId), matrices[0].AR_Entity_Ref__c);
    } catch (Exception e) {
      throw AR_AuraErrors.wrap(e, Label.AR_Msg_PTF_ResolveDefaultsAction);
    }
  }

  /**
   * Valideur retenu : celui de `valideurId` s'il fait partie des options, avec la fonction saisie
   * (à défaut son Title) ; sinon valideurDe avec son Title — la fonction saisie pour une autre
   * personne n'est jamais reportée sur le défaut.
   */
  private static ValideurChoice resolveValideur(User owner, Id entityId, String valideurId, String fonction) {
    ValideurChoice c = new ValideurChoice();
    if (owner == null) {
      return c;
    }
    if (String.isNotBlank(valideurId)) {
      for (ValideurOption opt : valideurOptions(owner, entityId)) {
        if (opt.id == valideurId) {
          c.id = opt.id;
          c.nom = opt.name;
          c.fonction = String.isNotBlank(fonction) ? fonction.left(VALIDEUR_FONCTION_MAX) : opt.title;
          c.fromInput = true;
          return c;
        }
      }
    }
    User def = valideurDe(owner);
    if (def != null) {
      c.id = def.Id;
      c.nom = def.Name;
      c.fonction = def.Title;
    }
    return c;
  }

  /**
   * Valideur par défaut d'un PTF ou d'un avenant : premier renseigné parmi DA, Directeur, DD sur la fiche du
   * propriétaire de la matrice. Un utilisateur inactif compte comme vide. Lecture directe à chaque
   * appel, jamais depuis un snapshot. Nom et fonction viennent de la même personne retenue.
   * La chaîne des dérogations (AR_ValidatorChain) est une autre règle, non concernée.
   */
  private static User valideurDe(User owner) {
    if (owner == null) {
      return null;
    }
    for (User candidate : new List<User>{ owner.TP_DA__r, owner.TP_Directeur__r, owner.TP_DD__r }) {
      if (candidate != null && candidate.IsActive == true) {
        return candidate;
      }
    }
    return null;
  }

  /**
   * Session 107 : vérification des prérequis avant validation PTF — source unique de vérité,
   * réutilisant les mêmes fonctions que la génération (pas de second calcul qui pourrait diverger).
   * Retourne la liste des champs manquants, vide si tout est présent.
   *
   * Cette méthode vérifie l'état SAISI (reçu en paramètre), pas sauvegardé — pour refléter ce que
   * l'utilisateur voit à l'écran avant de cliquer Valider.
   */
  public static List<Prerequisite> validationPrerequisites(AR_Price_Matrix__c m) {
    List<Prerequisite> missing = new List<Prerequisite>();
    // BLOQUANT — données de la matrice (bloc « 1 Contexte affaire »). Contrôle sur la matrice
    // TELLE QUE CONSTRUITE par buildMatrixFromInput (dates éventuellement pré-remplies depuis le
    // besoin) — jamais sur un parseur parallèle (session 108).
    if (m.AR_Seniority__c == null || String.isBlank(m.AR_Seniority__c)) {
      missing.add(new Prerequisite(Label.AR_Msg_PTF_PrereqSeniority, Label.AR_Msg_PTF_PrereqSeniorityWhere));
    }
    if (m.AR_Client_Site__c == null || String.isBlank(m.AR_Client_Site__c)) {
      missing.add(new Prerequisite(Label.AR_Msg_PTF_PrereqClientSite, Label.AR_Msg_PTF_PrereqClientSiteWhere));
    }
    if (m.AR_Start_Date__c == null) {
      missing.add(new Prerequisite(Label.AR_Msg_PTF_PrereqStartDate, Label.AR_Msg_PTF_PrereqStartDateWhere));
    }
    if (m.AR_End_Date__c == null) {
      missing.add(new Prerequisite(Label.AR_Msg_PTF_PrereqEndDate, Label.AR_Msg_PTF_PrereqEndDateWhere));
    }
    if (m.AR_Start_Date__c != null && m.AR_End_Date__c != null && m.AR_Start_Date__c > m.AR_End_Date__c) {
      missing.add(
        new Prerequisite(
          Label.AR_Msg_PTF_PrereqEndBeforeStart,
          Label.AR_Msg_PTF_PrereqEndBeforeStartWhere
        )
      );
    }

    // Session 237 : l'entité House of ABY est obligatoire pour valider ou demander une dérogation
    // (le brouillon, lui, reste enregistrable). Bloquant, contrairement à l'avertissement entité ci-dessous.
    if (m.AR_Entity_Ref__c == null) {
      missing.add(new Prerequisite(Label.AR_Msg_PTF_PrereqEntity, Label.AR_Msg_PTF_PrereqEntityWhere));
    }

    // Interlocuteur client du besoin : ni bloquant ni signalé — il se complète à la main dans le
    // formulaire PTF (décision d'Alexis, 24/09/2026).

    // AVERTISSEMENT — données de l'entité : mêmes règles que le blocage réel à la génération
    // (missingFieldsForTemplate), sans rien bloquer ici. Session 182 : uniquement pour le gabarit
    // qui sera réellement résolu (compte > entité > générique) — les autres gabarits ne seront pas
    // utilisés et les signaler affichait en permanence un avertissement faux.
    if (m.AR_Entity_Ref__c != null) {
      AR_PTF_Entity_Referential__c entityRef = loadEntityReferential(m.AR_Entity_Ref__c);
      Id accountId = AR_AccountHierarchy.accountOfPosition(m.AR_Position__c);
      String code = expectedTemplateCode(accountId, entityRef);
      String issue = TEMPLATE_LABELS.containsKey(code) ? missingFieldsForTemplate(code, entityRef) : null;
      if (issue != null) {
        missing.add(
          new Prerequisite(
            AR_I18n.format(Label.AR_Msg_PTF_PrereqEntityIncomplete, new List<Object>{ (entityRef == null ? '' : entityRef.Name), TEMPLATE_LABELS.get(code), issue }),
            Label.AR_Msg_PTF_PrereqEntityIncompleteWhere,
            false
          )
        );
      }
    }

    return missing;
  }

  private static String cleanHtmlPreservingLinebreaks(String html) {
    if (String.isBlank(html)) {
      return null;
    }
    // Strip HTML tags but preserve semantic linebreaks (p, br, li within ul/ol)
    String text = html.stripHtmlTags();
    // Normalize whitespace: collapse multiple spaces/tabs but keep newlines
    text = text.replaceAll('[ \t]+', ' ').replaceAll('(?m)^ +| +$', '');
    return String.isNotBlank(text) ? text : null;
  }

  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}