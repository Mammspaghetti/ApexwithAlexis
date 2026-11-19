/**
 * Contrôleur du gabarit PDF (AR_PTFTemplate.page) : lit UNIQUEMENT le snapshot JSON immuable
 * (AR_PTF_Document__c.AR_Snapshot__c), jamais la matrice ni le besoin — c'est la garantie qu'un
 * même document (même Id AR_PTF_Document__c, donc même snapshot déjà figé) se rend identiquement à
 * chaque nouveau rendu, même si la matrice source a depuis évolué ou disparu.
 *
 * Nuance (session 20d, constatée entre PTF-MAT-00065-V5 et -V6 : livrables et fréquence de suivi
 * différents sans qu'aucun champ de la matrice n'ait changé) : cette garantie porte sur le
 * RE-RENDU d'un document déjà généré, PAS sur deux VERSIONS successives (bouton « Régénérer la
 * PTF »). Régénérer crée un nouveau AR_PTF_Document__c via un nouvel appel à
 * AR_PTFDataService.collect(), qui fige à cet instant les valeurs alors en vigueur de la catégorie
 * B (référentiel administrable, AR_PTF_Setting__mdt/AR_PTF_Entity_Referential__c) et de la catégorie C
 * (saisie utilisateur passée à cet appel). Si l'un ou l'autre a changé entre deux régénérations,
 * les deux versions diffèrent légitimement à données de matrice égales — chaque snapshot reste
 * individuellement immuable et fidèle à ce qui était vrai au moment de SA génération, mais
 * « identique à données égales » suppose aussi « paramètres égaux ».
 *
 * `without sharing` : rendu déclenché en système par AR_PTFGenerationService (sur un enregistrement
 * qu'il vient d'insérer lui-même) — ne doit pas dépendre du partage de l'utilisateur qui a cliqué
 * "Générer la PTF" sur une matrice qui ne lui appartient pas forcément (ex. Directeur, Admin).
 *
 * Formats (session 20c) : `ptf.*` reste la donnée brute typée (source de vérité, telle que
 * sérialisée dans le snapshot) ; toute valeur affichée dans le gabarit passe par un libellé
 * pré-formaté en français ci-dessous (`AR_PTFFormatUtil`, indépendant de la locale de l'utilisateur
 * courant) plutôt que par les motifs `{0,date,...}`/`{0,number,...}` de Visualforce, qui suivent la
 * locale et produisaient des mois en anglais. C'est aussi ici, pas dans la page, que se distingue
 * une donnée manquante (« À définir ») d'une valeur réellement calculée à zéro.
 */
