import { LightningElement, api, wire } from 'lwc';
import {
    getPicklistValuesByRecordType,
    getObjectInfo
} from 'lightning/uiObjectInfoApi';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class DependentPicklistRT extends LightningElement {

    // =========================================================
    // PARAMETRES FOURNIS PAR LE FLOW
    // =========================================================

    @api objectApiName;
    @api recordTypeId;

    @api controllingFieldApiName;
    @api dependentFieldApiName;

    // Valeurs par défaut configurables dans le Flow
    @api defaultControllingValue;
    @api defaultDependentValue;

    // Paramètres d'affichage
    @api controllingPlaceholder = 'Sélectionnez une valeur';
    @api dependentPlaceholder = 'Sélectionnez une valeur';

    @api required = false;


    // =========================================================
    // VALEURS RETOURNEES AU FLOW
    // =========================================================

    @api controllingValue;
    @api dependentValue;


    // =========================================================
    // ETAT INTERNE DU COMPOSANT
    // =========================================================

    controllingFieldLabel;
    dependentFieldLabel;

    controllingOptions = [];
    dependentOptions = [];

    dependentPicklistData;

    errorMessage;
    isLoading = true;

    defaultsInitialized = false;


    // =========================================================
    // RECUPERATION DES METADONNEES DE L'OBJET
    // =========================================================

    @wire(getObjectInfo, {
        objectApiName: '$objectApiName'
    })
    wiredObjectInfo({ data, error }) {

        if (data) {

            const controllingField =
                data.fields[this.controllingFieldApiName];

            const dependentField =
                data.fields[this.dependentFieldApiName];

            this.controllingFieldLabel =
                controllingField?.label ||
                this.controllingFieldApiName;

            this.dependentFieldLabel =
                dependentField?.label ||
                this.dependentFieldApiName;

        } else if (error) {

            this.errorMessage =
                error?.body?.message ||
                'Impossible de récupérer les métadonnées de l’objet.';
        }
    }


    // =========================================================
    // RECUPERATION DES PICKLISTS POUR LE RECORD TYPE
    // =========================================================

    @wire(getPicklistValuesByRecordType, {
        objectApiName: '$objectApiName',
        recordTypeId: '$recordTypeId'
    })
    wiredPicklistValues({ data, error }) {

        this.isLoading = false;

        if (data) {

            this.errorMessage = undefined;

            const controllingData =
                data.picklistFieldValues[
                    this.controllingFieldApiName
                ];

            const dependentData =
                data.picklistFieldValues[
                    this.dependentFieldApiName
                ];

            if (!controllingData) {

                this.errorMessage =
                    `Champ contrôlant introuvable : ${this.controllingFieldApiName}`;

                return;
            }

            if (!dependentData) {

                this.errorMessage =
                    `Champ dépendant introuvable : ${this.dependentFieldApiName}`;

                return;
            }


            // Valeurs disponibles pour le Record Type

            this.controllingOptions =
                controllingData.values.map(item => ({
                    label: item.label,
                    value: item.value
                }));


            // Données nécessaires pour gérer la dépendance

            this.dependentPicklistData = dependentData;


            // Initialisation des valeurs

            this.initializeValues();
        }

        else if (error) {

            this.controllingOptions = [];
            this.dependentOptions = [];

            this.errorMessage =
                error?.body?.message ||
                'Impossible de récupérer les valeurs des picklists.';
        }
    }


    // =========================================================
    // INITIALISATION DES VALEURS
    // =========================================================

    initializeValues() {

        if (this.defaultsInitialized) {
            return;
        }

        this.defaultsInitialized = true;


        // -----------------------------------------------------
        // Valeur contrôlante
        // -----------------------------------------------------

        let initialControllingValue =
            this.controllingValue ||
            this.defaultControllingValue;


        // Vérification que la valeur existe pour le Record Type

        const controllingValueIsValid =
            this.controllingOptions.some(
                option =>
                    option.value === initialControllingValue
            );


        if (controllingValueIsValid) {

            this.controllingValue =
                initialControllingValue;

            this.dispatchEvent(
                new FlowAttributeChangeEvent(
                    'controllingValue',
                    this.controllingValue
                )
            );

            this.filterDependentOptions(false);
        }


        // -----------------------------------------------------
        // Valeur dépendante
        // -----------------------------------------------------

        let initialDependentValue =
            this.dependentValue ||
            this.defaultDependentValue;


        const dependentValueIsValid =
            this.dependentOptions.some(
                option =>
                    option.value === initialDependentValue
            );


        if (dependentValueIsValid) {

            this.dependentValue =
                initialDependentValue;

            this.dispatchEvent(
                new FlowAttributeChangeEvent(
                    'dependentValue',
                    this.dependentValue
                )
            );
        }
    }


    // =========================================================
    // MODIFICATION DE LA PICKLIST CONTROLANTE
    // =========================================================

    handleControllingChange(event) {

        this.controllingValue =
            event.detail.value;


        // Lorsque le contrôlant change,
        // l'ancienne valeur dépendante n'est plus garantie valide.

        this.dependentValue = null;


        // Envoi au Flow

        this.dispatchEvent(
            new FlowAttributeChangeEvent(
                'controllingValue',
                this.controllingValue
            )
        );

        this.dispatchEvent(
            new FlowAttributeChangeEvent(
                'dependentValue',
                null
            )
        );


        // Recalcul des valeurs dépendantes

        this.filterDependentOptions(true);
    }


    // =========================================================
    // MODIFICATION DE LA PICKLIST DEPENDANTE
    // =========================================================

    handleDependentChange(event) {

        this.dependentValue =
            event.detail.value;


        // Envoi au Flow

        this.dispatchEvent(
            new FlowAttributeChangeEvent(
                'dependentValue',
                this.dependentValue
            )
        );
    }


    // =========================================================
    // FILTRAGE DE LA PICKLIST DEPENDANTE
    // =========================================================

    filterDependentOptions(resetInvalidValue = true) {

        if (
            !this.dependentPicklistData ||
            !this.controllingValue
        ) {

            this.dependentOptions = [];

            return;
        }


        const controllingIndex =
            this.dependentPicklistData.controllerValues[
                this.controllingValue
            ];


        if (controllingIndex === undefined) {

            this.dependentOptions = [];

            return;
        }


        this.dependentOptions =
            this.dependentPicklistData.values

                .filter(item =>
                    item.validFor.includes(
                        controllingIndex
                    )
                )

                .map(item => ({
                    label: item.label,
                    value: item.value
                }));


        // Vérification de la valeur dépendante existante

        if (
            resetInvalidValue &&
            this.dependentValue
        ) {

            const dependentValueIsValid =
                this.dependentOptions.some(
                    option =>
                        option.value ===
                        this.dependentValue
                );


            if (!dependentValueIsValid) {

                this.dependentValue = null;

                this.dispatchEvent(
                    new FlowAttributeChangeEvent(
                        'dependentValue',
                        null
                    )
                );
            }
        }
    }


    // =========================================================
    // ETAT DE LA PICKLIST DEPENDANTE
    // =========================================================

    get isDependentDisabled() {

        return (
            this.isLoading ||
            !this.controllingValue ||
            this.dependentOptions.length === 0
        );
    }


    // =========================================================
    // VALIDATION DU SCREEN FLOW
    // =========================================================

    @api
    validate() {

        if (!this.required) {

            return {
                isValid: true
            };
        }


        if (!this.controllingValue) {

            return {
                isValid: false,
                errorMessage:
                    `Le champ "${this.controllingFieldLabel}" est obligatoire.`
            };
        }


        if (!this.dependentValue) {

            return {
                isValid: false,
                errorMessage:
                    `Le champ "${this.dependentFieldLabel}" est obligatoire.`
            };
        }


        return {
            isValid: true
        };
    }
}