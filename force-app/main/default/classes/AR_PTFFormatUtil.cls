/**
 * Formatage français des dates et nombres pour le gabarit PTF — session 20c.
 *
 * `Datetime.format()`/`{0,date,...}` en Visualforce suivent la locale de l'utilisateur ou de l'org
 * (constaté : mois en anglais sur un document généré par un utilisateur en locale anglaise). Un
 * document commercial français doit être en français indépendamment de qui le génère — c'est un
 * paramètre du gabarit, pas un format soumis à la locale courante. D'où une classe entièrement
 * autonome (aucun appel à `Datetime.format()`/`Date.format()`/`NumberFormat`, qui dépendent tous de
 * la locale) : mois construits depuis une liste française fixe, séparateurs construits caractère
 * par caractère. Le jour où l'outil gère plusieurs pays (multi-devises, réunion du 10/08/2026), la
 * locale du document devra suivre le pays de l'entité — cette classe est le point unique à faire
 * évoluer (un paramètre de pays/langue en plus, pas un `format()` de plus ailleurs dans le gabarit).
 */
public class AR_PTFFormatUtil {
  public static final List<String> MONTHS_FR = new List<String>{
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre'
  };

  // U+00A0 : espace insécable, convention typographique française avant une unité (€, j) et comme
  // séparateur de milliers — jamais un espace normal, qui autoriserait une coupure de ligne au
  // milieu d'un nombre ou entre un montant et son unité.
  public static final String NBSP = ' ';

  // Multi-devises (session 24b) : mêmes choix que arPricingEngine.js CURRENCY_SYMBOLS (cohérence
  // dans toute l'app) — EUR/GBP ont un symbole à un caractère non ambigu, CHF/CAD/MAD gardent le
  // code ISO (un "$" pour CAD serait confondu avec l'USD). Choix cosmétique documenté, pas une
  // clause contractuelle — ce qui EST contractuel, c'est que le bon code apparaisse quelque part
  // (cf. currencyLabelFr ci-dessous pour la mention légale en toutes lettres).
  private static final Map<String, String> CURRENCY_SYMBOLS = new Map<String, String>{
    'EUR' => '€',
    'GBP' => '£',
    'CHF' => 'CHF',
    'CAD' => 'CAD',
    'MAD' => 'MAD'
  };

  // Mention légale en toutes lettres (I.4.1 Tarification, AR_PTFTemplate.page) — texte non vérifié
  // par un juriste, à faire relire avant tout usage contractuel réel en devise étrangère (cf.
  // docs/24-multidevise.md, "à remonter à Alexis").
  private static final Map<String, String> CURRENCY_LABELS_FR = new Map<String, String>{
    'EUR' => 'euros',
    'GBP' => 'livres sterling',
    'CHF' => 'francs suisses',
    'CAD' => 'dollars canadiens',
    'MAD' => 'dirhams marocains'
  };

  public static String currencySymbol(String currencyCode) {
    String code = String.isNotBlank(currencyCode) ? currencyCode : 'EUR';
    return CURRENCY_SYMBOLS.containsKey(code) ? CURRENCY_SYMBOLS.get(code) : code;
  }

  public static String currencyLabelFr(String currencyCode) {
    String code = String.isNotBlank(currencyCode) ? currencyCode : 'EUR';
    return CURRENCY_LABELS_FR.containsKey(code) ? CURRENCY_LABELS_FR.get(code) : code;
  }

  public static String formatDateFr(Date d) {
    if (d == null) {
      return null;
    }
    // Session 37 : le premier du mois s'écrit "1er" en français, jamais "1" — défaut relevé au
    // contrôle visuel du PDF Abylsen (docs/36b-controle-visuel-pdf-abylsen.md), invisible à tout
    // test qui ne compare pas un jour 1 (les fixtures existantes utilisaient le 11 et le 15).
    String dayLabel = d.day() == 1 ? '1er' : String.valueOf(d.day());
    return dayLabel + ' ' + MONTHS_FR[d.month() - 1] + ' ' + d.year();
  }

  public static String formatDatetimeFr(Datetime dt) {
    if (dt == null) {
      return null;
    }
    // year()/month()/day() sur Datetime sont déjà ajustés au fuseau de l'utilisateur courant côté
    // plateforme ; reconstruire un Date à partir de ces trois composants évite tout passage par
    // format()/formatGmt() sensible à la locale.
    return formatDateFr(Date.newInstance(dt.year(), dt.month(), dt.day()));
  }

