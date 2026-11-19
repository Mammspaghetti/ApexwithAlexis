/**
 * Structure complète attendue par le gabarit PTF (pricing-tool.html:3035 buildPTFHTML), collectée
 * par AR_PTFDataService et sérialisée telle quelle dans AR_PTF_Document__c.AR_Snapshot__c. Classe
 * top-level (pas imbriquée) : une classe imbriquée en tant que type de propriété de contrôleur
 * Visualforce échoue à la résolution ("Propriété inconnue") sur AR_PTFTemplate — constaté en
 * déploiement, cf. AR_PTFTemplateController.
 *
 * ⚠️ Tous les champs sont des propriétés (`{ get; set; }`), jamais de simples champs publics.
 * Diagnostic du 11/08/2026 (sandbox `abylsengroup--full`) : dans cette org, le compilateur de pages
 * Visualforce échoue avec « Propriété 'X.champ' inconnue » sur TOUT champ public simple d'une classe
 * Apex utilisée comme type de propriété de contrôleur — y compris sans @AuraEnabled, y compris pour
 * une classe top-level triviale à un seul champ. Reproduit et isolé sur une classe minimale
 * (`public String entite;` échoue, `public String entite { get; set; }` réussit, seule différence).
 * Symétrique du piège documenté dans docs/19-payload-json.md (Aura n'alimente pas les champs publics
 * simples en ENTRÉE) : ici c'est Visualforce qui ne les lit pas en SORTIE. À revérifier si la
 * plateforme est corrigée.
 */
public class AR_PTFData {
  public class ScheduleRow {
    @AuraEnabled
    public String mois { get; set; }
    @AuraEnabled
    public Decimal jours { get; set; }
    @AuraEnabled
    public Decimal montant { get; set; }
    @AuraEnabled
    public Decimal cumul { get; set; }
  }

  // TJM par périodes (docs/254 §7.1) : ajout pur, nul sans évolution de TJM. `index` 1 = période 1
  // (dateDebut = début de mission). jours/montant = répartition de l'échéancier entre les périodes.
  public class TjmPeriodRow {
    @AuraEnabled
    public Integer index { get; set; }
    @AuraEnabled
    public Date dateDebut { get; set; }
    @AuraEnabled
    public Date dateFin { get; set; }
    @AuraEnabled
    public Decimal jours { get; set; }
    @AuraEnabled
    public Decimal tjm { get; set; }
    @AuraEnabled
    public Decimal montant { get; set; }
  }

  public class EntiteInfo {
    @AuraEnabled
    public String adresse { get; set; }
    @AuraEnabled
    public String cp { get; set; }
    @AuraEnabled
    public String ville { get; set; }
    @AuraEnabled
    public String siret { get; set; }
    @AuraEnabled
    public String tel { get; set; }
    // Coordonnées bancaires par entité (C48, article 4.5 de la PTF Abylsen — session 35). Jamais
    // de valeur d'amorce plausible : une PTF dont l'entité ne les porte pas ne se génère PAS pour
    // un gabarit qui les imprime (cf. AR_PTFDataService.requireBankDetails) — faire payer un
    // client au mauvais compte est pire que ne pas produire le document.
    @AuraEnabled
    public String banque { get; set; }
    @AuraEnabled
    public String rib { get; set; }
    @AuraEnabled
    public String iban { get; set; }
    @AuraEnabled
    public String bic { get; set; }
    // Session 38 (gabarit ABMI DQ012) : fax, site web, email commercial générique — champs que les
    // entités Abylsen ne portent pas. Référentiel étendu plutôt que dupliqué (CLAUDE.md §"Aucune
    // seconde source parallèle"). Informationnels, jamais requis par requireBankDetails.
    @AuraEnabled
    public String fax { get; set; }
    @AuraEnabled
    public String website { get; set; }
    @AuraEnabled
    public String commercialEmail { get; set; }
  }

