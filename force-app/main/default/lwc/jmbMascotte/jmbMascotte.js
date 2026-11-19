import { LightningElement, wire } from 'lwc';
import listerCadeaux from '@salesforce/apex/JMB_Mascotte.listerCadeaux';
import offrirCadeau from '@salesforce/apex/JMB_Mascotte.offrirCadeau';
import { createRecord } from 'lightning/uiRecordApi';
import CADEAU from '@salesforce/schema/JMB_KDO__c';
import NOM_CADEAU from '@salesforce/schema/JMB_KDO__c.Name';
import { refreshApex } from '@salesforce/apex';



const Colonnes=[{ label: 'Nom du cadeau', fieldName: 'Name' },    { label: 'Offert', fieldName: 'AB_Offert__c', type: 'boolean' },
                {type: 'button', typeAttributes: { label: 'Offrir', name: 'offrir', variant: 'brand' }}];

//Detail de la classe
export default class JmbMascotte extends LightningElement {
    //création d'une variable, pas besoin de définir le type
    faim = 5 ;
    rire = 0 ;
    croquette = 8 ;
    nomCadeau = '' ;
    
    colonnes = Colonnes;

    message;
    @wire(listerCadeaux)
    cadeaux;

    nom = 'Tony Pastrami';

    get humeur() {
            return this.faim > 3 ? ' Pas content' : 'Content';
    }

        laver(){
            this.rire = this.rire + 1;
    }
        nourrir(){
            this.faim <= 0 ? this.faim = 0: this.faim = this.faim - 1 ;

    }

        handleServir(){
            this.croquette > 0 ? this.croquette-- : this.croquette;
    }
        remplir(){
            this.croquette = 8 ;
            this.refs.bol.secouer() ;
    
        }

        handleNomCadeau(event) {
            this.nomCadeau = event.target.value;
        }

        async creerCadeau(){
            const nom = this.nomCadeau.trim();
              if (!nom) {
                this.message = 'Donne un nom au cadeau.';
                return;
            }
            try {
                await createRecord({
                apiName: CADEAU.objectApiName,
                fields: { [NOM_CADEAU.fieldApiName]: nom }
                });
                this.message = 'Cadeau créé : ' + nom;
                this.nomCadeau = '';
            } catch (e) {
                this.message = e?.body?.message ?? e?.message;
            }
        }

        get cadeauxEnStock() {
            return (this.cadeaux?.data ?? []).filter((c) => !c.Offert__c);
        }

        get aucunCadeau() {
            return this.cadeauxEnStock.length === 0;
        }
 
        async handleRowAction(event){
            const cadeau = event.detail.row;
            try {
                await offrirCadeau({ cadeauId: cadeau.Id });
                this.dernierCadeau = cadeau.Name;
                this.message = 'Merci pour : ' + cadeau.Name + ' !';
                await refreshApex(this.cadeaux);
            } catch (e) {
            this.message = e?.body?.message ?? e?.message;
            }
        }
        


}