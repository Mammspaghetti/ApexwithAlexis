/**
 * Calendrier ouvré de la régie sans régule (docs/265 §4). Mêmes attendus que c/arWorkingCalendar (Jest) :
 * cas C1, C2, C3 du cadrage, Pâques 2026 à 2028, mission d'un seul mois partiel, pays vide.
 */
@IsTest
private class AR_WorkingCalendarTest {
    private static List<Integer> ouvresOf(List<AR_WorkingCalendar.PlanMonth> plan) {
        List<Integer> out = new List<Integer>();
        for (AR_WorkingCalendar.PlanMonth pm : plan) {
            out.add(pm.ouvres);
        }
        return out;
    }

    private static List<Integer> produitsOf(List<AR_WorkingCalendar.PlanMonth> plan) {
        List<Integer> out = new List<Integer>();
        for (AR_WorkingCalendar.PlanMonth pm : plan) {
            out.add(pm.produits.intValue());
        }
        return out;
    }

    @IsTest
    static void testEaster_2026_2027_2028() {
        System.assertEquals(Date.newInstance(2026, 4, 5), AR_WorkingCalendar.easterSunday(2026));
        System.assertEquals(Date.newInstance(2027, 3, 28), AR_WorkingCalendar.easterSunday(2027));
        System.assertEquals(Date.newInstance(2028, 4, 16), AR_WorkingCalendar.easterSunday(2028));
    }

    @IsTest
    static void testIsFrance_caseAndSpacesInsensitive_otherCountriesNo() {
        System.assertEquals(true, AR_WorkingCalendar.isFrance(' France '));
        System.assertEquals(true, AR_WorkingCalendar.isFrance('fr'));
        System.assertEquals(false, AR_WorkingCalendar.isFrance('Belgique'));
        System.assertEquals(false, AR_WorkingCalendar.isFrance(''));
        System.assertEquals(false, AR_WorkingCalendar.isFrance(null));
    }

    @IsTest
    static void testIsBelgium_caseAccentAndSpacesInsensitive() {
        System.assertEquals(true, AR_WorkingCalendar.isBelgium('Belgique'));
        System.assertEquals(true, AR_WorkingCalendar.isBelgium('BELGIUM'));
        System.assertEquals(true, AR_WorkingCalendar.isBelgium('België'));
        System.assertEquals(true, AR_WorkingCalendar.isBelgium('belgie'));
        System.assertEquals(true, AR_WorkingCalendar.isBelgium(' BE '));
        System.assertEquals(false, AR_WorkingCalendar.isBelgium('Belgique-sud'));
        System.assertEquals(false, AR_WorkingCalendar.isBelgium(''));
        System.assertEquals(false, AR_WorkingCalendar.isBelgium(null));
        System.assertEquals(false, AR_WorkingCalendar.isBelgium('France'));
    }

    @IsTest
    static void testFrenchHolidays_movableAndFixed() {
        // 2027 : Pâques 28/03 → lundi de Pâques 29/03, Ascension 06/05, lundi de Pentecôte 17/05.
        System.assertEquals(true, AR_WorkingCalendar.isFrenchHoliday(Date.newInstance(2027, 3, 29)));
        System.assertEquals(true, AR_WorkingCalendar.isFrenchHoliday(Date.newInstance(2027, 5, 6)));
        System.assertEquals(true, AR_WorkingCalendar.isFrenchHoliday(Date.newInstance(2027, 5, 17)));
        System.assertEquals(true, AR_WorkingCalendar.isFrenchHoliday(Date.newInstance(2027, 11, 11)));
        System.assertEquals(false, AR_WorkingCalendar.isFrenchHoliday(Date.newInstance(2027, 3, 30)));
    }

