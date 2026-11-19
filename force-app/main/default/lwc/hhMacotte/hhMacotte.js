// ============================================================================
// Composant LWC « hhMacotte »
// Affiche une mascotte (Cloudy) interactive : messages aléatoires, compteur de
// rires, gestion de croquettes via le composant enfant <c-hh-bol>, et création
// de cadeaux (enregistrements HH_cadeaux__c) dans Salesforce.
// ============================================================================
import { refreshApex } from '@salesforce/apex';
// LightningElement : classe de base de tout composant LWC.
// wire : décorateur permettant de brancher une source de données (Apex, LDS...).
import { LightningElement , wire } from 'lwc';

// createRecord : fonction du Lightning Data Service (LDS) pour créer un
// enregistrement sans écrire de code Apex.
import { createRecord } from 'lightning/uiRecordApi';

// Références au schéma : importer l'objet et le champ de cette façon permet à
// Salesforce de vérifier qu'ils existent et empêche leur suppression tant que
// le composant les utilise.
import CADEAU from '@salesforce/schema/HH_cadeaux__c';
import NOM_CADEAU from '@salesforce/schema/HH_cadeaux__c.Name';

// Méthode Apex (classe HH_Mascotte) qui renvoie la liste des cadeaux.
// Elle doit être annotée @AuraEnabled(cacheable=true) pour être utilisée avec @wire.
import listerCadeaux from '@salesforce/apex/HH_Mascotte.listerCadeaux';

  const Colonnes = [   
     { label: 'Nom du cadeau', fieldName: 'Name' }, 
       { label: 'Offert', fieldName: 'Offert__c', type: 'boolean' },
           {
        type: 'button',
        typeAttributes: { label: 'Offrir', name: 'offrir', variant: 'brand' }
    }
    
    ];
export default class HhMacotte extends LightningElement {

    // ------------------------------------------------------------------------
    // Propriétés d'état de la mascotte
    // (en LWC, tous les champs de classe sont réactifs : toute modification
    //  provoque automatiquement un nouveau rendu du template)
    // ------------------------------------------------------------------------
    faim = 5;          // Niveau de faim : sert à calculer l'humeur (niveauDeJoie)
    nom = 'bidule';    // Nom de la mascotte (non utilisé dans le template pour l'instant)
    croquette = 5 ;    // Nombre de croquettes dans le bol (transmis à <c-hh-bol>)
    rire = 0;          // Compteur de clics sur le bouton « Fais-moi rire SF »

        // Liste des phrases que la mascotte peut dire au hasard
        messages = [
        "Salut ! Moi, c'est Cloudy ! 👋",
        "Encore une réunion ?! 😭☕",
        "J'ai perdu mon contact... 🤣",
        "Erreur 404 : motivation introuvable 🤖",
        "Keep calm, je suis dans le Cloud ☁️",
        "Je suis un CRM très stylé 😎",
        "Un petit Flow et ça repart ! 🌊",
        "Qui a touché à mes données ?! 😱",
        "Plus rapide que ton Excel ! 🚀",
        "Mission Salesforce accomplie ! 🏆",
        "Attention, je maîtrise Apex ! 💻"
    ];

        // Message actuellement affiché dans la bulle de dialogue
        message = 'Salut ! Moi, c’est Cloudy ! 👋';


        // Message de retour affiché après la tentative de création d'un cadeau
        // (succès ou erreur). Chaîne vide = rien n'est affiché (lwc:if).
        messagec = '';
        colonnes=Colonnes;

        // Valeur saisie dans le champ « Nom du cadeau » (valeur par défaut)
        nomCadeau="trottinette_80km/h";

        // ------------------------------------------------------------------------
        // Récupération des cadeaux via Apex
        // @wire appelle automatiquement listerCadeaux au chargement du composant.
        // Le résultat est un objet { data, error } stocké dans this.cadeaux.
        // ------------------------------------------------------------------------
        @wire(listerCadeaux)
        cadeaux;

      

 
        async handleRowAction(event) {
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

        // Getter : renvoie uniquement les cadeaux pas encore offerts.
        // - ?. évite une erreur si cadeaux est encore undefined
        // - ?? [] renvoie un tableau vide tant que les données ne sont pas arrivées
        get cadeauxEnStock() {
                return (this.cadeaux?.data ?? []).filter((c) => !c.Offert__c);
            }

         // Getter : vrai s'il n'y a aucun cadeau en stock
         // (pratique pour afficher un message « aucun cadeau » dans le template)
         get aucunCadeau() {
             return this.cadeauxEnStock.length === 0;
         }


        // Gestionnaire de l'événement onchange du <lightning-input> :
        // met à jour nomCadeau à chaque saisie de l'utilisateur.
        handleNomCadeau(event) {
            this.nomCadeau = event.target.value;
        }

        // ------------------------------------------------------------------------
        // Création d'un cadeau dans Salesforce (bouton « Créer mon cadeau »)
        // Méthode async car createRecord renvoie une Promise.
        // ------------------------------------------------------------------------
        async creerCadeau() {
            // trim() retire les espaces au début et à la fin
            const nom = this.nomCadeau.trim();

            // Validation : on refuse un nom vide
            if (!nom) {
                this.messagec = 'Donne un nom au cadeau.';
                return;
            }
            try {
                // Création de l'enregistrement HH_cadeaux__c avec le champ Name renseigné.
                // [NOM_CADEAU.fieldApiName] = nom de propriété calculé ('Name').
                await createRecord({
                    apiName: CADEAU.objectApiName,
                    fields: { [NOM_CADEAU.fieldApiName]: nom }
                });

                // Succès : message de confirmation et remise à zéro du champ
                this.messagec = 'Cadeau créé : ' + nom;
                this.nomCadeau = '';
            } catch (e) {
                // Erreur : on affiche le message renvoyé par Salesforce
                // (e.body.message pour les erreurs serveur, e.message sinon)
                this.messagec = e?.body?.messagec ?? e?.messagec;
            }
        }

    // ------------------------------------------------------------------------
    // Bouton « Fais-moi rire 😂 » : choisit un message au hasard
    // ------------------------------------------------------------------------
    changeMessage() {
        // Math.random() donne un nombre entre 0 (inclus) et 1 (exclu) ;
        // multiplié par la taille du tableau puis arrondi à l'entier inférieur,
        // on obtient un index valide entre 0 et messages.length - 1.
        const randomIndex = Math.floor(
            Math.random() * this.messages.length
        );

        this.message = this.messages[randomIndex];
    }

   // Getter : humeur de la mascotte calculée à partir de la faim
   // (utilisé dans le template via {niveauDeJoie})
   get  niveauDeJoie()
    {
        return this.faim > 3 ? 'content' : 'pas content'
    }

    // Bouton « Fais-moi rire 😂 SF » : incrémente le compteur de rires
    faisMoiRire()
    {
        this.rire = this.rire + 1;
    }


    // Gestionnaire de l'événement personnalisé « mangerhh » émis par <c-hh-bol>
    // (onmangerhh dans le template) : retire une croquette s'il en reste.
    handleServir(){
        this.croquette > 0 ? this.croquette-- : this.croquette;
    }

    // Bouton « Grandir » : remplit le bol (8 croquettes) puis appelle la méthode
    // publique secouer() du composant enfant, récupéré grâce à lwc:ref="bol".
    // (secouer doit être exposée avec @api dans hhBol.js)
    grandir()
    {
        this.croquette = 8;
        this.refs.bol.secouer();

    }

}