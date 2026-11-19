/**
 * Miroir JS strict de AR_PricingCalculator.cls (Apex), lui-même la reproduction à l'identique de
 * pricing-tool/pricing-tool.html:192-262. Utilisé par arPriceMatrixSimulator pour le calcul temps
 * réel (< 1 s). Le clic « Valider » repasse toujours par Apex (AR_PricingMatrixService.validate) :
 * le serveur fait foi, ce module n'est qu'un aperçu client.
 *
 * Convention Percent (docs/02-modele-de-donnees.md §7.2) : rfaPercent, ThresholdPercents.* et
 * mc2PercentHuman sont en valeur humaine (23.5 = 23,5 %) ; conversion en fraction en interne.
 */

import { workingDays as calendarWorkingDays } from "c/arWorkingCalendar";

export const JOURS_TRAVAIL_DEFAULT = 218;
export const MARKUP_PERCENT_DEFAULT = 18;
export const MARKUP_MAX_DEFAULT = 60;
export const FLOOR_PERCENT_DEFAULT = 20;
export const TARGET_PERCENT_DEFAULT = 25;
export const IDEAL_PERCENT_DEFAULT = 30;

// Miroir de AR_PricingCalculator.CONTRACT_COEFFICIENT_DEFAULT (session 28) : coefficient salaire ->
// CJM pour CDI/CDD, administrable (AR_General_Setting__c), 2,02 si non fourni par l'appelant.
export const CONTRACT_COEFFICIENT_DEFAULT = 2.02;

// Reproduit RoundingMode.HALF_UP d'Apex (arrondi au plus proche, .5 s'éloigne de zéro).
function roundTo(value, decimals) {
  const factor = 10 ** decimals;
  return (
    ((Math.sign(value) || 1) * Math.round(Math.abs(value) * factor)) / factor
  );
}

// Reproduit RoundingMode.CEILING d'Apex / Math.ceil de la maquette (valeurs toujours positives ici).
// Défaut de parité trouvé en session 27 (prompts/session-27-filet-de-tests.md §1) : Apex fait de
// l'arithmétique décimale exacte (`Decimal`), JavaScript des flottants IEEE 754 — `350/0.7` vaut
// exactement 500 côté Apex mais 500.00000000000006 côté JS, et `Math.ceil` arrondissait alors à 501
// au lieu de 500 chaque fois que coûtTotal/dénominateur tombait pile sur un entier. Un seuil affiché
// en aperçu pouvait donc être supérieur d'une unité à celui réellement enregistré par Apex. Corrigé
// en réduisant le bruit de représentation flottante à 6 décimales avant l'arrondi — largement en
// dessous de la précision utile d'un montant en euros, jamais une vraie valeur métier changée.
function ceilToInt(value) {
  return Math.ceil(Math.round(value * 1e6) / 1e6);
}

function num(value, fallback = 0) {
  return value === null || value === undefined || value === ""
    ? fallback
    : Number(value);
}

// Bornage défensif (session 18, miroir de AR_PricingCalculator.nonNegative/nonNegativeOrZero) : un
// salaire/CJM/frais négatif n'a pas de sens métier. `num()` gère déjà le null/undefined → fallback ;
// ceci clampe en plus les valeurs négatives réellement saisies.
function nonNegative(value) {
  return Math.max(0, value);
}

// AR_PricingCalculator.calcCJM — pricing-tool.html:208-213 (CDD ajouté en session 28, même formule
// que CDI avec un coefficient administrable au lieu du littéral 1,01 * 2).
// CDI/CDD : CJM pondéré par les périodes de salaire (identique au CJM de la période 1 sans période).
export function calcCJM(ctx) {
  if (hasSalary(ctx)) {
    return calcSalaryPeriods(ctx).cjmWeighted;
  }
  if (ctx.contractType === "VIE") {
    return ctx.cjmVie === null || ctx.cjmVie === undefined
      ? null
      : nonNegative(Number(ctx.cjmVie));
  }
  if (ctx.contractType === "NEARSHORE") {
    return ctx.cjmNearshore === null || ctx.cjmNearshore === undefined
      ? null
      : nonNegative(Number(ctx.cjmNearshore));
  }
  // INDEP
  return (
    nonNegative(num(ctx.cjmBeforeMarkup)) + nonNegative(num(ctx.markupApplied))
  );
}

// Statuts dont le CJM vient d'un salaire saisi.
export function hasSalary(ctx) {
  return ctx.contractType === "CDI" || ctx.contractType === "CDD";
}

// CJM d'un salaire annuel : salaire × coefficient du contrat ÷ jours travaillés/an, arrondi à l'euro.
function cjmOfSalary(ctx, salary) {
  const days =
    num(ctx.workingDaysPerYear, JOURS_TRAVAIL_DEFAULT) || JOURS_TRAVAIL_DEFAULT;
  const coefficient = num(
    ctx.contractCoefficient,
    CONTRACT_COEFFICIENT_DEFAULT
  );
  return Math.round((nonNegative(num(salary)) * coefficient) / days);
}