  /**
   * Une ligne de l'échéancier vue comme un LOT (session 35) — le gabarit Abylsen raisonne en lots,
   * le modèle historique en mois. Par défaut 1 lot = 1 mois (C43), échéance = fin du mois du lot
   * (C45), montant = TJM × jours ouvrés du mois (C44).
   *
   * `montantCalcule` est TOUJOURS conservé à côté de `montant`, même quand aucune surcharge n'a été
   * saisie : c'est ce qui permet d'afficher l'écart au commercial ET de le retrouver à l'audit sur
   * un document déjà généré. Un écart silencieux entre le prix affiché et le prix imprimé est le
   * pire défaut possible sur cet outil.
   */
  public class LotRow {
    @AuraEnabled
    public String libelle { get; set; }
    @AuraEnabled
    public String mois { get; set; }
    @AuraEnabled
    public Decimal jours { get; set; }
    // Montant théorique : TJM × jours. Jamais écrasé par une surcharge.
    @AuraEnabled
    public Decimal montantCalcule { get; set; }
    // Montant retenu : la surcharge si elle existe, sinon montantCalcule.
    @AuraEnabled
    public Decimal montant { get; set; }
    @AuraEnabled
    public Decimal cumul { get; set; }
    @AuraEnabled
    public Date echeance { get; set; }
    @AuraEnabled
    public Boolean isOverridden { get; set; }
  }

  /**
   * Une ligne de l'historique des modifications (page de garde) — session 30. Figée dans le
   * snapshot au moment de la génération (option (b), cf. docs/30-ptf-previsualisation-et-gabarits.md
   * §4) : un document déjà généré ne doit jamais afficher de versions apparues après sa propre
   * génération, même si la matrice a depuis été régénérée plusieurs fois.
   */
  public class HistoryRow {
    @AuraEnabled
    public String version { get; set; }
    @AuraEnabled
    public String reference { get; set; }
    @AuraEnabled
    public Datetime generatedAt { get; set; }
    @AuraEnabled
    public String objetModification { get; set; }
    @AuraEnabled
    public String redacteurNom { get; set; }
    @AuraEnabled
    public String valideurNom { get; set; }
    // Session 138 : responsable de la modification (CreatedBy du document ; utilisateur qui génère
    // pour la ligne en cours). Ajout seul — les snapshots antérieurs n'ont pas cette clé (null).
    @AuraEnabled
    public String responsable { get; set; }
  }

