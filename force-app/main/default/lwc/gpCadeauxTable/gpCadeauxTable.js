import LightningDatatable from 'lightning/datatable';
import boutonLarge from './boutonLarge.html';

// Datatable "maison" : la même que lightning-datatable,
// avec en plus un type de colonne "boutonLarge" (bouton qui prend toute la largeur de la colonne)
export default class GpCadeauxTable extends LightningDatatable {
    static customTypes = {
        boutonLarge: {
            template: boutonLarge,
            standardCellLayout: true,
            typeAttributes: ['label', 'variant', 'action', 'rowId']
        }
    };
}