// Miroir de AR_PricingCalculator.calcSalaryPeriods : un CJM par période, moyenne pondérée par les jours
// facturables comme le TJM pondéré. Sans période (ou statut sans salaire) : CJM de la période 1.
export function calcSalaryPeriods(ctx) {
  const p1Cjm = cjmOfSalary(ctx, ctx.annualSalary);
  const result = {
    cjmWeighted: p1Cjm,
    periods: [],
    exceedMission: false,
    missionUnknown: false
  };
  const added = Array.isArray(ctx.salaryPeriods) ? ctx.salaryPeriods : [];
  if (!hasSalary(ctx) || added.length === 0) {
    return result;
  }

  let othersDays = 0;
  let othersNumerator = 0;
  for (const p of added) {
    const days = nonNegative(num(p.days));
    othersDays += days;
    othersNumerator += days * cjmOfSalary(ctx, p.salary);
  }

  const missionDays = calcBillableDays(ctx);
  let p1Days = null;
  if (missionDays > 0) {
    p1Days = Math.max(0, missionDays - othersDays);
    result.exceedMission = othersDays >= missionDays;
    const totalDays = p1Days + othersDays;
    if (totalDays > 0) {
      result.cjmWeighted = (p1Days * p1Cjm + othersNumerator) / totalDays;
    }
  } else {
    result.missionUnknown = true;
  }

  result.periods.push({
    index: 1,
    days: p1Days,
    salary: nonNegative(num(ctx.annualSalary)),
    cjm: p1Cjm
  });
  added.forEach((p, i) => {
    result.periods.push({
      index: i + 2,
      days: nonNegative(num(p.days)),
      salary: nonNegative(num(p.salary)),
      cjm: cjmOfSalary(ctx, p.salary)
    });
  });
  return result;
}

// AR_PricingCalculator.calcMarkup — pricing-tool.html:199-206
export function calcMarkup(
  cjmAvantMarkup,
  markupApplique,
  markupPercentSetting,
  markupMaxSetting
) {
  if (cjmAvantMarkup === null || cjmAvantMarkup === undefined) {
    return { markupCalcule: null, markupMismatch: false };
  }
  const pct = num(markupPercentSetting, MARKUP_PERCENT_DEFAULT);
  const max = num(markupMaxSetting, MARKUP_MAX_DEFAULT);
  const raw = roundTo((cjmAvantMarkup * pct) / 100, 2);
  const markupCalcule = raw < max ? raw : roundTo(max, 2);
  const markupMismatch =
    markupApplique !== null &&
    markupApplique !== undefined &&
    roundTo(markupApplique, 0) !== roundTo(markupCalcule, 0);
  return { markupCalcule, markupMismatch };
}

// AR_PricingCalculator.calcFraisOMJour — pricing-tool.html:214-217
export function calcFraisOMJour(ctx) {
  return feeOmPerDayOf(ctx.feeIk, ctx.feeMeals, ctx.feeLodging, ctx.feeOmOther);
}

function feeOmPerDayOf(feeIk, feeMeals, feeLodging, feeOmOther) {
  return (
    nonNegative(num(feeIk)) +
    nonNegative(num(feeMeals)) +
    nonNegative(num(feeLodging)) +
    nonNegative(num(feeOmOther))
  );
}

// Miroir de AR_PricingCalculator.calcFeePeriods (docs/239 §3) : frais OM lissés sur les périodes,
// moyenne pondérée par les jours, numérateurs sommés avant une seule division.
export function calcFeePeriods(ctx) {
  const p1PerDay = calcFraisOMJour(ctx);
  const result = {
    periods: [],
    smoothedPerDay: p1PerDay,
    exceedMission: false,
    missionUnknown: false
  };
  const added = Array.isArray(ctx.feePeriods) ? ctx.feePeriods : [];
  if (added.length === 0) {
    return result;
  }

  let othersDays = 0;
  let othersNumerator = 0;
  for (const p of added) {
    const days = nonNegative(num(p.days));
    othersDays += days;
    othersNumerator +=
      days * feeOmPerDayOf(p.feeIk, p.feeMeals, p.feeLodging, p.feeOmOther);
  }

  const missionDays = calcBillableDays(ctx);
  let p1Days = null;
  if (missionDays > 0) {
    p1Days = Math.max(0, missionDays - othersDays);
    result.exceedMission = othersDays > missionDays;
    const totalDays = p1Days + othersDays;
    if (totalDays > 0) {
      result.smoothedPerDay = (p1Days * p1PerDay + othersNumerator) / totalDays;
    }
  } else {
    result.missionUnknown = true;
  }

  result.periods.push({ index: 1, days: p1Days, perDay: p1PerDay });
  added.forEach((p, i) => {
    result.periods.push({
      index: i + 2,
      days: nonNegative(num(p.days)),
      perDay: feeOmPerDayOf(p.feeIk, p.feeMeals, p.feeLodging, p.feeOmOther)
    });
  });
  return result;
}

