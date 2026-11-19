import { LightningElement, api } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { formatMoney, formatPercent } from "c/arPricingEngine";
import { formatLabel } from "c/arI18n";
import loadWonDeal from "@salesforce/apex/AR_WonDealService.loadWonDeal";
import confirmWonDealJson from "@salesforce/apex/AR_WonDealService.confirmWonDealJson";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Won_Dlg_Title from "@salesforce/label/c.AR_Won_Dlg_Title";
import LBL_AR_Won_Dlg_WonOn from "@salesforce/label/c.AR_Won_Dlg_WonOn";
import LBL_AR_Won_Dlg_Versions from "@salesforce/label/c.AR_Won_Dlg_Versions";
import LBL_AR_Won_Dlg_Proposed from "@salesforce/label/c.AR_Won_Dlg_Proposed";
import LBL_AR_Won_Dlg_Version from "@salesforce/label/c.AR_Won_Dlg_Version";
import LBL_AR_Won_Dlg_ValidatedOn from "@salesforce/label/c.AR_Won_Dlg_ValidatedOn";
import LBL_AR_Won_Dlg_SignedPrice from "@salesforce/label/c.AR_Won_Dlg_SignedPrice";
import LBL_AR_Won_Dlg_Price1 from "@salesforce/label/c.AR_Won_Dlg_Price1";
import LBL_AR_Won_Dlg_Price2 from "@salesforce/label/c.AR_Won_Dlg_Price2";
import LBL_AR_Won_Dlg_Price3 from "@salesforce/label/c.AR_Won_Dlg_Price3";
import LBL_AR_Won_Dlg_Other from "@salesforce/label/c.AR_Won_Dlg_Other";
import LBL_AR_Won_Dlg_OffGrid from "@salesforce/label/c.AR_Won_Dlg_OffGrid";
import LBL_AR_Won_Dlg_Amount from "@salesforce/label/c.AR_Won_Dlg_Amount";
import LBL_AR_Won_Dlg_Level from "@salesforce/label/c.AR_Won_Dlg_Level";
import LBL_AR_Won_Dlg_Date from "@salesforce/label/c.AR_Won_Dlg_Date";
import LBL_AR_Won_Dlg_Later from "@salesforce/label/c.AR_Won_Dlg_Later";
import LBL_AR_Won_Dlg_Confirm from "@salesforce/label/c.AR_Won_Dlg_Confirm";
import LBL_AR_Won_Dlg_NotSet from "@salesforce/label/c.AR_Won_Dlg_NotSet";
import LBL_AR_Won_Dlg_Mc2 from "@salesforce/label/c.AR_Won_Dlg_Mc2";
import LBL_AR_Won_Dlg_LoadError from "@salesforce/label/c.AR_Won_Dlg_LoadError";

const OTHER = "OTHER";
const LEVEL_LABELS = {
  P1: LBL_AR_Won_Dlg_Price1,
  P2: LBL_AR_Won_Dlg_Price2,
  P3: LBL_AR_Won_Dlg_Price3,
  "Hors grille": LBL_AR_Won_Dlg_OffGrid
};

/** Niveau le plus haut atteint — miroir de AR_SignedPriceLevel.compute (Apex). */
export function computeSignedLevel(amount, p1, p2, p3, clientGrid) {
  if (
    amount === null ||
    amount === undefined ||
    amount === "" ||
    Number.isNaN(Number(amount))
  ) {
    return null;
  }
  if (p1 === null || p1 === undefined) {
    return null;
  }
  const value = Number(amount);
  if (value >= p1) {
    return "P1";
  }
  if (clientGrid) {
    return "Hors grille";
  }
  if (p2 !== null && p2 !== undefined && value >= p2) {
    return "P2";
  }
  if (p3 !== null && p3 !== undefined && value >= p3) {
    return "P3";
  }
  return "Hors grille";
}

function todayIso() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function formatDate(value) {
  if (!value) {
    return "";
  }
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString("fr-FR");
}

export default class ArWonDealDialog extends LightningElement {
  _positionId;
  @api
  get positionId() {
    return this._positionId;
  }
  set positionId(value) {
    if (value !== this._positionId) {
      this._positionId = value;
      if (this._connected) {
        this.load();
      }
    }
  }
  // Version à présélectionner (ex. la matrice depuis laquelle la fenêtre est ouverte).
  @api preferredMatrixId;

