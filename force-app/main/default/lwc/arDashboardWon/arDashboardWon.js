import { LightningElement, api } from "lwc";
import LANG from "@salesforce/i18n/lang";
import {
  LBL,
  fill,
  pct,
  decimal1,
  monthLabel,
  width,
  axisNoun
} from "c/arDashboardShared";

const LEVEL_COLORS = {
  P1: "#16a34a",
  P2: "#4ade80",
  P3: "#f59e0b",
  "Hors grille": "#dc2626"
};

const LEVEL_LABELS = {
  P1: LBL.WnLevelP1,
  P2: LBL.WnLevelP2,
  P3: LBL.WnLevelP3,
  "Hors grille": LBL.WnLevelOffGrid
};

const LEVEL_ORDER = ["P1", "P2", "P3", "Hors grille"];

function formatDate(value) {
  if (!value) {
    return "—";
  }
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("fr-FR");
}

export default class ArDashboardWon extends LightningElement {
  @api data;

  i18n = LBL;

  get kpis() {
    return (this.data && this.data.kpis) || {};
  }

  get conversionText() {
    return pct(this.kpis.simulatedToWonPercent);
  }

  get validatedWonText() {
    return pct(this.kpis.validatedToWonPercent);
  }

  get priceOneText() {
    return pct(this.kpis.priceOnePercent);
  }

  get pendingCount() {
    return this.kpis.pendingCount || 0;
  }

  // ---------- Niveau de prix (anneau) ----------

  get levelSegments() {
    const levels = (this.data && this.data.levels) || [];
    return LEVEL_ORDER.map((level) => {
      const found = levels.find((l) => l.level === level) || {};
      return {
        label: LEVEL_LABELS[level],
        value: found.count || 0,
        color: LEVEL_COLORS[level],
        percent: found.percent || 0
      };
    });
  }

  get levelTotal() {
    return this.levelSegments.reduce((sum, s) => sum + s.value, 0);
  }

  get hasLevels() {
    return this.levelTotal > 0;
  }

  get levelLegend() {
    return this.levelSegments.map((s) => ({
      ...s,
      style: `background:${s.color}`,
      detail: `${s.value} (${pct(s.percent)})`
    }));
  }

  // ---------- Simulations par mois ----------

  get monthlyTitle() {
    return fill(LBL.WnMonthlyTitle, axisNoun(this.data && this.data.axis));
  }

  get monthHeaders() {
    return ((this.data && this.data.months) || []).map((m) => ({
      key: m,
      label: monthLabel(m, LANG)
    }));
  }

  get monthlyRows() {
    return ((this.data && this.data.simulationsByMonth) || []).map((r, i) => ({
      key: `${i}-${r.label}`,
      label: r.label,
      cells: (r.counts || []).map((count, j) => ({
        key: `${j}`,
        value: count
      })),
      total: r.total,
      average: decimal1(r.monthlyAverage)
    }));
  }

  // ---------- Transformation par axe ----------

  get transformTitle() {
    return fill(LBL.WnTransformTitle, axisNoun(this.data && this.data.axis));
  }

  levelSegmentsOf(row) {
    return [
      { label: LBL.WnLevelP1, value: row.priceOne, color: LEVEL_COLORS.P1 },
      { label: LBL.WnLevelP2, value: row.priceTwo, color: LEVEL_COLORS.P2 },
      { label: LBL.WnLevelP3, value: row.priceThree, color: LEVEL_COLORS.P3 },
      {
        label: LBL.WnLevelOffGrid,
        value: row.offGrid,
        color: LEVEL_COLORS["Hors grille"]
      }
    ];
  }

  toTransformRow(row, key, label, isTotal) {
    const hasPercent =
      row.simulatedToWonPercent !== null &&
      row.simulatedToWonPercent !== undefined;
    return {
      key,
      label,
      className: isTotal ? "total-row" : "",
      simulated: row.simulated,
      validated: row.validated,
      won: row.won,
      simToWon: pct(row.simulatedToWonPercent),
      simToWonStyle: hasPercent
        ? `width:${width(row.simulatedToWonPercent)}%;background:#D31876;`
        : "width:0;",
      valToWon: pct(row.validatedToWonPercent),
      levels: this.levelSegmentsOf(row),
      levelsLabel: label
    };
  }

  get transformRows() {
    const rows = ((this.data && this.data.transformation) || []).map((r, i) =>
      this.toTransformRow(r, `${i}-${r.label}`, r.label, false)
    );
    if (this.data && this.data.total && rows.length > 0) {
      rows.push(
        this.toTransformRow(this.data.total, "__total", LBL.WnTotal, true)
      );
    }
    return rows;
  }

  // ---------- Affaires à confirmer ----------

  get pendingRows() {
    return ((this.data && this.data.pending) || []).map((d, i) => ({
      key: `${d.positionId || i}`,
      positionId: d.positionId,
      positionName: d.positionName || "—",
      accountName: d.accountName || "—",
      consultantName: d.consultantName || "—",
      ownerName: d.ownerName || "—",
      versions: (d.versions || []).length,
      wonOn: formatDate(d.wonAt),
      ariaLabel: fill(LBL.WnConfirmAria, d.positionName || d.accountName || "")
    }));
  }

  get hasPending() {
    return this.pendingRows.length > 0;
  }

  get pendingMore() {
    const total = (this.data && this.data.pendingTotal) || 0;
    return total > this.pendingRows.length
      ? fill(LBL.WnPendingMore, total, this.pendingRows.length)
      : "";
  }

  handleConfirm(event) {
    this.dispatchEvent(
      new CustomEvent("confirmdeal", {
        detail: { positionId: event.currentTarget.dataset.position }
      })
    );
  }
}