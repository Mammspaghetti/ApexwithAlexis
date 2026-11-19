import { LightningElement, wire } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import listerCadeaux from '@salesforce/apex/GP_Mascotte.listerCadeaux';
import supprimerCadeau from '@salesforce/apex/GP_Mascotte.supprimerCadeau';
import donnerCadeau from '@salesforce/apex/GP_Mascotte.donnerCadeau';
import CADEAU from '@salesforce/schema/GPGift__c';
// Name = champ texte "GPGift Name" ; offert__c = case à cocher
import NOM_CADEAU from '@salesforce/schema/GPGift__c.Name';
import OFFERT from '@salesforce/schema/GPGift__c.offert__c';

export default class GpMascotte extends LightningElement {
    nomCadeau = '';
    isEnvoi = false;

    // Liste des cadeaux lue en base via Apex (GP_Mascotte.listerCadeaux, triée du plus récent au plus ancien).
    // On garde le résultat brut du @wire pour pouvoir le rafraîchir (refreshApex).
    nbCadeauxAffiches = 5;
    @wire(listerCadeaux)
    cadeauxWire;

    // On n'affiche que les N derniers
    get cadeaux() {
        return (this.cadeauxWire?.data ?? []).slice(0, this.nbCadeauxAffiches);
    }

    get hasCadeaux() {
        return this.cadeaux.length > 0;
    }

