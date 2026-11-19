import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { formatCoefficient } from "c/arPricingEngine";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getPtfEntities from "@salesforce/apex/AR_AdminReferentialService.getPtfEntities";
import savePtfEntityApex from "@salesforce/apex/AR_AdminReferentialService.savePtfEntity";
import deletePtfEntityApex from "@salesforce/apex/AR_AdminReferentialService.deletePtfEntity";
import searchActiveUsersApex from "@salesforce/apex/AR_AdminReferentialService.searchActiveUsers";
import getPtfTemplateOptions from "@salesforce/apex/AR_AdminReferentialService.getPtfTemplateOptions";
import {
  AUTO_VALUE,
  AUTO_LABEL,
  buildComboOptions,
  fromComboValue,
  isUnknownCode,
  toComboValue
} from "c/arPtfTemplateUtils";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_ADM_TabPtfEntities from "@salesforce/label/c.AR_ADM_TabPtfEntities";
import LBL_AR_APE_ActiveFem from "@salesforce/label/c.AR_APE_ActiveFem";
import LBL_AR_APE_AddEntity from "@salesforce/label/c.AR_APE_AddEntity";
import LBL_AR_APE_AddressBlock from "@salesforce/label/c.AR_APE_AddressBlock";
import LBL_AR_APE_AddressSection from "@salesforce/label/c.AR_APE_AddressSection";
import LBL_AR_APE_Bank from "@salesforce/label/c.AR_APE_Bank";
import LBL_AR_APE_BankDetails from "@salesforce/label/c.AR_APE_BankDetails";
import LBL_AR_APE_Bic from "@salesforce/label/c.AR_APE_Bic";
import LBL_AR_APE_CalculationSection from "@salesforce/label/c.AR_APE_CalculationSection";
import LBL_AR_APE_City from "@salesforce/label/c.AR_APE_City";
import LBL_AR_APE_Coefficient from "@salesforce/label/c.AR_APE_Coefficient";
import LBL_AR_APE_CoefficientColumn from "@salesforce/label/c.AR_APE_CoefficientColumn";
import LBL_AR_APE_CoefficientPlaceholder from "@salesforce/label/c.AR_APE_CoefficientPlaceholder";
import LBL_AR_APE_CommercialCourt from "@salesforce/label/c.AR_APE_CommercialCourt";
import LBL_AR_APE_CommercialCourtPlaceholder from "@salesforce/label/c.AR_APE_CommercialCourtPlaceholder";
import LBL_AR_APE_CountMany from "@salesforce/label/c.AR_APE_CountMany";
import LBL_AR_APE_CountOne from "@salesforce/label/c.AR_APE_CountOne";
import LBL_AR_APE_DefaultPtfTemplate from "@salesforce/label/c.AR_APE_DefaultPtfTemplate";
import LBL_AR_APE_Deleted from "@salesforce/label/c.AR_APE_Deleted";
import LBL_AR_APE_Empty from "@salesforce/label/c.AR_APE_Empty";
import LBL_AR_APE_EntityName from "@salesforce/label/c.AR_APE_EntityName";
import LBL_AR_APE_FaxOptional from "@salesforce/label/c.AR_APE_FaxOptional";
import LBL_AR_APE_Heading from "@salesforce/label/c.AR_APE_Heading";
import LBL_AR_APE_Iban from "@salesforce/label/c.AR_APE_Iban";
import LBL_AR_APE_InactiveFem from "@salesforce/label/c.AR_APE_InactiveFem";
import LBL_AR_APE_LegalTermsSection from "@salesforce/label/c.AR_APE_LegalTermsSection";
import LBL_AR_APE_NoEntity from "@salesforce/label/c.AR_APE_NoEntity";
import LBL_AR_APE_PostalCode from "@salesforce/label/c.AR_APE_PostalCode";
import LBL_AR_APE_PtfReadinessColumn from "@salesforce/label/c.AR_APE_PtfReadinessColumn";
import LBL_AR_APE_PtfTemplateColumn from "@salesforce/label/c.AR_APE_PtfTemplateColumn";
import LBL_AR_APE_ReadyForAllTemplates from "@salesforce/label/c.AR_APE_ReadyForAllTemplates";
import LBL_AR_APE_RibBlock from "@salesforce/label/c.AR_APE_RibBlock";
import LBL_AR_APE_RibHelp from "@salesforce/label/c.AR_APE_RibHelp";
import LBL_AR_APE_SalesEmail from "@salesforce/label/c.AR_APE_SalesEmail";
import LBL_AR_APE_Saved from "@salesforce/label/c.AR_APE_Saved";
import LBL_AR_APE_Siret from "@salesforce/label/c.AR_APE_Siret";
import LBL_AR_APE_ThresholdsColumn from "@salesforce/label/c.AR_APE_ThresholdsColumn";
import LBL_AR_APE_ThresholdsNone from "@salesforce/label/c.AR_APE_ThresholdsNone";
import LBL_AR_APE_Website from "@salesforce/label/c.AR_APE_Website";
import LBL_AR_APE_ValidatorsSection from "@salesforce/label/c.AR_APE_ValidatorsSection";
import LBL_AR_APE_ValidatorsHelp from "@salesforce/label/c.AR_APE_ValidatorsHelp";
import LBL_AR_APE_ValidatorAdd from "@salesforce/label/c.AR_APE_ValidatorAdd";
import LBL_AR_APE_ValidatorSearchPlaceholder from "@salesforce/label/c.AR_APE_ValidatorSearchPlaceholder";
import LBL_AR_APE_ValidatorNoResult from "@salesforce/label/c.AR_APE_ValidatorNoResult";
import LBL_AR_APE_ValidatorNone from "@salesforce/label/c.AR_APE_ValidatorNone";
import LBL_AR_APE_ValidatorRemove from "@salesforce/label/c.AR_APE_ValidatorRemove";
import LBL_AR_APE_ValidatorRemoveAria from "@salesforce/label/c.AR_APE_ValidatorRemoveAria";
import LBL_AR_APE_ValidatorInactiveBadge from "@salesforce/label/c.AR_APE_ValidatorInactiveBadge";
import LBL_AR_APE_ValidatorsColumn from "@salesforce/label/c.AR_APE_ValidatorsColumn";
import LBL_AR_APE_ValidatorsInactiveOne from "@salesforce/label/c.AR_APE_ValidatorsInactiveOne";
import LBL_AR_APE_ValidatorsInactiveMany from "@salesforce/label/c.AR_APE_ValidatorsInactiveMany";
import LBL_AR_APE_ValidatorsBanner from "@salesforce/label/c.AR_APE_ValidatorsBanner";
import LBL_AR_APE_ValidatorsBannerCountOne from "@salesforce/label/c.AR_APE_ValidatorsBannerCountOne";
import LBL_AR_APE_ValidatorsBannerCountMany from "@salesforce/label/c.AR_APE_ValidatorsBannerCountMany";
import LBL_AR_APE_WorkingDaysColumn from "@salesforce/label/c.AR_APE_WorkingDaysColumn";
import LBL_AR_APE_WorkingDaysPlaceholder from "@salesforce/label/c.AR_APE_WorkingDaysPlaceholder";
import LBL_AR_Common_Active from "@salesforce/label/c.AR_Common_Active";
import LBL_AR_Common_Contact from "@salesforce/label/c.AR_Common_Contact";
import LBL_AR_Common_Country from "@salesforce/label/c.AR_Common_Country";
import LBL_AR_Common_Delete from "@salesforce/label/c.AR_Common_Delete";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_FloorPercent from "@salesforce/label/c.AR_Common_FloorPercent";
import LBL_AR_Common_IdealPercent from "@salesforce/label/c.AR_Common_IdealPercent";
import LBL_AR_Common_ModifiedBy from "@salesforce/label/c.AR_Common_ModifiedBy";
import LBL_AR_Common_TargetPercent from "@salesforce/label/c.AR_Common_TargetPercent";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Phone from "@salesforce/label/c.AR_Common_Phone";
import LBL_AR_Common_Status from "@salesforce/label/c.AR_Common_Status";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_TemplateListUnavailable from "@salesforce/label/c.AR_Common_TemplateListUnavailable";
import LBL_AR_Common_UnknownTemplateCode from "@salesforce/label/c.AR_Common_UnknownTemplateCode";
import LBL_AR_Common_WorkingDaysPerYear from "@salesforce/label/c.AR_Common_WorkingDaysPerYear";

