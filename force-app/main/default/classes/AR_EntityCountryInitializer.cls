/**
 * Session 141 : initialisation ponctuelle de AR_PTF_Entity_Referential__c.AR_Country__c depuis le
 * bloc libre AR_Address__c. Appelée par scripts/apex/141-init-entity-country.apex — jamais par
 * l'application à l'exécution (le pays affiché en matrice est lu sur le champ, pas déduit).
 *
 * Règle prudente : le pays n'est retenu que s'il figure SEUL sur une ligne de l'adresse et correspond
 * à un pays de la liste fermée ci-dessous (mesure du 05/10/2026 : « France », « Belgique »,
 * « Espagne », « Italie », « Luxembourg », « Royaume-Uni » en ligne autonome sur les fiches réelles).
 * Deux pays différents sur deux lignes = ambigu, un nom de pays seulement présent dans une phrase =
 * non lisible : dans les deux cas la fiche reste vide et est listée dans le résultat. Une fiche déjà
 * renseignée n'est jamais écrasée.
 */
public with sharing class AR_EntityCountryInitializer {
  // Clé en minuscules, valeur = libellé écrit dans AR_Country__c.
  private static final Map<String, String> KNOWN_COUNTRIES = new Map<String, String>{
    'france' => 'France',
    'belgique' => 'Belgique',
    'espagne' => 'Espagne',
    'italie' => 'Italie',
    'luxembourg' => 'Luxembourg',
    'royaume-uni' => 'Royaume-Uni',
    'allemagne' => 'Allemagne',
    'suisse' => 'Suisse',
    'canada' => 'Canada',
    'maroc' => 'Maroc',
    'pays-bas' => 'Pays-Bas',
    'portugal' => 'Portugal',
    'irlande' => 'Irlande'
  };

  public class Result {
    public Boolean dryRun;
    // « Nom → Pays » : fiches renseignées (ou qui le seraient en dryRun)
    public List<String> filled = new List<String>();
    // Fiches déjà renseignées, laissées intactes
    public List<String> alreadySet = new List<String>();
    // Fiches avec plusieurs pays différents en ligne autonome : laissées vides
    public List<String> ambiguous = new List<String>();
    // Fiches sans aucun pays lisible en ligne autonome : laissées vides
    public List<String> unreadable = new List<String>();
  }

  /** Pays distincts figurant seuls sur une ligne de l'adresse. */
  private static Set<String> countriesOnOwnLine(String address) {
    Set<String> found = new Set<String>();
    if (String.isNotBlank(address)) {
      for (String line : address.split('\\r?\\n')) {
        String key = line.trim().toLowerCase();
        if (KNOWN_COUNTRIES.containsKey(key)) {
          found.add(KNOWN_COUNTRIES.get(key));
        }
      }
    }
    return found;
  }

  /** Pays lisible sans ambiguïté dans l'adresse, sinon null (adresse vide, aucun pays, ou plusieurs). */
  public static String detectCountry(String address) {
    Set<String> found = countriesOnOwnLine(address);
    return found.size() == 1 ? new List<String>(found)[0] : null;
  }

  public static Result run(Boolean dryRun) {
    Result result = new Result();
    result.dryRun = dryRun == true;
    List<AR_PTF_Entity_Referential__c> toUpdate = new List<AR_PTF_Entity_Referential__c>();
    for (AR_PTF_Entity_Referential__c e : [
      SELECT Id, Name, AR_Address__c, AR_Country__c
      FROM AR_PTF_Entity_Referential__c
      WHERE AR_Active__c = TRUE
      ORDER BY Name
    ]) {
      if (String.isNotBlank(e.AR_Country__c)) {
        result.alreadySet.add(e.Name + ' → ' + e.AR_Country__c);
        continue;
      }
      String country = detectCountry(e.AR_Address__c);
      if (country != null) {
        result.filled.add(e.Name + ' → ' + country);
        toUpdate.add(new AR_PTF_Entity_Referential__c(Id = e.Id, AR_Country__c = country));
      } else if (countriesOnOwnLine(e.AR_Address__c).size() > 1) {
        result.ambiguous.add(e.Name);
      } else {
        result.unreadable.add(e.Name);
      }
    }
    if (!result.dryRun && !toUpdate.isEmpty()) {
      update toUpdate;
    }
    return result;
  }
}