// Miroir de AR_PricingCalculator.calcTjmPeriods (docs/254 §3.1-3.3) : TJM moyen pondéré par les jours,
// numérateurs sommés avant une seule division. Sans période : tjm1. Durée inconnue : tjm1 et indicateur.
// Périodes ajoutées ≥ durée : période 1 à 0 jour, indicateur levé. tjm1 vide : pondéré vide, sauf si la
// période 1 n'a aucun jour.
export function calcTjmPeriods(ctx, tjm1) {
  const result = {
    tjmWeighted: isEmpty(tjm1) ? null : tjm1,
    periods: [],
    exceedMission: false,
    missionUnknown: false
  };
  const added = Array.isArray(ctx.tjmPeriods) ? ctx.tjmPeriods : [];
  if (added.length === 0) {
    return result;
  }

  let othersDays = 0;
  let othersNumerator = 0;
  for (const p of added) {
    const days = nonNegative(num(p.days));
    othersDays += days;
    othersNumerator += days * nonNegative(num(p.tjm));
  }

  const missionDays = calcBillableDays(ctx);
  let p1Days = null;
  if (missionDays > 0) {
    p1Days = Math.max(0, missionDays - othersDays);
    result.exceedMission = othersDays >= missionDays;
    const totalDays = p1Days + othersDays;
    if (totalDays > 0 && (p1Days === 0 || !isEmpty(tjm1))) {
      const p1Numerator = p1Days === 0 ? 0 : p1Days * Number(tjm1);
      result.tjmWeighted = (p1Numerator + othersNumerator) / totalDays;
    }
  } else {
    result.missionUnknown = true;
  }

  result.periods.push({
    index: 1,
    days: p1Days,
    tjm: isEmpty(tjm1) ? null : Number(tjm1)
  });
  added.forEach((p, i) => {
    result.periods.push({
      index: i + 2,
      days: nonNegative(num(p.days)),
      tjm: nonNegative(num(p.tjm))
    });
  });
  return result;
}

export function calcFraisOMJourLisse(ctx) {
  return calcFeePeriods(ctx).smoothedPerDay;
}

// Miroir de AR_PricingCalculator.calcBillableDays : jours de mission moins les congés prévus, plancher 0.
// En régie sans régule, les congés sont ignorés (le prévisionnel mensuel porte déjà les absences).
export function calcBillableDays(ctx) {
  const days = nonNegative(num(ctx.missionDays));
  if (!isEmpty(ctx.rplsrRatio)) {
    return days;
  }
  return Math.max(0, days - nonNegative(num(ctx.plannedLeaveDays)));
}

// Diviseur des frais ponctuels : jours facturables si connus, sinon jours travaillés/an.
function calcFeePonctuelsDivisor(ctx) {
  const billableDays = calcBillableDays(ctx);
  if (billableDays > 0) {
    return { days: billableDays, source: "mission" };
  }
  const days =
    num(ctx.workingDaysPerYear, JOURS_TRAVAIL_DEFAULT) || JOURS_TRAVAIL_DEFAULT;
  return { days, source: "year_fallback" };
}

function workingDaysOf(ctx) {
  return (
    num(ctx.workingDaysPerYear, JOURS_TRAVAIL_DEFAULT) || JOURS_TRAVAIL_DEFAULT
  );
}

function feeLine(key, amount, unit, multiplier, divisor, divisorSource) {
  const value = nonNegative(num(amount));
  if (value === 0) {
    return null;
  }
  return {
    key,
    amount: value,
    unit,
    divisor,
    divisorSource,
    perDay: (value * multiplier) / divisor
  };
}

// Taxe OFII proposée dans la matrice : min(taux × salaire mensuel brut, plafond), au centime.
// Le salaire mensuel est le salaire annuel de la matrice ÷ 12 ; le plafond est déjà dans la devise de
// la matrice. Null dès qu'une des trois données manque ou n'est pas strictement positive : jamais de
// montant plausible substitué. Le moteur ne reçoit ensuite que le montant retenu (`feeOfiiTax`).
export function computeOfiiTax(annualSalary, ratePercent, capInMatrixCurrency) {
  const salary = Number(annualSalary);
  const rate = Number(ratePercent);
  const cap = Number(capInMatrixCurrency);
  const present = (v, raw) =>
    raw !== null && raw !== undefined && raw !== "" && v > 0;
  if (
    !present(salary, annualSalary) ||
    !present(rate, ratePercent) ||
    !present(cap, capInMatrixCurrency)
  ) {
    return null;
  }
  return roundTo(Math.min(((salary / 12) * rate) / 100, cap), 2);
}

