import { LightningElement, track, api, wire } from 'lwc';
import LightningAlert from 'lightning/alert';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVacancyList from '@salesforce/apex/VacancyDashoardController.getVacancyForUser';
import countVacancyList from '@salesforce/apex/VacancyDashoardController.countVacancyForUser';
import getMatches from '@salesforce/apex/VacancyDashoardController.getMatchesByVacanyID';
import updateNeed from '@salesforce/apex/VacancyDashoardController.updateNeed';
import getFilters from '@salesforce/apex/VacancyDashoardController.getFilters';
import getAllUsersTA from '@salesforce/apex/VacancyDashoardController.getUsersTA';
import deleteUserTA from '@salesforce/apex/VacancyDashoardController.deleteUserTA';
import createJobApplication from '@salesforce/apex/VacancyDashoardController.createJobApplication';
import changeStatusJobApplication from '@salesforce/apex/VacancyDashoardController.changeStatusJobApplication';
import createUserTA from '@salesforce/apex/VacancyDashoardController.createUserTA';
import { _labels } from './labels';

export default class vacancyDashboard extends LightningElement {
    @track loading = true;
    @api color ='#DCDCDC';

    get colorTitle(){
        return 'background-color:' + this.color;
    }
    @track objectApiName = 'cxsrec__cxsPosition__c';
    @track recordId;
    @track vacancies = [];
    @track countVacancies = 0;
    @track pageNumber = 1;
    @track pageSize = 5;
    @track bDisableFirst = true;
    @track bDisableLast = false;
    @track openEditNeed = false;
    @track openCandidates = false;
    @track tableVisibleTA = false;
    @track collapse = false;
    @track matches = [];
    @track initialValue =null;
    @track labels;
    @track searchVisible = false;
    @track searchValue = '';
    @track openFullInfo = false;
    @track fullInfo = '';
    @track fullInfoTitle = '';
    @track showLoading = false;
    @track loadingModal = false;
    @track selectedFilters = [];
    @track filterTooltip = false;
    @track sortDesc = false;
    @track btnCreateVisible = false;
    @track sortField = 'CreatedDate';
    @track sortOrder = 'Desc';
    filters;
    filterBM = [];
    filterTA = [];
    filterSourcing = [];
    filterPriority = [];
    fiterAccount = [];

    filterStringBM = '';
    filterStringTA = '';
    filterStringSourcing = '';
    filterStringPriority = '';
    filterStringAccount = '';
    candidateId;
    modalCandidatesVacancyId;
    modalTaVacancyId;
    showModalTA = false;
    loadingModalTA = false;
    usersTA;

    constructor(){
        console.clear();
        super();
        this.labels = _labels;
        this.getFilters(true);
    }

    removeFilter(event){
        let label = event.currentTarget.dataset.label;
        let item = event.currentTarget.dataset.value;
        let currentFilters = this.selectedFilters;
        let currentFilter = currentFilters.find( e => e.code === label);
        console.log(JSON.stringify(currentFilter));

        currentFilter.selectedfilters = currentFilter.selectedfilters.filter( e => e.value !== item);
        if(currentFilter.selectedfilters.length == 0){
            currentFilters = currentFilters.filter( e => e.code !== label);
        }

        //Add to this.selectedFilters
        this.selectedFilters = currentFilters;
        
        sessionStorage.setItem('filters',JSON.stringify(this.selectedFilters));
        if(this.selectedFilters.length > 0){
            this.filterTooltip = true;
        }else{
            this.filterTooltip = false;
        }
        
        this.splitFilters();
      
    }

