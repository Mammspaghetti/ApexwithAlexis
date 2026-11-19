import { LightningElement, api } from "lwc";
import { formatMoneyPrecise } from "c/arPricingEngine";
import {
  LBL,
  SEGMENT_COLORS,
  POST_ORDER,
  POST_COLORS,
  POST_LABELS,
  axisNoun,
  fill,
  pct,
  decimal1,
  width
} from "c/arDashboardShared";

const MODE_PERCENT = "percent";
const MODE_PER_DAY = "perday";
// Un libellé n'est écrit dans un segment qu'à partir de cette part de la barre (en %).
const LABEL_MIN_SHARE = 8;

const KPI_CLASS = {
  below_floor: "kpi-card kpi-tint-red",
  low_margin: "kpi-card kpi-tint-amber",
  recommended: "kpi-card kpi-tint-green",
  superstar: "kpi-card kpi-tint-green"
};

const MC2_CLASS = {
  below_floor: "mc2-red",
  low_margin: "mc2-amber",
  recommended: "mc2-green",
  superstar: "mc2-green"
};

const SOURCE_LABEL = {
  ACCOUNT: LBL.SourceAccount,
  ENTITY: LBL.SourceEntity,
  DEFAULT: LBL.SourceDefault
};

export default class ArDashboardProfitability extends LightningElement {
  @api data;
  mode = MODE_PERCENT;

  i18n = LBL;

  get kpis() {
    return (this.data && this.data.kpis) || {};
  }

  get currency() {
    return this.kpis.pivotCurrencyCode || "EUR";
  }

  get mc2Text() {
    return pct(this.kpis.averageMc2Percent);
  }

  get mc2KpiClass() {
    return KPI_CLASS[this.data && this.data.groupSegment] || "kpi-card";
  }

  get costsText() {
    return this.kpis.costsOfSalesPerDay === null ||
      this.kpis.costsOfSalesPerDay === undefined
      ? "—"
      : `${formatMoneyPrecise(this.kpis.costsOfSalesPerDay, this.currency)}${LBL.PerDay}`;
  }

  get topPostText() {
    return this.kpis.topPost ? POST_LABELS[this.kpis.topPost] : "—";
  }

  get topPostDetail() {
    return this.kpis.topPost ? pct(this.kpis.topPostSharePercent) : "";
  }

  get belowFloorCount() {
    return this.kpis.belowFloorCount || 0;
  }

  // ---------- Décomposition des costs of sales ----------

  get costsTitle() {
    return fill(LBL.PfCostsTitle, axisNoun(this.data && this.data.axis));
  }

  get isPercentMode() {
    return this.mode === MODE_PERCENT;
  }

  get percentButtonClass() {
    return this.mode === MODE_PERCENT ? "toggle-btn is-active" : "toggle-btn";
  }

  get perDayButtonClass() {
    return this.mode === MODE_PER_DAY ? "toggle-btn is-active" : "toggle-btn";
  }

  get percentPressed() {
    return String(this.mode === MODE_PERCENT);
  }

  get perDayPressed() {
    return String(this.mode === MODE_PER_DAY);
  }

  handleModePercent() {
    this.mode = MODE_PERCENT;
  }

  handleModePerDay() {
    this.mode = MODE_PER_DAY;
  }