const I18N = {
  AR_ADM_TabPtfEntities: LBL_AR_ADM_TabPtfEntities,
  AR_APE_ActiveFem: LBL_AR_APE_ActiveFem,
  AR_APE_AddEntity: LBL_AR_APE_AddEntity,
  AR_APE_AddressBlock: LBL_AR_APE_AddressBlock,
  AR_APE_AddressSection: LBL_AR_APE_AddressSection,
  AR_APE_Bank: LBL_AR_APE_Bank,
  AR_APE_BankDetails: LBL_AR_APE_BankDetails,
  AR_APE_Bic: LBL_AR_APE_Bic,
  AR_APE_CalculationSection: LBL_AR_APE_CalculationSection,
  AR_APE_City: LBL_AR_APE_City,
  AR_APE_Coefficient: LBL_AR_APE_Coefficient,
  AR_APE_CoefficientColumn: LBL_AR_APE_CoefficientColumn,
  AR_APE_CoefficientPlaceholder: LBL_AR_APE_CoefficientPlaceholder,
  AR_APE_CommercialCourt: LBL_AR_APE_CommercialCourt,
  AR_APE_CommercialCourtPlaceholder: LBL_AR_APE_CommercialCourtPlaceholder,
  AR_APE_CountMany: LBL_AR_APE_CountMany,
  AR_APE_CountOne: LBL_AR_APE_CountOne,
  AR_APE_DefaultPtfTemplate: LBL_AR_APE_DefaultPtfTemplate,
  AR_APE_Deleted: LBL_AR_APE_Deleted,
  AR_APE_Empty: LBL_AR_APE_Empty,
  AR_APE_EntityName: LBL_AR_APE_EntityName,
  AR_APE_FaxOptional: LBL_AR_APE_FaxOptional,
  AR_APE_Heading: LBL_AR_APE_Heading,
  AR_APE_Iban: LBL_AR_APE_Iban,
  AR_APE_InactiveFem: LBL_AR_APE_InactiveFem,
  AR_APE_LegalTermsSection: LBL_AR_APE_LegalTermsSection,
  AR_APE_NoEntity: LBL_AR_APE_NoEntity,
  AR_APE_PostalCode: LBL_AR_APE_PostalCode,
  AR_APE_PtfReadinessColumn: LBL_AR_APE_PtfReadinessColumn,
  AR_APE_PtfTemplateColumn: LBL_AR_APE_PtfTemplateColumn,
  AR_APE_ReadyForAllTemplates: LBL_AR_APE_ReadyForAllTemplates,
  AR_APE_RibBlock: LBL_AR_APE_RibBlock,
  AR_APE_RibHelp: LBL_AR_APE_RibHelp,
  AR_APE_SalesEmail: LBL_AR_APE_SalesEmail,
  AR_APE_Saved: LBL_AR_APE_Saved,
  AR_APE_Siret: LBL_AR_APE_Siret,
  AR_APE_ThresholdsColumn: LBL_AR_APE_ThresholdsColumn,
  AR_APE_ThresholdsNone: LBL_AR_APE_ThresholdsNone,
  AR_APE_Website: LBL_AR_APE_Website,
  AR_APE_ValidatorsSection: LBL_AR_APE_ValidatorsSection,
  AR_APE_ValidatorsHelp: LBL_AR_APE_ValidatorsHelp,
  AR_APE_ValidatorAdd: LBL_AR_APE_ValidatorAdd,
  AR_APE_ValidatorSearchPlaceholder: LBL_AR_APE_ValidatorSearchPlaceholder,
  AR_APE_ValidatorNoResult: LBL_AR_APE_ValidatorNoResult,
  AR_APE_ValidatorNone: LBL_AR_APE_ValidatorNone,
  AR_APE_ValidatorRemove: LBL_AR_APE_ValidatorRemove,
  AR_APE_ValidatorRemoveAria: LBL_AR_APE_ValidatorRemoveAria,
  AR_APE_ValidatorInactiveBadge: LBL_AR_APE_ValidatorInactiveBadge,
  AR_APE_ValidatorsColumn: LBL_AR_APE_ValidatorsColumn,
  AR_APE_ValidatorsInactiveOne: LBL_AR_APE_ValidatorsInactiveOne,
  AR_APE_ValidatorsInactiveMany: LBL_AR_APE_ValidatorsInactiveMany,
  AR_APE_ValidatorsBanner: LBL_AR_APE_ValidatorsBanner,
  AR_APE_ValidatorsBannerCountOne: LBL_AR_APE_ValidatorsBannerCountOne,
  AR_APE_ValidatorsBannerCountMany: LBL_AR_APE_ValidatorsBannerCountMany,
  AR_APE_WorkingDaysColumn: LBL_AR_APE_WorkingDaysColumn,
  AR_APE_WorkingDaysPlaceholder: LBL_AR_APE_WorkingDaysPlaceholder,
  AR_Common_Active: LBL_AR_Common_Active,
  AR_Common_Contact: LBL_AR_Common_Contact,
  AR_Common_Country: LBL_AR_Common_Country,
  AR_Common_Delete: LBL_AR_Common_Delete,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_FloorPercent: LBL_AR_Common_FloorPercent,
  AR_Common_IdealPercent: LBL_AR_Common_IdealPercent,
  AR_Common_ModifiedBy: LBL_AR_Common_ModifiedBy,
  AR_Common_TargetPercent: LBL_AR_Common_TargetPercent,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Phone: LBL_AR_Common_Phone,
  AR_Common_Status: LBL_AR_Common_Status,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_TemplateListUnavailable: LBL_AR_Common_TemplateListUnavailable,
  AR_Common_UnknownTemplateCode: LBL_AR_Common_UnknownTemplateCode,
  AR_Common_WorkingDaysPerYear: LBL_AR_Common_WorkingDaysPerYear
};
// Session 252 : « Modifié par <Nom> le JJ/MM/AAAA », date seule, sous le nom de l'entité.
function formatFrenchDate(value) {
  if (!value) {
    return "—";
  }
  return new Date(value).toLocaleDateString("fr-FR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  });
}

const EMPTY_FORM = {
  id: undefined,
  name: "",
  active: true,
  address: "",
  postalCode: "",
  city: "",
  country: "",
  siret: "",
  phone: "",
  fax: "",
  website: "",
  commercialEmail: "",
  bankName: "",
  iban: "",
  rib: "",
  bic: "",
  tribunalCompetent: "",
  templateCode: "",
  coefficient: null,
  workingDays: null,
  // Session 252 : seuils de l'entité, tous les trois ou aucun (validé côté serveur).
  floorPercent: null,
  targetPercent: null,
  idealPercent: null,
  validators: []
};

const SEARCH_DELAY_MS = 250;
const REMOVE_ANIMATION_MS = 160;

/** Initiales d'une pastille : première lettre du premier et du dernier mot du nom. */
function initialsOf(name) {
  const words = (name || "").trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return "?";
  }
  const first = words[0].charAt(0);
  const last = words.length > 1 ? words[words.length - 1].charAt(0) : "";
  return (first + last).toUpperCase();
}