    splitFilters(){
        this.filterStringBM = '';
        this.filterStringTA = '';
        this.filterStringSourcing = '';
        this.filterStringPriority = '';
        this.filterStringAccount = '';
        this.selectedFilters.forEach(element => {
            if(element.code === 'BM'){
                this.filterBM = element.selectedfilters.map( e => e.value);
                if(this.filterBM.length > 0){ this.filterStringBM = this.filterBM.join("','"); }else{ this.filterStringBM = '';}
            }else if(element.code === 'TA'){
                this.filterTA = element.selectedfilters.map( e => e.value);
                if(this.filterTA.length > 0){ this.filterStringTA = this.filterTA.join("','"); }else{ this.filterStringTA = '';}
            }else if(element.code === 'sourcingPriority'){
                this.filterSourcing = element.selectedfilters.map( e => e.value);
                if(this.filterSourcing.length > 0){ this.filterStringSourcing = this.filterSourcing.join("','");}else{ this.filterStringSourcing = '';}
            }else if(element.code === 'needPriority'){
                this.filterPriority = element.selectedfilters.map( e => e.value);
                if(this.filterPriority.length > 0){ this.filterStringPriority = this.filterPriority.join("','");}else{ this.filterStringPriority = '';}
            }else if(element.code === 'account'){
                this.fiterAccount = element.selectedfilters.map( e => e.value);
                if(this.fiterAccount.length > 0){ this.filterStringAccount = this.fiterAccount.join("','");}else{ this.filterStringAccount = '';}
            }
        });
        this.getCount();
    }
        

    handleFilterSelect(event){
        debugger;
        console.log(JSON.stringify(this.selectedFilters));
        let currentFilters = this.selectedFilters.find( e => e.code === event.detail.code);
        console.log(JSON.stringify(currentFilters));

        if(currentFilters === undefined){
            this.selectedFilters.push({code:event.detail.code,label:event.detail.label,selectedfilters:event.detail.selectedFilter});
            this.filterTooltip = true;
        }else{
            //add event.detail.selectedFilter to currentFilters.selectedfilters
            event.detail.selectedFilter.forEach(element => {
                let exist = false;
                currentFilters.selectedfilters.forEach( e => {
                    if(e.value === element.value){
                        exist = true;
                    }
                });
                if(!exist){
                    currentFilters.selectedfilters.push(element);
                }
            });
            this.selectedFilters = this.selectedFilters.map( e => e.code === event.detail.code ? currentFilters : e);
            this.filterTooltip = true;
       
        }
        sessionStorage.setItem('filters',JSON.stringify(this.selectedFilters));
        console.log(JSON.stringify(this.selectedFilters));
        this.splitFilters();   
    }

    getFilters(afterSearch){
        getFilters({search:this.searchValue,filterBM:this.filterStringBM,filterTA:this.filterStringTA,filterSourcing:this.filterStringSourcing,filterPriority:this.filterStringPriority,filterAccount:this.filterStringAccount})
        .then(result => {
            let json = JSON.parse(result);
            this.filters = json.filter;
            if(afterSearch){
                this.getCount();
            }
            
        }); 
    }

    getCount(){
        countVacancyList({search:this.searchValue,filterBM:this.filterStringBM,filterTA:this.filterStringTA,filterSourcing:this.filterStringSourcing,filterPriority:this.filterStringPriority,filterAccount:this.filterStringAccount})
        .then(result => {
            this.countVacancies = result;
            this.pageSize =  Math.ceil(this.countVacancies / 20);
            this.getVacancies();
        });
   }


    getVacancies(){
        getVacancyList({offset: this.pageNumber,search:this.searchValue,filterBM:this.filterStringBM,filterTA:this.filterStringTA,filterSourcing:this.filterStringSourcing,filterPriority:this.filterStringPriority,filterAccount:this.filterStringAccount, sortOrder:this.sortOrder,sortField:this.sortField})
        .then(result => {
            this.getFilters(false);
            this.vacancies = result;
            setTimeout(() => {
                this.openAll();
            }, 200);
            
            this.loading = false;
        })
        .catch(error => {
            this.vacancies = undefined;
        });
    }
    refreshPanel(){
        this.loading = true;
        this.searchValue = '';
        this.template.querySelector('[data-name="search"]').value = '';
        this.getCount();
    }