    @IsTest
    static void testBelgianHolidays_movableAndFixed() {
        // 2026 : Pâques 05/04 → lundi de Pâques 06/04, Ascension 14/05, lundi de Pentecôte 25/05.
        System.assertEquals(true, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 4, 6))); // Lundi de Pâques
        System.assertEquals(true, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 5, 14))); // Ascension
        System.assertEquals(true, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 5, 25))); // Lundi de Pentecôte
        System.assertEquals(true, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 7, 21))); // Belgian National Day
        System.assertEquals(true, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 1, 1))); // New Year
        System.assertEquals(false, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 5, 8))); // May 8 not BE holiday
        System.assertEquals(false, AR_WorkingCalendar.isBelgianHoliday(Date.newInstance(2026, 7, 14))); // July 14 not BE holiday
    }

    @IsTest
    static void testIsHoliday_2026_fourDates_frenchVsBelgian() {
        // 2026 : 08/05 (vendredi) férié FR, ouvré BE ; 14/07 (mardi) férié FR, ouvré BE ; 21/07 (mardi) férié BE, ouvré FR ; 25/05 (lundi) férié FR et BE.
        System.assertEquals(true, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 8), 'France'), '08/05/2026 is French holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 8), 'Belgium'), '08/05/2026 not Belgian holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 8), 'Spain'), '08/05/2026 not Spanish holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 8), null), '08/05/2026 not holiday without country');

        System.assertEquals(true, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 14), 'France'), '14/07/2026 is French holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 14), 'Belgium'), '14/07/2026 not Belgian holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 14), 'Spain'), '14/07/2026 not Spanish holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 14), null), '14/07/2026 not holiday without country');

        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 21), 'France'), '21/07/2026 not French holiday');
        System.assertEquals(true, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 21), 'Belgium'), '21/07/2026 is Belgian holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 21), 'Spain'), '21/07/2026 not Spanish holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 7, 21), null), '21/07/2026 not holiday without country');

        System.assertEquals(true, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 25), 'France'), '25/05/2026 is French holiday');
        System.assertEquals(true, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 25), 'Belgium'), '25/05/2026 is Belgian holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 25), 'Spain'), '25/05/2026 not Spanish holiday');
        System.assertEquals(false, AR_WorkingCalendar.isHoliday(Date.newInstance(2026, 5, 25), null), '25/05/2026 not holiday without country');
    }

    @IsTest
    static void testWorkingDays_emptyCountry_weekendsOnly() {
        // Mai 2027 : 21 jours ouvrés sans férié, 19 en France (1er et 8 mai tombent un week-end, Ascension et Pentecôte comptent).
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 5, 1), Date.newInstance(2027, 5, 31), ''));
        System.assertEquals(19, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 5, 1), Date.newInstance(2027, 5, 31), 'France'));
        System.assertEquals(0, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 5, 31), Date.newInstance(2027, 5, 1), 'France'));
    }

    @IsTest
    static void testWorkingDays_may2026_frenchVsBelgianVsSpain() {
        // Mai 2026 : 31 jours = 10 jours de week-end (2-3, 9-10, 16-17, 23-24, 30-31), 21 weekdays
        // - France : 1st (Labor Day), 8th (May 8), 14th (Ascension), 25th (Whit Monday) = 21 - 4 = 17 days
        // - Belgium : 1st (Labor Day), 14th (Ascension), 25th (Whit Monday) = 21 - 3 = 18 days
        // - Spain/Empty : 21 days
        System.assertEquals(17, AR_WorkingCalendar.workingDays(Date.newInstance(2026, 5, 1), Date.newInstance(2026, 5, 31), 'France'), 'May 2026 France: 17 working days');
        System.assertEquals(18, AR_WorkingCalendar.workingDays(Date.newInstance(2026, 5, 1), Date.newInstance(2026, 5, 31), 'Belgium'), 'May 2026 Belgium: 18 working days');
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2026, 5, 1), Date.newInstance(2026, 5, 31), 'Spain'), 'May 2026 Spain: 21 working days');
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2026, 5, 1), Date.newInstance(2026, 5, 31), ''), 'May 2026 no country: 21 working days');
    }

    @IsTest
    static void testC1_fullYear2027_france() {
        List<AR_WorkingCalendar.PlanMonth> plan = AR_WorkingCalendar.monthsOf(
            Date.newInstance(2027, 1, 1), Date.newInstance(2027, 12, 31), 'France', 18.17
        );
        AR_WorkingCalendar.balance(plan);
        System.assertEquals(new List<Integer>{ 20, 20, 22, 22, 19, 22, 21, 22, 22, 21, 20, 23 }, ouvresOf(plan));
        System.assertEquals(new List<Integer>{ 18, 18, 19, 18, 18, 18, 18, 18, 19, 18, 18, 18 }, produitsOf(plan));
        System.assertEquals(218.04, AR_WorkingCalendar.totalSold(plan));
        System.assertEquals(218, AR_WorkingCalendar.totalProduced(plan));
    }

    @IsTest
    static void testC2_partialFirstMonth_france() {
        List<AR_WorkingCalendar.PlanMonth> plan = AR_WorkingCalendar.monthsOf(
            Date.newInstance(2027, 2, 15), Date.newInstance(2028, 1, 31), 'France', 18.17
        );
        AR_WorkingCalendar.balance(plan);
        System.assertEquals('2027-02', plan[0].m);
        System.assertEquals(10, plan[0].ouvres);
        System.assertEquals(9.09, plan[0].vendus);
        System.assertEquals(new List<Integer>{ 9, 18, 18, 19, 18, 18, 18, 18, 18, 19, 18, 18 }, produitsOf(plan));
        System.assertEquals(208.96, AR_WorkingCalendar.totalSold(plan));
        System.assertEquals(209, AR_WorkingCalendar.totalProduced(plan));
    }

    @IsTest
    static void testC3_belgium_weekendsOnly() {
        // Belgium Feb 15 2027 - Jan 31 2028 : includes Belgian holidays
        // May 2027 has 3 holidays (Easter Mon 29, Ascension 6, Whit Mon 17) = 22 - 3 = 19 ouvres
        // Nov 2027 has 2 holidays (1st, 11th) = 22 - 2 = 20 ouvres
        // Other months have fixed holidays or holiday-free periods
        List<AR_WorkingCalendar.PlanMonth> plan = AR_WorkingCalendar.monthsOf(
            Date.newInstance(2027, 2, 15), Date.newInstance(2028, 1, 31), 'Belgique', 18.17
        );
        System.assertEquals(new List<Integer>{ 10, 22, 22, 19, 22, 21, 22, 22, 21, 20, 23, 21 }, ouvresOf(plan));
        AR_WorkingCalendar.balance(plan);
        System.assertEquals(208.96, AR_WorkingCalendar.totalSold(plan));
    }

    @IsTest
    static void testBelgianMissionPlan_may_july_2026() {
        // Mission 01/05/2026–31/07/2026 en Belgique
        // May 2026 (18 ouvres): 1st (Labor Day), 14th (Ascension), 25th (Whit Monday)
        // June 2026 (22 ouvres): no Belgian holidays
        // July 2026 (22 ouvres): 21st (Belgian National Day on Tuesday)
        // Total: 62 working days for the full period
        List<AR_WorkingCalendar.PlanMonth> plan = AR_WorkingCalendar.monthsOf(
            Date.newInstance(2026, 5, 1), Date.newInstance(2026, 7, 31), 'Belgium', 18.17
        );
        System.assertEquals(3, plan.size(), 'Should have 3 months');
        System.assertEquals(18, plan[0].ouvres, 'May 2026: 18 working days');
        System.assertEquals(22, plan[1].ouvres, 'June 2026: 22 working days');
        System.assertEquals(22, plan[2].ouvres, 'July 2026: 22 working days');
    }

    @IsTest
    static void testSinglePartialMonth() {
        List<AR_WorkingCalendar.PlanMonth> plan = AR_WorkingCalendar.monthsOf(
            Date.newInstance(2027, 3, 10), Date.newInstance(2027, 3, 19), 'France', 18.17
        );
        AR_WorkingCalendar.balance(plan);
        System.assertEquals(1, plan.size());
        System.assertEquals(22, plan[0].full);
        System.assertEquals(8, plan[0].ouvres);
        System.assertEquals(6.61, plan[0].vendus);
        System.assertEquals(7, plan[0].produits);
    }

    @IsTest
    static void testMonthsOf_missingOrInvertedDates_empty() {
        System.assert(AR_WorkingCalendar.monthsOf(null, Date.newInstance(2027, 12, 31), 'France', 18.17).isEmpty());
        System.assert(AR_WorkingCalendar.monthsOf(Date.newInstance(2027, 12, 31), Date.newInstance(2027, 1, 1), 'France', 18.17).isEmpty());
    }

    // Session 274 : mêmes cas que c/arWorkingCalendar (Jest) pour le comptage unique de l'application.
    @IsTest
    static void testWorkingDays_session274SharedCases() {
        System.assertEquals(20, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 1, 1), Date.newInstance(2027, 1, 31), 'France'));
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 1, 1), Date.newInstance(2027, 1, 31), null), 'Sans fériés');
        System.assertEquals(19, AR_WorkingCalendar.workingDays(Date.newInstance(2027, 5, 1), Date.newInstance(2027, 5, 31), 'France'), 'Ascension 06/05, Pentecôte 17/05');
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2030, 8, 1), Date.newInstance(2030, 8, 31), 'France'), '15/08 un jeudi (holiday)');
        System.assertEquals(21, AR_WorkingCalendar.workingDays(Date.newInstance(2030, 8, 1), Date.newInstance(2030, 8, 31), 'Belgique'), '15/08 un jeudi (holiday for Belgium too)');
        System.assertEquals(22, AR_WorkingCalendar.workingDays(Date.newInstance(2030, 8, 1), Date.newInstance(2030, 8, 31), null), 'No holidays');
    }

    @IsTest
    static void testSoldDays_halfUpAtCents() {
        System.assertEquals(9.09, AR_WorkingCalendar.soldDays(18.17, 10, 20), '18,17 × 10 / 20 = 9,085 → 9,09');
        System.assertEquals(18.17, AR_WorkingCalendar.soldDays(18.17, 22, 22));
    }
}