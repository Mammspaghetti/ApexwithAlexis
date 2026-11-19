/**
 * Calendrier ouvré de la régie sans régule (docs/265 §4.1 à §4.3). Miroir de AR_WorkingCalendar (Apex) :
 * mêmes attendus des deux côtés (cas C1, C2, C3 du cadrage). Module pur, sans état ni appel serveur.
 *
 * Les jours vendus et les cumuls sont calculés en centièmes entiers : `18,17 × 10 / 20` vaut 9,085 en
 * flottant et donnerait 9,08 au lieu de 9,09.
 */

const MS_PER_DAY = 86400000;

/** Jour UTC (ms) depuis un jour déjà converti, un objet Date ou une chaîne `AAAA-MM-JJ`, sans effet de fuseau. */
function toUtcDay(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  if (typeof value === "number") {
    return value;
  }
  if (value instanceof Date) {
    return Date.UTC(value.getFullYear(), value.getMonth(), value.getDate());
  }
  const parts = String(value).slice(0, 10).split("-").map(Number);
  if (parts.length !== 3 || parts.some((p) => Number.isNaN(p))) {
    return null;
  }
  return Date.UTC(parts[0], parts[1] - 1, parts[2]);
}

function utcParts(day) {
  const d = new Date(day);
  return { y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, d: d.getUTCDate() };
}

/** « France » ou « FR », sans casse ni espaces. Tout autre pays, ou aucun : week-ends seuls. */
export function isFrance(country) {
  if (country === null || country === undefined) {
    return false;
  }
  const c = String(country).trim().toLowerCase();
  return c === "france" || c === "fr";
}

/** « Belgique », « Belgium », « België », « Belgie » ou « BE », sans casse ni accents ni espaces. */
export function isBelgium(country) {
  if (country === null || country === undefined) {
    return false;
  }
  const c = String(country).trim().toLowerCase().replace("ë", "e");
  return c === "belgique" || c === "belgium" || c === "belgie" || c === "be";
}

/** Dimanche de Pâques (algorithme grégorien anonyme, Meeus/Jones/Butcher), en jour UTC. */
export function easterSunday(year) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const mm = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * mm + 114) / 31);
  const day = ((h + l - 7 * mm + 114) % 31) + 1;
  return Date.UTC(year, month - 1, day);
}

const FRENCH_FIXED = [
  "1-1",
  "5-1",
  "5-8",
  "7-14",
  "8-15",
  "11-1",
  "11-11",
  "12-25"
];

const BELGIAN_FIXED = ["1-1", "5-1", "7-21", "8-15", "11-1", "11-11", "12-25"];

/** Fériés France : fixes + lundi de Pâques, Ascension (Pâques + 39), lundi de Pentecôte (Pâques + 50). */
export function isFrenchHoliday(day) {
  const { y, mo, d } = utcParts(day);
  if (FRENCH_FIXED.includes(`${mo}-${d}`)) {
    return true;
  }
  const easter = easterSunday(y);
  return [1, 39, 50].some((offset) => day === easter + offset * MS_PER_DAY);
}

/** Fériés Belgique : fixes + lundi de Pâques, Ascension (Pâques + 39), lundi de Pentecôte (Pâques + 50).
 * Pas de report si un férié tombe un week-end : la Belgique n'applique pas de report (fixé par employeur). */
export function isBelgianHoliday(day) {
  const { y, mo, d } = utcParts(day);
  if (BELGIAN_FIXED.includes(`${mo}-${d}`)) {
    return true;
  }
  const easter = easterSunday(y);
  return [1, 39, 50].some((offset) => day === easter + offset * MS_PER_DAY);
}

/** Fériés selon le pays : route vers isFrenchHoliday ou isBelgianHoliday selon country. */
export function isHoliday(day, country) {
  if (isFrance(country)) {
    return isFrenchHoliday(day);
  } else if (isBelgium(country)) {
    return isBelgianHoliday(day);
  }
  return false;
}

function isWeekend(day) {
  const dow = new Date(day).getUTCDay(); // 0 dimanche, 6 samedi
  return dow === 0 || dow === 6;
}

/** Jours ouvrés de `from` à `to` inclus ; 0 si l'intervalle est vide ou inversé. */
export function workingDays(from, to, country) {
  const start = toUtcDay(from);
  const end = toUtcDay(to);
  if (start === null || end === null) {
    return 0;
  }
  let count = 0;
  for (let day = start; day <= end; day += MS_PER_DAY) {
    if (!isWeekend(day) && !isHoliday(day, country)) {
      count += 1;
    }
  }
  return count;
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

/** Jours vendus d'un mois : base × ouvrés ÷ jours du mois, 2 décimales HALF_UP (mois complet = base). */
export function soldDays(base, ouvres, full) {
  if (!full || full <= 0) {
    return 0;
  }
  return Math.round((Math.round(Number(base) * 100) * ouvres) / full) / 100;
}

/**
 * Mois civils touchés par la mission : `{ m, full, ouvres, vendus }`. Liste vide si une date manque, si
 * l'intervalle est inversé ou si la base est absente.
 */
export function monthsOf(startDate, endDate, country, base) {
  const start = toUtcDay(startDate);
  const end = toUtcDay(endDate);
  if (start === null || end === null || end < start || !(Number(base) >= 0)) {
    return [];
  }
  const months = [];
  const first = utcParts(start);
  let year = first.y;
  let month = first.mo;
  for (;;) {
    const monthStart = Date.UTC(year, month - 1, 1);
    if (monthStart > end) {
      break;
    }
    const monthEnd = Date.UTC(year, month, 0);
    const full = workingDays(monthStart, monthEnd, country);
    const ouvres = workingDays(
      Math.max(monthStart, start),
      Math.min(monthEnd, end),
      country
    );
    months.push({
      m: `${year}-${pad2(month)}`,
      full,
      ouvres,
      vendus: soldDays(base, ouvres, full)
    });
    month += 1;
    if (month === 13) {
      month = 1;
      year += 1;
    }
  }
  return months;
}

/**
 * Répartition équilibrée (§4.3) : chaque mois reçoit clamp(arrondi(cumul vendu − cumul réparti), 0, ouvrés),
 * en centièmes entiers. Renvoie de nouveaux mois avec `produits` ; le solde cumulé reste à moins d'un
 * demi-jour de zéro.
 */
export function balance(months) {
  let cumSoldCents = 0;
  let cumProduced = 0;
  return months.map((month) => {
    cumSoldCents += Math.round(month.vendus * 100);
    const gapCents = cumSoldCents - cumProduced * 100;
    const rounded = gapCents >= 0 ? Math.floor((gapCents + 50) / 100) : 0;
    const produits = Math.min(rounded, month.ouvres);
    cumProduced += produits;
    return { ...month, produits };
  });
}

/** Σ vendus du plan, en centièmes entiers. */
export function totalSold(months) {
  return (
    months.reduce((sum, month) => sum + Math.round(month.vendus * 100), 0) / 100
  );
}

export function totalProduced(months) {
  return months.reduce((sum, month) => sum + (Number(month.produits) || 0), 0);
}

/** Base par défaut à l'activation : jours travaillés/an ÷ 12, 2 décimales HALF_UP (18,17 pour 218). */
export function defaultDaysPerMonth(workingDaysPerYear) {
  return Math.round((Number(workingDaysPerYear) * 100) / 12) / 100;
}