public without sharing class AR_PTFTemplateController {
  public AR_PTFData ptf { get; private set; }
  public Decimal totalJours { get; private set; }
  // La fonction formule SPLIT() n'est pas reconnue en Visualforce EL (constaté en déploiement) :
  // le découpage des livrables (un par ligne) se fait ici, pas dans la page.
  public List<String> livrableLines { get; private set; }

  // true seulement si l'échéancier a pu être calculé (dates de mission renseignées) — distingue
  // "donnée manquante" de "montant réellement nul", cf. docs/20-generation-ptf.md.
  public Boolean hasSchedule { get; private set; }

  public String generatedAtLabel { get; private set; }
  public String dateDebutLabel { get; private set; }
  public String dateFinLabel { get; private set; }
  public String tjmLabel { get; private set; }
  public String tjmPerDayLabel { get; private set; }
  // TJM par périodes (docs/254d) : tous nuls / faux sans évolution de TJM (et pour tout snapshot
  // antérieur) — les pages gardent alors leur texte actuel. Construits ici, jamais dans le balisage.
  public Boolean hasTjmPeriodes { get; private set; }
  public String tjmPeriodesLabel { get; private set; }
  // « Prix journalier HT » du gabarit générique : libellé de périodes, sinon tjmLabel.
  public String tjmPrixLabel { get; private set; }
  // Dernière période (dépassement du nombre de jours facturé à son tarif, gabarit ABMI).
  public String tjmDernierePeriodeLabel { get; private set; }
  public String totalHTLabel { get; private set; }
  public String totalJoursLabel { get; private set; }
  public String joursParMoisLabel { get; private set; }
  // Mention légale I.4.1 (session 24b) : "Tous les montants sont exprimés en {devise} hors taxes."
  // — identique au texte d'avant ce bloc pour une PTF en EUR (non-régression), dynamique sinon.
  public String currencyLegalMentionLabel { get; private set; }
  // Devise de facturation explicite (session 24b), affichée UNIQUEMENT pour une PTF non-EUR — une
  // PTF en euros reste rendue à l'identique de ce qu'elle était avant ce bloc.
  public Boolean showCurrencyMention { get; private set; }
  public String currencyCodeLabel { get; private set; }
  public List<ScheduleRowDisplay> scheduleDisplay { get; private set; }
  // Session 35 — consommés par les gabarits 36-38, jamais par AR_PTFTemplate.page (le gabarit
  // générique reste rendu à l'identique, c'est une non-régression prouvée en réel).
  public List<LotRowDisplay> lotsDisplay { get; private set; }
  // Au-delà de 9 lots, « Lot 10: » ne tient plus dans l'étiquette calée sur le modèle (26,5 pt) :
  // la page élargit alors toutes les étiquettes pour garder les montants alignés.
  public Boolean lotsLibellesLarges {
    get { return lotsDisplay != null && lotsDisplay.size() > 9; }
  }
  // C27 : « Mis à disposition par <NOM CLIENT> » si aucun item n'est renseigné dans la matrice,
  // sinon « OUI » suivi des items. Construit ici, jamais dans le balisage de la page.
  public String materielLabel { get; private set; }
  // Écart total entre les lots réellement facturés et le total théorique — non nul seulement si un
  // lot a été surchargé. Sert au contrôle, pas à l'impression.
  public String lotsEcartLabel { get; private set; }
  public Boolean hasLotOverride { get; private set; }
  // Total retenu / total théorique des lots (session 36) : dérivés de la MÊME liste que lotsDisplay,
  // jamais recalculés séparément — c'est ce qui garantit que l'article 4.1 (liste des lots) et
  // l'article 4.3 (tableau Lots/Montant/Échéancier) du gabarit Abylsen affichent un total identique
  // au centime, la même donnée étant lue à deux endroits (piège documenté en session de gabarit).
  public String lotsTotalLabel { get; private set; }
  public String lotsTotalCalculeLabel { get; private set; }
  // C57 (gabarit Abylsen, article 3 des Conditions générales) : durée en mois, jamais un nombre nu
  // sans repli quand Connexys ne la donne pas.
  public String dureeMoisLabel { get; private set; }
  // Historique multi-versions (session 30) : ptf.historique reste la donnée brute figée dans le
  // snapshot, historiqueDisplay porte les dates pré-formatées en français pour le gabarit.
  public List<HistoryRowDisplay> historiqueDisplay { get; private set; }
  // Session 138 — gabarit Abylsen : la page de garde est une page à géométrie fixe (hauteur 841,8 pt,
  // pied en image), un historique long ne peut pas y déborder sans recouvrir le pied puis le sommaire
  // (constaté sur un PDF réel à 25 versions). historiqueDisplay est donc scindé : les premières
  // lignes qui tiennent dans la place restante de la garde (historiqueCoverRows), le reste sur une
  // page de continuation en flux normal (historiqueSuiteRows), jamais une ligne perdue.
  public List<HistoryRowDisplay> historiqueCoverRows { get; private set; }
  public List<HistoryRowDisplay> historiqueSuiteRows { get; private set; }
  public Boolean hasHistoriqueSuite { get; private set; }
  // Session 151 : vrai si le bloc « Historique des modifications » doit être affiché (false pour V01 PTF).
  public Boolean showHistorique { get; private set; }

  // Place disponible pour les lignes d'historique sur la page de garde (points), mesurée sur un PDF
  // réel : lignes de 1re à dernière entre le bas des en-têtes du tableau (~508 pt) et le haut du
  // bloc d'adresses qui doit rester au-dessus du pied image (~647 pt), moins une marge de sécurité.
  @TestVisible
  private static final Decimal COVER_HISTORY_BUDGET_PT = 135;
  // Hauteur d'une ligne d'une seule ligne de texte (10,35 pt d'interligne + filets/bordures,
  // mesurée : 13,05 pt) puis incrément par ligne de texte supplémentaire.
  private static final Decimal HISTORY_ROW_BASE_PT = 13.1;
  private static final Decimal HISTORY_LINE_PT = 10.35;
  // Capacités des colonnes Modification (120,6 pt) et Responsable (184,8 pt) en caractères, volontairement
  // basses : surestimer une hauteur ne fait que déplacer une ligne sur la page suivante, la sous-estimer
  // ferait déborder la garde.
  private static final Integer MODIFICATION_CHARS_PER_LINE = 19;
  private static final Integer RESPONSABLE_CHARS_PER_LINE = 32;

  // Session 37 — gabarit AVENANT_AT_V11 : dates pré-formatées du corps de l'avenant (C8/C9 et les
  // deux variables de corps), sur le même principe que dateDebutLabel/dateFinLabel ci-dessus. Jamais
  // consommées par les autres gabarits.
  public String ptfInitialeDateLabel { get; private set; }
  public String prolongationJusquAuLabel { get; private set; }
  public String revisionPrixADateDuLabel { get; private set; }
  // Session 123 : nouveau TJM saisi dans le bloc révision de prix d'avenant.
  public String nouveauTjmLabel { get; private set; }

  // Session 57 — tableau d'identification de la page de garde Abylsen/avenant : le modèle attend un
  // numéro de version zéro-paddé ("01", "02"...), jamais le préfixe de lettre porté par ptf.version
  // ("V1", "AV2"...) qui reste le format interne inchangé partout ailleurs (historique, référence).
  public String versionNumeroLabel { get; private set; }

  /** Vue pré-formatée d'une ligne d'échéancier : ptf.schedule reste la donnée brute (Decimal). */
  public class ScheduleRowDisplay {
    public String mois { get; private set; }
    public String joursLabel { get; private set; }
    public String montantLabel { get; private set; }
    public String cumulLabel { get; private set; }

    public ScheduleRowDisplay(AR_PTFData.ScheduleRow row, String currencySymbol) {
      mois = row.mois;
      joursLabel = AR_PTFFormatUtil.formatNumberFr(row.jours, 2, 'j');
      montantLabel = AR_PTFFormatUtil.formatNumberFr(row.montant, 0, currencySymbol);
      cumulLabel = AR_PTFFormatUtil.formatNumberFr(row.cumul, 0, currencySymbol);
    }
  }

  /**
   * Vue pré-formatée d'un LOT (session 35). `montantLabel` est le montant retenu (surcharge
   * comprise) ; `montantCalculeLabel` reste disponible à côté, y compris sur un lot non surchargé —
   * un écart entre le prix affiché au commercial et le prix imprimé au client doit toujours être
   * reconstituable depuis le document lui-même.
   */
  public class LotRowDisplay {
    public String libelle { get; private set; }
    public String mois { get; private set; }
    public String joursLabel { get; private set; }
    public String montantLabel { get; private set; }
    public String montantCalculeLabel { get; private set; }
    public String echeanceLabel { get; private set; }
    public String cumulLabel { get; private set; }
    public Boolean isOverridden { get; private set; }

    public LotRowDisplay(AR_PTFData.LotRow row, String currencySymbol) {
      libelle = row.libelle;
      mois = row.mois;
      joursLabel = AR_PTFFormatUtil.formatNumberFr(row.jours, 2, 'j');
      montantLabel = AR_PTFFormatUtil.formatNumberFr(row.montant, 0, currencySymbol);
      montantCalculeLabel = AR_PTFFormatUtil.formatNumberFr(row.montantCalcule, 0, currencySymbol);
      echeanceLabel = AR_PTFFormatUtil.formatDateFr(row.echeance);
      cumulLabel = AR_PTFFormatUtil.formatNumberFr(row.cumul, 0, currencySymbol);
      isOverridden = row.isOverridden == true;
    }
  }

  /** Vue pré-formatée d'une ligne d'historique : AR_PTFData.HistoryRow reste la donnée brute. */
  public class HistoryRowDisplay {
    public String version { get; private set; }
    public String reference { get; private set; }
    public String dateLabel { get; private set; }
    public String objetModification { get; private set; }
    public String redacteurNom { get; private set; }
    public String valideurNom { get; private set; }
    public String responsable { get; private set; }

    public HistoryRowDisplay(AR_PTFData.HistoryRow row) {
      version = row.version;
      reference = row.reference;
      dateLabel = AR_PTFFormatUtil.formatDatetimeFr(row.generatedAt);
      objetModification = allowBreaks(row.objetModification);
      redacteurNom = row.redacteurNom;
      valideurNom = row.valideurNom;
      responsable = allowBreaks(row.responsable);
    }
  }

  // Le moteur PDF ne coupe pas un mot plus long que sa cellule (constaté sur un PDF réel : le texte
  // déborde sur la colonne voisine). `word-wrap: break-word`, l'espace de largeur nulle U+200B et
  // l'espace ultra-fine U+200A ont tous été essayés en réel sans effet — seule une espace ordinaire
  // est une opportunité de coupure pour ce moteur. Compromis assumé : un mot de plus de
  // MAX_UNBROKEN_TOKEN caractères (cas pathologique : saisie sans espace, URL) est coupé par une
  // espace visible tous les BREAK_EVERY caractères, plutôt que de déborder sur la colonne voisine ;
  // tout mot plus court est laissé strictement intact.
  private static final Integer MAX_UNBROKEN_TOKEN = 20;
  private static final Integer BREAK_EVERY = 18;

  @TestVisible
  private static String allowBreaks(String text) {
    if (String.isBlank(text)) {
      return text;
    }
    List<String> words = text.split(' ');
    for (Integer i = 0; i < words.size(); i++) {
      String word = words[i];
      if (word.length() > MAX_UNBROKEN_TOKEN) {
        List<String> chunks = new List<String>();
        for (Integer start = 0; start < word.length(); start += BREAK_EVERY) {
          chunks.add(word.substring(start, Math.min(start + BREAK_EVERY, word.length())));
        }
        words[i] = String.join(chunks, ' ');
      }
    }
    return String.join(words, ' ');
  }

  public AR_PTFTemplateController() {
    resetEmpty();

    // Trois sources possibles de données (session 124) : `previewId` (aperçu persistant sur
    // AR_PTF_Preview__c), `data` (prévisualisation transitoire, JSON encodé en base64), ou `id`
    // (document déjà généré). Ordre de priorité : previewId > data > id. Un appel qui passe plusieurs
    // paramètres obtient celui avec la priorité la plus haute — la confusion est moins probable ici
    // que sur la branche `data`/`id` de la session 30 puisque previewId voyage via le nouvel objet,
    // jamais dans l'URL.
    String previewIdParam = ApexPages.currentPage().getParameters().get('previewId');
    String dataParam = ApexPages.currentPage().getParameters().get('data');
    String idParam = ApexPages.currentPage().getParameters().get('id');

    if (String.isNotBlank(previewIdParam)) {
      try {
        // Session 124 : aperçu créé par createPreview, persiste sur AR_PTF_Preview__c (OWD Privé).
        // Session 126 : lecture en SYSTEM_MODE filtrée sur le créateur — seul l'auteur de l'aperçu le voit,
        // sans dépendre de la FLS (enregistrement technique).
        List<AR_PTF_Preview__c> previews = [
          SELECT AR_Data__c, AR_Template_Code__c
          FROM AR_PTF_Preview__c
          WHERE Id = :previewIdParam
            AND CreatedById = :UserInfo.getUserId()
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        if (!previews.isEmpty() && String.isNotBlank(previews[0].AR_Data__c)) {
          AR_PTFData decoded = (AR_PTFData) JSON.deserialize(
            previews[0].AR_Data__c,
            AR_PTFData.class
          );
          decoded.isPreview = true;
          applyDecoded(decoded);
        } else {
          // ID de prévisualisation introuvable ou données vides — message explicite, pas une page
          // blanche.
          ApexPages.addMessage(
            new ApexPages.Message(
              ApexPages.Severity.ERROR,
              'Prévisualisation non disponible. La clé de session a peut-être expiré.'
            )
          );
        }
      } catch (Exception e) {
        ApexPages.addMessage(
          new ApexPages.Message(
            ApexPages.Severity.ERROR,
            'Erreur lors de la lecture de la prévisualisation : ' + e.getMessage()
          )
        );
      }
    } else if (String.isNotBlank(dataParam)) {
      try {
        // Nom local délibérément différent de "json" : Apex est insensible à la casse sur les
        // identifiants, "json" masquerait la classe système JSON dans cette portée et ferait
        // échouer JSON.deserialize(...) à la compilation (résolu en tant que méthode d'instance
        // inexistante sur String) — piège rencontré en écrivant ce code, corrigé avant livraison.
        String decodedJson = EncodingUtil.base64Decode(dataParam).toString();
        AR_PTFData decoded = (AR_PTFData) JSON.deserialize(decodedJson, AR_PTFData.class);
        decoded.isPreview = true;
        applyDecoded(decoded);
      } catch (Exception e) {
        // Payload de prévisualisation invalide/corrompu : page rendue avec une structure vide
        // plutôt qu'une erreur brute, même politique que la branche `id` ci-dessous.
        resetEmpty();
      }
    } else if (String.isNotBlank(idParam)) {
      try {
        List<AR_PTF_Document__c> docs = [
          SELECT AR_Snapshot__c
          FROM AR_PTF_Document__c
          WHERE Id = :idParam
          LIMIT 1
        ];
        if (!docs.isEmpty() && String.isNotBlank(docs[0].AR_Snapshot__c)) {
          AR_PTFData decoded = (AR_PTFData) JSON.deserialize(
            docs[0].AR_Snapshot__c,
            AR_PTFData.class
          );
          applyDecoded(decoded);
        }
      } catch (Exception e) {
        // id absent/invalide ou snapshot corrompu : page rendue avec une structure vide plutôt
        // qu'une erreur brute — ne devrait jamais arriver en usage normal (l'id est toujours celui
        // du document qu'AR_PTFGenerationService vient d'insérer lui-même).
        resetEmpty();
      }
    }

    applyDisplayLabels();
  }

  private void resetEmpty() {
    ptf = new AR_PTFData();
    ptf.schedule = new List<AR_PTFData.ScheduleRow>();
    ptf.entiteInfo = new AR_PTFData.EntiteInfo();
    ptf.historique = new List<AR_PTFData.HistoryRow>();
    ptf.lots = new List<AR_PTFData.LotRow>();
    ptf.materielItems = new List<String>();
    totalJours = 0;
    livrableLines = new List<String>();
  }

  private void applyDecoded(AR_PTFData decoded) {
    ptf = decoded;
    if (ptf.schedule == null) {
      ptf.schedule = new List<AR_PTFData.ScheduleRow>();
    }
    if (ptf.entiteInfo == null) {
      ptf.entiteInfo = new AR_PTFData.EntiteInfo();
    }
    if (ptf.historique == null) {
      ptf.historique = new List<AR_PTFData.HistoryRow>();
    }
    // Snapshots antérieurs à la session 35 : ni lots ni items de matériel dans leur JSON. Repli sur
    // des listes vides, jamais sur null — un ancien document doit continuer de se rendre.
    if (ptf.lots == null) {
      ptf.lots = new List<AR_PTFData.LotRow>();
    }
    if (ptf.materielItems == null) {
      ptf.materielItems = new List<String>();
    }
    totalJours = 0;
    for (AR_PTFData.ScheduleRow row : ptf.schedule) {
      totalJours += row.jours;
    }
    livrableLines = splitLivrables(ptf.livrables);
  }

  private void applyDisplayLabels() {
    hasSchedule = ptf.schedule != null && !ptf.schedule.isEmpty();

    generatedAtLabel = AR_PTFFormatUtil.formatDatetimeFr(ptf.generatedAt);
    dateDebutLabel = AR_PTFFormatUtil.formatDateFr(ptf.dateDebut);
    dateFinLabel = AR_PTFFormatUtil.formatDateFr(ptf.dateFin);
    ptfInitialeDateLabel = AR_PTFFormatUtil.formatDateFr(ptf.ptfInitialeDate);
    prolongationJusquAuLabel = AR_PTFFormatUtil.formatDateFr(ptf.prolongationJusquAu);
    revisionPrixADateDuLabel = AR_PTFFormatUtil.formatDateFr(ptf.revisionPrixADateDu);
    versionNumeroLabel = extractVersionNumero(ptf.version);

    // Devise de facturation (session 24b) : symbole/code unique résolu ici et réutilisé pour
    // TOUTES les zones financières de la page (TJM, échéancier, totaux) — jamais un '€' en dur au
    // fil de l'eau, un document en devise étrangère avec un symbole euro serait un défaut
    // contractuel, pas un défaut d'affichage.
    String currencySymbol = AR_PTFFormatUtil.currencySymbol(ptf.currencyCode);
    Boolean isEur = String.isBlank(ptf.currencyCode) || ptf.currencyCode == 'EUR';
    showCurrencyMention = !isEur;
    currencyCodeLabel = String.isNotBlank(ptf.currencyCode) ? ptf.currencyCode : 'EUR';
    currencyLegalMentionLabel = 'Tous les montants sont exprimés en ' +
      AR_PTFFormatUtil.currencyLabelFr(ptf.currencyCode) +
      ' hors taxes. TVA au taux légal en vigueur à la date de facturation.';

    tjmLabel = AR_PTFFormatUtil.formatNumberFr(ptf.tjm, 0, currencySymbol);
    tjmPerDayLabel = tjmLabel == null ? null : tjmLabel + '/j';
    tjmPrixLabel = tjmLabel;
    hasTjmPeriodes = false;
    // Un libellé nul (date manquante dans un snapshot incohérent) laisse le texte actuel : jamais de page blanche.
    String periodesLabel = AR_PTFFormatUtil.tjmPeriodesLabel(ptf.tjmPeriodes, ptf.currencyCode);
    if (periodesLabel != null) {
      hasTjmPeriodes = true;
      tjmPeriodesLabel = periodesLabel;
      tjmPrixLabel = periodesLabel;
      tjmPerDayLabel = AR_PTFFormatUtil.tjmRangeLabel(ptf.tjmPeriodes, ptf.currencyCode);
      tjmDernierePeriodeLabel = AR_PTFFormatUtil.formatNumberFr(
        ptf.tjmPeriodes[ptf.tjmPeriodes.size() - 1].tjm, 2, currencySymbol
      );
    }
    joursParMoisLabel = AR_PTFFormatUtil.formatNumberFr(ptf.joursParMois, 2, 'j');
    // Session 123 : nouveau TJM de l'avenant en bloc révision de prix, avec format devise identique.
    nouveauTjmLabel = AR_PTFFormatUtil.formatNumberFr(ptf.nouveauTjm, 0, currencySymbol);

    // "À définir", jamais un zéro inventé, quand l'échéancier n'a pas pu être calculé (dates de
    // mission manquantes) — un vrai montant à zéro calculé (cas théorique) reste affiché tel quel.
    totalHTLabel = (!hasSchedule || ptf.totalHT == null)
      ? 'À définir'
      : AR_PTFFormatUtil.formatNumberFr(ptf.totalHT, 0, currencySymbol);
    totalJoursLabel = !hasSchedule
      ? 'À définir'
      : AR_PTFFormatUtil.formatNumberFr(totalJours, 2, 'j');

    scheduleDisplay = new List<ScheduleRowDisplay>();
    if (ptf.schedule != null) {
      for (AR_PTFData.ScheduleRow row : ptf.schedule) {
        scheduleDisplay.add(new ScheduleRowDisplay(row, currencySymbol));
      }
    }

    // --- Session 35 : lots et matériel (consommés par les gabarits 36-38) --------------------
    lotsDisplay = new List<LotRowDisplay>();
    hasLotOverride = false;
    Decimal lotsCalcule = 0;
    Decimal lotsRetenu = 0;
    if (ptf.lots != null) {
      for (AR_PTFData.LotRow row : ptf.lots) {
        lotsDisplay.add(new LotRowDisplay(row, currencySymbol));
        if (row.isOverridden == true) {
          hasLotOverride = true;
        }
        if (row.montantCalcule != null) {
          lotsCalcule += row.montantCalcule;
        }
        if (row.montant != null) {
          lotsRetenu += row.montant;
        }
      }
    }
    // Écart affiché seulement s'il existe : sur un échéancier entièrement calculé, il vaut zéro et
    // afficher « 0 € d'écart » suggérerait à tort qu'une surcharge a eu lieu.
    lotsEcartLabel = hasLotOverride
      ? AR_PTFFormatUtil.formatNumberFr(lotsRetenu - lotsCalcule, 0, currencySymbol)
      : null;
    lotsTotalLabel = ptf.lots != null && !ptf.lots.isEmpty()
      ? AR_PTFFormatUtil.formatNumberFr(lotsRetenu, 0, currencySymbol)
      : null;
    lotsTotalCalculeLabel = ptf.lots != null && !ptf.lots.isEmpty()
      ? AR_PTFFormatUtil.formatNumberFr(lotsCalcule, 0, currencySymbol)
      : null;

    dureeMoisLabel = ptf.dureeMois == null ? null : String.valueOf(ptf.dureeMois);

    // C27 : sans items renseignés, le matériel est « mis à disposition par le client » — formule
    // demandée par Matthieu, pas un « non renseigné ». Guillemets français corrigés en session 49
    // (cause C #3, relevé contre le .docx source) : la session 35 avait posé des guillemets droits.
    if (ptf.materielItems != null && !ptf.materielItems.isEmpty()) {
      materielLabel = 'OUI — ' + String.join(ptf.materielItems, ', ');
    } else {
      materielLabel = 'Mis à disposition par « ' +
        (String.isNotBlank(ptf.client) ? ptf.client.toUpperCase() : 'LE CLIENT') + ' »';
    }

    historiqueDisplay = new List<HistoryRowDisplay>();
    if (ptf.historique != null && !ptf.historique.isEmpty()) {
      for (AR_PTFData.HistoryRow row : ptf.historique) {
        historiqueDisplay.add(new HistoryRowDisplay(row));
      }
    } else if (String.isNotBlank(ptf.reference)) {
      // Repli legacy (session 30) : un document généré avant l'introduction de l'historique figé
      // n'a pas de "historique" dans son snapshot — reproduit EXACTEMENT le comportement d'avant
      // cette session (une seule ligne, la version courante), jamais une table vide.
      AR_PTFData.HistoryRow current = new AR_PTFData.HistoryRow();
      current.version = ptf.version;
      current.reference = ptf.reference;
      current.generatedAt = ptf.generatedAt;
      // Session 138 : plus de libellé Création/Régénération — la colonne Modification ne se lit que
      // depuis les champs de la PTF, jamais d'une règle de numéro ; un ancien snapshot sans
      // historique figé n'a pas cette information, la cellule reste vide.
      current.redacteurNom = ptf.redacteurNom;
      current.valideurNom = ptf.valideurNom;
      historiqueDisplay.add(new HistoryRowDisplay(current));
    }
    splitHistorique();
    showHistorique = ptf.historique != null && ptf.historique.size() > 1;
  }

  /**
   * Nombre de lignes de texte qu'occupe `text` dans une cellule de `charsPerLine` caractères :
   * retour à la ligne glouton sur les espaces, un mot plus long que la cellule se coupe (word-wrap).
   */
  @TestVisible
  private static Integer estimateLines(String text, Integer charsPerLine) {
    if (String.isBlank(text)) {
      return 1;
    }
    Integer lines = 1;
    Integer used = 0;
    for (String word : text.trim().split('\\s+')) {
      Integer len = word.length();
      while (len > charsPerLine) {
        if (used > 0) {
          lines++;
          used = 0;
        }
        len -= charsPerLine;
        lines++;
      }
      if (used == 0) {
        used = len;
      } else if (used + 1 + len <= charsPerLine) {
        used += 1 + len;
      } else {
        lines++;
        used = len;
      }
    }
    return lines;
  }

  @TestVisible
  private static Decimal estimateRowHeight(HistoryRowDisplay row) {
    Integer lines = Math.max(
      estimateLines(row.objetModification, MODIFICATION_CHARS_PER_LINE),
      estimateLines(row.responsable, RESPONSABLE_CHARS_PER_LINE)
    );
    return HISTORY_ROW_BASE_PT + (lines - 1) * HISTORY_LINE_PT;
  }

  /** Répartit historiqueDisplay entre la page de garde et la page de continuation (cf. déclaration). */
  private void splitHistorique() {
    historiqueCoverRows = new List<HistoryRowDisplay>();
    historiqueSuiteRows = new List<HistoryRowDisplay>();
    Decimal used = 0;
    Boolean overflow = false;
    for (HistoryRowDisplay row : historiqueDisplay) {
      Decimal height = estimateRowHeight(row);
      // La première ligne reste toujours sur la garde (au rang 1 sa cellule Modification est vide).
      if (!overflow && (historiqueCoverRows.isEmpty() || used + height <= COVER_HISTORY_BUDGET_PT)) {
        historiqueCoverRows.add(row);
        used += height;
      } else {
        overflow = true;
        historiqueSuiteRows.add(row);
      }
    }
    hasHistoriqueSuite = !historiqueSuiteRows.isEmpty();
  }

  // "V1" → "01", "AV12" → "12" : ne garde que les chiffres, zéro-paddés sur 2 positions minimum.
  // Aucune valeur de repli fabriquée si ptf.version ne porte aucun chiffre (snapshot vide/corrompu,
  // cf. resetEmpty()) — la cellule reste alors vide, jamais un "00" inventé.
  private String extractVersionNumero(String version) {
    if (String.isBlank(version)) {
      return null;
    }
    String digits = version.replaceAll('[^0-9]', '');
    if (String.isBlank(digits)) {
      return null;
    }
    return digits.length() < 2 ? '0' + digits : digits;
  }

  private List<String> splitLivrables(String livrables) {
    List<String> lines = new List<String>();
    if (String.isBlank(livrables)) {
      return lines;
    }
    for (String line : livrables.split('\n')) {
      if (String.isNotBlank(line)) {
        lines.add(line);
      }
    }
    return lines;
  }
}