    // Colonnes du lightning-datatable
    colonnes = [
        {
            // Croix rouge à gauche : retirer le cadeau
            type: 'button-icon',
            fixedWidth: 40,
            typeAttributes: {
                name: 'supprimer',
                iconName: 'utility:close',
                iconClass: 'slds-icon-text-error',
                variant: 'bare',
                title: 'Supprimer ce cadeau',
                alternativeText: 'Supprimer'
            }
        },
        {
            // Icône cadeau si pas encore donné, coche verte si donné
            label: 'Cadeau',
            fieldName: 'Name',
            type: 'text',
            wrapText: true,
            iconName: 'utility:gift',
            cellAttributes: {
                iconName: { fieldName: 'nomIcone' },
                iconPosition: 'left',
                class: { fieldName: 'nomClasse' }
            }
        },
        {
            label: 'Date',
            fieldName: 'CreatedDate',
            type: 'date',
            initialWidth: 110,
            iconName: 'utility:event',
            typeAttributes: { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' },
            cellAttributes: { class: 'slds-text-color_weak' }
        },
        {
            // Bouton Donner (vert) / Reprendre (rouge) selon offert__c
            type: 'button',
            initialWidth: 115,
            typeAttributes: {
                name: 'donner',
                label: { fieldName: 'boutonLabel' },
                variant: { fieldName: 'boutonVariant' },
                title: { fieldName: 'boutonLabel' }
            }
        }
    ];

    // Lignes du tableau : on ajoute le libellé et la couleur du bouton selon offert__c
    get lignes() {
        return this.cadeaux.map((c) => ({
            ...c,
            boutonLabel: c.offert__c ? 'Reprendre' : 'Donner',
            boutonVariant: c.offert__c ? 'destructive' : 'success',
            nomIcone: c.offert__c ? 'utility:check' : 'utility:gift',
            // Classes SLDS (les seules qui s'appliquent dans un datatable)
            nomClasse: c.offert__c ? 'slds-text-color_success slds-text-title_bold' : 'slds-text-title_bold'
        }));
    }

    // Badge du titre : combien de cadeaux affichés ont été donnés
    get compteurDonnes() {
        const donnes = this.cadeaux.filter((c) => c.offert__c).length;
        return `${donnes} / ${this.cadeaux.length} donnés`;
    }

    // Clic sur un bouton d'une ligne du tableau
    handleRowAction(event) {
        const action = event.detail.action.name;
        const ligne = event.detail.row;
        if (action === 'supprimer') {
            this.supprimer(ligne.Id);
        } else if (action === 'donner') {
            // Pas donné -> on le donne ; déjà donné -> on le reprend
            this.donner(ligne.Id, ligne.Name, !ligne.offert__c);
        }
    }

    // Content seulement quelques secondes juste après qu'on lui a donné un cadeau
    // (on coche la case "Donné")
    aUnCadeau = false;
    aUnCadeauTimer;
    dureeContent = 2500; // en millisecondes

    faim = 5;
    nom = 'TAMAGP-chi';
    croquettesMax = 5;
    croquettes = 5;

    // Nombre de croquettes mangées alors qu'elle n'avait plus faim
    surpoids = 0;
    surpoidsMax = 5;

    // Message temporaire affiché dans la zone du STOP (remplace les toasts)
    message = '';
    messageTimer;

    // true pendant 2,5 s après un vol
    isVole = false;
    voleTimer;

    // Elle grossit dès le premier dépassement
    get isGros() {
        return this.surpoids > 0;
    }

    // Plus de nourriture possible après 5 dépassements
    get isGave() {
        return this.surpoids >= this.surpoidsMax;
    }

    get bulleClass() {
        return this.isGros ? 'mascotte-bulle gros' : 'mascotte-bulle';
    }

    // "STOP" de plus en plus gros (1 à 5)
    get stopTexte() {
        return 'STOP' + '!'.repeat(this.surpoids);
    }

    get stopStyle() {
        return `font-size:${12 + this.surpoids * 8}px;`;
    }

    get stopClass() {
        return `stop stop-${this.surpoids}`;
    }

    // Niveau de satisfaction
    get niveauDeJoie() {
        if (this.isGros) return '🐷 GROS';
        if (this.isTresGrognon) return '🤬 TRÈS GROGNON';
        if (this.aUnCadeau) return '🎁 CONTENT';
        return this.faim > 3 ? '💢 GROGNON' : '🥰 CONTENT';
    }

    // Déterminer si la mascotte est grognon
    get isGrognon() {
        return this.faim > 2;
    }

    // Très grognon : elle a faim ET aucun cadeau en base
    // (on attend que la liste soit chargée pour ne pas "clignoter" au démarrage)
    get isTresGrognon() {
        return this.isGrognon && this.cadeauxWire?.data !== undefined && !this.hasCadeaux;
    }

    // Simple grognon : on cache le 💢 seul quand elle est très grognon ou contente (cadeau)
    get isGrognonSimple() {
        return this.isGrognon && !this.isTresGrognon && !this.aUnCadeau;
    }

    // true pendant 2,5 s quand on lui reprend un cadeau (bras qui s'agitent)
    isReclame = false;
    reclameTimer;

    // true pendant 2,5 s après la suppression d'un cadeau
    isTriste = false;
    tristeTimer;

    // Changer le visage selon son humeur
    get visage() {
        if (this.isTriste) return '(T w T)';
        if (this.isGave) return '(×﹏×)';
        if (this.isGros) return '(｡>﹏<｡)';
        if (this.isTresGrognon) return 'ヽ(ಠ益ಠヽ)';
        if (this.aUnCadeau) return '(> w <)';
        return this.isGrognon ? 'ಠ益ಠ' : '◕‿◕';
    }

    // true seulement quand c'est le visage très grognon qui est affiché
    // (pleurer / gros / gavé passent avant)
    get isVisageTresGrognon() {
        return this.isTresGrognon && !this.isTriste && !this.isGave && !this.isGros;
    }

    // Visage plus petit en très grognon pour qu'il tienne sur une ligne
    get visageClass() {
        return this.isVisageTresGrognon ? 'mascotte-visage tres-grognon' : 'mascotte-visage';
    }

    // Affiche un message façon STOP pendant 2,5 s
    afficherMessage(texte) {
        this.message = texte;
        clearTimeout(this.messageTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.messageTimer = setTimeout(() => {
            this.message = '';
        }, 2500);
    }

    // La gamelle sert une croquette : la mascotte mange
    handleManger() {
        if (this.croquettes <= 0 || this.isGave) {
            return;
        }
        this.croquettes--;
        if (this.faim > 0) {
            this.faim--;
        } else {
            // Plus faim mais on la nourrit quand même : elle grossit
            this.surpoids++;
            this.afficherMessage(this.isGave ? 'JE VAIS EXPLOSER ! 🤢' : 'J’AI PLUS FAIM ! 🐷');
        }
    }

    // La gamelle est remplie au maximum
    handleRemplir() {
        this.croquettes = this.croquettesMax;
    }

    // On vole la nourriture : gamelle vidée, mascotte furieuse
    handleVol() {
        this.faim = 5; // retour à la faim max
        this.croquettes = 0;
        this.surpoids = 0; // affamée, elle reperd ses kilos

        // Le parent appelle la méthode @api de l'enfant via sa ref
        // (le nom doit être identique au lwc:ref="bolgp" du HTML)
        this.refs.bolgp.secouer();

        // Affiche "C'EST MAL DE VOLER" (dans le HTML) pendant 2,5 s
        this.isVole = true;
        clearTimeout(this.voleTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.voleTimer = setTimeout(() => {
            this.isVole = false;
        }, 2500);
    }

    handleNomCadeau(event) {
        this.nomCadeau = event.target.value;
    }

    // Le bouton est grisé si pas de nom ou si un envoi est en cours
    get isEnvoiImpossible() {
        return this.isEnvoi || !this.nomCadeau.trim();
    }

    async creerCadeau() {
        const nom = this.nomCadeau.trim();
        if (!nom) {
            this.afficherMessage('Donne un nom au cadeau.');
            return;
        }
        this.isEnvoi = true;
        try {
            // Envoi vers Salesforce : crée un enregistrement GPGift__c
            // Pas encore donné : on le donnera en cochant la case dans le tableau
            const cadeau = await createRecord({
                apiName: CADEAU.objectApiName,
                fields: {
                    [NOM_CADEAU.fieldApiName]: nom,
                    [OFFERT.fieldApiName]: false
                }
            });
            // Réponse de Salesforce : l'enregistrement créé, avec ses champs
            this.afficherMessage('OH UN CADEAU : ' + cadeau.fields.Name.value + ' 👀');
            this.nomCadeau = '';
            // Le @wire est en cache : on redemande la liste au serveur
            await refreshApex(this.cadeauxWire);
        } catch (e) {
            this.afficherMessage(e?.body?.message ?? e?.message);
        } finally {
            this.isEnvoi = false;
        }
    }

    // Bouton Donner / Reprendre : met à jour offert__c en base ; la mascotte réagit
    async donner(cadeauId, nom, offert) {
        try {
            await donnerCadeau({ cadeauId, offert });
            if (offert) {
                this.afficherMessage('MERCI POUR : ' + nom + ' 🎁');
                // Content le temps de déballer son cadeau, puis retour à l'humeur normale
                this.aUnCadeau = true;
                clearTimeout(this.aUnCadeauTimer);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                this.aUnCadeauTimer = setTimeout(() => {
                    this.aUnCadeau = false;
                }, this.dureeContent);
            } else {
                // On lui reprend : il n'est plus content
                this.aUnCadeau = false;
                clearTimeout(this.aUnCadeauTimer);
                // On lui reprend le cadeau : il le réclame en agitant les bras
                this.afficherMessage('REND-LE-MOI ! 😠');
                this.isReclame = true;
                clearTimeout(this.reclameTimer);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                this.reclameTimer = setTimeout(() => {
                    this.isReclame = false;
                }, 2500);
            }
            await refreshApex(this.cadeauxWire);
        } catch (e) {
            this.afficherMessage(e?.body?.message ?? e?.message);
        }
    }

    // Croix rouge : supprime le cadeau en base, la mascotte pleure
    async supprimer(cadeauId) {
        try {
            await supprimerCadeau({ cadeauId });
            this.isTriste = true;
            clearTimeout(this.tristeTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.tristeTimer = setTimeout(() => {
                this.isTriste = false;
            }, 2500);
            this.afficherMessage('Mon cadeau sniff !! 😭');
            await refreshApex(this.cadeauxWire);
        } catch (e) {
            this.afficherMessage(e?.body?.message ?? e?.message);
        }
    }
}