    nextPage(){
        this.pageNumber++;
        this.getCount();
        this.bDisableFirst = false;
        if(this.pageNumber == this.pageSize){
            this.bDisableLast = true;
        }
    }

    sorteringChange(event){
        this.sortDesc = !this.sortDesc;
        if(this.sortDesc){
            this.sortOrder = 'DESC';
        }else{
            this.sortOrder = 'ASC';
        }
        this.loading = true;
        this.getCount();
    }

    get options() {
        return [
            { label: this.labels.dashboardCreatedDate, value: 'CreatedDate' },
            { label: this.labels.dashboardAccountName, value: 'accountName' },
            { label: this.labels.dashboardBM, value: 'BM' },
            { label: this.labels.dashboardPriorite, value: 'priorite' },
            { label: this.labels.dashboardPrioriteSourcing, value: 'prioriteSourcing' },
        ];
    }

    handleChange(event) {
        this.sortField = event.detail.value;
        this.loading = true;
        this.getCount();
    }

    previousPage(){
        this.pageNumber--;
        this.getCount();
        this.bDisableLast = false;
        if(this.pageNumber == 1){
            this.bDisableFirst = true;
        }
    }

    searchEvent(event){
        this.searchValue = event.target.value;
        this.pageNumber = 1;
        this.loading = true;
        setTimeout(() => {
            this.getCount();
        }, 500);

    }

    searchPanel(){
        if(this.template.querySelector('[data-name="search"]').classList.contains("hide")){
            this.template.querySelector('[data-name="search"]').classList.remove("hide");
        }else{
            this.template.querySelector('[data-name="search"]').classList.add("hide");
        }
    }

    lastPage(){
        this.pageNumber = this.pageSize;
        this.getVacancies();
        this.bDisableLast = true;
        this.bDisableFirst = false;
    }

    firstPage(){
        this.pageNumber = 1;
        this.getVacancies();
        this.bDisableFirst = true;
        this.bDisableLast = false;
    }
    
    handlerCandidates(event){
        this.loading = true;
        let vacancyId = event.currentTarget.dataset.id;
        this.modalCandidatesVacancyId = vacancyId;
        this.getCandidatesByVacancyId(vacancyId);
        this.openCandidates = true;
        this.loading = false;
    }

    getCandidatesByVacancyId(vacancyId){
        this.matches = null;
        this.getMatchesByVacanyID(vacancyId);
        this.loading = false;
    }

    handleChangeRecordPicker(event){
        this.initialValue = null;
    }


    collapseOne(event){
        let id = event.target.dataset.id;
        //data-id on extraInfo class
        let extraInfo = this.template.querySelector('.extraInfo[data-id="'+id+'"]');
        extraInfo.hidden = !extraInfo.hidden;
    }
 

    async getMatchesByVacanyID(vacancyId){
        this.matches = await getMatches({vacancyId: vacancyId,limitItems:2000});
        console.log(JSON.stringify(this.matches));
        this.loadingModal = false;
    }

    openAccount(event){
        let accountId = event.target.dataset.id;
        window.open('/' + accountId, '_blank');
    }
    openVacancy(event){
        let vacancyId = event.target.dataset.id;
        window.open('/' + vacancyId, '_blank');
    }

    openCandidate(event){
        let candidateId = event.target.dataset.id;
        window.open('/' + candidateId, '_blank');
    }

    openMatch(event){
        let matchId = event.target.dataset.id;
        window.open('/' + matchId, '_blank');
    }

    openModifyNeed(event){
        const vacancyId = event.target.dataset.id;
        this.recordId = vacancyId;
        this.openEditNeed = true;
    }

    handleInputChange(event){
        let value = event.detail.recordId;
        if(value != null){
            this.btnCreateVisible = true;
        }else{
            this.btnCreateVisible = false;
        }
        this.candidateId =value;
    }

