/**
 * Producteur ALGORITHMIQUE des arguments de vente (session 28, spec §5.1/§6.4). Aucun appel modèle
 * de langage : chaque argument est une phrase gabarit remplie avec des données déjà calculées
 * (arPricingEngine, AR_ComparablesService). C'est la frontière volontairement posée pour la phase 4
 * (CLAUDE.md : pas de LLM dans le lot 1) — `arSalesArgumentsPanel` ne connaît que la forme
 * `{ key, text }` d'un argument, jamais comment il a été produit. Remplacer ce module par un appel à
 * un LLM en phase 4 ne devrait toucher ni le panneau ni son contrat d'entrée.
 *
 * Règle de conception (prompt de session) : aucun argument ne s'affiche si la donnée manque — un
 * argument sans chiffre vérifiable est une opinion, pas un fait. `unavailableNotes` porte les raisons
 * explicites de ce qui manque, pour ne jamais laisser un panneau creux sans explication.
 */
import { formatMoney, formatPercent } from "c/arPricingEngine";
import { formatLabel } from "c/arI18n";
import LBL_AR_SAE_Above from "@salesforce/label/c.AR_SAE_Above";
import LBL_AR_SAE_Below from "@salesforce/label/c.AR_SAE_Below";
import LBL_AR_SAE_CorridorDetail from "@salesforce/label/c.AR_SAE_CorridorDetail";
import LBL_AR_SAE_MarginGenerated from "@salesforce/label/c.AR_SAE_MarginGenerated";
import LBL_AR_SAE_MarginNotComputable from "@salesforce/label/c.AR_SAE_MarginNotComputable";
import LBL_AR_SAE_MarketInsufficientHistory from "@salesforce/label/c.AR_SAE_MarketInsufficientHistory";
import LBL_AR_SAE_MarketNoData from "@salesforce/label/c.AR_SAE_MarketNoData";
import LBL_AR_SAE_MarketNotComparableCurrency from "@salesforce/label/c.AR_SAE_MarketNotComparableCurrency";
import LBL_AR_SAE_MarketVolumeMany from "@salesforce/label/c.AR_SAE_MarketVolumeMany";
import LBL_AR_SAE_MarketVolumeOne from "@salesforce/label/c.AR_SAE_MarketVolumeOne";
import LBL_AR_SAE_RfaApplied from "@salesforce/label/c.AR_SAE_RfaApplied";
import LBL_AR_SAE_SegBelowFloor from "@salesforce/label/c.AR_SAE_SegBelowFloor";
import LBL_AR_SAE_SegLowMargin from "@salesforce/label/c.AR_SAE_SegLowMargin";
import LBL_AR_SAE_SegRecommended from "@salesforce/label/c.AR_SAE_SegRecommended";
import LBL_AR_SAE_SegSuperstar from "@salesforce/label/c.AR_SAE_SegSuperstar";
import LBL_AR_SAE_VsMarket from "@salesforce/label/c.AR_SAE_VsMarket";

const I18N = {
  AR_SAE_Above: LBL_AR_SAE_Above,
  AR_SAE_Below: LBL_AR_SAE_Below,
  AR_SAE_CorridorDetail: LBL_AR_SAE_CorridorDetail,
  AR_SAE_MarginGenerated: LBL_AR_SAE_MarginGenerated,
  AR_SAE_MarginNotComputable: LBL_AR_SAE_MarginNotComputable,
  AR_SAE_MarketInsufficientHistory: LBL_AR_SAE_MarketInsufficientHistory,
  AR_SAE_MarketNoData: LBL_AR_SAE_MarketNoData,
  AR_SAE_MarketNotComparableCurrency: LBL_AR_SAE_MarketNotComparableCurrency,
  AR_SAE_MarketVolumeMany: LBL_AR_SAE_MarketVolumeMany,
  AR_SAE_MarketVolumeOne: LBL_AR_SAE_MarketVolumeOne,
  AR_SAE_RfaApplied: LBL_AR_SAE_RfaApplied,
  AR_SAE_SegBelowFloor: LBL_AR_SAE_SegBelowFloor,
  AR_SAE_SegLowMargin: LBL_AR_SAE_SegLowMargin,
  AR_SAE_SegRecommended: LBL_AR_SAE_SegRecommended,
  AR_SAE_SegSuperstar: LBL_AR_SAE_SegSuperstar,
  AR_SAE_VsMarket: LBL_AR_SAE_VsMarket
};
const SEGMENT_LABELS = {
  below_floor: I18N.AR_SAE_SegBelowFloor,
  low_margin: I18N.AR_SAE_SegLowMargin,
  recommended: I18N.AR_SAE_SegRecommended,
  superstar: I18N.AR_SAE_SegSuperstar
};