  @AuraEnabled
  public String client { get; set; }
  @AuraEnabled
  public String adresseClient { get; set; }
  // Session 279 : adresse du compte (buildAddress) au moment de la génération, et indicateur posé
  // quand l'adresse imprimée (adresseClient) a été saisie à la main et en diffère. Ajout additif :
  // un snapshot antérieur ne porte ni l'un ni l'autre (null), relu sans perte.
  @AuraEnabled
  public String adresseClientCompte { get; set; }
  @AuraEnabled
  public Boolean adresseClientModifiee { get; set; }
  @AuraEnabled
  public String entite { get; set; }
  @AuraEnabled
  public EntiteInfo entiteInfo { get; set; }
  @AuraEnabled
  public String reference { get; set; }
  // Session 138 : rang d'affichage de CETTE PTF dans l'historique (1 = première version cochée du
  // périmètre) — différent du compteur technique AR_Version_Number__c. Figé à la génération.
  @AuraEnabled
  public Integer displayRank { get; set; }
  @AuraEnabled
  public String version { get; set; }
  @AuraEnabled
  public String missionType { get; set; }
  @AuraEnabled
  public String objet { get; set; }
  @AuraEnabled
  public String contexte { get; set; }
  @AuraEnabled
  public Date dateDebut { get; set; }
  @AuraEnabled
  public Date dateFin { get; set; }
  @AuraEnabled
  public String lieuPrestation { get; set; }
  // Devise de facturation (session 24b) : celle de la matrice source (AR_Price_Matrix__c.AR_Currency__c),
  // figée à la collecte comme le reste — une régénération lit la matrice à nouveau, mais sa devise est
  // elle-même immuable depuis la décision (verrou post-décision, session 24), donc reproduit d'office
  // la devise d'origine. EUR par défaut si absente (matrices antérieures à la session 24).
  @AuraEnabled
  public String currencyCode { get; set; }
  @AuraEnabled
  public Decimal tjm { get; set; }
  // TJM par périodes (docs/254) : `tjm` ci-dessus reste le TJM de la période 1. Nul sans évolution
  // de TJM (et dans tout snapshot antérieur) : les gabarits gardent alors leur texte actuel.
  @AuraEnabled
  public List<TjmPeriodRow> tjmPeriodes { get; set; }
  @AuraEnabled
  public Decimal joursParMois { get; set; }
  // Facturation mensuelle lissée (chaque mois complet = TJM × jours annuels / 12).
  // Absent des snapshots antérieurs à ce champ : null, lu comme décoché.
  @AuraEnabled
  public Boolean mensualisationLissee { get; set; }
  // Régie sans régule (docs/265c) : la matrice est en mode actif, l'échéancier reprend son plan de production
  // et la case lissée est imposée. Absent des snapshots antérieurs : null, lu comme éteint.
  @AuraEnabled
  public Boolean rplsrActive { get; set; }
  @AuraEnabled
  public Integer nbConsultants { get; set; }
  @AuraEnabled
  public Decimal totalHT { get; set; }
  @AuraEnabled
  public List<ScheduleRow> schedule { get; set; }
  @AuraEnabled
  public String livrables { get; set; }
  @AuraEnabled
  public String freqReunions { get; set; }
  @AuraEnabled
  public Boolean fraisDepl { get; set; }
  // ⚠️ Reste un Boolean (session 35, écart assumé avec le prompt de session — cf.
  // docs/35-socle-multi-gabarits.md §2). Le prompt demandait d'en changer le type pour porter
  // « PC, licence… » ; deux contraintes l'interdisent : (1) tous les snapshots déjà générés
  // portent `"materielClient": true|false` — JSON.deserialize lèverait sur un champ devenu String,
  // et AR_PTFTemplateController rattrape toute exception en rendant une page VIDE : chaque PDF déjà
  // produit deviendrait irrécupérable ; (2) le gabarit générique est en production fonctionnelle et
  // doit rendre à l'identique. La capacité demandée est portée par `materielItems` ci-dessous, qui
  // est le vrai besoin de C27 ; ce booléen ne sert plus qu'au gabarit générique.
  @AuraEnabled
  public Boolean materielClient { get; set; }
  // C27 (session 35) : items de matériel mis à disposition (PC, licence…). Vide/absent →
  // « Mis à disposition par <NOM CLIENT> » ; renseigné → « OUI » suivi des items. Le libellé est
  // construit par AR_PTFTemplateController (materielLabel), pas ici.
  @AuraEnabled
  public List<String> materielItems { get; set; }
  @AuraEnabled
  public String conditionsReglement { get; set; }
  @AuraEnabled
  public String tribunalCompetent { get; set; }
  @AuraEnabled
  public String evolutionPrix { get; set; }
  // Texte saisi par l'utilisateur, renseigné seulement quand il diffère des textes du modèle : les
  // gabarits à texte contractuel fixe (Abylsen) n'impriment l'objet et l'évolution des prix que dans ce cas.
  public String objetSaisi { get; set; }
  public String evolutionPrixSaisie { get; set; }
  // Texte pré-rempli du formulaire par code de gabarit ; GENERIQUE sert à tout gabarit absent de la carte.
  @AuraEnabled
  public Map<String, String> objetParGabarit { get; set; }
  @AuraEnabled
  public Map<String, String> evolutionPrixParGabarit { get; set; }
  @AuraEnabled
  public String redacteurNom { get; set; }
  @AuraEnabled
  public String redacteurFonction { get; set; }
  @AuraEnabled
  public String valideurNom { get; set; }
  @AuraEnabled
  public String valideurFonction { get; set; }
  // Texte de blocage du valideur, calculé à la lecture des défauts (null si le valideur existe).
  @AuraEnabled
  public String valideurBlocage { get; set; }
  @AuraEnabled
  public String interNom { get; set; }
  @AuraEnabled
  public String interFonction { get; set; }
  @AuraEnabled
  public String interTel { get; set; }
  @AuraEnabled
  public String interEmail { get; set; }
  @AuraEnabled
  public String consultantNom { get; set; }
  @AuraEnabled
  public String consultantExperience { get; set; }
  @AuraEnabled
  public String consultantCompetences { get; set; }
  @AuraEnabled
  public String managerName { get; set; }
  @AuraEnabled
  public Datetime generatedAt { get; set; }
  // Gabarit résolu (session 30) : figé à la collecte comme le reste — une PTF déjà générée
  // continue de se rendre avec le gabarit qui existait à ce moment, même si la résolution
  // (compte/entité) change ensuite. 'GENERIQUE' tant qu'aucun autre gabarit n'existe.
  @AuraEnabled
  public String templateCode { get; set; }
  // true uniquement pour une prévisualisation transitoire (jamais persistée) — jamais vrai sur un
  // snapshot réellement inséré. Pilote le bandeau "APERÇU — NON CONTRACTUEL" du gabarit.
  @AuraEnabled
  public Boolean isPreview { get; set; }
  // Historique multi-versions figé (session 30) : toutes les générations de la matrice connues au
  // moment de CETTE génération, y compris la présente — cf. HistoryRow.
  @AuraEnabled
  public List<HistoryRow> historique { get; set; }
  // Session 151 : vrai uniquement si la PTF n'est pas en V01 (il y a au moins une version antérieure)
  // — pilote l'affichage du bloc « Historique des modifications » dans le gabarit.
  @AuraEnabled
  public Boolean showHistorique { get; set; }

