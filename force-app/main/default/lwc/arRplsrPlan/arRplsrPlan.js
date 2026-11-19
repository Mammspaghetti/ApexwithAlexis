import { LightningElement, api } from "lwc";
import { formatLabel } from "c/arI18n";
import LBL_TITLE from "@salesforce/label/c.AR_RPLSR_Title";
import LBL_DAYS_PER_MONTH from "@salesforce/label/c.AR_RPLSR_DaysPerMonth";
import LBL_PRODUCED from "@salesforce/label/c.AR_RPLSR_Produced";
import LBL_SOLD from "@salesforce/label/c.AR_RPLSR_Sold";
import LBL_BALANCE from "@salesforce/label/c.AR_RPLSR_Balance";
import LBL_WORKING from "@salesforce/label/c.AR_RPLSR_Working";
import LBL_EQUATION_ARIA from "@salesforce/label/c.AR_RPLSR_EquationAria";
import LBL_SOLD_LINE from "@salesforce/label/c.AR_RPLSR_SoldLine";
import LBL_HANDLE_ARIA from "@salesforce/label/c.AR_RPLSR_HandleAria";
import LBL_VALUE_ARIA from "@salesforce/label/c.AR_RPLSR_ValueAria";
import LBL_DATES_MISSING from "@salesforce/label/c.AR_RPLSR_DatesMissing";
import LBL_DAYS_UNIT from "@salesforce/label/c.AR_RPLSR_DaysUnit";
import LBL_MONTHS_SHORT from "@salesforce/label/c.AR_RPLSR_MonthsShort";
import LBL_MONTHS_LONG from "@salesforce/label/c.AR_RPLSR_MonthsLong";
import LBL_EXPAND_ARIA from "@salesforce/label/c.AR_RPLSR_ExpandAria";

/**
 * Carte « Régie par lot sans régule » (docs/265 §5, maquette pricing-tool/maquettes/265-regie-par-lot-sans-regule) : interrupteur,
 * jours facturés par mois, équation PRÉVISIONNEL − VENDUS = SOLDE et graphique des jours prévisionnels par mois.
 *
 * Composant d'affichage : il reçoit le plan calculé par le simulateur (`months` : m, ouvres, vendus, produits) et
 * n'émet que des intentions — `toggle`, `basechange`, `producedchange` (entier déjà borné entre 0 et les ouvrés).
 *
 * Échelle du graphique (axe = écart au vendu de chaque mois) : ligne des vendus au centre, plafond = jours ouvrés
 * max en haut (au moins 4 crans), autant de jours en dessous ; sous ce plancher (gros congés), chaque jour ajoute un
 * cran 15 % plus petit et toute l'échelle se resserre d'autant. La hauteur totale ne change jamais ; l'échelle est
 * recalculée en continu pendant un glisser, la poignée reste donc toujours dans le cadre.
 *
 * Carte rétractable (session 269) : à l'ouverture d'une matrice dont le mode est actif, seule la frise reste (mois,
 * trait de la couleur de la barre, jours en noir). Mêmes délais et même mécanique que le panneau des périodes de TJM
 * d'`arPriceMatrixSimulator` : survol 100 ms ou clic pour ouvrir ; clic extérieur, Échap ou 8 s hors de la carte pour
 * replier — jamais pendant un glisser ni tant qu'un champ a le focus.
 */

export const CHART_HEIGHT = 180;
const TOP = 2;
const BOTTOM = 4;
const SHRINK = 0.85;
const MIN_COLUMN_WIDTH = 38;
const BUBBLE_GUTTER = 60;
const CURVE_VIEWBOX_WIDTH = 1000;
const PAN_THRESHOLD_PX = 4;
const TIP_GAP_PX = 10;
const TIP_WIDTH_PX = 210;
const TIP_EDGE_PX = 8;
const MAX_BASE = 23;
const HOVER_INTENT_MS = 100;
const HOVER_LEAVE_MS = 8000;
const COLLAPSED_CHART_HEIGHT = 10;
const COLLAPSED_BAR_TOP = 3;
const COLLAPSED_BAR_HEIGHT = 4;
const INK = "#111";
const EASE = "cubic-bezier(.2,0,0,1)";
const PINK = "#d31876";
const NAVY = "#0d2a45";
const GREEN = "#16a34a";
const NEUTRAL = "#94a3b8";

