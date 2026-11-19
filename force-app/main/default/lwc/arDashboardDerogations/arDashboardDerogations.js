import { LightningElement, api } from "lwc";
import LANG from "@salesforce/i18n/lang";
import {
  LBL,
  BRAND,
  BRAND_PALE,
  MIN_SAMPLE_SIZE,
  axisNoun,
  fill,
  pct,
  days,
  monthLabel,
  width
} from "c/arDashboardShared";

const DECISION_COLORS = {
  accepted: "#16a34a",
  refused: "#dc2626",
  pending: "#94a3b8"
};

export default class ArDashboardDerogations extends LightningElement {
  @api data;

  i18n = LBL;

  get kpis() {
    return (this.data && this.data.kpis) || {};
  }

  get hasRequests() {
    return (this.kpis.requestedCount || 0) > 0;
  }

  get rateText() {
    return pct(this.kpis.derogationRatePercent);
  }

  get acceptedText() {
    return pct(this.kpis.acceptedPercent);
  }

  get acceptedDetail() {
    return fill(
      LBL.DrKpiAcceptedDetail,
      this.kpis.acceptedCount || 0,
      this.kpis.refusedCount || 0,
      this.kpis.pendingCount || 0
    );
  }

  get delayText() {
    return days(this.kpis.medianDelayDays);
  }

  // ---------- Dérogations par mois ----------

  get monthColumns() {
    const months = (this.data && this.data.monthly) || [];
    const totals = months.map(
      (m) => (m.accepted || 0) + (m.refused || 0) + (m.pending || 0)
    );
    const max = Math.max(1, ...totals);
    return months.map((m, i) => {
      const label = monthLabel(m.month, LANG);
      return {
        key: m.month,
        label,
        total: totals[i],
        columnStyle: `height:${(totals[i] / max) * 100}%;`,
        title: `${label} : ${totals[i]}`,
        parts: ["accepted", "refused", "pending"]
          .filter((k) => m[k] > 0)
          .map((k) => ({
            key: k,
            style: `flex:${m[k]};background:${DECISION_COLORS[k]};`,
            title: `${this.decisionLabel(k)} : ${m[k]}`
          }))
      };
    });
  }

  get monthlyHasData() {
    return this.monthColumns.some((c) => c.total > 0);
  }

  decisionLabel(key) {
    return {
      accepted: LBL.DrAccepted,
      refused: LBL.DrRefused,
      pending: LBL.DrPending
    }[key];
  }

  get decisionLegend() {
    return ["accepted", "refused", "pending"].map((k) => ({
      key: k,
      label: this.decisionLabel(k),
      style: `background:${DECISION_COLORS[k]}`
    }));
  }

  // ---------- Taux par axe ----------

  get rateTitle() {
    return fill(LBL.DrRateByAxisTitle, axisNoun(this.data && this.data.axis));
  }

  get rateRows() {
    const rows = (this.data && this.data.rateByAxis) || [];
    const global = this.kpis.derogationRatePercent;
    return rows.map((r) => {
      const hasRate = r.ratePercent !== null && r.ratePercent !== undefined;
      const above = hasRate && global !== null && r.ratePercent > global;
      return {
        key: r.key || r.label,
        label: r.label,
        detail: hasRate
          ? `${pct(r.ratePercent)} (${r.derogationValidatedCount}/${r.validatedCount})`
          : "—",
        barStyle: hasRate
          ? `width:${width(r.ratePercent)}%;background:${above ? BRAND : BRAND_PALE};`
          : "width:0;"
      };
    });
  }

  get rateLegend() {
    return [
      { key: "above", label: LBL.DrRateAbove, style: `background:${BRAND}` },
      {
        key: "below",
        label: LBL.DrRateBelow,
        style: `background:${BRAND_PALE}`
      }
    ];
  }

  // ---------- Motifs ----------

  get pills() {
    const selected = (this.data && this.data.motifAxisValue) || "";
    const options = (this.data && this.data.motifAxisOptions) || [];
    return [{ key: "", label: LBL.DrAll }, ...options].map((o) => {
      const value = o.key || "";
      const active = value === selected;
      return {
        key: value || "__all",
        value,
        label: o.label,
        className: active ? "pill is-active" : "pill",
        pressed: String(active)
      };
    });
  }

  get reasons() {
    return (this.data && this.data.reasons) || {};
  }

  get hasReasons() {
    return (this.reasons.derogationCount || 0) > 0;
  }

  get reasonRows() {
    const rows = (this.reasons.top || []).map((r) => ({
      key: r.reasonName,
      label: r.reasonName,
      detail: `${r.count} (${pct(r.percent)})`,
      barStyle: `width:${width(r.percent)}%;background:${BRAND};`
    }));
    if (this.reasons.othersCount > 0) {
      rows.push({
        key: "__others",
        label: LBL.PostOther,
        detail: `${this.reasons.othersCount} (${pct(this.reasons.othersPercent)})`,
        barStyle: `width:${width(this.reasons.othersPercent)}%;background:#94a3b8;`
      });
    }
    return rows;
  }

  get reasonsInsufficient() {
    return (
      this.hasReasons && (this.reasons.derogationCount || 0) < MIN_SAMPLE_SIZE
    );
  }

  handlePill(event) {
    const value = event.currentTarget.dataset.value;
    this.dispatchEvent(
      new CustomEvent("motiffilter", { detail: { value: value || null } })
    );
  }

  // ---------- Valideurs et clients ----------

  get validatorRows() {
    return ((this.data && this.data.validators) || []).map((v, i) => {
      const decided = (v.accepted || 0) + (v.refused || 0) + (v.pending || 0);
      const part = (n) => (decided > 0 ? (n / decided) * 100 : 0);
      return {
        key: v.validatorId || `v${i}`,
        name: v.name,
        received: v.received,
        split: `${v.accepted} / ${v.refused}`,
        acceptedStyle: `width:${part(v.accepted)}%;background:${DECISION_COLORS.accepted};`,
        refusedStyle: `width:${part(v.refused)}%;background:${DECISION_COLORS.refused};`,
        pendingStyle: `width:${part(v.pending)}%;background:${DECISION_COLORS.pending};`,
        refusal: pct(v.refusalPercent),
        delay: days(v.medianDelayDays)
      };
    });
  }

  get clientRows() {
    return ((this.data && this.data.topClients) || []).map((c, i) => ({
      key: `${i}-${c.accountName}`,
      accountName: c.accountName,
      derogationCount: c.derogationCount,
      validatedCount: c.validatedCount,
      rate: pct(c.ratePercent),
      mainReason: c.mainReason || "—"
    }));
  }
}