// AR_PricingCalculator.calcFeeBreakdown — détail par poste des frais ponctuels ramenés au jour, selon
// l'unité de saisie : PC par jour (tel quel) ; téléphone et autres frais mensuels par mois (× 12 ÷ jours travaillés/an) ;
// formation, EPI et autre par mission (÷ jours de mission, repli sur jours travaillés/an) ; taxe OFII
// par an (÷ jours travaillés/an, jamais la durée de la mission). La gratuité n'en fait pas partie.
export function calcFeeBreakdown(ctx) {
  const workingDays = workingDaysOf(ctx);
  const mission = calcFeePonctuelsDivisor(ctx);
  const missionSource =
    mission.source === "mission" ? "mission" : "working_days";
  return [
    feeLine("feeComputer", ctx.feeComputer, "day", 1, 1, null),
    feeLine("feePhone", ctx.feePhone, "month", 12, workingDays, "working_days"),
    feeLine(
      "feeMonthlyOther",
      ctx.feeMonthlyOther,
      "month",
      12,
      workingDays,
      "working_days"
    ),
    feeLine(
      "feeTraining",
      ctx.feeTraining,
      "mission",
      1,
      mission.days,
      missionSource
    ),
    feeLine("feeEpi", ctx.feeEpi, "mission", 1, mission.days, missionSource),
    feeLine(
      "feeOfiiTax",
      ctx.feeOfiiTax,
      "year",
      1,
      workingDays,
      "working_days"
    ),
    feeLine("feeOther", ctx.feeOther, "mission", 1, mission.days, missionSource)
  ].filter(Boolean);
}

// AR_PricingCalculator.calcFraisPonctuelsJour — pricing-tool.html:218-224 (gratuité = jours × CJM)
// La gratuité est ramenée au jour par les jours de mission (repli jours travaillés/an) ; chaque autre
// poste par sa propre unité (cf. calcFeeBreakdown). Les numérateurs qui partagent un même diviseur
// sont additionnés avant la division, comme côté Apex.
export function calcFraisPonctuelsJour(ctx, cjm) {
  const divisor = calcFeePonctuelsDivisor(ctx);
  const numeratorByDivisor = new Map();
  const add = (days, numerator) =>
    numeratorByDivisor.set(
      days,
      (numeratorByDivisor.get(days) || 0) + numerator
    );
  add(divisor.days, nonNegative(num(ctx.gratuityDays)) * nonNegative(num(cjm)));
  calcFeeBreakdown(ctx).forEach((line) =>
    add(line.divisor, line.unit === "month" ? line.amount * 12 : line.amount)
  );
  let total = 0;
  numeratorByDivisor.forEach((numerator, days) => {
    total += numerator / days;
  });
  return total;
}

// AR_PricingCalculator.calcTotalDailyCost — pricing-tool.html:225-231
// CDI/CDD/VIE : CJM + fraisOM + fraisPonctuels ; INDEP/NEARSHORE : CJM + gratuité×CJM/joursMission
// Session 121 : gratuité divisée par jours de mission si connus, sinon jours travaillés/an.
export function calcTotalDailyCost(ctx) {
  const cjm = calcCJM(ctx);
  if (
    ctx.contractType === "CDI" ||
    ctx.contractType === "CDD" ||
    ctx.contractType === "VIE"
  ) {
    return (
      num(cjm) + calcFraisOMJourLisse(ctx) + calcFraisPonctuelsJour(ctx, cjm)
    );
  }
  const divisor = calcFeePonctuelsDivisor(ctx);
  const gratuite = nonNegative(num(ctx.gratuityDays)) * num(cjm);
  return num(cjm) + gratuite / divisor.days;
}

function isPonctuelsContract(ctx) {
  return (
    ctx.contractType === "CDI" ||
    ctx.contractType === "CDD" ||
    ctx.contractType === "VIE"
  );
}

function defaultThresholdPercents() {
  return {
    floorPercent: FLOOR_PERCENT_DEFAULT,
    targetPercent: TARGET_PERCENT_DEFAULT,
    idealPercent: IDEAL_PERCENT_DEFAULT
  };
}

// Robustesse (session 18, miroir de AR_PricingCalculator.MIN_THRESHOLD_DENOMINATOR) : RFA hors
// bornes (>100%, ou RFA + palier = 100% pile) fait chuter ce dénominateur à 0 ou en dessous —
// division par zéro ou seuil négatif absurde. Les bornes UI empêchent ce cas depuis les champs, pas
// un appel direct à ce module.
const MIN_THRESHOLD_DENOMINATOR = 0.01;

function boundedDenominator(value) {
  return Math.max(MIN_THRESHOLD_DENOMINATOR, value);
}

// AR_PricingCalculator.calcThresholds — pricing-tool.html:232-242 (TJM_x = coût / (1 - %RFA - x))
// Session 126 : add zeroMarginValue (TJM at 0% margin = coût / (1 - %RFA))
export function calcThresholds(
  coutTotal,
  rfaPercent,
  top10Comparables,
  customPcts
) {
  const pcts = customPcts || defaultThresholdPercents();
  const rfa = num(rfaPercent) / 100;
  const fp = pcts.floorPercent / 100;
  const tp = pcts.targetPercent / 100;
  const ip = pcts.idealPercent / 100;

  const zeroMarginValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa));
  const floorValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - fp));
  const targetValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - tp));
  const idealValue = ceilToInt(coutTotal / boundedDenominator(1 - rfa - ip));
  const top10FromIdeal = ceilToInt(idealValue * 1.1);
  const top10Ai = num(top10Comparables);
  const top10Value = top10Ai > top10FromIdeal ? top10Ai : top10FromIdeal;

  return { floorValue, targetValue, idealValue, top10Value, zeroMarginValue };
}