/** Onglet « Entités PTF » (session 46) : CRUD de AR_PTF_Entity_Referential__c, remplace
 * l'administration via Setup > Custom Metadata Types de AR_PTF_Entity__mdt — même pattern que
 * arAdminCorridors (liste + formulaire + toast, enregistrement synchrone). */
export default class ArAdminPtfEntities extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  entities = [];
  // Gabarits de PTF servis par le serveur (même carte que la résolution) ; null tant que non chargés.
  templateOptions = null;
  templateOptionsError;

  showForm = false;
  form = { ...EMPTY_FORM, validators: [] };

  // Recherche de valideurs (pop-up) : terme saisi, résultats, index surligné au clavier.
  searchTerm = "";
  searchResults = [];
  searchError;
  searchLoading = false;
  searchOpen = false;
  highlightedIndex = -1;
  searchSeq = 0;
  searchTimer;
  removeTimers = [];

  connectedCallback() {
    this.loadEntities();
    this.loadTemplateOptions();
  }

  /** Catch classé « afficher » (CLAUDE.md, session 34) : un échec n'est jamais pris pour une
   * liste vide — le formulaire l'écrit sous le champ, la valeur existante reste conservée. */
  async loadTemplateOptions() {
    this.templateOptionsError = undefined;
    try {
      this.templateOptions = (await getPtfTemplateOptions()) || null;
    } catch (error) {
      this.templateOptions = null;
      this.templateOptionsError = this.reduceError(error);
    }
  }

  get templateComboOptions() {
    if (this.templateOptionsError) {
      // Liste inconnue : on ne peut rien déclarer « inconnu », on garde seulement la valeur en place.
      const options = [{ value: AUTO_VALUE, label: AUTO_LABEL }];
      if (this.form.templateCode) {
        options.push({
          value: this.form.templateCode,
          label: this.form.templateCode
        });
      }
      return options;
    }
    return buildComboOptions(this.templateOptions, this.form.templateCode);
  }

  get templateComboValue() {
    return toComboValue(this.form.templateCode);
  }

  get templateCodeIsUnknown() {
    return (
      !this.templateOptionsError &&
      this.templateOptions !== null &&
      isUnknownCode(this.form.templateCode, this.templateOptions)
    );
  }

  handleTemplateChange(event) {
    this.form = {
      ...this.form,
      templateCode: fromComboValue(event.detail.value)
    };
  }

  async loadEntities() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      const rows = await getPtfEntities();
      this.entities = rows.map((row) => ({
        ...row,
        activeLabel: row.active
          ? I18N.AR_APE_ActiveFem
          : I18N.AR_APE_InactiveFem,
        modifiedLine: formatLabel(
          I18N.AR_Common_ModifiedBy,
          row.lastModifiedByName,
          formatFrenchDate(row.lastModifiedDate)
        ),
        // Session 252 : seuils de l'entité, ou « Paramètres généraux » si elle n'en porte pas (les trois).
        thresholdsLabel:
          row.floorPercent != null &&
          row.targetPercent != null &&
          row.idealPercent != null
            ? `${row.floorPercent} / ${row.targetPercent} / ${row.idealPercent} %`
            : I18N.AR_APE_ThresholdsNone,
        // Session 47 : état de préparation par gabarit — ce que arPtfPanel/le sélecteur d'entité ne
        // peuvent que signaler brièvement, cet écran d'administration l'affiche en détail (le
        // registre technique a sa place ici, cf. prompts/session-47-blocages-en-amont.md §4).
        readinessLabel: this.buildReadinessLabel(row.readinessIssues),
        readinessClass:
          !row.readinessIssues || row.readinessIssues.length === 0
            ? "readiness-ok"
            : "readiness-missing",
        // Session 48 : ce qui s'applique RÉELLEMENT (cascade entité → paramètre général →
        // constante moteur), jamais seulement la case brute — sinon un champ vide laisse croire
        // qu'aucun coefficient/jours travaillés ne s'applique à cette entité.
        coefficientEffectiveLabel: `${formatCoefficient(row.coefficientEffective)} (${row.coefficientSource})`,
        workingDaysEffectiveLabel: `${row.workingDaysEffective} (${row.workingDaysSource})`,
        validatorCount: (row.validators || []).length,
        hasInactiveValidators: (row.inactiveValidatorCount || 0) > 0,
        inactiveValidatorsLabel: pluralLabel(
          row.inactiveValidatorCount || 0,
          I18N.AR_APE_ValidatorsInactiveOne,
          I18N.AR_APE_ValidatorsInactiveMany
        )
      }));
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  /** Un résumé par ligne de tableau : "GABARIT : champs manquants" par gabarit concerné, séparés
   * par " · " — jamais un seul champ agrégé qui masquerait de quel gabarit vient chaque manque. */
  buildReadinessLabel(readinessIssues) {
    if (!readinessIssues || readinessIssues.length === 0) {
      return I18N.AR_APE_ReadyForAllTemplates;
    }
    return readinessIssues
      .map((issue) => `${issue.templateLabel} : ${issue.missingFields}`)
      .join(" · ");
  }

  get unknownTemplateCodeMessage() {
    return formatLabel(
      I18N.AR_Common_UnknownTemplateCode,
      this.form.templateCode
    );
  }

  get templateListErrorMessage() {
    return formatLabel(
      I18N.AR_Common_TemplateListUnavailable,
      this.templateOptionsError
    );
  }

  get countLabel() {
    const n = this.entities.length;
    return n === 0
      ? I18N.AR_APE_NoEntity
      : pluralLabel(n, I18N.AR_APE_CountOne, I18N.AR_APE_CountMany);
  }

  get entitiesWithInactiveValidators() {
    return this.entities.filter((e) => e.hasInactiveValidators).length;
  }

  get showInactiveBanner() {
    return !this.isLoading && this.entitiesWithInactiveValidators > 0;
  }

  get inactiveBannerCount() {
    return pluralLabel(
      this.entitiesWithInactiveValidators,
      I18N.AR_APE_ValidatorsBannerCountOne,
      I18N.AR_APE_ValidatorsBannerCountMany
    );
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.entities.length === 0;
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
    this.removeTimers.forEach((t) => clearTimeout(t));
  }

  handleAdd() {
    this.form = { ...EMPTY_FORM, validators: [] };
    this.resetSearch();
    this.showForm = true;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.entities.find((e) => e.id === id);
    if (!row) {
      return;
    }
    this.form = {
      ...EMPTY_FORM,
      ...row,
      validators: (row.validators || []).map((v) => ({
        userId: v.userId,
        name: v.name,
        title: v.title,
        active: v.active
      }))
    };
    this.resetSearch();
    this.showForm = true;
  }

  /** Ouvre la pop-up d'une entité depuis le badge « N inactif(s) » de la liste. */
  handleEditFromBadge(event) {
    this.handleEdit(event);
  }

  handleCancel() {
    this.showForm = false;
    this.resetSearch();
  }

  // --- Valideurs d'entité -------------------------------------------------

  get validatorChips() {
    return this.form.validators.map((v) => ({
      ...v,
      initials: initialsOf(v.name),
      chipClass:
        "validator-chip" +
        (v.active === false ? " validator-chip_inactive" : "") +
        (v.removing ? " validator-chip_leaving" : "") +
        (v.entering ? " validator-chip_entering" : ""),
      isInactive: v.active === false,
      removeAria: formatLabel(I18N.AR_APE_ValidatorRemoveAria, v.name)
    }));
  }

  get hasValidators() {
    return this.form.validators.length > 0;
  }

  get resultItems() {
    return this.searchResults.map((r, index) => ({
      ...r,
      initials: initialsOf(r.name),
      optionId: `validator-option-${index}`,
      optionClass:
        "validator-option" +
        (index === this.highlightedIndex ? " validator-option_active" : ""),
      ariaSelected: index === this.highlightedIndex ? "true" : "false"
    }));
  }

  get showResultsPanel() {
    return this.searchOpen && this.searchTerm.trim().length >= 2;
  }

  get showNoResult() {
    return (
      this.showResultsPanel &&
      !this.searchLoading &&
      !this.searchError &&
      this.searchResults.length === 0
    );
  }

  get hasResults() {
    return this.searchResults.length > 0;
  }

  resetSearch() {
    clearTimeout(this.searchTimer);
    this.searchSeq++;
    this.searchTerm = "";
    this.searchResults = [];
    this.searchError = undefined;
    this.searchLoading = false;
    this.searchOpen = false;
    this.highlightedIndex = -1;
  }

  handleSearchInput(event) {
    this.searchTerm = event.target.value;
    this.searchOpen = true;

    clearTimeout(this.searchTimer);
    if (this.searchTerm.trim().length < 2) {
      this.searchSeq++;
      this.searchResults = [];
      this.searchError = undefined;
      this.searchLoading = false;
      this.highlightedIndex = -1;
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- anti-rebond de la saisie.
    this.searchTimer = setTimeout(() => this.runSearch(), SEARCH_DELAY_MS);
  }

  /** Catch classé « afficher » (CLAUDE.md, session 34) : un échec de recherche n'est jamais pris pour
   * « aucun résultat » — il est écrit sous le champ. */
  async runSearch() {
    const seq = ++this.searchSeq;
    const term = this.searchTerm.trim();
    this.searchLoading = true;
    this.searchError = undefined;
    try {
      const rows = (await searchActiveUsersApex({ term })) || [];
      if (seq !== this.searchSeq) {
        return;
      }
      const present = new Set(this.form.validators.map((v) => v.userId));
      this.searchResults = rows.filter((r) => !present.has(r.userId));
      this.highlightedIndex = this.searchResults.length > 0 ? 0 : -1;
    } catch (error) {
      if (seq !== this.searchSeq) {
        return;
      }
      this.searchResults = [];
      this.highlightedIndex = -1;
      this.searchError = this.reduceError(error);
    } finally {
      if (seq === this.searchSeq) {
        this.searchLoading = false;
      }
    }
  }

  handleSearchFocus() {
    this.searchOpen = true;
  }

  handleSearchBlur() {
    this.searchOpen = false;
  }

  handleSearchKeydown(event) {
    const count = this.searchResults.length;
    if (event.key === "ArrowDown" && count > 0) {
      event.preventDefault();
      this.searchOpen = true;
      this.highlightedIndex = (this.highlightedIndex + 1) % count;
    } else if (event.key === "ArrowUp" && count > 0) {
      event.preventDefault();
      this.highlightedIndex = (this.highlightedIndex - 1 + count) % count;
    } else if (event.key === "Enter") {
      // Entrée ne doit jamais enregistrer la pop-up : elle choisit le résultat surligné.
      event.preventDefault();
      if (this.searchOpen && this.highlightedIndex >= 0) {
        this.addValidator(this.searchResults[this.highlightedIndex]);
      }
    } else if (event.key === "Escape" && this.searchOpen) {
      event.preventDefault();
      event.stopPropagation();
      this.searchOpen = false;
    }
  }

  handleResultHover(event) {
    this.highlightedIndex = Number(event.currentTarget.dataset.index);
  }

  /** mousedown (et non click) : le champ garde le focus, la liste ne se ferme donc pas avant le choix. */
  handleResultMouseDown(event) {
    event.preventDefault();
    const row = this.searchResults[Number(event.currentTarget.dataset.index)];
    if (row) {
      this.addValidator(row);
    }
  }

  addValidator(row) {
    if (this.form.validators.some((v) => v.userId === row.userId)) {
      return;
    }
    this.form = {
      ...this.form,
      validators: [
        ...this.form.validators,
        {
          userId: row.userId,
          name: row.name,
          title: row.title,
          active: true,
          entering: true
        }
      ]
    };
    this.searchTerm = "";
    this.searchResults = [];
    this.highlightedIndex = -1;
    this.searchSeq++;
    const input = this.template.querySelector('[data-id="validator-search"]');
    if (input) {
      input.value = "";
      input.focus();
    }
  }

  /** Retrait sans confirmation : la pastille s'efface (animation brève) puis disparaît de la liste. */
  handleRemoveValidator(event) {
    const userId = event.currentTarget.dataset.userid;
    this.form = {
      ...this.form,
      validators: this.form.validators.map((v) => {
        return v.userId === userId ? { ...v, removing: true } : v;
      })
    };
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- durée de l'animation de sortie de la pastille.
    const timer = setTimeout(() => {
      this.form = {
        ...this.form,
        validators: this.form.validators.filter((v) => v.userId !== userId)
      };
    }, REMOVE_ANIMATION_MS);
    this.removeTimers.push(timer);
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    let value = event.target.value;
    if (field === "active") {
      value = event.target.checked;
    } else if (
      field === "coefficient" ||
      field === "workingDays" ||
      field === "floorPercent" ||
      field === "targetPercent" ||
      field === "idealPercent"
    ) {
      // lightning-input type="number" renvoie une chaîne : convertie en Decimal côté Apex,
      // jamais une chaîne vide, qui casserait le contrat Decimal de savePtfEntity.
      value = value === "" ? null : Number(value);
    }
    this.form = { ...this.form, [field]: value };
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await savePtfEntityApex({
        recordId: this.form.id,
        name: this.form.name,
        active: this.form.active,
        address: this.form.address,
        postalCode: this.form.postalCode,
        city: this.form.city,
        country: this.form.country,
        siret: this.form.siret,
        phone: this.form.phone,
        fax: this.form.fax,
        website: this.form.website,
        commercialEmail: this.form.commercialEmail,
        bankName: this.form.bankName,
        iban: this.form.iban,
        rib: this.form.rib,
        bic: this.form.bic,
        tribunalCompetent: this.form.tribunalCompetent,
        templateCode: this.form.templateCode,
        coefficient: this.form.coefficient,
        workingDays: this.form.workingDays,
        floorPercent: this.form.floorPercent,
        targetPercent: this.form.targetPercent,
        idealPercent: this.form.idealPercent,
        validatorUserIds: this.form.validators
          .filter((v) => !v.removing)
          .map((v) => v.userId)
      });
      this.showForm = false;
      this.resetSearch();
      await this.loadEntities();
      this.showToast(I18N.AR_Common_SuccessTitle, I18N.AR_APE_Saved, "success");
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  async handleDelete(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.entities.find((r) => r.id === id);
    // Rien n'est appelé côté serveur sans confirmation.
    if (!row || !(await confirmAdminDelete(row.name))) {
      return;
    }
    try {
      await deletePtfEntityApex({ recordId: id });
      await this.loadEntities();
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_APE_Deleted,
        "success"
      );
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}