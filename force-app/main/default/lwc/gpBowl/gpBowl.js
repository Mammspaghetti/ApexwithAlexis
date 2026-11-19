import { api, LightningElement } from 'lwc';

// Positions des croquettes dans la gamelle (left %, bottom px, rotation)
const POSITIONS = [
    { left: 22, bottom: 0, rot: -15 },
    { left: 40, bottom: 0, rot: 20 },
    { left: 58, bottom: 0, rot: -30 },
    { left: 31, bottom: 9, rot: 40 },
    { left: 49, bottom: 9, rot: -10 },
    { left: 67, bottom: 3, rot: 25 },
    { left: 13, bottom: 4, rot: 10 },
    { left: 40, bottom: 17, rot: -35 }
];

export default class GpBowl extends LightningElement {
    @api capacite = 5; // croquettes actuellement dans la gamelle
    @api capaciteMax = 5; // taille de la gamelle
    @api faim = 0; // faim actuelle de la mascotte
    @api gave = false; // true quand la mascotte a trop mangé (bloque Nourrir)

    croquetteQuiSaute = false;
    secoue = false;

    get croquettes() {
        const nb = Math.min(this.capacite, POSITIONS.length);
        return POSITIONS.slice(0, nb).map((p, index) => ({
            id: index,
            style: `left:${p.left}%;bottom:${p.bottom}px;transform:rotate(${p.rot}deg);`
        }));
    }

    get estVide() {
        return this.capacite <= 0;
    }

    get estPleine() {
        return this.capacite >= this.capaciteMax;
    }

    get aPasFaim() {
        return this.faim <= 0;
    }

    // Le bouton Nourrir est désactivé si gamelle vide ou mascotte gavée
    // (on peut dépasser la limite de faim : elle grossit)
    get nourrirDesactive() {
        return this.estVide || this.gave;
    }

    get message() {
        if (this.gave) return 'Elle va exploser ! 🤢';
        if (this.estVide) return 'Gamelle vide ! 😿';
        if (this.aPasFaim) return 'Plus faim… attention ! 😬';
        return `${this.capacite}/${this.capaciteMax} croquettes`;
    }

    get gamelleClass() {
        return this.croquetteQuiSaute ? 'gamelle-bol miam' : 'gamelle-bol';
    }

    nourrir() {
        if (this.nourrirDesactive) return;
        this.animer();
        this.dispatchEvent(new CustomEvent('gpmanger'));
    }

    remplir() {
        this.dispatchEvent(new CustomEvent('gpremplir'));
    }

    voler() {
        this.dispatchEvent(new CustomEvent('gpvol'));
    }

    // Petite secousse de la gamelle quand on nourrit
    animer() {
        this.croquetteQuiSaute = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.croquetteQuiSaute = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.croquetteQuiSaute = false;
            }, 400);
        });
    }

    @api secouer(){
        this.secoue = true;
        setTimeout(() => { this.secoue = false}, 600);
    }

    get classBol(){
        return this.secoue ? "Etat1" : "Etat2";
    }
}