  // ------------------------------------------------------------------------
  // Session 35 — socle multi-gabarits. Aucune de ces propriétés n'est consommée par
  // AR_PTFTemplate.page (gabarit générique inchangé) : elles alimentent les gabarits des sessions
  // 36 à 38, et sont figées dès maintenant dans le snapshot pour que les documents générés d'ici là
  // les portent déjà.
  // ------------------------------------------------------------------------

  // Provenance du gabarit résolu : 'Manuel' | 'Compte' | 'Entité' | 'Générique'. Figée avec le
  // code lui-même — savoir QUEL gabarit a été utilisé sans savoir POURQUOI ne suffit pas à
  // reconstituer une décision commerciale des mois plus tard.
  @AuraEnabled
  public String templateCodeSource { get; set; }
  // C9 / C5 (avenant) : SIRET du client, lu sur le compte Connexys (Account.SIRET__c).
  @AuraEnabled
  public String siretClient { get; set; }
  // C17 : titre du besoin Connexys, distinct de `objet` (phrase rédigée, surchargée à la saisie).
  @AuraEnabled
  public String titreBesoin { get; set; }
  // C57 : durée de la mission en mois.
  @AuraEnabled
  public Integer dureeMois { get; set; }
  // C40, C43-C45 : l'échéancier vu en lots. `schedule` (mensuel) reste inchangé et reste la source
  // du gabarit générique ; `lots` en est la vue enrichie, seule à porter les surcharges.
  @AuraEnabled
  public List<LotRow> lots { get; set; }
  // Total réellement facturé (somme des lots, surcharges comprises) — à comparer à totalHT, qui
  // reste le total théorique. Les deux sont figés : l'écart doit rester lisible à l'audit.
  @AuraEnabled
  public Decimal lotsTotal { get; set; }
  // C2 / C3 de l'AVENANT : interlocuteur *technique* du besoin, distinct de l'interlocuteur client
  // (interNom/interFonction) qui reste celui de la PTF.
  @AuraEnabled
  public String interlocuteurTechniqueNom { get; set; }
  @AuraEnabled
  public String interlocuteurTechniqueFonction { get; set; }
  // C8 / C9 de l'AVENANT : la PTF initiale que l'avenant modifie. Un avenant ne remplace pas la PTF
  // et ne consomme pas son numéro de version — il la cite.
  @AuraEnabled
  public String ptfInitialeReference { get; set; }
  @AuraEnabled
  public Date ptfInitialeDate { get; set; }
  // Données de marge figées, nécessaires pour chiffrer l'impact d'une surcharge de lot sans
  // relire la matrice (qui peut avoir évolué). Lecture seule, jamais imprimées sur le document.
  @AuraEnabled
  public Decimal coutTotalJour { get; set; }
  @AuraEnabled
  public Decimal rfaPercent { get; set; }
  public Decimal plancherPercent { get; set; } // session 123b

