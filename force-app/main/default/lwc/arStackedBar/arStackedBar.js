import { LightningElement, api } from "lwc";
import { formatLabel } from "c/arI18n";
import LBL_AR_DB_SeverityLegend from "@salesforce/label/c.AR_DB_SeverityLegend";

export default class ArStackedBar extends LightningElement {
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

  describe(s) {
    const pct = this.total > 0 ? (Number(s.value) / this.total) * 100 : 0;
    return formatLabel(
      LBL_AR_DB_SeverityLegend,
      s.label,
      s.value,
      `${Math.round(pct * 10) / 10} %`
    );
  }

  // Largeurs en % de la barre ; les segments nuls ne sont pas dessinés.
  get parts() {
    let x = 0;
    return this._segments
      .filter((s) => Number(s.value) > 0)
      .map((s) => {
        const width = (Number(s.value) / this.total) * 100;
        const part = {
          key: s.label,
          color: s.color,
          x,
          width,
          tooltip: this.describe(s)
        };
        x += width;
        return part;
      });
  }

  get ariaLabel() {
    return [this.ariaTitle, ...this._segments.map((s) => this.describe(s))]
      .filter(Boolean)
      .join(", ");
  }

  get hasData() {
    return this.total > 0;
  }
}