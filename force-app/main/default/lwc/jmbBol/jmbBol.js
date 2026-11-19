import { LightningElement , api} from 'lwc';

export default class JmbBol extends LightningElement {

    // première lettre de la constante en majsucule, habitude de lecture
    @api capacite = 10;
    secoue = false ;

    servirCroquette(){
        this.dispatchEvent( new CustomEvent ('mangerjmb')) ;
    }

    @api secouer(){
        this.secoue = true ;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.secoue = false; }, 600);

    }

    get classBol(){
        return this.secoue ? "Etat1" : "Etat2" ;
    }


}