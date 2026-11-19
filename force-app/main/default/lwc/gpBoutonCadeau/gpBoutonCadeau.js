import { LightningElement, api } from 'lwc';

// Bouton d'une ligne du tableau des cadeaux (Donner / Reprendre)
export default class GpBoutonCadeau extends LightningElement {
    @api label;
    @api variant;
    @api action;
    @api rowId;

    handleClick() {
        // bubbles + composed : l'événement traverse le datatable jusqu'à gpMascotte
        this.dispatchEvent(
            new CustomEvent('boutoncadeau', {
                bubbles: true,
                composed: true,
                detail: { action: this.action, rowId: this.rowId }
            })
        );
    }
}
