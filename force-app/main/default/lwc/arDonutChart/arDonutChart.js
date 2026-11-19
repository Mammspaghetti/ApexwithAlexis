import { LightningElement, api } from "lwc";
import { formatLabel } from "c/arI18n";
import LBL_AR_DB_SeverityLegend from "@salesforce/label/c.AR_DB_SeverityLegend";

const RADIUS = 40;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export default class ArDonutChart extends LightningElement {
  @api centerLabel;
  @api ariaTitle;
  _segments = [];

  @api
  get segments() {
    return this._segments;
  }
  set segments(value) {
    this._segments = Array.isArray(value) ? value : [];
  }

  get total() {
    return this._segments.reduce((sum, s) => sum + (Number(s.value) || 0), 0);
  }

  percentOf(value) {
    return this.total > 0 ? (Number(value) / this.total) * 100 : 0;
  }

  formatShare(value) {
    return `${Math.round(this.percentOf(value) * 10) / 10} %`;
  }

  // Un arc par segment non nul : stroke-dasharray = longueur de l'arc, décalage = somme des arcs précédents.
  get arcs() {
    let offset = 0;
    return this._segments
      .filter((s) => Number(s.value) > 0)
      .map((s) => {
        const length = (Number(s.value) / this.total) * CIRCUMFERENCE;
        const arc = {
          key: s.label,
          color: s.color,
          length,
          dashArray: `${length} ${CIRCUMFERENCE - length}`,
          dashOffset: -offset,
          tooltip: formatLabel(
            LBL_AR_DB_SeverityLegend,
            s.label,
            s.value,
            this.formatShare(s.value)
          )
        };
        offset += length;
        return arc;
      });
  }

  get ariaLabel() {
    const parts = this._segments.map((s) =>
      formatLabel(
        LBL_AR_DB_SeverityLegend,
        s.label,
        s.value,
        this.formatShare(s.value)
      )
    );
    return [this.ariaTitle, ...parts].filter(Boolean).join(", ");
  }

  get hasData() {
    return this.total > 0;
  }

  get radius() {
    return RADIUS;
  }
}