  // ------------------------------------------------------------------------
  // Session 37 — cinq correctifs sur le gabarit Abylsen (docs/36b-controle-visuel-pdf-abylsen.md)
  // et rattachement d'un avenant à sa PTF d'origine.
  // ------------------------------------------------------------------------

  // I.2 « Contexte du projet » : domaine d'expertise mis en avant, saisie pure — aucune source
  // Connexys identifiée à ce jour (à la différence de titreBesoin/contexte). Vide tant que
  // l'utilisateur ne le renseigne pas, jamais une valeur héritée de l'exemple SIGMA du .docx source
  // (« des méthodes », codée en dur avant cette session — cf. docs/36b §"Deux textes hérités").
  @AuraEnabled
  public String domaineExpertise { get; set; }

  // Session 142b : avertissements de génération PTF — liste de messages (type chaîne) affichés à
  // l'utilisateur sans bloquer la validation. Exemple : adresse client non renseignée.
  @AuraEnabled
  public List<String> warnings { get; set; }

  // Session 148 : brouillon du formulaire PTF/avenant (AR_Price_Matrix__c.AR_PTF_Form_Draft__c), servi
  // À CÔTÉ des défauts — jamais fusionné côté serveur : le LWC applique les valeurs non vides par-dessus.
  // formDraft = JSON { version, ptf?, avenant? } assaini ; formDraftWarning = brouillon illisible ou
  // entrée écartée (le brouillon concerné est ignoré, jamais une exception muette).
  @AuraEnabled
  public String formDraft { get; set; }
  @AuraEnabled
  public String formDraftWarning { get; set; }

  // --- Avenant (AVENANT_AT_V11) ---------------------------------------------------------------
  // Id de la PTF d'origine que cet avenant modifie — distinct de ptfInitialeReference/Date
  // (session 35, valeurs affichées) : c'est la clé qui permet de retrouver et de vérifier le
  // document d'origine, jamais recalculée après coup (cf. AR_PTF_Document__c.AR_Parent_PTF__c).
  @AuraEnabled
  public Id ptfInitialeDocumentId { get; set; }
  // C2/C3 de l'avenant : interlocuteur *technique* du besoin (interlocuteurTechniqueNom/Fonction
  // ci-dessus), pas l'interlocuteur client de la PTF (interNom/interFonction) — remis ici en
  // toutes lettres pour éviter toute confusion au moment du rendu de l'avenant.
  // Prolongation (corps de l'avenant, variable 1) : toujours renseignée sur un avenant.
  @AuraEnabled
  public Date prolongationJusquAu { get; set; }
  // Révision de prix — bloc conditionnel (corps de l'avenant, variable 2). `revisionPrix` pilote
  // l'affichage du bloc entier : un avenant de simple prolongation le laisse à false et n'affiche
  // ni date d'effet ni tableau de lots, jamais un tableau vide ou une date sans portée.
  @AuraEnabled
  public Boolean revisionPrix { get; set; }
  @AuraEnabled
  public Date revisionPrixADateDu { get; set; }
  // Session 123 : nouveau TJM saisi dans le bloc révision de prix, obligatoire quand revisionPrix = true.
  // Valeur figée au snapshot pour retrouver le prix proposé après coup. Null sur un avenant sans révision.
  @AuraEnabled
  public Decimal nouveauTjm { get; set; }