// AR_PricingCalculator.calcMC2 — pricing-tool.html:243-248
// Robustesse (session 18b) : `!tjm` ne filtrait que null/0 — un TJM négatif (saisissable avant
// l'ajout de `min="0"` sur le champ, ou envoyé hors bornes directement) passait ce garde-fou et
// produisait mc2PercentFraction = mc2Jour/tjm = négatif/négatif = un pourcentage positif absurde
// (ex. TJM -100, coût 447 → mc2Jour -547, mc2% = 547 % — lu comme une marge excellente).
export function calcMC2(tjm, coutTotal, rfaPercent) {
  if (!tjm || tjm < 0) {
    return { mc2PerDay: 0, mc2PercentFraction: 0 };
  }
  const rfa = num(rfaPercent) / 100;
  const mc2Jour = tjm * (1 - rfa) - num(coutTotal);
  return { mc2PerDay: roundTo(mc2Jour, 1), mc2PercentFraction: mc2Jour / tjm };
}

// AR_PricingCalculator.getCorridorSegment — pricing-tool.html:249-258
export function getCorridorSegment(mc2PercentFraction, customPcts) {
  const pcts = customPcts || defaultThresholdPercents();
  const p = num(mc2PercentFraction) * 100;
  if (p < pcts.floorPercent) {
    return "below_floor";
  }
  if (p < pcts.targetPercent) {
    return "low_margin";
  }
  if (p < pcts.idealPercent) {
    return "recommended";
  }
  return "superstar";
}

/**
 * MC2 et segment d'un TJM donné pour un coût total déjà calculé : les mêmes appels que `compute`
 * (calcMC2 puis getCorridorSegment, `mc2PercentHuman` arrondi comme lui). Sert aux prix de négociation
 * indicatifs, qui ne passent pas par le reste du calcul.
 */
export function calcMc2ForTjm(tjm, totalDailyCost, rfaPercent, customPcts) {
  const mc2 = calcMC2(tjm, totalDailyCost, rfaPercent);
  return {
    mc2PerDay: mc2.mc2PerDay,
    mc2PercentHuman: roundTo(mc2.mc2PercentFraction * 100, 2),
    corridorSegment: getCorridorSegment(mc2.mc2PercentFraction, customPcts)
  };
}

/**
 * Résout le taux vers EUR d'une devise depuis la liste retournée par
 * AR_CurrencyRateService.getCurrentRates() (déjà résolue « à la date du jour » côté serveur — ce
 * miroir n'a pas de logique d'historique à reproduire, juste un lookup). EUR est la devise pivot
 * elle-même : taux 1 sans lookup. Une devise absente de `currentRates` (aucun taux en base) renvoie
 * `null` — au LWC de traiter ce cas comme un blocage de saisie, même garde-fou que le serveur
 * (AR_CurrencyRateService.NoRateAvailableException).
 */
export function resolveRateToEur(currencyCode, currentRates) {
  if (!currencyCode || currencyCode === "EUR") {
    return { rateToEur: 1, effectiveDate: null };
  }
  const found = (currentRates || []).find(
    (r) => r.currencyCode === currencyCode
  );
  if (!found) {
    return null;
  }
  return {
    rateToEur: Number(found.rateToEur),
    effectiveDate: found.effectiveDate
  };
}