    handleInputChangeUserTA(event){
        let value = event.detail.recordId;
        this.userId =value;
    }

    handleCandidateClick(event){
        this.loading = true;
        this.createCandidate();
    }

    handleUserClick(event){
        this.loading = true;
        this.createUserTA();
    }

    deleteTA(event){
        this.loadingModalTA = true;
        let userId = event.currentTarget.dataset.id;
        setTimeout(() => {
             deleteUserTA({userId: userId,vacancyId:this.modalTaVacancyId}).then(async result => {
                if(result == true){
                    let toast = new ShowToastEvent({
                        title: this.labels.dashboardToastTitleDeleteTA,
                        variant: 'Success',
                        message: this.labels.dashboardToastMessageDeleteTA
                    });
                    this.dispatchEvent(toast);
                    this.usersTA = await getAllUsersTA({vacancyId: this.modalTaVacancyId,limitItems:2000});
                    if(this.usersTA.length > 0){
                        this.tableVisibleTA = true;
                    }else{
                        this.tableVisibleTA = false;
                    }
                }else{
                    let toast = new ShowToastEvent({
                        title: this.labels.dashboardToastTitleDeleteTA,
                        variant: 'Error',
                        message: 'Server Error'
                    });
                }
                this.loadingModalTA = false;
                this.refreshPanel();
            });
        });
    }

    async openModalTA(event){
        this.modalTaVacancyId = event.currentTarget.dataset.id;
        this.usersTA = await getAllUsersTA({vacancyId: this.modalTaVacancyId,limitItems:2000});
        if(this.usersTA.length > 0){
            this.tableVisibleTA = true;
        }else{
            this.tableVisibleTA = false;
        }
        this.showModalTA = true;
    }

    matchToKO(event){
        this.loadingModal = true;
        let matchId = event.target.dataset.id;
        let matchName = event.target.dataset.name;
      
        setTimeout(() => {
            changeStatusJobApplication({status:matchName,jobAppID:matchId}).then(result => {
                console.log(result);
                let json = JSON.parse(result);
                if(json.status != 200){
                    let toast = new ShowToastEvent({
                        title: this.labels.dashboardChangeStatusJobApplicationToastTitleError,
                        variant: 'Error',
                        message: json.message
                    });
                    this.dispatchEvent(toast);
                    this.loadingModal = false;
                }else{
                    let toastSuccess = new ShowToastEvent({
                        title: this.labels.dashboardChangeStatusJobApplicationToastTitle,
                        variant: 'Success',
                        message: this.labels.dashboardChangeStatusJobApplicationToastMessageSuccess
                    });
                    this.dispatchEvent(toastSuccess);
                    this.getCandidatesByVacancyId(this.modalCandidatesVacancyId);
                }
            })
        }, 200);
    }

    createUserTA(){
        this.loading = true;
        setTimeout(() => {
            createUserTA({userId:this.userId,vacancyId: this.modalTaVacancyId}).then(result => {
                if(result == true){
                    let toast = new ShowToastEvent({
                        title: this.labels.dashboardToastTitleCreateTA,
                        variant: 'Success',
                        message: this.labels.dashboardToastMessageCreateTA
                    });
                    this.dispatchEvent(toast); 
                    this.loading = false;
                    setTimeout(() => {
                        this.showModalTA = false;
                        this.refreshPanel();
                    });
                }
            }).catch(error => {
                let toast = new ShowToastEvent({
                    title: this.labels.dashboardToastTitleCreateTA,
                    variant: 'Error',
                    message: 'Server Error'
                });
                this.dispatchEvent(toast);
                this.loading = false;
            });
        }, 200);
    }
    
