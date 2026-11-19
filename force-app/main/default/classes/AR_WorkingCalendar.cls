/**
 * Calendrier ouvré de la régie sans régule (docs/265 §4.1 à §4.3). Classe pure, sans DML ni SOQL :
 * jours ouvrés d'un intervalle selon le pays, mois du plan (jours ouvrés, jours vendus) et répartition
 * équilibrée des jours produits. Miroir de c/arWorkingCalendar (LWC) : mêmes attendus des deux côtés.
 *
 * Les jours vendus sont calculés en centièmes entiers (base × ouvrés ÷ jours du mois, HALF_UP) pour
 * rester identiques au JS, qui ne peut pas diviser sans dérive flottante.
 */
public with sharing class AR_WorkingCalendar {
    /** Un mois du plan. `produits` reste null tant que la répartition n'est pas faite. */
    public class PlanMonth {
        public String m; // yyyy-MM
        public Integer full; // jours ouvrés du mois entier
        public Integer ouvres; // jours ouvrés couverts par la mission dans le mois
        public Decimal vendus;
        public Decimal produits;
    }

    private static final Date MONDAY_REFERENCE = Date.newInstance(2000, 1, 3);

    /** « France » ou « FR », sans casse ni espaces. Tout autre pays, ou aucun : week-ends seuls. */
    public static Boolean isFrance(String country) {
        if (String.isBlank(country)) {
            return false;
        }
        String c = country.trim().toLowerCase();
        return c == 'france' || c == 'fr';
    }

    /** « Belgique », « Belgium », « België », « Belgie » ou « BE », sans casse ni accents ni espaces. */
    public static Boolean isBelgium(String country) {
        if (String.isBlank(country)) {
            return false;
        }
        String c = country.trim().toLowerCase().replaceAll('ë', 'e');
        return c == 'belgique' || c == 'belgium' || c == 'belgie' || c == 'be';
    }

    /** Dimanche de Pâques (algorithme grégorien anonyme, Meeus/Jones/Butcher). */
    public static Date easterSunday(Integer year) {
        Integer a = Math.mod(year, 19);
        Integer b = year / 100;
        Integer c = Math.mod(year, 100);
        Integer d = b / 4;
        Integer e = Math.mod(b, 4);
        Integer f = (b + 8) / 25;
        Integer g = (b - f + 1) / 3;
        Integer h = Math.mod(19 * a + b - d - g + 15, 30);
        Integer i = c / 4;
        Integer k = Math.mod(c, 4);
        Integer l = Math.mod(32 + 2 * e + 2 * i - h - k, 7);
        Integer mm = (a + 11 * h + 22 * l) / 451;
        Integer month = (h + l - 7 * mm + 114) / 31;
        Integer day = Math.mod(h + l - 7 * mm + 114, 31) + 1;
        return Date.newInstance(year, month, day);
    }

    /** Jours fériés France : fixes + lundi de Pâques, Ascension (Pâques + 39), lundi de Pentecôte (Pâques + 50). */
    public static Boolean isFrenchHoliday(Date d) {
        Integer mo = d.month();
        Integer da = d.day();
        if ((mo == 1 && da == 1) || (mo == 5 && (da == 1 || da == 8)) || (mo == 7 && da == 14) || (mo == 8 && da == 15)
            || (mo == 11 && (da == 1 || da == 11)) || (mo == 12 && da == 25)) {
            return true;
        }
        Date easter = easterSunday(d.year());
        return d == easter.addDays(1) || d == easter.addDays(39) || d == easter.addDays(50);
    }

    /** Jours fériés Belgique : fixes + lundi de Pâques, Ascension (Pâques + 39), lundi de Pentecôte (Pâques + 50).
     * Pas de report si un férié tombe un week-end : la Belgique n'applique pas de report (fixé par employeur). */
    public static Boolean isBelgianHoliday(Date d) {
        Integer mo = d.month();
        Integer da = d.day();
        if ((mo == 1 && da == 1) || (mo == 5 && da == 1) || (mo == 7 && da == 21) || (mo == 8 && da == 15)
            || (mo == 11 && (da == 1 || da == 11)) || (mo == 12 && da == 25)) {
            return true;
        }
        Date easter = easterSunday(d.year());
        return d == easter.addDays(1) || d == easter.addDays(39) || d == easter.addDays(50);
    }

    /** Jours fériés selon le pays : route vers isFrenchHoliday ou isBelgianHoliday selon country. */
    public static Boolean isHoliday(Date d, String country) {
        if (isFrance(country)) {
            return isFrenchHoliday(d);
        } else if (isBelgium(country)) {
            return isBelgianHoliday(d);
        }
        return false;
    }

    public static Boolean isWeekend(Date d) {
        Integer dow = Math.mod(MONDAY_REFERENCE.daysBetween(d), 7);
        if (dow < 0) {
            dow += 7;
        }
        return dow >= 5;
    }

    public static Boolean isWorkingDay(Date d, String country) {
        return !isWeekend(d) && !isHoliday(d, country);
    }

    /** Jours ouvrés de `fromDate` à `toDate` inclus ; 0 si l'intervalle est vide ou inversé. */
    public static Integer workingDays(Date fromDate, Date toDate, String country) {
        Integer count = 0;
        if (fromDate == null || toDate == null) {
            return count;
        }
        for (Date d = fromDate; d <= toDate; d = d.addDays(1)) {
            if (!isWeekend(d) && !isHoliday(d, country)) {
                count++;
            }
        }
        return count;
    }

    public static String monthKey(Date d) {
        return String.valueOf(d.year()) + '-' + String.valueOf(d.month()).leftPad(2, '0');
    }

    /** Jours vendus d'un mois : base × ouvrés ÷ jours du mois, 2 décimales HALF_UP (mois complet = base). */
    public static Decimal soldDays(Decimal base, Integer ouvres, Integer full) {
        Decimal baseCents = base.setScale(2, RoundingMode.HALF_UP);
        if (full == null || full <= 0) {
            return 0;
        }
        return (baseCents * ouvres).divide(full, 2, RoundingMode.HALF_UP);
    }

    /** Mois civils touchés par la mission, sans jours produits. Liste vide si une date manque ou si l'intervalle est inversé. */
    public static List<PlanMonth> monthsOf(Date startDate, Date endDate, String country, Decimal base) {
        List<PlanMonth> months = new List<PlanMonth>();
        if (startDate == null || endDate == null || endDate < startDate || base == null) {
            return months;
        }
        Date cursor = startDate.toStartOfMonth();
        while (cursor <= endDate) {
            Date monthEnd = cursor.addMonths(1).addDays(-1);
            Date rangeStart = cursor < startDate ? startDate : cursor;
            Date rangeEnd = monthEnd > endDate ? endDate : monthEnd;
            PlanMonth pm = new PlanMonth();
            pm.m = monthKey(cursor);
            pm.full = workingDays(cursor, monthEnd, country);
            pm.ouvres = workingDays(rangeStart, rangeEnd, country);
            pm.vendus = soldDays(base, pm.ouvres, pm.full);
            months.add(pm);
            cursor = cursor.addMonths(1);
        }
        return months;
    }

    /**
     * Répartition équilibrée (§4.3) : chaque mois reçoit clamp(arrondi(cumul vendu − cumul réparti), 0, ouvrés),
     * en centièmes entiers. Le solde cumulé reste à moins d'un demi-jour de zéro.
     */
    public static void balance(List<PlanMonth> months) {
        Long cumSoldCents = 0;
        Long cumProduced = 0;
        for (PlanMonth pm : months) {
            cumSoldCents += (pm.vendus * 100).setScale(0, RoundingMode.HALF_UP).longValue();
            Long gapCents = cumSoldCents - cumProduced * 100;
            Long rounded = gapCents >= 0 ? (gapCents + 50) / 100 : 0;
            Long produced = Math.min(rounded, (Long) pm.ouvres);
            pm.produits = produced;
            cumProduced += produced;
        }
    }

    /** Σ vendus du plan, en centièmes exacts. */
    public static Decimal totalSold(List<PlanMonth> months) {
        Long cents = 0;
        for (PlanMonth pm : months) {
            cents += (pm.vendus * 100).setScale(0, RoundingMode.HALF_UP).longValue();
        }
        return Decimal.valueOf(cents).divide(100, 2, RoundingMode.HALF_UP);
    }

    public static Decimal totalProduced(List<PlanMonth> months) {
        Decimal total = 0;
        for (PlanMonth pm : months) {
            total += pm.produits == null ? 0 : pm.produits;
        }
        return total;
    }
}