  // ------------------------------------------------------------------------
  // Session 38 — gabarit ABMI_DQ012 (docs/38-gabarit-abmi-dq012.md). Document non annoté par
  // Matthieu, structure sans équivalent avec la PTF Abylsen (cf. docs/33-...md §3) : cinq points
  // d'arbitrage sans réponse client à ce jour, tous tranchés en repli "saisie libre vide plutôt
  // qu'une valeur inventée" — jamais un texte d'exemple du .docx source comme valeur par défaut.
  // ------------------------------------------------------------------------

  // Arbitrage 1 (numérotation) : "Nos références" reste un champ saisissable distinct de `reference`
  // (PTF-MAT-...) — jamais un faux format "DEVIS N° XXX-AT-XXX-26.XX.XXXX" fabriqué par le code.
  // Défaut = reference (AR_PTFDataService.collect) : garde la référence interne existante, comme
  // demandé par l'arbitrage de repli, sans empêcher la surcharge.
  @AuraEnabled
  public String abmiNosReferences { get; set; }
  // Lettre d'accompagnement : "à l'attention de Madame/Monsieur ..."
  @AuraEnabled
  public String abmiAttentionDe { get; set; }

  // Arbitrage 4 (deux signataires) : couples nom/fonction saisissables, préremplis avec
  // rédacteur/valideur par AR_PTFDataService.collect — jamais recalculés depuis une hiérarchie
  // Connexys que Matthieu n'a pas confirmée pour ce gabarit (à la différence d'Abylsen/avenant).
  @AuraEnabled
  public String abmiSignataire1Nom { get; set; }
  @AuraEnabled
  public String abmiSignataire1Fonction { get; set; }
  @AuraEnabled
  public String abmiSignataire1Tel { get; set; }
  @AuraEnabled
  public String abmiSignataire1Mobile { get; set; }
  @AuraEnabled
  public String abmiSignataire1Email { get; set; }
  @AuraEnabled
  public String abmiSignataire2Nom { get; set; }
  @AuraEnabled
  public String abmiSignataire2Fonction { get; set; }
  @AuraEnabled
  public String abmiSignataire2Tel { get; set; }
  @AuraEnabled
  public String abmiSignataire2Email { get; set; }

  // Arbitrage 3 (sections sans équivalent avec la PTF Abylsen) : saisie libre pure, jamais de valeur
  // par défaut tirée du texte d'exemple du .docx ("Nom du client est un leader international...",
  // "Rédaction des spécifications d'un banc d'essai moteur"...). Null/blank tant que non renseigné :
  // le gabarit affiche alors un état vide explicite, jamais le texte d'exemple du Word.
  @AuraEnabled
  public String abmiDescriptionTravaux { get; set; } // 2.2
  @AuraEnabled
  public String abmiDonneesEntree { get; set; } // 2.3
  @AuraEnabled
  public String abmiDescriptionSolution { get; set; } // 3.1
  @AuraEnabled
  public String abmiAvantages { get; set; } // 3.2
  @AuraEnabled
  public String abmiRessources { get; set; } // 3.3
  @AuraEnabled
  public String abmiOrganisationProjet { get; set; } // 3.4
  // 3.9 : aucun catalogue d'habilitations n'existe (hors périmètre de cette session, cf. prompt
  // "N'invente pas de catalogue d'habilitations").
  @AuraEnabled
  public String abmiHabilitations { get; set; }
  // 3.10 : aucun catalogue de risques n'existe (hors périmètre, cf. prompt "N'invente pas de
  // catalogue de risques") — le tableau d'exemple du .docx (10 lignes génériques) n'est PAS repris.
  @AuraEnabled
  public String abmiAnalyseRisques { get; set; }

  // Arbitrage 2 (pas de notion de lot) : proposition financière en texte libre amendable, dont le
  // défaut est calculé depuis la matrice (TJM, jours, total) par AR_PTFDataService.collect — jamais
  // le tableau de lots des gabarits Abylsen/avenant, que ce document ne connaît pas.
  @AuraEnabled
  public String abmiPropositionFinanciereTexte { get; set; } // 4.1
}