// AR_PricingCalculator.compute — orchestrateur du pipeline complet, miroir du résultat AR_PricingResult
// rateToEur (session 24) : taux déjà résolu par l'appelant (resolveRateToEur ci-dessus), jamais
// recalculé ici. Sert uniquement aux équivalents pivot EUR (comparaison/consolidation, session
// 24b) — le calcul natif reste intégralement dans la devise de la matrice (CLAUDE.md).
export function compute(
  ctx,
  rfaPercent,
  proposedTjm,
  top10Comparables,
  customPcts,
  rateToEur = 1
) {
  const cjm = calcCJM(ctx);
  const salary = hasSalary(ctx) ? calcSalaryPeriods(ctx) : null;

  // Miroir de AR_PricingCalculator.compute() (session 28) : coefficient CDI/CDD figé, null pour les
  // autres statuts de contrat.
  const contractCoefficientApplied =
    ctx.contractType === "CDI" || ctx.contractType === "CDD"
      ? num(ctx.contractCoefficient, CONTRACT_COEFFICIENT_DEFAULT)
      : null;

  // Miroir de AR_PricingCalculator.compute() (session 48) : jours travaillés/an figés, jamais null
  // (tous les statuts de contrat en dépendent, contrairement au coefficient ci-dessus).
  const workingDaysPerYearApplied =
    num(ctx.workingDaysPerYear, JOURS_TRAVAIL_DEFAULT) || JOURS_TRAVAIL_DEFAULT;

  let markupCalcule = null;
  let markupMismatch = false;
  if (ctx.contractType === "INDEP") {
    const markup = calcMarkup(
      ctx.cjmBeforeMarkup,
      ctx.markupApplied,
      ctx.markupPercentSetting,
      ctx.markupMaxSetting
    );
    markupCalcule = markup.markupCalcule;
    markupMismatch = markup.markupMismatch;
  }

  const feePeriods = calcFeePeriods(ctx);
  const feeOmPerDay = feePeriods.smoothedPerDay;
  const feePonctuelsPerDay = calcFraisPonctuelsJour(ctx, cjm);
  const totalDailyCost = calcTotalDailyCost(ctx);

  // Session 121 : enregistre le divisor des frais ponctuels pour affichage du contexte (durée).
  const divisor = calcFeePonctuelsDivisor(ctx);

  // Régie sans régule (miroir de AR_PricingCalculator.compute, docs/265 §4.4) : le coût par jour vendu est le
  // coût unitaire × ratio de production ; mode éteint (ratio absent), rien ne change. Un ratio de 0 (aucun jour
  // produit) est une vraie valeur, calculée telle quelle.
  const rplsrActive = !isEmpty(ctx.rplsrRatio);
  const rplsrRatio = rplsrActive ? Number(ctx.rplsrRatio) : null;
  const totalDailyCostPiloted = rplsrActive
    ? totalDailyCost * rplsrRatio
    : null;
  const costForMargin = rplsrActive ? totalDailyCostPiloted : totalDailyCost;

  const thresholds = calcThresholds(
    costForMargin,
    rfaPercent,
    top10Comparables,
    customPcts
  );
  // TJM pondéré (miroir de AR_PricingCalculator.compute, docs/254 §3.5) : MC2 et équivalent EUR en partent.
  const tjm = calcTjmPeriods(ctx, proposedTjm);
  const mc2 = calcMC2(tjm.tjmWeighted, costForMargin, rfaPercent);
  // Valeurs du mode éteint, pour l'affichage barré et le repère fantôme de la jauge.
  const theoretical = rplsrActive
    ? calcMC2(tjm.tjmWeighted, totalDailyCost, rfaPercent)
    : null;
  const corridorSegment = getCorridorSegment(
    mc2.mc2PercentFraction,
    customPcts
  );

  const currencyRateApplied = num(rateToEur, 1) || 1;
  const totalDailyCostEurEquivalent = roundTo(
    totalDailyCost * currencyRateApplied,
    2
  );
  const mc2PerDayEurEquivalent = roundTo(
    mc2.mc2PerDay * currencyRateApplied,
    2
  );
  const tjmEurEquivalent = isEmpty(tjm.tjmWeighted)
    ? null
    : roundTo(tjm.tjmWeighted * currencyRateApplied, 2);

  return {
    cjm,
    salaryPeriods: salary ? salary.periods : [],
    salaryPeriodsExceedMission: salary ? salary.exceedMission : false,
    salaryPeriodsMissionUnknown: salary ? salary.missionUnknown : false,
    markupCalcule,
    markupMismatch,
    feeOmPerDay,
    feeOmPeriods: feePeriods.periods,
    feePeriodsExceedMission: feePeriods.exceedMission,
    feePeriodsMissionUnknown: feePeriods.missionUnknown,
    tjmWeighted: tjm.tjmWeighted,
    tjmPeriods: tjm.periods,
    tjmPeriodsExceedMission: tjm.exceedMission,
    tjmPeriodsMissionUnknown: tjm.missionUnknown,
    feePonctuelsPerDay,
    totalDailyCost,
    rplsrRatio,
    totalDailyCostPiloted,
    mc2PerDayTheoretical: theoretical ? theoretical.mc2PerDay : null,
    mc2PercentTheoretical: theoretical
      ? roundTo(theoretical.mc2PercentFraction * 100, 2)
      : null,
    tjmFloor: thresholds.floorValue,
    tjmTarget: thresholds.targetValue,
    tjmIdeal: thresholds.idealValue,
    tjmTop10: thresholds.top10Value,
    tjmZeroMargin: thresholds.zeroMarginValue,
    mc2PerDay: mc2.mc2PerDay,
    mc2PercentHuman: roundTo(mc2.mc2PercentFraction * 100, 2),
    corridorSegment,
    contractCoefficientApplied,
    workingDaysPerYearApplied,
    currencyRateApplied,
    tjmEurEquivalent,
    totalDailyCostEurEquivalent,
    mc2PerDayEurEquivalent,
    feePonctuelsDivisorDays: divisor.days,
    feePonctuelsDivisorSource: divisor.source,
    feeBreakdown: isPonctuelsContract(ctx) ? calcFeeBreakdown(ctx) : []
  };
}

const FR_MONEY_FORMATTER = new Intl.NumberFormat("fr-FR", {
  maximumFractionDigits: 0
});
const FR_MONEY_PRECISE_FORMATTER = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});
const FR_MONEY_ONE_DECIMAL_FORMATTER = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1
});
const FR_PERCENT_FORMATTER = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1
});

function isEmpty(value) {
  return (
    value === null ||
    value === undefined ||
    value === "" ||
    Number.isNaN(Number(value))
  );
}