    createCandidate(){
        this.loadingModal = true;
        setTimeout(() => {
            createJobApplication({candidateId:this.candidateId,vacancyId: this.modalCandidatesVacancyId}).then(result => {         
                if(result == 'exist'){
                    let toastExist= new ShowToastEvent({
                        title: this.labels.dashboardCreateJobApplicationToastTitleExist,
                        variant: 'Error',
                        message: this.labels.dashboardCreateJobApplicationToastMessageExist
                    });
                    this.dispatchEvent(toastExist);
                    this.loadingModal = false;
                }else{
                    let toast = new ShowToastEvent({
                        title: this.labels.dashboardCreateJobApplicationToastTitle,
                        variant: 'Success',
                        message: this.labels.dashboardCreateJobApplicationToastMessage
                    });
                    this.dispatchEvent(toast);
                    this.loadingModal = false;
                    this.getCandidatesByVacancyId(this.modalCandidatesVacancyId);
                }

            }).catch(error => {
                let toast = new ShowToastEvent({
                    title: this.labels.dashboardCreateJobApplicationToastTitleError,
                    variant: 'Error',
                    message: error.message
                });
                this.loadingModal = false;
                this.dispatchEvent(toast);
            });
        }, 200);
    }

    handleDashboardButtonClose(event){
        this.openEditNeed = false;
        this.openCandidates = false;
        this.openFullInfo = false;
        this.showModalTA = false;
        this.loading = false;
    }

    validationCheck(need){
        if(need.Name == null || need.Name == ''){
            return {status:false,message:this.labels.dashboardUpdateNeedToastMessageName};
        }
        if(need.TP_Experience__c == null || need.TP_Experience__c == ''){
            return {status:false,message:this.labels.dashboardUpdateNeedToastMessageExperience};
        }
        return {status:true,message:''};
    }

    onsubmit =  async(event) => {
        this.showLoading = true;
        let toast;
        try{
            event.preventDefault();
            let need = {...event.detail.fields};
            need.Id = this.recordId;
            let validation = this.validationCheck(need);
            if(validation.status == true){
                const res = await updateNeed({data:JSON.stringify(need)});
                let response = JSON.parse(res);
                if(response?.status!=200){ //update toast to error
                    console.error(res);
                    toast = new ShowToastEvent({ //update toast to error
                        title: this.labels.lblUpdateNeedToastTitleError,
                        variant: 'Error',
                        message: res.message
                    });
                }else{
                    toast = new ShowToastEvent({
                        title: this.labels.lblUpdateNeedToastTitleSuccess,
                        variant: 'Success',
                        message: this.labels.lblUpdateNeedToastMessageSuccess
                    });
                }   
                this.dispatchEvent(toast);
                this.showLoading = false;
                setTimeout(() => {
                    this.openEditNeed = false;
                    this.refreshPanel();
                });
            }else{
                let errorToast = new ShowToastEvent({ //update toast to error
                    title: this.labels.lblUpdateNeedToastTitleError,
                    variant: 'Error',
                    message: validation.message
                });
                this.dispatchEvent(errorToast);
                this.showLoading = false;
            }
        }catch(error){
            console.error(error);
        }
    }

   

    
    handlerExtraInfo(event){
        let id = event.target.dataset.id;
        let name = event.target.dataset.name;
        this.vacancies.forEach(element => {
            if(element.Id == id){
                this.fullInfo = element[name];
            }
        });
        if(name == 'infoSolutions'){
            this.fullInfoTitle = this.labels.dashboardInfosSolution;
        }else{
            this.fullInfoTitle = this.labels.dashboardAvancement;
        }

        this.openFullInfo = true;
    }

    collapseAll(event){
        this.collapse = !this.collapse;
        const allDetails = this.template.querySelectorAll('.extraInfo');
        allDetails.forEach(element => {
            if(this.collapse){
                element.hidden = true;
            }else{
                element.hidden = false;
            }
        });
    }

    openAll(event){
        const allDetails = this.template.querySelectorAll('.extraInfo');
        allDetails.forEach(element => {
            element.hidden = false;
        });  
    }
}