  deal;
  selectedMatrixId;
  selectedLevel = "P1";
  freeAmount = "";
  signedDate = todayIso();
  isLoading = true;
  isSaving = false;
  errorMessage = "";
  _connected = false;

  i18n = {
    loading: LBL_AR_Common_Loading,
    versions: LBL_AR_Won_Dlg_Versions,
    signedPrice: LBL_AR_Won_Dlg_SignedPrice,
    amount: LBL_AR_Won_Dlg_Amount,
    date: LBL_AR_Won_Dlg_Date,
    later: LBL_AR_Won_Dlg_Later,
    confirm: LBL_AR_Won_Dlg_Confirm,
    proposed: LBL_AR_Won_Dlg_Proposed
  };

  connectedCallback() {
    this._connected = true;
    this.load();
  }

  disconnectedCallback() {
    this._connected = false;
  }

  async load() {
    if (!this._positionId) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const deal = await loadWonDeal({ positionId: this._positionId });
      this.deal = deal || null;
      if (!deal || !deal.versions || deal.versions.length === 0) {
        this.errorMessage = LBL_AR_Won_Dlg_LoadError;
      } else {
        this.preselect(deal);
      }
    } catch (error) {
      this.deal = null;
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isLoading = false;
    }
  }

  preselect(deal) {
    const won = deal.versions.find((v) => v.won);
    const preferred = deal.versions.find(
      (v) => v.matrixId === this.preferredMatrixId
    );
    // Versions triées de la plus récente à la plus ancienne : la première est la dernière validée.
    const chosen = won || preferred || deal.versions[0];
    this.selectedMatrixId = chosen.matrixId;
    if (chosen.won && chosen.signedPriceLevel) {
      this.applyConfirmedPrice(chosen);
    } else {
      this.selectedLevel = "P1";
      this.freeAmount = "";
    }
    this.signedDate =
      chosen.won && chosen.wonDate ? chosen.wonDate : todayIso();
  }

  applyConfirmedPrice(version) {
    const level = version.signedPriceLevel;
    const priceOf = {
      P1: version.price1,
      P2: version.price2,
      P3: version.price3
    };
    if (
      LEVEL_LABELS[level] &&
      level !== "Hors grille" &&
      priceOf[level] === version.signedTjm
    ) {
      this.selectedLevel = level;
      this.freeAmount = "";
    } else {
      this.selectedLevel = OTHER;
      this.freeAmount =
        version.signedTjm === null || version.signedTjm === undefined
          ? ""
          : String(version.signedTjm);
    }
  }

  get selectedVersion() {
    return (
      this.deal &&
      this.deal.versions.find((v) => v.matrixId === this.selectedMatrixId)
    );
  }

  get hasDeal() {
    return !!this.deal && this.deal.versions.length > 0;
  }

  get title() {
    return formatLabel(
      LBL_AR_Won_Dlg_Title,
      this.deal ? this.deal.accountName || "" : ""
    );
  }

  get recap() {
    if (!this.deal) {
      return "";
    }
    const parts = [this.deal.positionName, this.deal.consultantName];
    if (this.deal.wonAt) {
      parts.push(
        formatLabel(LBL_AR_Won_Dlg_WonOn, formatDate(this.deal.wonAt))
      );
    }
    return parts.filter((p) => !!p).join(" · ");
  }

  get versionCards() {
    if (!this.deal) {
      return [];
    }
    return this.deal.versions.map((v, index) => {
      const selected = v.matrixId === this.selectedMatrixId;
      const cur = v.currencyCode;
      const priceParts = [
        `${LBL_AR_Won_Dlg_Price1} ${formatMoney(v.price1, cur)}`
      ];
      if (v.price2 !== null && v.price2 !== undefined && !v.clientGrid) {
        priceParts.push(
          `${LBL_AR_Won_Dlg_Price2} ${formatMoney(v.price2, cur)}`
        );
      }
      if (v.price3 !== null && v.price3 !== undefined && !v.clientGrid) {
        priceParts.push(
          `${LBL_AR_Won_Dlg_Price3} ${formatMoney(v.price3, cur)}`
        );
      }
      return {
        matrixId: v.matrixId,
        title: formatLabel(
          LBL_AR_Won_Dlg_Version,
          v.version === null || v.version === undefined ? "" : v.version
        ),
        validatedOn: formatLabel(
          LBL_AR_Won_Dlg_ValidatedOn,
          formatDate(v.validatedAt)
        ),
        prices: priceParts.join(" · "),
        mc2: formatLabel(
          LBL_AR_Won_Dlg_Mc2,
          v.mc2Percent === null || v.mc2Percent === undefined
            ? LBL_AR_Won_Dlg_NotSet
            : formatPercent(v.mc2Percent)
        ),
        proposed: index === 0,
        selected,
        cssClass: selected ? "ver-card ver-card-selected" : "ver-card",
        ariaChecked: selected ? "true" : "false"
      };
    });
  }

  get priceCards() {
    const v = this.selectedVersion;
    if (!v) {
      return [];
    }
    const cur = v.currencyCode;
    const slots = [
      { key: "P1", label: LBL_AR_Won_Dlg_Price1, value: v.price1 },
      {
        key: "P2",
        label: LBL_AR_Won_Dlg_Price2,
        value: v.clientGrid ? null : v.price2
      },
      {
        key: "P3",
        label: LBL_AR_Won_Dlg_Price3,
        value: v.clientGrid ? null : v.price3
      }
    ];
    const cards = slots.map((slot) => {
      const available = slot.value !== null && slot.value !== undefined;
      const selected = this.selectedLevel === slot.key;
      return {
        key: slot.key,
        label: slot.label,
        amount: available
          ? formatMoney(slot.value, cur)
          : LBL_AR_Won_Dlg_NotSet,
        disabled: !available,
        cssClass: `price-card${selected ? " price-card-selected" : ""}${available ? "" : " price-card-disabled"}`,
        ariaChecked: selected ? "true" : "false"
      };
    });
    const otherSelected = this.selectedLevel === OTHER;
    cards.push({
      key: OTHER,
      label: LBL_AR_Won_Dlg_Other,
      amount: "…",
      disabled: false,
      cssClass: `price-card${otherSelected ? " price-card-selected" : ""}`,
      ariaChecked: otherSelected ? "true" : "false"
    });
    return cards;
  }

  get isOtherSelected() {
    return this.selectedLevel === OTHER;
  }

  get computedLevel() {
    const v = this.selectedVersion;
    if (!v || !this.isOtherSelected) {
      return null;
    }
    return computeSignedLevel(
      this.freeAmount,
      v.price1,
      v.price2,
      v.price3,
      v.clientGrid
    );
  }

  get computedLevelText() {
    const level = this.computedLevel;
    return level ? formatLabel(LBL_AR_Won_Dlg_Level, LEVEL_LABELS[level]) : "";
  }

  get canConfirm() {
    if (this.isSaving || !this.selectedVersion || !this.signedDate) {
      return false;
    }
    if (this.isOtherSelected) {
      return this.computedLevel !== null;
    }
    return true;
  }

  get confirmDisabled() {
    return !this.canConfirm;
  }

  handleSelectVersion(event) {
    const id = event.currentTarget.dataset.id;
    if (id === this.selectedMatrixId) {
      return;
    }
    this.selectedMatrixId = id;
    const version = this.selectedVersion;
    if (version && version.won && version.signedPriceLevel) {
      this.applyConfirmedPrice(version);
    } else if (this.selectedLevel !== OTHER) {
      this.selectedLevel = "P1";
    }
  }

  handleSelectLevel(event) {
    const key = event.currentTarget.dataset.key;
    const card = this.priceCards.find((c) => c.key === key);
    if (!card || card.disabled) {
      return;
    }
    this.selectedLevel = key;
  }

  handleAmountChange(event) {
    this.freeAmount = event.target.value;
  }

  handleDateChange(event) {
    this.signedDate = event.target.value;
  }

  handleLater() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  async handleConfirm() {
    if (!this.canConfirm) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = "";
    const other = this.isOtherSelected;
    try {
      await confirmWonDealJson({
        requestJson: JSON.stringify({
          matrixId: this.selectedMatrixId,
          priceLevel: other ? "" : this.selectedLevel,
          signedTjm: other ? Number(this.freeAmount) : null,
          signedDate: this.signedDate
        })
      });
      this.dispatchEvent(
        new CustomEvent("confirmed", {
          detail: {
            matrixId: this.selectedMatrixId,
            positionId: this._positionId
          }
        })
      );
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isSaving = false;
    }
  }
}