// Symboles/codes affichés après le montant (convention FR conservée pour toutes les devises,
// session 24 — cf. docs/24-multidevise.md : "800,00 £", pas "£800.00"). EUR/GBP ont un symbole
// à un caractère reconnu sans ambiguïté ; CHF/CAD/MAD gardent le code ISO plutôt qu'un symbole
// inventé (ex. "$" pour CAD serait confondu avec l'USD) — choix cosmétique documenté, pas une
// règle métier, ajustable sans impact sur les montants ou les calculs.
const CURRENCY_SYMBOLS = {
  EUR: "€",
  GBP: "£",
  CHF: "CHF",
  CAD: "CAD",
  MAD: "MAD"
};

function currencySuffix(currencyCode) {
  return CURRENCY_SYMBOLS[currencyCode] || currencyCode || "€";
}

/** Symbole affiché pour une devise (€, £, CHF…), pour les libellés de champ « Repas (€/jour) ». */
export function currencySymbol(currencyCode) {
  return currencySuffix(currencyCode);
}

/**
 * Format monétaire FR (espace milliers, 0 décimale, signe − propre) — utilitaire unique pour tous
 * les montants affichés dans l'app (session 8, revue UX : le bug visible était un float JS brut
 * du type « −20.233463035019454 % » affiché sans arrondi ni séparateur).
 * `currencyCode` (session 24) : optionnel, défaut EUR — un appelant qui ne connaît pas encore la
 * devise de la matrice (ex. vues multi-matrices non encore câblées, session 24b) garde le
 * comportement exact d'avant cette session, à l'euro près (non-régression).
 */
export function formatMoney(value, currencyCode = "EUR") {
  if (isEmpty(value)) {
    return "—";
  }
  return `${FR_MONEY_FORMATTER.format(Math.round(Number(value)))} ${currencySuffix(currencyCode)}`;
}

/**
 * Format monétaire FR à 2 décimales (session 18b) — pendant de `formatMoney` pour les montants où
 * l'arrondi à l'euro perd l'information utile (mark-up calculé INDEP, gratuité/jour). `formatMoney`
 * reste le bon choix pour tout le reste (TJM, CJM, coûts, seuils) — ne pas remplacer les usages déjà
 * corrects par celui-ci ; ne pas non plus recréer un `toFixed(2)` local à la place de celui-ci.
 */
// Détail des périodes de TJM (docs/254 §11.2) : « TJM moyen pondéré · 650 € · 60 j → 700 € · 60 j ».
// Vide sans évolution (moins de deux périodes) : l'appelant n'affiche alors que le TJM.
export function formatTjmPeriodsDetail(periods, currencyCode, weightedLabel) {
  if (!Array.isArray(periods) || periods.length < 2) {
    return "";
  }
  const parts = periods.map(
    (p) => `${formatMoney(p.tjm, currencyCode)} · ${p.days ?? "?"} j`
  );
  return `${weightedLabel} · ${parts.join(" → ")}`;
}

export function formatMoneyPrecise(value, currencyCode = "EUR") {
  if (isEmpty(value)) {
    return "—";
  }
  return `${FR_MONEY_PRECISE_FORMATTER.format(Number(value))} ${currencySuffix(currencyCode)}`;
}

/** Format coefficient FR (virgule, 2 décimales : « 1,80 », « 2,02 ») — session 182. */
export function formatCoefficient(value) {
  if (isEmpty(value)) {
    return "—";
  }
  return FR_MONEY_PRECISE_FORMATTER.format(Number(value));
}

/** Format pourcentage FR (virgule, 1 décimale) — pendant de formatMoney pour les %. */
export function formatPercent(value) {
  if (isEmpty(value)) {
    return "—";
  }
  return `${FR_PERCENT_FORMATTER.format(Number(value))} %`;
}

/**
 * Décomposition montant avec une décimale alignée (session 150).
 * Retourne { intPart, decPart, hasDecimal, sign, symbol } pour un rendu en deux spans.
 */
export function formatMoneyWithDecimalBreakdown(value, currencyCode = "EUR") {
  if (isEmpty(value)) {
    return {
      intPart: "—",
      decPart: "",
      hasDecimal: false,
      sign: "",
      symbol: currencySuffix(currencyCode)
    };
  }
  const numValue = Number(value);
  const sign = numValue < 0 ? "- " : "";
  const absValue = Math.abs(numValue);
  const rounded = roundTo(absValue, 1);
  const formattedFull = FR_MONEY_ONE_DECIMAL_FORMATTER.format(rounded);
  const parts = formattedFull.split(",");
  const intPart = parts[0];
  const decPart = parts[1] || "0";
  const hasDecimal = Number(decPart) !== 0;
  return {
    intPart: `${sign}${intPart}`,
    decPart: `,${decPart}`,
    hasDecimal,
    sign,
    symbol: currencySuffix(currencyCode)
  };
}

// Marges de l'échelle de la jauge. Session 126 : min = zeroMarginValue (coût de revient, 0% marge),
// max = top10 + span × 0,15. Les anciennes constantes sont inutilisées.
const GAUGE_SCALE_RIGHT_MARGIN_RATIO = 0.15;

