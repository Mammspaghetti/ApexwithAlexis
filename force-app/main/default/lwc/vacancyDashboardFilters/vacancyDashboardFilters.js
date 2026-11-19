/**
 * Created by Kobe on 12/12/2019.
 */

import { LightningElement, api, track, wire } from 'lwc';

export default class vacancyDashboardFilters extends LightningElement {
    @api filters = {};
    @api facetType;
    @track facetPropertyMutable;
    @track searchTerm = null;
    @api selectedFacets = [];

    @track label;
    @track code;
    @track dateValues;
    @track dateValuesMutable;





    connectedCallback(){
        this.facetPropertyMutable = {...this.filters};
        this.label = this.filters.Name;
        this.code = this.filters.Code;

    }

    toggleOptions(event){
        let combobox = this.template.querySelector('[data-id="combobox"]');
        let dropdown = this.template.querySelector('.slds-dropdown');
        if(event.type === 'focus'){
            combobox.classList.add('slds-is-open');
            combobox.classList.add('combobox-focus');
            let facets = this.filters.items;
            this.facetPropertyMutable.items = facets.filter( e => this.selectedFacets.map(function(obj) {return obj.value;}).indexOf(e.value) < 0);
            dropdown.classList.add('dropdown-focus');
            combobox.setAttribute('aria-expanded','true');
        } else if(event.type === 'focusout'){
            combobox.classList.remove('slds-is-open');
        }
    }

    searchOptions(event){
        this.searchTerm = event.target.value;
        let facets = this.filters.items;
        facets = facets.filter( e => this.selectedFacets.map(function(obj) {return obj.value;}).indexOf(e.value) < 0);
        facets = facets.filter( e => String(e.Name.toLowerCase()).includes(event.target.value.toLowerCase()) && this.selectedFacets.indexOf(e.Name.toLowerCase()) < 0);
        this.facetPropertyMutable.items = facets;
    }


    selectOption(event){
        debugger;
        let combobox = this.template.querySelector('[data-id="combobox"]');
        combobox.classList.remove('slds-is-open');
        combobox.setAttribute('aria-expanded','false');
        let dropdown = this.template.querySelector('.slds-dropdown');
         dropdown.classList.remove('dropdown-focus');
        let facets = this.filters.items;
        let item = event.currentTarget.dataset.item;
        let lbl = event.currentTarget.dataset.label != null && event.currentTarget.dataset.label !== undefined && event.currentTarget.dataset.label != '' ? event.currentTarget.dataset.label : item;

        this.searchTerm = null;
        this.selectedFacets = [...this.selectedFacets];
        this.selectedFacets.push();

        const selectEvent = new CustomEvent("facetselect", {
           detail : {
                selectedFilter : [{value:item,label:lbl}],
                label: this.label,
                code: this.code
            }
        });

        this.dispatchEvent(selectEvent);
    }

    get disableInput(){
        return this.filters == null ? true : false;
    }

}