const FR_INT = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const FR_2 = new Intl.NumberFormat("fr-FR", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

function round2(n) {
  return Math.round(n * 100) / 100;
}

/** Jours sans décimale inutile : « 18 », « 9,09 ». */
function formatDays(n) {
  const v = round2(n);
  return Number.isInteger(v) ? FR_INT.format(v) : FR_2.format(v);
}

function signed(n) {
  return (round2(n) > 0 ? "+" : "") + formatDays(n);
}

/** Saisie libre (« 18,5 », « 18.5 », « 18 ») → nombre, NaN si illisible. */
export function parseNumber(raw) {
  const text = String(raw ?? "")
    .replace(",", ".")
    .replace(/\s/g, "");
  return text === "" ? NaN : Number(text);
}

/** Crans sous le plancher : chacun 15 % plus petit que le précédent. */
function extra(x) {
  return (1 - Math.pow(SHRINK, x)) / (1 - SHRINK);
}

/**
 * Géométrie du graphique, en pixels depuis le haut de la zone. Exportée pour les tests : `ppd` (pixels par jour de
 * la zone linéaire), `zeroY` (ligne des vendus), `yOf(écart)`, `yCum(cumul)`.
 */
export function chartScale(months) {
  const ecarts = months.map((m) => Number(m.produits) - Number(m.vendus));
  const span =
    Math.max(4, ...months.map((m) => Number(m.ouvres) - Number(m.vendus))) +
    0.15;
  const depth = Math.max(0, ...ecarts.map((e) => -e - span));
  const ppd = (CHART_HEIGHT - TOP - BOTTOM) / (2 * span + extra(depth));
  const zeroY = TOP + span * ppd;
  const linearBottom = zeroY + span * ppd;
  const yOf = (e) => {
    return e >= -span
      ? zeroY - Math.min(e, span) * ppd
      : linearBottom + extra(-span - e) * ppd;
  };
  let cumCents = 0;
  const cums = ecarts.map((e) => {
    cumCents += Math.round(e * 100);
    return cumCents / 100;
  });
  const k = Math.max(4, ...cums.map(Math.abs));
  const ppc = (zeroY - TOP - 4) / k;
  const yCum = (v) => zeroY - v * ppc;
  return { ecarts, cums, span, depth, ppd, zeroY, yOf, yCum };
}

function tone(e) {
  if (e > 0.5) {
    return PINK;
  }
  return e < -0.5 ? NAVY : NEUTRAL;
}

function balanceColor(balance) {
  if (Math.abs(balance) < 0.5) {
    return GREEN;
  }
  return balance > 0 ? PINK : NAVY;
}

export default class ArRplsrPlan extends LightningElement {
  _enabled = false;
  collapsed = true;
  _openOnEnable = false;
  _intentTimer;
  _leaveTimer;
  _fieldFocused = false;
  _pointerInside = false;

  @api
  get enabled() {
    return this._enabled;
  }
  set enabled(value) {
    const on = !!value;
    if (on && !this._enabled) {
      // Allumé par l'utilisateur : carte ouverte. Allumé par le chargement d'une matrice : rétractée.
      this.collapsed = !this._openOnEnable;
      this._openOnEnable = false;
    }
    if (!on) {
      this.clearTimers();
    }
    this._enabled = on;
  }

  @api daysPerMonth;
  @api readOnly = false;
  _months = [];

  @api
  get months() {
    return this._months;
  }
  set months(value) {
    this._months = Array.isArray(value) ? value : [];
  }

  hoverIndex = null;
  pinIndex = null;
  // Saisies en cours (session 276) : le template lie ces brouillons tant que le champ n'est pas validé,
  // sinon un rendu déclenché par une animation réécrit la valeur DOM avec l'ancienne valeur.
  _baseDraft = null;
  _valueDrafts = {};
  drag = null;
  _overIndex = null;
  panning = false;
  scrollable = false;
  tipLeft = 0;
  tipRight = 0;
  tipY = 0;
  cardWidth = 1000;
  _pan = null;
  _noClick = false;

  labels = {
    title: LBL_TITLE,
    daysPerMonth: LBL_DAYS_PER_MONTH,
    produced: LBL_PRODUCED,
    sold: LBL_SOLD,
    balance: LBL_BALANCE,
    working: LBL_WORKING,
    equationAria: LBL_EQUATION_ARIA,
    soldLine: LBL_SOLD_LINE,
    datesMissing: LBL_DATES_MISSING,
    expandAria: LBL_EXPAND_ARIA
  };

  get monthsShort() {
    return String(LBL_MONTHS_SHORT).split(",");
  }

  get monthsLong() {
    return String(LBL_MONTHS_LONG).split(",");
  }

  days(n) {
    return formatLabel(LBL_DAYS_UNIT, formatDays(n));
  }

  // --- En-tête --------------------------------------------------------------

  get ariaPressed() {
    return this.enabled ? "true" : "false";
  }

  get headerClass() {
    return this.enabled ? "rplsr-head rplsr-head_on" : "rplsr-head";
  }

  get switchTrackClass() {
    let cls = "rplsr-switch-track";
    if (this.enabled) {
      cls += " rplsr-switch-track_on";
      if (this.readOnly) {
        cls += " rplsr-switch-track_readonly";
      }
    }
    return cls;
  }

  get baseDisplay() {
    const v = Number(this.daysPerMonth);
    return Number.isFinite(v) && this.daysPerMonth !== null
      ? formatDays(v)
      : "";
  }

  get baseInputValue() {
    return this._baseDraft !== null ? this._baseDraft : this.baseDisplay;
  }

  get hasPlan() {
    return this._months.length > 0;
  }

  get totals() {
    let soldCents = 0;
    let produced = 0;
    this._months.forEach((m) => {
      soldCents += Math.round(Number(m.vendus) * 100);
      produced += Number(m.produits) || 0;
    });
    return {
      sold: soldCents / 100,
      produced,
      balance: (produced * 100 - soldCents) / 100
    };
  }

  get totalProducedLabel() {
    return this.days(this.totals.produced);
  }

  get totalSoldLabel() {
    return this.days(this.totals.sold);
  }

  get balanceLabel() {
    return formatLabel(LBL_DAYS_UNIT, signed(this.totals.balance));
  }

  get balanceTitleStyle() {
    return `color: ${balanceColor(this.totals.balance)};`;
  }

  get balanceChipStyle() {
    const c = balanceColor(this.totals.balance);
    return `background: ${c}; box-shadow: 0 0 0 3px ${c}22;`;
  }

  handleToggle() {
    if (this.readOnly) {
      return;
    }
    this.hoverIndex = null;
    this.pinIndex = null;
    this._openOnEnable = !this.enabled;
    this.dispatchEvent(
      new CustomEvent("toggle", { detail: { enabled: !this.enabled } })
    );
  }

  /** Application immédiate (à la validation du champ) ; une valeur hors ]0 ; 23] est refusée et l'affichage revient. */
  handleBaseInput(event) {
    this._baseDraft = event.target.value;
  }

  handleBaseKey(event) {
    if (event.key === "Escape") {
      this._baseDraft = null;
      event.target.value = this.baseDisplay;
    }
  }

  handleBaseChange(event) {
    if (this._baseDraft === null && event.type === "blur") {
      return;
    }
    this._baseDraft = null;
    const value = round2(parseNumber(event.target.value));
    if (!(value > 0) || value > MAX_BASE) {
      event.target.value = this.baseDisplay;
      return;
    }
    event.target.value = formatDays(value);
    if (value === Number(this.daysPerMonth)) {
      return;
    }
    // Le plan est reconstruit : une infobulle figée garderait les coordonnées de l'ancienne mise en page.
    this.hoverIndex = null;
    this.pinIndex = null;
    this.dispatchEvent(
      new CustomEvent("basechange", { detail: { daysPerMonth: value } })
    );
  }

  // --- Graphique -------------------------------------------------------------

  get scale() {
    return chartScale(this._months);
  }

  get focusIndex() {
    if (this.drag) {
      return this.drag.i;
    }
    return this.hoverIndex !== null ? this.hoverIndex : this.pinIndex;
  }

  get panStyle() {
    const cursor = this.panning
      ? "grabbing"
      : this.scrollable
        ? "grab"
        : "default";
    return `cursor: ${cursor};`;
  }

  get innerStyle() {
    return `min-width: ${this._months.length * MIN_COLUMN_WIDTH + BUBBLE_GUTTER}px;`;
  }

  get chartStyle() {
    return `height: ${this.collapsed ? COLLAPSED_CHART_HEIGHT : CHART_HEIGHT}px;`;
  }

  get cardClass() {
    return this.collapsed ? "rplsr-card rplsr-card_collapsed" : "rplsr-card";
  }

  get soldLineStyle() {
    return `top: ${this.scale.zeroY - 1}px;`;
  }

  get viewItems() {
    const scale = this.scale;
    const focus = this.focusIndex;
    const collapsed = this.collapsed;
    const short = this.monthsShort;
    return this._months.map((month, i) => {
      const [y, mo] = month.m.split("-").map(Number);
      const label = short[mo - 1] + (mo === 1 ? ` ${String(y).slice(2)}` : "");
      const e = scale.ecarts[i];
      const yP = scale.yOf(e);
      const color = tone(e);
      const dragging = !!this.drag && this.drag.i === i;
      const faint = Math.abs(e) < 0.5;
      const dur = collapsed ? ".4s" : ".3s";
      const ease = dragging
        ? "none"
        : `top ${dur} ${EASE}, height ${dur} ${EASE}, border-radius ${dur} ${EASE}, background-color .2s`;
      const capTop = scale.yOf(Number(month.ouvres) - Number(month.vendus)) - 3;
      const produced = Number(month.produits) || 0;
      return {
        key: month.m,
        index: i,
        label,
        produced,
        inputValue:
          this._valueDrafts[i] !== undefined ? this._valueDrafts[i] : produced,
        ouvres: month.ouvres,
        focused: focus === i,
        monthClass:
          focus === i
            ? "rplsr-month-cell rplsr-month-cell_focus"
            : "rplsr-month-cell",
        colClass: focus === i ? "rplsr-col rplsr-col_focus" : "rplsr-col",
        capStyle: `top: ${capTop}px; bottom: ${BOTTOM}px;`,
        barStyle: collapsed
          ? `top: ${COLLAPSED_BAR_TOP}px; height: ${COLLAPSED_BAR_HEIGHT}px; border-radius: 2px; background: ${color};` +
            ` opacity: 1; transition: ${ease};`
          : `top: ${Math.min(yP, scale.zeroY)}px; height: ${Math.max(2, Math.abs(yP - scale.zeroY))}px;` +
            ` border-radius: ${e >= 0 ? "6px 6px 2px 2px" : "2px 2px 6px 6px"}; background: ${color};` +
            ` opacity: ${faint ? 0.2 : 0.92}; transition: ${ease};`,
        handleStyle: `top: ${collapsed ? COLLAPSED_BAR_TOP : yP}px; transition: ${dragging ? "none" : `top ${dur} ${EASE}`};`,
        valueReadonly: collapsed,
        valueTabindex: collapsed ? "-1" : "0",
        knobStyle: `border-color: ${faint ? NAVY : color};${dragging ? " transform: scale(1.35);" : ""}`,
        valueStyle: `color: ${e > 0.5 && !collapsed ? PINK : INK};`,
        handleAria: formatLabel(LBL_HANDLE_ARIA, label, produced),
        valueAria: formatLabel(LBL_VALUE_ARIA, label)
      };
    });
  }

  /** Courbe du solde cumulé, au centre de chaque colonne (viewBox fixe 1000 × 180, étiré sur la largeur). */
  get soldePoints() {
    const scale = this.scale;
    const width = CURVE_VIEWBOX_WIDTH / Math.max(1, this._months.length);
    return scale.cums
      .map((v, i) => `${(i + 0.5) * width},${scale.yCum(v).toFixed(1)}`)
      .join(" ");
  }

  get endBubbleStyle() {
    const balance = this.totals.balance;
    return `top: ${this.scale.yCum(balance)}px; background: ${balanceColor(balance)};`;
  }

  // --- Infobulle --------------------------------------------------------------

  get tip() {
    const i = this.focusIndex;
    if (this.collapsed || i === null || i >= this._months.length) {
      return null;
    }
    const cw = this.cardWidth;
    const left = this.tipLeft;
    const right = this.tipRight;
    if (!(right > 8 && left < cw - 8)) {
      return null;
    }
    // À droite de la colonne ; à gauche si elle déborderait sur la zone du solde (bulle à droite du graphique).
    const flip = right + TIP_GAP_PX + TIP_WIDTH_PX > cw - BUBBLE_GUTTER;
    // Session 289 : jamais coupée. Si la place manque aussi à gauche (mission d'un seul mois : colonne
    // collée au bord gauche), on repasse à droite du point ; si aucun côté ne convient, l'infobulle est
    // calée dans la zone visible de la carte, sans pointe.
    const fitsLeft = left - TIP_GAP_PX - TIP_WIDTH_PX >= TIP_EDGE_PX;
    const fitsRight = right + TIP_GAP_PX + TIP_WIDTH_PX <= cw - TIP_EDGE_PX;
    let style;
    let arrowStyle;
    if (flip && fitsLeft) {
      style = `left: ${left - TIP_GAP_PX}px; top: ${this.tipY}px; transform: translateX(-100%);`;
      arrowStyle = `right: -5px; top: 14px;`;
    } else if (!flip || fitsRight) {
      style = `left: ${right + TIP_GAP_PX}px; top: ${this.tipY}px;`;
      arrowStyle = `left: -5px; top: 14px;`;
    } else {
      const x = Math.max(
        TIP_EDGE_PX,
        Math.min(
          left + TIP_GAP_PX,
          cw - BUBBLE_GUTTER - TIP_WIDTH_PX - TIP_EDGE_PX
        )
      );
      style = `left: ${x}px; top: ${this.tipY}px;`;
      arrowStyle = `display: none;`;
    }
    const month = this._months[i];
    const [y, mo] = month.m.split("-").map(Number);
    const e = this.scale.ecarts[i];
    const chip = e > 0.5 ? PINK : e < -0.5 ? "#3b5b7d" : "#3f6b54";
    return {
      style,
      arrowStyle,
      title: `${this.monthsLong[mo - 1]} ${y}`,
      ecart: formatLabel(LBL_DAYS_UNIT, signed(e)),
      ecartStyle: `background: ${chip};`,
      ouvres: formatDays(month.ouvres),
      vendus: formatDays(month.vendus),
      showSold:
        Math.abs(Number(month.vendus) - Number(this.daysPerMonth)) > 0.005
    };
  }

  get showTip() {
    return !!this.tip;
  }

  /** Infobulle accrochée à la carte (pas au conteneur défilant) : colonne relevée dans la carte, la pointe vise sa bordure. */
  focusColumn(i) {
    if (this.collapsed || (this._pan && this._pan.moved)) {
      return;
    }
    const card = this.template.querySelector(".rplsr-card");
    const col = this.template.querySelectorAll(".rplsr-month-cell")[i];
    const chart = this.template.querySelector(".rplsr-chart");
    if (card && col && chart) {
      const cr = card.getBoundingClientRect();
      const r = col.getBoundingClientRect();
      const top = chart.getBoundingClientRect().top;
      this.tipLeft = r.left - cr.left;
      this.tipRight = r.left + r.width - cr.left;
      this.tipY = top - cr.top;
      this.cardWidth = cr.width || 1000;
    }
    if (this.pinIndex !== null && this.pinIndex !== i) {
      this.pinIndex = null;
    }
    this.hoverIndex = i;
  }

  handleColumnEnter(event) {
    const i = Number(event.currentTarget.dataset.index);
    if (this.drag) {
      // Pendant un glisser le focus reste sur le mois glissé ; on retient la colonne survolée pour le relâchement.
      this._overIndex = i;
      return;
    }
    this.focusColumn(i);
  }

  handleColumnClick(event) {
    if (this._noClick || this.collapsed) {
      return;
    }
    const i = Number(event.currentTarget.dataset.index);
    this.focusColumn(i);
    this.pinIndex = this.pinIndex === i ? null : i;
  }

  handleChartLeave() {
    if (this.drag) {
      this._overIndex = null;
      return;
    }
    this.hoverIndex = null;
  }

  handleCardLeave() {
    if (this.drag) {
      this._overIndex = null;
      return;
    }
    this.hoverIndex = null;
    this.pinIndex = null;
    this.startLeaveTimer();
  }

  // --- Rétractation (session 269) ---------------------------------------------

  clearTimers() {
    clearTimeout(this._intentTimer);
    clearTimeout(this._leaveTimer);
  }

  expand() {
    this.clearTimers();
    this.collapsed = false;
    this._fieldFocused = false;
  }

  collapse() {
    this.clearTimers();
    this.collapsed = true;
    this._fieldFocused = false;
    this.hoverIndex = null;
    this.pinIndex = null;
  }

  // Seul repli au pointeur : 8 s hors de la carte, annulé dès son retour.
  startLeaveTimer() {
    clearTimeout(this._intentTimer);
    if (this.collapsed || !this._enabled) {
      return;
    }
    clearTimeout(this._leaveTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai de repli de la carte, nettoyé au démontage.
    this._leaveTimer = setTimeout(() => {
      if (!this._fieldFocused && !this.drag) {
        this.collapse();
      }
    }, HOVER_LEAVE_MS);
  }

  handleCardEnter() {
    clearTimeout(this._leaveTimer);
    this.startIntentTimer();
  }

  startIntentTimer() {
    if (!this.collapsed || !this._enabled) {
      return;
    }
    clearTimeout(this._intentTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai d'intention de la carte, nettoyé au démontage.
    this._intentTimer = setTimeout(() => this.expand(), HOVER_INTENT_MS);
  }

  // Rétractée, un clic n'importe où dans la carte la déplie ; l'interrupteur garde son seul rôle.
  handleCardClick(event) {
    if (!this.collapsed || !this._enabled) {
      return;
    }
    if (event.target?.closest?.('[data-id="toggle"]')) {
      return;
    }
    this.expand();
  }

  handleStripEnter() {
    this.startIntentTimer();
  }

  // Le survol reste dans la carte : l'intention continue tant que le curseur n'a pas quitté la carte.
  handleStripLeave() {}

  handleStripClick() {
    if (this.collapsed) {
      this.expand();
    }
  }

  // Posé au pointerdown dans la carte ; l'écouteur document, qui passe après, l'ignore.
  handleCardPointerDown() {
    this._pointerInside = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- drapeau de pointerdown remis à zéro après la propagation.
    setTimeout(() => {
      this._pointerInside = false;
    }, 0);
  }

  // Un clic extérieur replie même si un champ a le focus (comme pour les périodes de TJM).
  handleDocumentPointerDown = () => {
    if (this._pointerInside) {
      this._pointerInside = false;
      return;
    }
    if (!this.collapsed) {
      this.collapse();
    }
  };

  handleCardFocusIn(event) {
    if (event.target?.tagName === "INPUT") {
      if (this.collapsed && this._enabled) {
        this.expand();
      }
      this._fieldFocused = true;
    }
  }

  handleCardFocusOut(event) {
    if (event.target?.tagName === "INPUT") {
      this._fieldFocused = false;
    }
  }

  handleCardKeydown(event) {
    if (event.key === "Escape" && !this.collapsed) {
      this.collapse();
    }
  }

  // --- Modification d'un mois ------------------------------------------------

  /** Entier borné entre 0 et les jours ouvrés du mois ; n'émet que si la valeur change. */
  emitProduced(i, raw, current) {
    const month = this._months[i];
    if (!month) {
      return current;
    }
    const parsed = parseNumber(raw);
    if (Number.isNaN(parsed)) {
      return current;
    }
    const value = Math.max(
      0,
      Math.min(Number(month.ouvres), Math.round(parsed))
    );
    if (value !== current) {
      this.dispatchEvent(
        new CustomEvent("producedchange", {
          detail: { month: month.m, produced: value }
        })
      );
    }
    return value;
  }

  handleHandleDown(event) {
    if (this.readOnly) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    // preventDefault annule le mousedown de compatibilité, donc la mise au focus : les flèches ↑ ↓ doivent suivre.
    event.currentTarget.focus();
    const i = Number(event.currentTarget.dataset.index);
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // Capture refusée : les écouteurs posés sur window ci-dessous suivent le geste de toute façon.
    }
    const step = Math.max(10, Math.min(18, this.scale.ppd));
    const value = Number(this._months[i].produits) || 0;
    this.drag = {
      i,
      y0: event.clientY,
      v0: value,
      step,
      last: value
    };
    this._overIndex = i;
    // Constaté en sandbox (session 265b) : sous Lightning, la capture du pointeur ne prend pas sur la poignée et les
    // mouvements partent vers l'élément survolé. Le geste est donc suivi sur window, jusqu'au relâchement.
    this.listenToDrag(true);
    this.focusColumn(i);
  }

  handleDragMove = (event) => {
    const d = this.drag;
    if (!d) {
      return;
    }
    d.last = this.emitProduced(
      d.i,
      d.v0 - (event.clientY - d.y0) / d.step,
      d.last
    );
  };

  handleDragEnd = () => {
    this.listenToDrag(false);
    if (this.drag) {
      this.drag = null;
      // Au relâchement, le focus revient à la colonne sous la souris (ou plus rien hors de la carte).
      if (this._overIndex === null || this._overIndex === undefined) {
        this.hoverIndex = null;
      } else {
        this.focusColumn(this._overIndex);
      }
      if (this._overIndex === null || this._overIndex === undefined) {
        this.startLeaveTimer();
      }
    }
  };

  listenToDrag(on) {
    const method = on ? "addEventListener" : "removeEventListener";
    window[method]("pointermove", this.handleDragMove);
    window[method]("pointerup", this.handleDragEnd);
    window[method]("pointercancel", this.handleDragEnd);
  }

  connectedCallback() {
    document.addEventListener("pointerdown", this.handleDocumentPointerDown);
  }

  disconnectedCallback() {
    this.listenToDrag(false);
    this.clearTimers();
    document.removeEventListener("pointerdown", this.handleDocumentPointerDown);
  }

  handleHandleKey(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
      return;
    }
    event.preventDefault();
    const i = Number(event.currentTarget.dataset.index);
    const current = Number(this._months[i].produits) || 0;
    this.emitProduced(i, current + (event.key === "ArrowUp" ? 1 : -1), current);
  }

  handleHandleFocus(event) {
    this.focusColumn(Number(event.currentTarget.dataset.index));
  }

  dropValueDraft(i) {
    const rest = { ...this._valueDrafts };
    delete rest[i];
    this._valueDrafts = rest;
  }

  handleValueInput(event) {
    const i = Number(event.target.dataset.index);
    this._valueDrafts = { ...this._valueDrafts, [i]: event.target.value };
  }

  handleValueChange(event) {
    const i = Number(event.target.dataset.index);
    if (this._valueDrafts[i] === undefined && event.type === "blur") {
      return;
    }
    this.dropValueDraft(i);
    const current = Number(this._months[i].produits) || 0;
    const value = this.emitProduced(i, event.target.value, current);
    // Jamais de virgule ni de valeur hors bornes affichée : le champ reprend l'entier retenu.
    event.target.value = String(value);
  }

  handleValueKey(event) {
    const i = Number(event.target.dataset.index);
    if (event.key === "Escape" && this._valueDrafts[i] !== undefined) {
      this.dropValueDraft(i);
      event.target.value = String(Number(this._months[i].produits) || 0);
      return;
    }
    this.handleHandleKey(event);
  }

  // --- Défilement horizontal au glisser ----------------------------------------

  handlePanEnter(event) {
    const el = event.currentTarget;
    this.scrollable = el.scrollWidth > el.clientWidth + 1;
  }

  handlePanDown(event) {
    if (
      event.button !== 0 ||
      (event.target.closest &&
        event.target.closest(".rplsr-handle, input, button"))
    ) {
      return;
    }
    const el = event.currentTarget;
    if (el.scrollWidth <= el.clientWidth + 1) {
      return;
    }
    this._pan = {
      x: event.clientX,
      s: el.scrollLeft,
      id: event.pointerId,
      moved: false
    };
  }

  handlePanMove(event) {
    const p = this._pan;
    if (!p) {
      return;
    }
    const dx = event.clientX - p.x;
    if (!p.moved && Math.abs(dx) > PAN_THRESHOLD_PX) {
      p.moved = true;
      try {
        event.currentTarget.setPointerCapture(p.id);
      } catch {
        // Sans capture, le défilement suit tant que le pointeur reste dans le graphique.
      }
      this.panning = true;
      this.hoverIndex = null;
      this.pinIndex = null;
    }
    if (p.moved) {
      event.currentTarget.scrollLeft = p.s - dx;
    }
  }

  handlePanUp() {
    const p = this._pan;
    if (!p) {
      return;
    }
    this._pan = null;
    if (p.moved) {
      // Le clic qui suit la fin d'un glisser ne fige pas l'infobulle.
      this._noClick = true;
      // eslint-disable-next-line @lwc/lwc/no-async-operation -- le clic arrive dans la tâche suivante.
      setTimeout(() => {
        this._noClick = false;
      }, 0);
      this.panning = false;
    }
  }

  handleScroll() {
    if (!this._pan && (this.hoverIndex !== null || this.pinIndex !== null)) {
      this.hoverIndex = null;
      this.pinIndex = null;
    }
  }
}