  get costRows() {
    const rows = [];
    // Vue Groupe : la ligne d'axe est déjà « House of ABY » — pas de seconde ligne de total (recette 287b).
    if (this.data && this.data.groupRow && this.data.axis !== "group") {
      rows.push({ ...this.data.groupRow, isGroup: true });
    }
    ((this.data && this.data.costRows) || []).forEach((r) => rows.push(r));
    const maxTotal = Math.max(
      1,
      ...rows.map((r) => Number(r.totalPerDay) || 0)
    );
    return rows.map((row, index) => {
      const parts = row.parts || [];
      const total = Number(row.totalPerDay) || 0;
      const byPost = {};
      parts.forEach((p) => {
        byPost[p.post] = p;
      });
      const sample = parts.length > 0 && total > 0;
      const segments = sample
        ? POST_ORDER.filter(
            (post) => byPost[post] && byPost[post].perDay > 0
          ).map((post) => {
            const part = byPost[post];
            const share = Number(part.percent) || 0;
            const text = this.isPercentMode
              ? pct(part.percent)
              : formatMoneyPrecise(part.perDay, this.currency);
            return {
              key: post,
              style: `flex:${this.isPercentMode ? share : part.perDay};background:${POST_COLORS[post]};`,
              text: share >= LABEL_MIN_SHARE ? text : "",
              title: `${POST_LABELS[post]} : ${pct(part.percent)} · ${formatMoneyPrecise(part.perDay, this.currency)}${LBL.PerDay}`
            };
          })
        : [];
      const scale = this.isPercentMode ? 100 : (total / maxTotal) * 100;
      return {
        key: `${index}-${row.key || row.label}`,
        label: row.isGroup ? LBL.PfGroupRow : row.label,
        className: row.isGroup ? "cost-row is-group" : "cost-row",
        hasBar: segments.length > 0,
        wrapStyle: `width:${width(scale)}%;`,
        segments,
        totalText: sample
          ? `${formatMoneyPrecise(total, this.currency)}${LBL.PerDay}`
          : "—"
      };
    });
  }

  get hasCostRows() {
    return this.costRows.length > 0;
  }

  get postLegend() {
    return POST_ORDER.map((post) => ({
      key: post,
      label: POST_LABELS[post],
      style: `background:${POST_COLORS[post]}`
    }));
  }

  get excludedNote() {
    const n = this.data && this.data.excludedWithoutDays;
    return n > 0 ? fill(LBL.PfExcluded, n) : "";
  }

  // ---------- Points de MC2 par poste ----------

  get pointRows() {
    const rows = (this.data && this.data.mc2PointsByPost) || [];
    const max = Math.max(0.0001, ...rows.map((r) => Number(r.points) || 0));
    return rows.map((r) => ({
      key: r.post,
      label: POST_LABELS[r.post] || r.post,
      detail: fill(LBL.PfPointsUnit, decimal1(r.points)),
      barStyle: `width:${width(((Number(r.points) || 0) / max) * 100)}%;background:${POST_COLORS[r.post] || "#94a3b8"};`
    }));
  }

  get pointsTitle() {
    return LBL.PfPointsTitle;
  }

  // ---------- MC2 par axe ----------

  get mc2AxisTitle() {
    return fill(LBL.PfMc2AxisTitle, axisNoun(this.data && this.data.axis));
  }

  get mc2AxisRows() {
    return ((this.data && this.data.mc2ByAxis) || []).map((r, i) => {
      const has =
        r.averageMc2Percent !== null && r.averageMc2Percent !== undefined;
      return {
        key: `${i}-${r.label}`,
        label: r.label,
        detail: has ? `${pct(r.averageMc2Percent)} (${r.matrixCount})` : "—",
        barStyle: has
          ? `width:${width(r.averageMc2Percent)}%;background:${SEGMENT_COLORS[r.segment] || "#94a3b8"};`
          : "width:0;"
      };
    });
  }

  // ---------- Clients à marge basse, seuils les plus hauts ----------

  get lowClientRows() {
    return ((this.data && this.data.lowestMarginClients) || []).map((c, i) => ({
      key: `${i}-${c.accountName}`,
      accountName: c.accountName,
      axisLabel: c.axisLabel || "—",
      matrixCount: c.matrixCount,
      mc2: pct(c.averageMc2Percent),
      gap:
        c.gapPoints === null || c.gapPoints === undefined
          ? "—"
          : `${c.gapPoints > 0 ? "+" : ""}${decimal1(c.gapPoints)} pt`,
      mc2Class: `mc2-cell ${this.mc2ClassOf(c)}`
    }));
  }

  mc2ClassOf(client) {
    if (client.gapPoints === null || client.gapPoints === undefined) {
      return "";
    }
    return client.gapPoints >= 0
      ? MC2_CLASS.recommended
      : MC2_CLASS.below_floor;
  }

  get thresholdRows() {
    return ((this.data && this.data.highestThresholdAccounts) || []).map(
      (a, i) => ({
        key: `${i}-${a.accountName}`,
        accountName: a.accountName,
        floor: pct(a.floorPercent),
        target: pct(a.targetPercent),
        ideal: pct(a.idealPercent),
        source: SOURCE_LABEL[a.source] || a.source || "—"
      })
    );
  }
}