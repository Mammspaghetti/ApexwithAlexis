import { LightningElement , api} from 'lwc';

export default class HhBol extends LightningElement {
   @api capacity = 5;


    secoue= false;

   servirCroquette(){
    this.dispatchEvent(new CustomEvent('mangerhh'));
   }

    // croquette(){
    //     return this.capatite --;
    // }

    @api secouer()
    {
        this.secoue = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation     
        setTimeout(() => {this.secoue = false;}, 600);

    }

    get classBol(){
        return this.secoue ? "minibaby" :  "baby";
    }

}