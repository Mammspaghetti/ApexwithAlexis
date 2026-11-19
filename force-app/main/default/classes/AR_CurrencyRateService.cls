/**
 * Résolution du taux de change applicable, depuis la table de conversion AR_Currency_Rate__c
 * (session 23) — socle multi-devises (session 24, réunion du 10/08/2026). `with sharing` : la
 * lecture des taux n'a pas besoin de contourner le partage, l'objet est en visibilité Public.
 *
 * Principe de calcul (CLAUDE.md) : le calcul se fait intégralement dans la devise de la matrice,
 * jamais en la convertissant. Ce service ne sert donc jamais le calcul lui-même — seulement le gel
 * du taux et les équivalents pivot EUR (comparaison/consolidation, session 24b), figés une fois
 * pour toutes sur AR_Price_Matrix__c par AR_PricingMatrixService.
 *
 * Date de résolution (arbitrage provisoire du 18/08/2026, à confirmer avec Matthieu — cf.
 * docs/24-multidevise.md) : date de décision. Tant que la matrice reste éditable (Brouillon, En
 * dérogation), AR_PricingMatrixService.calculateAndPopulate rappelle resolveRate(devise,
 * Date.today()) à chaque sauvegarde — même principe que le corridor (AR_Floor_Percent_Applied__c,
 * session 23b) : la valeur affichée suit le taux courant jusqu'à la décision, puis se fige
 * définitivement dès que le statut quitte ces deux états (AR_PriceMatrixTriggerHandler verrouille
 * la matrice, plus aucun recalcul n'est possible).
 */
public with sharing class AR_CurrencyRateService {
    public class RateResolution {
        public Decimal rateToEur;
        public Date effectiveDate;
    }

    /**
     * Une devise sans taux ne doit jamais être traitée comme un taux de 1 (erreur de facteur 1 à
     * 12 sur le dirham, invisible à l'écran) : bloque bruyamment plutôt que de retomber sur une
     * valeur par défaut. Message actionnable, affiché tel quel côté LWC (cf. AR_PricingMatrixService).
     */
    public class NoRateAvailableException extends Exception {
    }

    /**
     * EUR est la devise pivot elle-même : pas de ligne de taux, taux 1, pas de date d'effet.
     * Pour toute autre devise, résout la ligne AR_Currency_Rate__c la plus récente dont la date
     * d'effet est antérieure ou égale à referenceDate (tranche entre les lignes en la bornant à
     * une date dans le passé ou aujourd'hui — une ligne future n'est jamais appliquée par
     * anticipation).
     */
    public static RateResolution resolveRate(String currencyCode, Date referenceDate) {
        RateResolution result = new RateResolution();
        if (String.isBlank(currencyCode) || currencyCode == 'EUR') {
            result.rateToEur = 1;
            result.effectiveDate = null;
            return result;
        }

        Date effectiveReferenceDate = referenceDate != null ? referenceDate : Date.today();
        List<AR_Currency_Rate__c> rows = [
            SELECT AR_Rate_To_EUR__c, AR_Effective_Date__c
            FROM AR_Currency_Rate__c
            WHERE AR_Currency_Code__c = :currencyCode AND AR_Effective_Date__c <= :effectiveReferenceDate
            ORDER BY AR_Effective_Date__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new NoRateAvailableException(
                AR_I18n.format(Label.AR_Msg_CUR_NoRate, new List<Object>{ currencyCode, effectiveReferenceDate.format() })
            );
        }
        result.rateToEur = rows[0].AR_Rate_To_EUR__c;
        result.effectiveDate = rows[0].AR_Effective_Date__c;
        return result;
    }

    /** Devises non-EUR gérées par la table de conversion — reprend AR_Currency_Rate__c.AR_Currency_Code__c. */
    public static final List<String> NON_EUR_CURRENCIES = new List<String>{ 'GBP', 'CHF', 'CAD', 'MAD' };

    public class CurrentRateDto {
        @AuraEnabled
        public String currencyCode;
        @AuraEnabled
        public Decimal rateToEur;
        @AuraEnabled
        public Date effectiveDate;
    }

    /**
     * Taux courants (résolus à la date du jour) des devises non-EUR, pour le calcul temps réel
     * côté LWC (arPriceMatrixSimulator / arPricingEngine) — une devise absente de la liste retournée
     * signale une devise sans taux, à traiter côté client comme un blocage de saisie (même garde-fou
     * que le serveur, cf. AR_PricingMatrixService.calculateAndPopulate). `cacheable=true` : les taux
     * changent rarement (mise à jour manuelle), cohérent avec getAccountCorridorPercents.
     */
    @AuraEnabled(cacheable=true)
    public static List<CurrentRateDto> getCurrentRates() {
        List<CurrentRateDto> results = new List<CurrentRateDto>();
        for (String code : NON_EUR_CURRENCIES) {
            try {
                RateResolution resolved = resolveRate(code, Date.today());
                CurrentRateDto dto = new CurrentRateDto();
                dto.currencyCode = code;
                dto.rateToEur = resolved.rateToEur;
                dto.effectiveDate = resolved.effectiveDate;
                results.add(dto);
            } catch (NoRateAvailableException e) {
                // Omis volontairement : l'absence de la devise dans la liste EST le signal côté client.
            }
        }
        return results;
    }
}