// Marge gauche de repli (session 18d) quand le coût de revient n'est pas fourni (cf. computeGaugeScale).
const GAUGE_SCALE_LEFT_SPAN_RATIO = 0.25;
const GAUGE_SCALE_LEFT_FLOOR_RATIO = 0.17;

/**
 * Calcule les bornes [min, max] de l'échelle de la jauge — factorisé pour que `calcGaugePosition`
 * et `isGaugePositionOutOfScale` (session 18d) partagent exactement le même calcul, jamais deux
 * échelles qui divergent silencieusement. Session 126 : min = zeroMarginValue.
 */
function computeGaugeScale(thresholds) {
  const zeroMargin = num(thresholds.zeroMarginValue);
  const ceiling = num(thresholds.top10Value);
  const floor = num(thresholds.floorValue);
  const span = ceiling - floor;

  if (span > 0) {
    // Session 126 : bord gauche = coût de revient (0 % de marge). Repli (126b) si l'appelant ne
    // fournit pas zeroMarginValue ou s'il est incohérent (≥ plancher) : ancienne marge gauche 18d,
    // plutôt qu'une échelle démarrant à 0 € qui gonflerait la zone rouge.
    const min =
      zeroMargin > 0 && zeroMargin < floor
        ? zeroMargin
        : floor -
          Math.max(
            span * GAUGE_SCALE_LEFT_SPAN_RATIO,
            floor * GAUGE_SCALE_LEFT_FLOOR_RATIO
          );
    return {
      min,
      max: ceiling + span * GAUGE_SCALE_RIGHT_MARGIN_RATIO
    };
  }
  // Seuils dégénérés (span nul ou négatif — coût non calculable, ou palier mal configuré) : une
  // marge proportionnelle à un span nul/négatif n'a pas de sens. Marge absolue à la place, pour ne
  // jamais renvoyer NaN ni une échelle inversée — `recompute()` appelle `calcGaugePosition` sans
  // condition, y compris quand la jauge elle-même est masquée (`isCostCalculable` faux).
  const fallbackMargin = Math.max(Math.abs(floor) * 0.1, 1);
  return { min: floor - fallbackMargin, max: ceiling + fallbackMargin };
}

/**
 * Position du curseur « Actuel » (et de chaque graduation, session 18c/18d) sur la jauge corridor,
 * bornée [0, 100] — un TJM hors échelle est visuellement écrasé au bord, cf.
 * `isGaugePositionOutOfScale` pour le distinguer d'une position réelle au bord.
 *
 * Historique de l'échelle (docs/18c-echelle-jauge.md, docs/18d-marge-gauche-jauge.md) : les marges
 * étaient d'abord proportionnelles aux bornes elles-mêmes (avant 18c), puis au corridor entier des
 * deux côtés (18c) — ce qui recentrait bien le corridor sur la piste, mais la marge gauche
 * (span × 0,25) valait alors ~25% du plancher, écrasant à 0% tout TJM à plus de ~6% sous le
 * plancher. La marge gauche est maintenant dissociée du span (session 18d, cf.
 * `GAUGE_SCALE_LEFT_FLOOR_RATIO`) ; la marge droite reste inchangée.
 */
export function calcGaugePosition(tjm, thresholds) {
  const { min, max } = computeGaugeScale(thresholds);
  if (max === min) {
    return 0;
  }
  const position = ((num(tjm) - min) / (max - min)) * 100;
  return Math.max(0, Math.min(100, position));
}

/**
 * Un TJM hors de l'échelle [min, max] (session 18d) : `calcGaugePosition` le borne à 0/100 comme
 * n'importe quel affichage de jauge, mais un curseur au bord peut alors être confondu avec une
 * position réelle au bord de l'échelle — même défaut de principe que les affichages faux corrigés
 * en sessions 15/16 (un chiffre qui a l'air correct mais ne l'est pas). L'appelant (LWC) utilise ce
 * signal pour distinguer visuellement les deux cas plutôt que d'épingler silencieusement.
 */
export function isGaugePositionOutOfScale(tjm, thresholds) {
  const { min, max } = computeGaugeScale(thresholds);
  if (max === min) {
    return false;
  }
  const value = num(tjm);
  return value < min || value > max;
}

/**
 * calcJoursOuvres — pricing-tool.html:183-190 (Zone 1, session 17). Compte inclusif des jours
 * ouvrés entre deux dates ISO (yyyy-mm-dd). Session 274 : délègue au calendrier unique
 * c/arWorkingCalendar (week-ends + jours fériés France selon le pays de l'entité PTF ; sans pays ou
 * hors France : week-ends seuls), miroir de AR_WorkingCalendar.workingDays. Retourne 0 si une date
 * manque ou si fin < début — c'est l'appelant (arPriceMatrixSimulator) qui distingue ce cas d'une
 * vraie erreur de saisie à signaler.
 */
export function calcBusinessDays(startDate, endDate, country) {
  if (!startDate || !endDate) {
    return 0;
  }
  return calendarWorkingDays(startDate, endDate, country);
}