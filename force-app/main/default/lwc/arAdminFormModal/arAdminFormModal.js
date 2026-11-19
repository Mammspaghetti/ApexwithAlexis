import { LightningElement, api } from "lwc";

import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_Common_Save from "@salesforce/label/c.AR_Common_Save";

const I18N = {
  AR_Common_Cancel: LBL_AR_Common_Cancel,
  AR_Common_Save: LBL_AR_Common_Save
};
const FOCUSABLE_SELECTOR =
  "lightning-input, lightning-combobox, lightning-textarea, input, select, textarea";

/**
 * Modale générique des formulaires d'ajout/modification de l'administration (session 170).
 * Le contenu du formulaire arrive par le slot (il reste dans l'onglet parent : ses handlers et son
 * état ne bougent pas) ; la modale ne fait qu'émettre `save` / `cancel`. Échap et clic sur le
 * fond = `cancel`. Elle n'est montée que tant que le parent affiche le formulaire (`if:true`),
 * le focus est donc posé une seule fois, au premier rendu.
 */
export default class ArAdminFormModal extends LightningElement {
  i18n = I18N;

  @api heading;
  @api saving = false;
  @api saveLabel = I18N.AR_Common_Save;

  _focused = false;
  _resizeObserver = null;
  _onWindowResize = () => this.recalcBodyOverflow();

  connectedCallback() {
    window.addEventListener("resize", this._onWindowResize);
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this._onWindowResize);
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = null;
    }
  }

  renderedCallback() {
    this.observeLayout();
    this.recalcBodyOverflow();
    if (this._focused) {
      return;
    }
    this._focused = true;
    this.focusFirstField();
  }

  handleSlotChange() {
    this.observeLayout();
    this.recalcBodyOverflow();
  }

  /**
   * Défile le corps seulement quand son contenu dépasse la place disponible. La mesure se fait
   * sans la classe de défilement : le corps repasse en débordement visible, son `scrollHeight`
   * reflète alors tout le contenu, et il n'est plus plafonné.
   */
  recalcBodyOverflow() {
    const body = this.template.querySelector(".afm-body");
    if (!body) {
      return;
    }
    body.classList.remove("afm-body_scroll");
    const overflows = body.scrollHeight > body.clientHeight;
    body.classList.toggle("afm-body_scroll", overflows);
  }

  observeLayout() {
    if (typeof ResizeObserver === "undefined") {
      return;
    }
    if (!this._resizeObserver) {
      this._resizeObserver = new ResizeObserver(() =>
        this.recalcBodyOverflow()
      );
    }
    const body = this.template.querySelector(".afm-body");
    if (body) {
      this._resizeObserver.observe(body);
    }
    for (const el of this.assignedElements()) {
      this._resizeObserver.observe(el);
    }
  }

  assignedElements() {
    const slot = this.template.querySelector("slot");
    return slot && slot.assignedElements
      ? slot.assignedElements({ flatten: true })
      : [];
  }

  focusFirstField() {
    for (const el of this.assignedElements()) {
      const target = el.matches(FOCUSABLE_SELECTOR)
        ? el
        : el.querySelector(FOCUSABLE_SELECTOR);
      if (target && typeof target.focus === "function") {
        target.focus();
        return;
      }
    }
    const dialog = this.template.querySelector("section");
    if (dialog) {
      dialog.focus();
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape" || event.key === "Esc") {
      event.stopPropagation();
      this.handleCancel();
    }
  }

  handleCancel() {
    if (this.saving) {
      return;
    }
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleSave() {
    this.dispatchEvent(new CustomEvent("save"));
  }
}