  /**
   * Notation française : virgule décimale, zéros non significatifs supprimés (comme `#,##0.##`),
   * espace insécable comme séparateur de milliers.
   */
  public static String formatNumberFr(Decimal value, Integer maxDecimals) {
    if (value == null) {
      return null;
    }
    Boolean negative = value < 0;
    Decimal absValue = negative ? -value : value;
    Decimal rounded = absValue.setScale(maxDecimals, System.RoundingMode.HALF_UP);
    String plain = rounded.toPlainString();

    List<String> parts = plain.split('\\.');
    String intPart = parts[0];
    String decPart = parts.size() > 1 ? parts[1] : '';
    while (decPart.endsWith('0')) {
      decPart = decPart.substring(0, decPart.length() - 1);
    }

    String result = groupThousands(intPart) + (String.isNotBlank(decPart) ? ',' + decPart : '');
    return (negative ? '-' : '') + result;
  }

  /** Ajoute une unité précédée d'une espace insécable ; null si la valeur formatée est null. */
  public static String formatNumberFr(Decimal value, Integer maxDecimals, String unit) {
    String formatted = formatNumberFr(value, maxDecimals);
    return formatted == null ? null : formatted + NBSP + unit;
  }

  /** Date numérique JJ/MM/AAAA (libellé des périodes de TJM, docs/254) ; null si absente. */
  public static String formatDateShortFr(Date d) {
    if (d == null) {
      return null;
    }
    String dd = String.valueOf(d.day());
    String mm = String.valueOf(d.month());
    return (dd.length() < 2 ? '0' : '') + dd + '/' + (mm.length() < 2 ? '0' : '') + mm + '/' + d.year();
  }

  /**
   * Libellé des TJM par périodes (docs/254 §7, décision 3 du §11) :
   * « 650 € HT/jour jusqu'au 14/03/2026, puis 700 € HT/jour à partir du 15/03/2026 » ; à trois périodes,
   * « …, puis 750 € HT/jour à partir du … » enchaîné. « Jusqu'au » = veille de la date de début de la
   * période suivante. null sans évolution de TJM (moins de deux périodes) ou si une date manque.
   * Construit côté Apex : SPLIT() n'est pas reconnu par Visualforce, et l'apostrophe ne passe jamais
   * par un MessageFormat (la page l'imprime par expression, pas par un value littéral).
   */
  public static String tjmPeriodesLabel(List<AR_PTFData.TjmPeriodRow> periodes, String currencyCode) {
    if (periodes == null || periodes.size() < 2) {
      return null;
    }
    String symbol = currencySymbol(currencyCode);
    String label = '';
    for (Integer i = 0; i < periodes.size(); i++) {
      AR_PTFData.TjmPeriodRow p = periodes[i];
      String price = formatNumberFr(p.tjm, 2, symbol);
      if (price == null) {
        return null;
      }
      if (i == 0) {
        Date next = periodes[1].dateDebut;
        if (next == null) {
          return null;
        }
        label = price + ' HT/jour jusqu\'au ' + formatDateShortFr(next.addDays(-1));
      } else {
        if (p.dateDebut == null) {
          return null;
        }
        label += ', puis ' + price + ' HT/jour à partir du ' + formatDateShortFr(p.dateDebut);
      }
    }
    return label;
  }

  /** « de 650 à 700 €/j » (min–max) pour les cases de synthèse ; null sans évolution de TJM. */
  public static String tjmRangeLabel(List<AR_PTFData.TjmPeriodRow> periodes, String currencyCode) {
    if (periodes == null || periodes.size() < 2) {
      return null;
    }
    Decimal lo = null;
    Decimal hi = null;
    for (AR_PTFData.TjmPeriodRow p : periodes) {
      if (p.tjm == null) {
        return null;
      }
      lo = (lo == null || p.tjm < lo) ? p.tjm : lo;
      hi = (hi == null || p.tjm > hi) ? p.tjm : hi;
    }
    return 'de ' + formatNumberFr(lo, 2) + ' à ' + formatNumberFr(hi, 2, currencySymbol(currencyCode)) + '/j';
  }

  private static String groupThousands(String digits) {
    String grouped = '';
    Integer count = 0;
    for (Integer i = digits.length() - 1; i >= 0; i--) {
      grouped = digits.substring(i, i + 1) + grouped;
      count++;
      if (Math.mod(count, 3) == 0 && i != 0) {
        grouped = NBSP + grouped;
      }
    }
    return grouped;
  }
}