function formatFrDate(value) {
  if (!value) {
    return "—";
  }
  return new Date(value).toLocaleDateString("fr-FR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  });
}

function isPresent(value) {
  return value !== null && value !== undefined && value !== "";
}

/**
 * Repères marché exploitables pour un argument commercial : mêmes conditions que la jauge
 * (arPriceMatrixSimulator.marketReferenceUsableForGauge, session 26) — un repère insuffisant ou resté
 * en EUR faute de taux ne doit jamais alimenter un argument chiffré.
 */
function marketReferenceUsable(marketReference, currencyCode) {
  return !!(
    marketReference &&
    marketReference.hasEnoughData &&
    marketReference.currencyCode === currencyCode
  );
}

function buildMarketUnavailableNote(marketReference, currencyCode) {
  if (!marketReference) {
    return I18N.AR_SAE_MarketNoData;
  }
  if (!marketReference.hasEnoughData) {
    return I18N.AR_SAE_MarketInsufficientHistory;
  }
  if (marketReference.currencyCode !== currencyCode) {
    return formatLabel(I18N.AR_SAE_MarketNotComparableCurrency, currencyCode);
  }
  return null;
}

/**
 * @param {Object} input
 * @param {number} input.proposedTjm
 * @param {string} input.currencyCode
 * @param {number} input.totalDailyCost
 * @param {number} input.mc2PerDay
 * @param {number} input.mc2PercentHuman
 * @param {string} input.corridorSegment
 * @param {{floorPercent:number,targetPercent:number,idealPercent:number}} [input.corridorPercents]
 * @param {Object} [input.marketReference] AR_ComparablesService.MarketReference (déjà chargé)
 * @param {number} [input.rfaPercent]
 * @returns {{arguments: Array<{key:string,text:string}>, unavailableNotes: string[]}}
 */
export function buildSalesArguments(input) {
  const args = [];
  const notes = [];
  const currency = input.currencyCode || "EUR";
  const hasTjm = isPresent(input.proposedTjm);
  const hasCost = Number(input.totalDailyCost) > 0;
  const ref = input.marketReference;
  const marketUsable = marketReferenceUsable(ref, currency);

  if (!marketUsable) {
    const note = buildMarketUnavailableNote(ref, currency);
    if (note) {
      notes.push(note);
    }
  }

  // Positionnement vs médiane et Top 10 % (points 1 de la spec).
  if (marketUsable && hasTjm) {
    const deltaMedian = input.proposedTjm - ref.medianTjm;
    const deltaMedianPct = ref.medianTjm
      ? (Math.abs(deltaMedian) / ref.medianTjm) * 100
      : null;
    const vsMedianWord =
      deltaMedian >= 0 ? I18N.AR_SAE_Above : I18N.AR_SAE_Below;
    const deltaP90 = input.proposedTjm - ref.p90Tjm;
    const vsP90Word = deltaP90 >= 0 ? I18N.AR_SAE_Above : I18N.AR_SAE_Below;
    args.push({
      key: "vsMarket",
      text: formatLabel(
        I18N.AR_SAE_VsMarket,
        formatMoney(input.proposedTjm, currency),
        vsMedianWord,
        formatMoney(ref.medianTjm, currency),
        formatMoney(Math.abs(deltaMedian), currency),
        deltaMedianPct !== null ? ` (${formatPercent(deltaMedianPct)})` : "",
        vsP90Word,
        formatMoney(ref.p90Tjm, currency)
      )
    });
  }

  // Volume et période des comparables mobilisés (point 2 de la spec).
  if (marketUsable) {
    const n = ref.comparableCount;
    args.push({
      key: "marketVolume",
      text: formatLabel(
        n === 1 ? I18N.AR_SAE_MarketVolumeOne : I18N.AR_SAE_MarketVolumeMany,
        n,
        ref.circleLabel,
        formatFrDate(ref.periodStart),
        formatFrDate(ref.periodEnd)
      )
    });
  }

  // Remise consentie (RFA) par rapport au prix de référence (point 3 de la spec).
  const rfa = Number(input.rfaPercent) || 0;
  if (rfa > 0 && hasTjm) {
    args.push({
      key: "rfa",
      text: formatLabel(
        I18N.AR_SAE_RfaApplied,
        formatPercent(rfa),
        formatMoney(input.proposedTjm, currency)
      )
    });
  }

  // Marge dégagée et position dans le corridor (point 4 de la spec).
  if (hasTjm && hasCost && input.corridorSegment) {
    const segLabel =
      SEGMENT_LABELS[input.corridorSegment] || input.corridorSegment;
    const pcts = input.corridorPercents;
    const corridorDetail = pcts
      ? " " +
        formatLabel(
          I18N.AR_SAE_CorridorDetail,
          formatPercent(pcts.floorPercent),
          formatPercent(pcts.targetPercent),
          formatPercent(pcts.idealPercent)
        )
      : "";
    args.push({
      key: "margin",
      text: formatLabel(
        I18N.AR_SAE_MarginGenerated,
        formatMoney(input.mc2PerDay, currency),
        formatPercent(input.mc2PercentHuman),
        segLabel,
        corridorDetail
      )
    });
  } else if (hasTjm && !hasCost) {
    notes.push(I18N.AR_SAE_MarginNotComputable);
  }

  return { arguments: args, unavailableNotes: notes };
}