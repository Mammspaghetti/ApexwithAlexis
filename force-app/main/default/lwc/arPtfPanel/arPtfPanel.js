import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { reduceErrors } from "c/arErrorUtils";
import { avenantCreatedToast } from "c/arAvenantGeneration";
import listValideurOptionsApex from "@salesforce/apex/AR_PTFDataService.listValideurOptions";
import getGenerationDefaults from "@salesforce/apex/AR_PTFDataService.getGenerationDefaults";
import savePtfFormDraftApex from "@salesforce/apex/AR_PTFDataService.savePtfFormDraft";
import clearPtfFormDraftApex from "@salesforce/apex/AR_PTFDataService.clearPtfFormDraft";
import previewPtfLotsApex from "@salesforce/apex/AR_PTFDataService.previewPtfLots";
import getEntityReadinessByTemplate from "@salesforce/apex/AR_PTFDataService.getEntityReadinessByTemplate";
import getEntityTemplateInfo from "@salesforce/apex/AR_PTFDataService.getEntityTemplateInfo";
import generatePTFApex from "@salesforce/apex/AR_PTFGenerationService.generatePTF";
import renderAndStorePTFApex from "@salesforce/apex/AR_PTFGenerationService.renderAndStorePTF";
import retryRenderPTFApex from "@salesforce/apex/AR_PTFGenerationService.retryRenderPTF";
import markRenderFailedApex from "@salesforce/apex/AR_PTFGenerationService.markRenderFailed";
import listPTFDocuments from "@salesforce/apex/AR_PTFGenerationService.listPTFDocuments";
import createPreviewApex from "@salesforce/apex/AR_PTFGenerationService.createPreview";
import getTemplateOptions from "@salesforce/apex/AR_PTFDataService.getTemplateOptions";
import previewAvenantLotsApex from "@salesforce/apex/AR_PTFDataService.previewAvenantLots";
import getAvenantDefaultsApex from "@salesforce/apex/AR_PTFDataService.getAvenantDefaults";
import getPreviousVersionDocumentsApex from "@salesforce/apex/AR_MatrixChainService.getPreviousVersionDocuments";
import generateAvenantApex from "@salesforce/apex/AR_PTFGenerationService.generateAvenant";
import getAvenantStateApex from "@salesforce/apex/AR_PTFGenerationService.getAvenantState";
import isLegacyAvenantFormEnabledApex from "@salesforce/apex/AR_PTFGenerationService.isLegacyAvenantFormEnabled";
import setIncludedInHistoryApex from "@salesforce/apex/AR_PTFHistoryService.setIncludedInHistory";
import setModificationApex from "@salesforce/apex/AR_PTFHistoryService.setModification";
import getNextDisplayRankApex from "@salesforce/apex/AR_PTFHistoryService.getNextDisplayRank";
// Formats monétaires et calcul de MC2 : jamais réimplémentés ici. Le miroir JS du moteur est la
// source unique côté client (cf. CLAUDE.md — arPricingEngine et AR_PricingCalculator doivent rester
// synchrones), et formatMoney porte le symbole de la devise, pas seulement le nombre (session 26).
import { calcMC2, formatMoney, formatPercent } from "c/arPricingEngine";
import { formatLabel } from "c/arI18n";
import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_Common_Download from "@salesforce/label/c.AR_Common_Download";
import LBL_AR_Common_Email from "@salesforce/label/c.AR_Common_Email";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_Generate from "@salesforce/label/c.AR_Common_Generate";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Name from "@salesforce/label/c.AR_Common_Name";
import LBL_AR_Common_No from "@salesforce/label/c.AR_Common_No";
import LBL_AR_Common_Open from "@salesforce/label/c.AR_Common_Open";
import LBL_AR_Common_Phone from "@salesforce/label/c.AR_Common_Phone";
import LBL_AR_Common_Preview from "@salesforce/label/c.AR_Common_Preview";
import LBL_AR_Common_Reference from "@salesforce/label/c.AR_Common_Reference";
import LBL_AR_Common_Refresh from "@salesforce/label/c.AR_Common_Refresh";
import LBL_AR_Common_Save from "@salesforce/label/c.AR_Common_Save";
import LBL_AR_Common_Status from "@salesforce/label/c.AR_Common_Status";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_UnknownErrorLower from "@salesforce/label/c.AR_Common_UnknownErrorLower";
import LBL_AR_Common_Version from "@salesforce/label/c.AR_Common_Version";
import LBL_AR_PTF_AbmiTemplateFields from "@salesforce/label/c.AR_PTF_AbmiTemplateFields";
import LBL_AR_PTF_AlreadyGeneratedPdfs from "@salesforce/label/c.AR_PTF_AlreadyGeneratedPdfs";
import LBL_AR_PTF_ApplyDraftTemplate from "@salesforce/label/c.AR_PTF_ApplyDraftTemplate";
import LBL_AR_PTF_AuthorName from "@salesforce/label/c.AR_PTF_AuthorName";
import LBL_AR_PTF_AuthorRole from "@salesforce/label/c.AR_PTF_AuthorRole";
import LBL_AR_PTF_AvenantBelowFloor from "@salesforce/label/c.AR_PTF_AvenantBelowFloor";
import LBL_AR_PTF_AvenantGenerated from "@salesforce/label/c.AR_PTF_AvenantGenerated";
import LBL_AR_PTF_AvenantGeneratedAfterValidation from "@salesforce/label/c.AR_PTF_AvenantGeneratedAfterValidation";
import LBL_AR_PTF_AvenantNotInHistory from "@salesforce/label/c.AR_PTF_AvenantNotInHistory";
import LBL_AR_PTF_AvenantOfOriginReadonly from "@salesforce/label/c.AR_PTF_AvenantOfOriginReadonly";
import LBL_AR_PTF_AvenantReadFromMatrix from "@salesforce/label/c.AR_PTF_AvenantReadFromMatrix";
import LBL_AR_PTF_AvenantRowLabel from "@salesforce/label/c.AR_PTF_AvenantRowLabel";
import LBL_AR_PTF_AvenantStateUnavailable from "@salesforce/label/c.AR_PTF_AvenantStateUnavailable";
import LBL_AR_PTF_AvenantToPtf from "@salesforce/label/c.AR_PTF_AvenantToPtf";
import LBL_AR_PTF_ClickToSpecify from "@salesforce/label/c.AR_PTF_ClickToSpecify";
import LBL_AR_PTF_ClientContactName from "@salesforce/label/c.AR_PTF_ClientContactName";
import LBL_AR_PTF_ClientContactRole from "@salesforce/label/c.AR_PTF_ClientContactRole";
import LBL_AR_PTF_ClientNeedsSection from "@salesforce/label/c.AR_PTF_ClientNeedsSection";
import LBL_AR_PTF_ClientProvidedEquipment from "@salesforce/label/c.AR_PTF_ClientProvidedEquipment";
import LBL_AR_PTF_CommaSeparatedPlaceholder from "@salesforce/label/c.AR_PTF_CommaSeparatedPlaceholder";
import LBL_AR_PTF_CompetentCourt from "@salesforce/label/c.AR_PTF_CompetentCourt";
import LBL_AR_PTF_ComputedAmountColumn from "@salesforce/label/c.AR_PTF_ComputedAmountColumn";
import LBL_AR_PTF_ConfirmAndGenerate from "@salesforce/label/c.AR_PTF_ConfirmAndGenerate";
import LBL_AR_PTF_ConfirmGenerateAvenant from "@salesforce/label/c.AR_PTF_ConfirmGenerateAvenant";
import LBL_AR_PTF_ContactEmail from "@salesforce/label/c.AR_PTF_ContactEmail";
import LBL_AR_PTF_ContactPhone from "@salesforce/label/c.AR_PTF_ContactPhone";
import LBL_AR_PTF_CreateAvenant from "@salesforce/label/c.AR_PTF_CreateAvenant";
import LBL_AR_PTF_DaysColumn from "@salesforce/label/c.AR_PTF_DaysColumn";
import LBL_AR_PTF_Deliverables from "@salesforce/label/c.AR_PTF_Deliverables";
import LBL_AR_PTF_DocumentGenerated from "@salesforce/label/c.AR_PTF_DocumentGenerated";
import LBL_AR_PTF_DocumentTemplate from "@salesforce/label/c.AR_PTF_DocumentTemplate";
import LBL_AR_PTF_DraftOtherAvenantWarning from "@salesforce/label/c.AR_PTF_DraftOtherAvenantWarning";
import LBL_AR_PTF_DraftOtherTemplate from "@salesforce/label/c.AR_PTF_DraftOtherTemplate";
import LBL_AR_PTF_DraftSaved from "@salesforce/label/c.AR_PTF_DraftSaved";
import LBL_AR_PTF_DraftSavedBy from "@salesforce/label/c.AR_PTF_DraftSavedBy";
import LBL_AR_PTF_DraftSavedOn from "@salesforce/label/c.AR_PTF_DraftSavedOn";
import LBL_AR_PTF_DraftSavedOnBy from "@salesforce/label/c.AR_PTF_DraftSavedOnBy";
import LBL_AR_PTF_DraftUnreadable from "@salesforce/label/c.AR_PTF_DraftUnreadable";
import LBL_AR_PTF_DueDateColumn from "@salesforce/label/c.AR_PTF_DueDateColumn";
import LBL_AR_PTF_EntityNotConfigured from "@salesforce/label/c.AR_PTF_EntityNotConfigured";
import LBL_AR_PTF_ExcludedFromHistory from "@salesforce/label/c.AR_PTF_ExcludedFromHistory";
import LBL_AR_PTF_ExpertiseDomain from "@salesforce/label/c.AR_PTF_ExpertiseDomain";
import LBL_AR_PTF_ExpertiseDomainPlaceholder from "@salesforce/label/c.AR_PTF_ExpertiseDomainPlaceholder";
import LBL_AR_PTF_ExtensionUntil from "@salesforce/label/c.AR_PTF_ExtensionUntil";
import LBL_AR_PTF_FailedNotInHistory from "@salesforce/label/c.AR_PTF_FailedNotInHistory";
import LBL_AR_PTF_FirstVersionNoModification from "@salesforce/label/c.AR_PTF_FirstVersionNoModification";
import LBL_AR_PTF_ForTheAttentionOf from "@salesforce/label/c.AR_PTF_ForTheAttentionOf";
import LBL_AR_PTF_GapPrefix from "@salesforce/label/c.AR_PTF_GapPrefix";
import LBL_AR_PTF_GenerateAvenant from "@salesforce/label/c.AR_PTF_GenerateAvenant";
import LBL_AR_PTF_GeneratePtf from "@salesforce/label/c.AR_PTF_GeneratePtf";
import LBL_AR_PTF_GeneratedOnColumn from "@salesforce/label/c.AR_PTF_GeneratedOnColumn";
import LBL_AR_PTF_GeneratedWithWarning from "@salesforce/label/c.AR_PTF_GeneratedWithWarning";
import LBL_AR_PTF_GenerationFailed from "@salesforce/label/c.AR_PTF_GenerationFailed";
import LBL_AR_PTF_GenerationInProgress from "@salesforce/label/c.AR_PTF_GenerationInProgress";
import LBL_AR_PTF_GenerationInProgressFewSeconds from "@salesforce/label/c.AR_PTF_GenerationInProgressFewSeconds";
import LBL_AR_PTF_HistoryCheckboxTitle from "@salesforce/label/c.AR_PTF_HistoryCheckboxTitle";
import LBL_AR_PTF_HistoryColumnShort from "@salesforce/label/c.AR_PTF_HistoryColumnShort";
import LBL_AR_PTF_HistoryUnavailable from "@salesforce/label/c.AR_PTF_HistoryUnavailable";
import LBL_AR_PTF_IncludeInHistory from "@salesforce/label/c.AR_PTF_IncludeInHistory";
import LBL_AR_PTF_LegacyDocumentTitle from "@salesforce/label/c.AR_PTF_LegacyDocumentTitle";
import LBL_AR_PTF_LotAmount from "@salesforce/label/c.AR_PTF_LotAmount";
import LBL_AR_PTF_LotColumn from "@salesforce/label/c.AR_PTF_LotColumn";
import LBL_AR_PTF_LotGapNoMargin from "@salesforce/label/c.AR_PTF_LotGapNoMargin";
import LBL_AR_PTF_LotGapWithMargin from "@salesforce/label/c.AR_PTF_LotGapWithMargin";
import LBL_AR_PTF_LotsAndSchedule from "@salesforce/label/c.AR_PTF_LotsAndSchedule";
import LBL_AR_PTF_LotsTotals from "@salesforce/label/c.AR_PTF_LotsTotals";
import LBL_AR_PTF_MarginImpactPrefix from "@salesforce/label/c.AR_PTF_MarginImpactPrefix";
import LBL_AR_PTF_MarginImpactUnavailable from "@salesforce/label/c.AR_PTF_MarginImpactUnavailable";
import LBL_AR_PTF_MeetingFrequency from "@salesforce/label/c.AR_PTF_MeetingFrequency";
import LBL_AR_PTF_Mobile from "@salesforce/label/c.AR_PTF_Mobile";
import LBL_AR_PTF_ModificationColumn from "@salesforce/label/c.AR_PTF_ModificationColumn";
import LBL_AR_PTF_MonthColumn from "@salesforce/label/c.AR_PTF_MonthColumn";
import LBL_AR_PTF_NeedAndSolutionSection from "@salesforce/label/c.AR_PTF_NeedAndSolutionSection";
import LBL_AR_PTF_NewDailyRate from "@salesforce/label/c.AR_PTF_NewDailyRate";
import LBL_AR_PTF_NewRateEffectiveDate from "@salesforce/label/c.AR_PTF_NewRateEffectiveDate";
import LBL_AR_PTF_NewVersionDialogTitle from "@salesforce/label/c.AR_PTF_NewVersionDialogTitle";
import LBL_AR_PTF_NextVersionUnknown from "@salesforce/label/c.AR_PTF_NextVersionUnknown";
import LBL_AR_PTF_NoAvenantForMatrix from "@salesforce/label/c.AR_PTF_NoAvenantForMatrix";
import LBL_AR_PTF_NoPtfForMatrix from "@salesforce/label/c.AR_PTF_NoPtfForMatrix";
import LBL_AR_PTF_NoRankNotGenerated from "@salesforce/label/c.AR_PTF_NoRankNotGenerated";
import LBL_AR_PTF_OldDailyRatePrefix from "@salesforce/label/c.AR_PTF_OldDailyRatePrefix";
import LBL_AR_PTF_OldRateUnavailable from "@salesforce/label/c.AR_PTF_OldRateUnavailable";
import LBL_AR_PTF_OpenDocument from "@salesforce/label/c.AR_PTF_OpenDocument";
import LBL_AR_PTF_OriginContactsNotLoaded from "@salesforce/label/c.AR_PTF_OriginContactsNotLoaded";
import LBL_AR_PTF_OurReferences from "@salesforce/label/c.AR_PTF_OurReferences";
import LBL_AR_PTF_Overridden from "@salesforce/label/c.AR_PTF_Overridden";
import LBL_AR_PTF_PanelTitle from "@salesforce/label/c.AR_PTF_PanelTitle";
import LBL_AR_PTF_PaymentTerms from "@salesforce/label/c.AR_PTF_PaymentTerms";
import LBL_AR_PTF_PdfRenderFailed from "@salesforce/label/c.AR_PTF_PdfRenderFailed";
import LBL_AR_PTF_PdfRenderUnknownError from "@salesforce/label/c.AR_PTF_PdfRenderUnknownError";
import LBL_AR_PTF_PendingNotInHistory from "@salesforce/label/c.AR_PTF_PendingNotInHistory";
import LBL_AR_PTF_PopupBlockedMessage from "@salesforce/label/c.AR_PTF_PopupBlockedMessage";
import LBL_AR_PTF_PopupBlockedTitle from "@salesforce/label/c.AR_PTF_PopupBlockedTitle";
import LBL_AR_PTF_PreviewOpenedAt from "@salesforce/label/c.AR_PTF_PreviewOpenedAt";
import LBL_AR_PTF_PriceChanges from "@salesforce/label/c.AR_PTF_PriceChanges";
import LBL_AR_PTF_PriceEvolution from "@salesforce/label/c.AR_PTF_PriceEvolution";
import LBL_AR_PTF_ProjectContextSection from "@salesforce/label/c.AR_PTF_ProjectContextSection";
import LBL_AR_PTF_ProjectDefinitionSection from "@salesforce/label/c.AR_PTF_ProjectDefinitionSection";
import LBL_AR_PTF_ProvidedEquipment from "@salesforce/label/c.AR_PTF_ProvidedEquipment";
import LBL_AR_PTF_PtfGenerated from "@salesforce/label/c.AR_PTF_PtfGenerated";
import LBL_AR_PTF_RegenerateAvenant from "@salesforce/label/c.AR_PTF_RegenerateAvenant";
import LBL_AR_PTF_RegeneratePtf from "@salesforce/label/c.AR_PTF_RegeneratePtf";
import LBL_AR_PTF_RemoveFromHistory from "@salesforce/label/c.AR_PTF_RemoveFromHistory";
import LBL_AR_PTF_RenderProbablyInterrupted from "@salesforce/label/c.AR_PTF_RenderProbablyInterrupted";
import LBL_AR_PTF_ResetDraftConfirm from "@salesforce/label/c.AR_PTF_ResetDraftConfirm";
import LBL_AR_PTF_ResetToDefaults from "@salesforce/label/c.AR_PTF_ResetToDefaults";
import LBL_AR_PTF_ResumeImpossible from "@salesforce/label/c.AR_PTF_ResumeImpossible";
import LBL_AR_PTF_RetainedAmountColumn from "@salesforce/label/c.AR_PTF_RetainedAmountColumn";
import LBL_AR_PTF_RetryRender from "@salesforce/label/c.AR_PTF_RetryRender";
import LBL_AR_PTF_RevisedScheduleUnavailable from "@salesforce/label/c.AR_PTF_RevisedScheduleUnavailable";
import LBL_AR_PTF_Role from "@salesforce/label/c.AR_PTF_Role";
import LBL_AR_PTF_SaveDraft from "@salesforce/label/c.AR_PTF_SaveDraft";
import LBL_AR_PTF_TjmPeriodDateHelp from "@salesforce/label/c.AR_PTF_TjmPeriodDateHelp";
import LBL_AR_PTF_TjmPeriodDateLabel from "@salesforce/label/c.AR_PTF_TjmPeriodDateLabel";
import LBL_AR_PTF_TjmPeriodDateOrder from "@salesforce/label/c.AR_PTF_TjmPeriodDateOrder";
import LBL_AR_PTF_TjmPeriodDateOutside from "@salesforce/label/c.AR_PTF_TjmPeriodDateOutside";
import LBL_AR_PTF_TjmPeriodDateRequired from "@salesforce/label/c.AR_PTF_TjmPeriodDateRequired";
import LBL_AR_PTF_TjmPeriodRow from "@salesforce/label/c.AR_PTF_TjmPeriodRow";
import LBL_AR_PTF_TjmPeriodsTitle from "@salesforce/label/c.AR_PTF_TjmPeriodsTitle";
import LBL_AR_PTF_ScheduleLoading from "@salesforce/label/c.AR_PTF_ScheduleLoading";
import LBL_AR_PTF_ScheduleNeedsInputs from "@salesforce/label/c.AR_PTF_ScheduleNeedsInputs";
import LBL_AR_PTF_Section22 from "@salesforce/label/c.AR_PTF_Section22";
import LBL_AR_PTF_Section23 from "@salesforce/label/c.AR_PTF_Section23";
import LBL_AR_PTF_Section31 from "@salesforce/label/c.AR_PTF_Section31";
import LBL_AR_PTF_Section310 from "@salesforce/label/c.AR_PTF_Section310";
import LBL_AR_PTF_Section32 from "@salesforce/label/c.AR_PTF_Section32";
import LBL_AR_PTF_Section33 from "@salesforce/label/c.AR_PTF_Section33";
import LBL_AR_PTF_Section34 from "@salesforce/label/c.AR_PTF_Section34";
import LBL_AR_PTF_Section39 from "@salesforce/label/c.AR_PTF_Section39";
import LBL_AR_PTF_Section41 from "@salesforce/label/c.AR_PTF_Section41";
import LBL_AR_PTF_Signatory1 from "@salesforce/label/c.AR_PTF_Signatory1";
import LBL_AR_PTF_Signatory2 from "@salesforce/label/c.AR_PTF_Signatory2";
import LBL_AR_PTF_Signatory2Help from "@salesforce/label/c.AR_PTF_Signatory2Help";
import LBL_AR_PTF_SpecifyEllipsis from "@salesforce/label/c.AR_PTF_SpecifyEllipsis";
import LBL_AR_PTF_StatusFailed from "@salesforce/label/c.AR_PTF_StatusFailed";
import LBL_AR_PTF_StatusGenerated from "@salesforce/label/c.AR_PTF_StatusGenerated";
import LBL_AR_PTF_Subject from "@salesforce/label/c.AR_PTF_Subject";
import LBL_AR_PTF_ClientAddress from "@salesforce/label/c.AR_PTF_ClientAddress";
import LBL_AR_PTF_ClientAddressModified from "@salesforce/label/c.AR_PTF_ClientAddressModified";
import LBL_AR_PTF_ClientAddressRestore from "@salesforce/label/c.AR_PTF_ClientAddressRestore";
import LBL_AR_PTF_ClientAddressModifiedHelp from "@salesforce/label/c.AR_PTF_ClientAddressModifiedHelp";
import LBL_AR_PTF_PreviousVersionsTitle from "@salesforce/label/c.AR_PTF_PreviousVersionsTitle";
import LBL_AR_PTF_PreviousVersionGroup from "@salesforce/label/c.AR_PTF_PreviousVersionGroup";
import LBL_AR_PTF_PreviousVersionGroupNoDate from "@salesforce/label/c.AR_PTF_PreviousVersionGroupNoDate";
import LBL_AR_Msg_PTF_ClientAddressMissing from "@salesforce/label/c.AR_Msg_PTF_ClientAddressMissing";
import LBL_AR_PTF_SummaryDailyRate from "@salesforce/label/c.AR_PTF_SummaryDailyRate";
import LBL_AR_PTF_SummaryEffectiveDate from "@salesforce/label/c.AR_PTF_SummaryEffectiveDate";
import LBL_AR_PTF_SummaryEndDate from "@salesforce/label/c.AR_PTF_SummaryEndDate";
import LBL_AR_PTF_TemplateOrigin from "@salesforce/label/c.AR_PTF_TemplateOrigin";
import LBL_AR_PTF_TemplateOriginOverridden from "@salesforce/label/c.AR_PTF_TemplateOriginOverridden";
import LBL_AR_PTF_TemplateNotEntityTemplate from "@salesforce/label/c.AR_PTF_TemplateNotEntityTemplate";
import LBL_AR_PTF_TemplateSourceAccount from "@salesforce/label/c.AR_PTF_TemplateSourceAccount";
import LBL_AR_PTF_TemplateSourceEntity from "@salesforce/label/c.AR_PTF_TemplateSourceEntity";
import LBL_AR_PTF_TemplateSourceGeneric from "@salesforce/label/c.AR_PTF_TemplateSourceGeneric";
import LBL_AR_PTF_TemplateSourceManual from "@salesforce/label/c.AR_PTF_TemplateSourceManual";
import LBL_AR_PTF_TemplateSourceOther from "@salesforce/label/c.AR_PTF_TemplateSourceOther";
import LBL_AR_PTF_TogglePdfHistoryTitle from "@salesforce/label/c.AR_PTF_TogglePdfHistoryTitle";
import LBL_AR_PTF_MonthlyLissed from "@salesforce/label/c.AR_PTF_MonthlyLissed";
import LBL_AR_PTF_MonthlyLissedHelp from "@salesforce/label/c.AR_PTF_MonthlyLissedHelp";
import LBL_AR_PTF_RplsrPtfHelp from "@salesforce/label/c.AR_PTF_RplsrPtfHelp";
import LBL_AR_PTF_TravelCostsAtActual from "@salesforce/label/c.AR_PTF_TravelCostsAtActual";
import LBL_AR_PTF_ValidatorName from "@salesforce/label/c.AR_PTF_ValidatorName";
import LBL_AR_PTF_ValidatorRole from "@salesforce/label/c.AR_PTF_ValidatorRole";
import LBL_AR_PTF_VersionModificationAriaLabel from "@salesforce/label/c.AR_PTF_VersionModificationAriaLabel";
import LBL_AR_PTF_YesClear from "@salesforce/label/c.AR_PTF_YesClear";

const I18N = {
  AR_Common_Cancel: LBL_AR_Common_Cancel,
  AR_Common_Download: LBL_AR_Common_Download,
  AR_Common_Email: LBL_AR_Common_Email,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_Generate: LBL_AR_Common_Generate,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Name: LBL_AR_Common_Name,
  AR_Common_No: LBL_AR_Common_No,
  AR_Common_Open: LBL_AR_Common_Open,
  AR_Common_Phone: LBL_AR_Common_Phone,
  AR_Common_Preview: LBL_AR_Common_Preview,
  AR_Common_Reference: LBL_AR_Common_Reference,
  AR_Common_Refresh: LBL_AR_Common_Refresh,
  AR_Common_Save: LBL_AR_Common_Save,
  AR_Common_Status: LBL_AR_Common_Status,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_UnknownErrorLower: LBL_AR_Common_UnknownErrorLower,
  AR_Common_Version: LBL_AR_Common_Version,
  AR_PTF_AbmiTemplateFields: LBL_AR_PTF_AbmiTemplateFields,
  AR_PTF_AlreadyGeneratedPdfs: LBL_AR_PTF_AlreadyGeneratedPdfs,
  AR_PTF_ApplyDraftTemplate: LBL_AR_PTF_ApplyDraftTemplate,
  AR_PTF_AuthorName: LBL_AR_PTF_AuthorName,
  AR_PTF_AuthorRole: LBL_AR_PTF_AuthorRole,
  AR_PTF_AvenantBelowFloor: LBL_AR_PTF_AvenantBelowFloor,
  AR_PTF_AvenantGenerated: LBL_AR_PTF_AvenantGenerated,
  AR_PTF_AvenantGeneratedAfterValidation:
    LBL_AR_PTF_AvenantGeneratedAfterValidation,
  AR_PTF_AvenantNotInHistory: LBL_AR_PTF_AvenantNotInHistory,
  AR_PTF_AvenantOfOriginReadonly: LBL_AR_PTF_AvenantOfOriginReadonly,
  AR_PTF_AvenantReadFromMatrix: LBL_AR_PTF_AvenantReadFromMatrix,
  AR_PTF_AvenantRowLabel: LBL_AR_PTF_AvenantRowLabel,
  AR_PTF_AvenantStateUnavailable: LBL_AR_PTF_AvenantStateUnavailable,
  AR_PTF_AvenantToPtf: LBL_AR_PTF_AvenantToPtf,
  AR_PTF_ClickToSpecify: LBL_AR_PTF_ClickToSpecify,
  AR_PTF_ClientContactName: LBL_AR_PTF_ClientContactName,
  AR_PTF_ClientContactRole: LBL_AR_PTF_ClientContactRole,
  AR_PTF_ClientNeedsSection: LBL_AR_PTF_ClientNeedsSection,
  AR_PTF_ClientProvidedEquipment: LBL_AR_PTF_ClientProvidedEquipment,
  AR_PTF_CommaSeparatedPlaceholder: LBL_AR_PTF_CommaSeparatedPlaceholder,
  AR_PTF_CompetentCourt: LBL_AR_PTF_CompetentCourt,
  AR_PTF_ComputedAmountColumn: LBL_AR_PTF_ComputedAmountColumn,
  AR_PTF_ConfirmAndGenerate: LBL_AR_PTF_ConfirmAndGenerate,
  AR_PTF_ConfirmGenerateAvenant: LBL_AR_PTF_ConfirmGenerateAvenant,
  AR_PTF_ContactEmail: LBL_AR_PTF_ContactEmail,
  AR_PTF_ContactPhone: LBL_AR_PTF_ContactPhone,
  AR_PTF_CreateAvenant: LBL_AR_PTF_CreateAvenant,
  AR_PTF_DaysColumn: LBL_AR_PTF_DaysColumn,
  AR_PTF_Deliverables: LBL_AR_PTF_Deliverables,
  AR_PTF_DocumentGenerated: LBL_AR_PTF_DocumentGenerated,
  AR_PTF_DocumentTemplate: LBL_AR_PTF_DocumentTemplate,
  AR_PTF_DraftOtherAvenantWarning: LBL_AR_PTF_DraftOtherAvenantWarning,
  AR_PTF_DraftOtherTemplate: LBL_AR_PTF_DraftOtherTemplate,
  AR_PTF_DraftSaved: LBL_AR_PTF_DraftSaved,
  AR_PTF_DraftSavedBy: LBL_AR_PTF_DraftSavedBy,
  AR_PTF_DraftSavedOn: LBL_AR_PTF_DraftSavedOn,
  AR_PTF_DraftSavedOnBy: LBL_AR_PTF_DraftSavedOnBy,
  AR_PTF_DraftUnreadable: LBL_AR_PTF_DraftUnreadable,
  AR_PTF_DueDateColumn: LBL_AR_PTF_DueDateColumn,
  AR_PTF_EntityNotConfigured: LBL_AR_PTF_EntityNotConfigured,
  AR_PTF_ExcludedFromHistory: LBL_AR_PTF_ExcludedFromHistory,
  AR_PTF_ExpertiseDomain: LBL_AR_PTF_ExpertiseDomain,
  AR_PTF_ExpertiseDomainPlaceholder: LBL_AR_PTF_ExpertiseDomainPlaceholder,
  AR_PTF_ExtensionUntil: LBL_AR_PTF_ExtensionUntil,
  AR_PTF_FailedNotInHistory: LBL_AR_PTF_FailedNotInHistory,
  AR_PTF_FirstVersionNoModification: LBL_AR_PTF_FirstVersionNoModification,
  AR_PTF_ForTheAttentionOf: LBL_AR_PTF_ForTheAttentionOf,
  AR_PTF_GapPrefix: LBL_AR_PTF_GapPrefix,
  AR_PTF_GenerateAvenant: LBL_AR_PTF_GenerateAvenant,
  AR_PTF_GeneratePtf: LBL_AR_PTF_GeneratePtf,
  AR_PTF_GeneratedOnColumn: LBL_AR_PTF_GeneratedOnColumn,
  AR_PTF_GeneratedWithWarning: LBL_AR_PTF_GeneratedWithWarning,
  AR_PTF_GenerationFailed: LBL_AR_PTF_GenerationFailed,
  AR_PTF_GenerationInProgress: LBL_AR_PTF_GenerationInProgress,
  AR_PTF_GenerationInProgressFewSeconds:
    LBL_AR_PTF_GenerationInProgressFewSeconds,
  AR_PTF_HistoryCheckboxTitle: LBL_AR_PTF_HistoryCheckboxTitle,
  AR_PTF_HistoryColumnShort: LBL_AR_PTF_HistoryColumnShort,
  AR_PTF_HistoryUnavailable: LBL_AR_PTF_HistoryUnavailable,
  AR_PTF_IncludeInHistory: LBL_AR_PTF_IncludeInHistory,
  AR_PTF_LegacyDocumentTitle: LBL_AR_PTF_LegacyDocumentTitle,
  AR_PTF_LotAmount: LBL_AR_PTF_LotAmount,
  AR_PTF_LotColumn: LBL_AR_PTF_LotColumn,
  AR_PTF_LotGapNoMargin: LBL_AR_PTF_LotGapNoMargin,
  AR_PTF_LotGapWithMargin: LBL_AR_PTF_LotGapWithMargin,
  AR_PTF_LotsAndSchedule: LBL_AR_PTF_LotsAndSchedule,
  AR_PTF_LotsTotals: LBL_AR_PTF_LotsTotals,
  AR_PTF_MarginImpactPrefix: LBL_AR_PTF_MarginImpactPrefix,
  AR_PTF_MarginImpactUnavailable: LBL_AR_PTF_MarginImpactUnavailable,
  AR_PTF_MeetingFrequency: LBL_AR_PTF_MeetingFrequency,
  AR_PTF_Mobile: LBL_AR_PTF_Mobile,
  AR_PTF_ModificationColumn: LBL_AR_PTF_ModificationColumn,
  AR_PTF_MonthColumn: LBL_AR_PTF_MonthColumn,
  AR_PTF_NeedAndSolutionSection: LBL_AR_PTF_NeedAndSolutionSection,
  AR_PTF_NewDailyRate: LBL_AR_PTF_NewDailyRate,
  AR_PTF_NewRateEffectiveDate: LBL_AR_PTF_NewRateEffectiveDate,
  AR_PTF_NewVersionDialogTitle: LBL_AR_PTF_NewVersionDialogTitle,
  AR_PTF_NextVersionUnknown: LBL_AR_PTF_NextVersionUnknown,
  AR_PTF_NoAvenantForMatrix: LBL_AR_PTF_NoAvenantForMatrix,
  AR_PTF_NoPtfForMatrix: LBL_AR_PTF_NoPtfForMatrix,
  AR_PTF_NoRankNotGenerated: LBL_AR_PTF_NoRankNotGenerated,
  AR_PTF_OldDailyRatePrefix: LBL_AR_PTF_OldDailyRatePrefix,
  AR_PTF_OldRateUnavailable: LBL_AR_PTF_OldRateUnavailable,
  AR_PTF_OpenDocument: LBL_AR_PTF_OpenDocument,
  AR_PTF_OriginContactsNotLoaded: LBL_AR_PTF_OriginContactsNotLoaded,
  AR_PTF_OurReferences: LBL_AR_PTF_OurReferences,
  AR_PTF_Overridden: LBL_AR_PTF_Overridden,
  AR_PTF_PanelTitle: LBL_AR_PTF_PanelTitle,
  AR_PTF_PaymentTerms: LBL_AR_PTF_PaymentTerms,
  AR_PTF_PdfRenderFailed: LBL_AR_PTF_PdfRenderFailed,
  AR_PTF_PdfRenderUnknownError: LBL_AR_PTF_PdfRenderUnknownError,
  AR_PTF_PendingNotInHistory: LBL_AR_PTF_PendingNotInHistory,
  AR_PTF_PopupBlockedMessage: LBL_AR_PTF_PopupBlockedMessage,
  AR_PTF_PopupBlockedTitle: LBL_AR_PTF_PopupBlockedTitle,
  AR_PTF_PreviewOpenedAt: LBL_AR_PTF_PreviewOpenedAt,
  AR_PTF_PriceChanges: LBL_AR_PTF_PriceChanges,
  AR_PTF_PriceEvolution: LBL_AR_PTF_PriceEvolution,
  AR_PTF_ProjectContextSection: LBL_AR_PTF_ProjectContextSection,
  AR_PTF_ProjectDefinitionSection: LBL_AR_PTF_ProjectDefinitionSection,
  AR_PTF_ProvidedEquipment: LBL_AR_PTF_ProvidedEquipment,
  AR_PTF_PtfGenerated: LBL_AR_PTF_PtfGenerated,
  AR_PTF_RegenerateAvenant: LBL_AR_PTF_RegenerateAvenant,
  AR_PTF_RegeneratePtf: LBL_AR_PTF_RegeneratePtf,
  AR_PTF_RemoveFromHistory: LBL_AR_PTF_RemoveFromHistory,
  AR_PTF_RenderProbablyInterrupted: LBL_AR_PTF_RenderProbablyInterrupted,
  AR_PTF_ResetDraftConfirm: LBL_AR_PTF_ResetDraftConfirm,
  AR_PTF_ResetToDefaults: LBL_AR_PTF_ResetToDefaults,
  AR_PTF_ResumeImpossible: LBL_AR_PTF_ResumeImpossible,
  AR_PTF_RetainedAmountColumn: LBL_AR_PTF_RetainedAmountColumn,
  AR_PTF_RetryRender: LBL_AR_PTF_RetryRender,
  AR_PTF_RevisedScheduleUnavailable: LBL_AR_PTF_RevisedScheduleUnavailable,
  AR_PTF_Role: LBL_AR_PTF_Role,
  AR_PTF_SaveDraft: LBL_AR_PTF_SaveDraft,
  AR_PTF_TjmPeriodDateHelp: LBL_AR_PTF_TjmPeriodDateHelp,
  AR_PTF_TjmPeriodDateLabel: LBL_AR_PTF_TjmPeriodDateLabel,
  AR_PTF_TjmPeriodDateOrder: LBL_AR_PTF_TjmPeriodDateOrder,
  AR_PTF_TjmPeriodDateOutside: LBL_AR_PTF_TjmPeriodDateOutside,
  AR_PTF_TjmPeriodDateRequired: LBL_AR_PTF_TjmPeriodDateRequired,
  AR_PTF_TjmPeriodRow: LBL_AR_PTF_TjmPeriodRow,
  AR_PTF_TjmPeriodsTitle: LBL_AR_PTF_TjmPeriodsTitle,
  AR_PTF_ScheduleLoading: LBL_AR_PTF_ScheduleLoading,
  AR_PTF_ScheduleNeedsInputs: LBL_AR_PTF_ScheduleNeedsInputs,
  AR_PTF_Section22: LBL_AR_PTF_Section22,
  AR_PTF_Section23: LBL_AR_PTF_Section23,
  AR_PTF_Section31: LBL_AR_PTF_Section31,
  AR_PTF_Section310: LBL_AR_PTF_Section310,
  AR_PTF_Section32: LBL_AR_PTF_Section32,
  AR_PTF_Section33: LBL_AR_PTF_Section33,
  AR_PTF_Section34: LBL_AR_PTF_Section34,
  AR_PTF_Section39: LBL_AR_PTF_Section39,
  AR_PTF_Section41: LBL_AR_PTF_Section41,
  AR_PTF_Signatory1: LBL_AR_PTF_Signatory1,
  AR_PTF_Signatory2: LBL_AR_PTF_Signatory2,
  AR_PTF_Signatory2Help: LBL_AR_PTF_Signatory2Help,
  AR_PTF_SpecifyEllipsis: LBL_AR_PTF_SpecifyEllipsis,
  AR_PTF_StatusFailed: LBL_AR_PTF_StatusFailed,
  AR_PTF_StatusGenerated: LBL_AR_PTF_StatusGenerated,
  AR_PTF_Subject: LBL_AR_PTF_Subject,
  AR_PTF_ClientAddress: LBL_AR_PTF_ClientAddress,
  AR_PTF_ClientAddressModified: LBL_AR_PTF_ClientAddressModified,
  AR_PTF_ClientAddressRestore: LBL_AR_PTF_ClientAddressRestore,
  AR_PTF_ClientAddressModifiedHelp: LBL_AR_PTF_ClientAddressModifiedHelp,
  AR_PTF_PreviousVersionsTitle: LBL_AR_PTF_PreviousVersionsTitle,
  AR_PTF_PreviousVersionGroup: LBL_AR_PTF_PreviousVersionGroup,
  AR_PTF_PreviousVersionGroupNoDate: LBL_AR_PTF_PreviousVersionGroupNoDate,
  AR_PTF_SummaryDailyRate: LBL_AR_PTF_SummaryDailyRate,
  AR_PTF_SummaryEffectiveDate: LBL_AR_PTF_SummaryEffectiveDate,
  AR_PTF_SummaryEndDate: LBL_AR_PTF_SummaryEndDate,
  AR_PTF_TemplateOrigin: LBL_AR_PTF_TemplateOrigin,
  AR_PTF_TemplateOriginOverridden: LBL_AR_PTF_TemplateOriginOverridden,
  AR_PTF_TemplateNotEntityTemplate: LBL_AR_PTF_TemplateNotEntityTemplate,
  AR_PTF_TemplateSourceAccount: LBL_AR_PTF_TemplateSourceAccount,
  AR_PTF_TemplateSourceEntity: LBL_AR_PTF_TemplateSourceEntity,
  AR_PTF_TemplateSourceGeneric: LBL_AR_PTF_TemplateSourceGeneric,
  AR_PTF_TemplateSourceManual: LBL_AR_PTF_TemplateSourceManual,
  AR_PTF_TemplateSourceOther: LBL_AR_PTF_TemplateSourceOther,
  AR_PTF_TogglePdfHistoryTitle: LBL_AR_PTF_TogglePdfHistoryTitle,
  AR_PTF_MonthlyLissed: LBL_AR_PTF_MonthlyLissed,
  AR_PTF_MonthlyLissedHelp: LBL_AR_PTF_MonthlyLissedHelp,
  AR_PTF_RplsrPtfHelp: LBL_AR_PTF_RplsrPtfHelp,
  AR_PTF_TravelCostsAtActual: LBL_AR_PTF_TravelCostsAtActual,
  AR_PTF_ValidatorName: LBL_AR_PTF_ValidatorName,
  AR_PTF_ValidatorRole: LBL_AR_PTF_ValidatorRole,
  AR_PTF_VersionModificationAriaLabel: LBL_AR_PTF_VersionModificationAriaLabel,
  AR_PTF_YesClear: LBL_AR_PTF_YesClear
};
// Téléchargement direct d'un ContentDocument déjà lié à la matrice/au besoin (session 20) : pas
// besoin d'un appel Apex dédié, l'URL standard Salesforce Files suffit.
const DOWNLOAD_BASE_URL = "/sfc/servlet.shepherd/document/download/";
// Doit rester égal à AR_PTFGenerationService.RENDER_RETRY_AFTER_SECONDS × 1000 : le serveur
// revérifie ce seuil, l'écran ne fait que décider quand afficher le bouton (session 153b).
const RENDER_RETRY_AFTER_MS = 120000;

// Prévisualisation (session 30) : le payload complet (même structure qu'une génération réelle) est
// encodé en base64 dans l'URL du gabarit Visualforce — aucune trace serveur (cf. docs/30-...md §2).
// Risque assumé et documenté : au-delà de cette longueur d'URL encodée, certains navigateurs/proxys
// tronquent silencieusement — on préfère bloquer côté client avec un message actionnable plutôt que
// risquer un aperçu tronqué qui mentirait sur le document réel.
//
// Page corrigée en session 39 : jusqu'ici cette URL était fixée en dur sur le gabarit générique quel
// que soit le gabarit résolu/surchargé — correct à la session 30 (les trois autres pages étaient
// encore des coquilles), plus du tout depuis que les sessions 36-38 les ont mises en page. Un aperçu
// Abylsen/avenant/ABMI montrait la mise en page générique. Résolue maintenant côté serveur
// (AR_PTFGenerationService.getPreviewPageUrl, même aiguillage que la génération réelle) pour ne
// jamais dupliquer la correspondance gabarit → page à un second endroit. Session 124 : données
// persistées sur AR_PTF_Preview__c, plus de limite d'URL.

const EMPTY_FORM = {
  objet: "",
  // Session 279 : adresse client imprimée (pré-remplie depuis le compte, modifiable).
  adresseClient: "",
  contexte: "",
  // I.2 "Contexte du projet" (gabarit Abylsen, session 37) : domaine d'expertise mis en avant.
  // Saisie libre qui POURSUIT la phrase "...savoir-faire éprouvé dans le domaine ___" : inclure
  // l'article ("des méthodes", "de la cybersécurité industrielle"), pas seulement le nom du domaine
  // — cf. le libellé du champ ci-dessous et docs/37-avenant.md.
  domaineExpertise: "",
  livrables: "",
  redacteurNom: "",
  redacteurFonction: "",
  valideurId: "",
  valideurNom: "",
  valideurFonction: "",
  freqReunions: "",
  materielClient: false,
  fraisDepl: false,
  // Facturation mensuelle lissée, décochée par défaut pour toutes les entités.
  facturationMensuelleLissee: false,
  // TJM par périodes (docs/254d) : dates de début des périodes 2, 3, 4 (AAAA-MM-JJ), dans l'ordre.
  // Vide pour une matrice sans période — le formulaire est alors celui d'avant.
  tjmPeriodStarts: [],
  conditionsReglement: "",
  tribunalCompetent: "",
  evolutionPrix: "",
  interTel: "",
  interEmail: "",
  // C27 (session 35) : items de matériel mis à disposition, séparés par des virgules ou des sauts
  // de ligne. Vide = « Mis à disposition par <NOM CLIENT> » sur les gabarits qui l'impriment.
  materielItems: "",
  // Surcharge manuelle du gabarit (vide = résolution automatique compte > entité > générique).
  templateCode: "",

  // Champs propres au gabarit ABMI_DQ012 (session 38, AR_PTFData/AR_PTFDataService.GenerationInput
  // abmi*) — câblés côté Apex et imprimables depuis la session 38, mais sans interface de saisie
  // jusqu'à cette session (cf. CLAUDE.md « Reste à faire »). N'affichés que quand le gabarit résolu
  // ou surchargé est ABMI_DQ012 (cf. isAbmiTemplate) : ne jamais montrer 18 champs de plus sur les
  // trois autres gabarits, déjà longs. Aucune valeur par défaut autre que celle renvoyée par
  // getGenerationDefaults (rédacteur/valideur pour les signataires) : les cinq arbitrages structurels
  // de docs/33-gabarits-ptf-annotations-matthieu.md §3 restent sans réponse client, la doctrine
  // appliquée en session 38 (saisie libre vide plutôt qu'une valeur inventée) vaut aussi ici.
  abmiNosReferences: "",
  abmiAttentionDe: "",
  abmiSignataire1Nom: "",
  abmiSignataire1Fonction: "",
  abmiSignataire1Tel: "",
  abmiSignataire1Mobile: "",
  abmiSignataire1Email: "",
  abmiSignataire2Nom: "",
  abmiSignataire2Fonction: "",
  abmiSignataire2Tel: "",
  abmiSignataire2Email: "",
  abmiDescriptionTravaux: "",
  abmiDonneesEntree: "",
  abmiDescriptionSolution: "",
  abmiAvantages: "",
  abmiRessources: "",
  abmiOrganisationProjet: "",
  abmiHabilitations: "",
  abmiAnalyseRisques: "",
  abmiPropositionFinanciereTexte: ""
};

// Champs du formulaire utilisés par chaque gabarit du sélecteur (docs/294-champs-par-gabarit.md).
// Un champ absent de la liste est masqué, jamais effacé : sa valeur reste dans le formulaire et le
// brouillon. Un gabarit inconnu (ou pas encore résolu) affiche tout. Le valideur, les périodes de TJM
// et la facturation mensuelle lissée sont affichés pour tous : ils bloquent ou modifient la génération.
const COMMON_FIELDS = [
  "adresseClient",
  "objet",
  "contexte",
  "livrables",
  "redacteur"
];
const TEMPLATE_FIELDS = {
  GENERIQUE: [
    ...COMMON_FIELDS,
    "inter",
    "freqReunions",
    "materielRow",
    "materielClient",
    "fraisDepl",
    "conditionsReglement",
    "tribunalCompetent",
    "evolutionPrix"
  ],
  ABYLSEN_AT_V11: [
    ...COMMON_FIELDS,
    "domaineExpertise",
    "inter",
    "freqReunions",
    "materielRow",
    "materielItems",
    "conditionsReglement",
    "tribunalCompetent",
    "evolutionPrix",
    "lots"
  ],
  ABMI_DQ012: [...COMMON_FIELDS],
  AVENANT_AT_V11: ["adresseClient", "redacteur", "inter"]
};
const ALL_FIELD_KEYS = [
  ...new Set(Object.values(TEMPLATE_FIELDS).flat()),
  "domaineExpertise",
  "materielItems",
  "lots"
];

const DRAFT_MODE_PTF = "ptf";
const GENERIC_TEXT_KEY = "GENERIQUE";
const LEGACY_OBJET_PREFIX =
  "La présente Proposition Technique et Financière a pour objet";
// Champs dont le pré-remplissage dépend du gabarit : [champ du formulaire, carte servie par le serveur].
const TEMPLATE_TEXT_FIELDS = [
  ["objet", "objetParGabarit"],
  ["evolutionPrix", "evolutionPrixParGabarit"]
];
const DRAFT_MODE_AVENANT = "avenant";
// Champs texte du formulaire d'avenant repris d'un brouillon ; les huit premiers sont aussi ceux que
// les valeurs serveur (contacts de la PTF d'origine) pré-remplissent — repris du brouillon, ils sont
// marqués « saisis » pour que la réponse tardive des défauts ne les écrase pas.
const AVENANT_CONTACT_FIELDS = [
  "redacteurNom",
  "redacteurFonction",
  "interNom",
  "interFonction",
  "interTel",
  "interEmail"
];
// Valideur : choisi parmi les options du serveur (RA/DA/DD/Directeur du propriétaire), fonction
// modifiable. Repris d'un brouillon seulement s'il fait encore partie des options (cf. applyValideurDraft).
const VALIDEUR_FIELDS = ["valideurId", "valideurNom", "valideurFonction"];
const AVENANT_DRAFT_TEXT_FIELDS = [
  ...AVENANT_CONTACT_FIELDS,
  "prolongationJusquAu",
  "revisionPrixADateDu",
  "adresseClient"
];

/** Session 279 : adresse comparée sans les espaces de début/fin ni les fins de ligne Windows (même règle que le serveur). */
function normalizeAddress(raw) {
  return (raw || "").replace(/\r\n?/g, "\n").trim();
}

/** « Brouillon enregistré le 06/10 à 14:32 par X » (date et heure locales de l'utilisateur). */
// Nombre de jours du lot formaté comme la PTF (« 18,17 j ») : même virgule et même arrondi que le
// reste de l'écran, sans toucher à la valeur (session 239b, reliquat 238).
const FR_DAYS_FORMATTER = new Intl.NumberFormat("fr-FR", {
  maximumFractionDigits: 2
});
/** « 2026-10-01 » → « 01/10/2026 » sans passer par Date (pas de décalage de fuseau sur une date pure). */
function formatIsoDateFr(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : String(iso || "");
}

function formatDraftStamp(entry) {
  const when = new Date(entry.savedAt);
  const by = entry.savedByName;
  if (Number.isNaN(when.getTime())) {
    return by
      ? formatLabel(I18N.AR_PTF_DraftSavedBy, by)
      : I18N.AR_PTF_DraftSaved;
  }
  const day = when.toLocaleDateString("fr-FR", {
    day: "2-digit",
    month: "2-digit"
  });
  const time = when.toLocaleTimeString("fr-FR", {
    hour: "2-digit",
    minute: "2-digit"
  });
  return by
    ? formatLabel(I18N.AR_PTF_DraftSavedOnBy, day, time, by)
    : formatLabel(I18N.AR_PTF_DraftSavedOn, day, time);
}

/** Lots surchargés d'un brouillon → { rang: montant }, limité aux rangs qui existent encore. */
/** Dates de début des périodes 2+ servies avec les défauts (estimées par le serveur), AAAA-MM-JJ. */
function periodStartsFromServer(periodes) {
  if (!Array.isArray(periodes) || periodes.length < 2) {
    return [];
  }
  return periodes.slice(1).map((p) => p.dateDebut || "");
}

function lotOverridesFromDraft(list, lotCount) {
  const out = {};
  (Array.isArray(list) ? list : []).forEach((item) => {
    const index = Number(item && item.index);
    const montant = Number(item && item.montant);
    if (
      Number.isInteger(index) &&
      index >= 0 &&
      index < lotCount &&
      item.montant !== null &&
      item.montant !== "" &&
      Number.isFinite(montant)
    ) {
      out[index] = montant;
    }
  });
  return out;
}

/**
 * Panneau « Proposition Technique et Financière » affiché uniquement quand la matrice parente est
 * validée (gating porté par arPriceMatrixSimulator — cf. isValidatedStatus). Le serveur revalide
 * systématiquement le statut (AR_PTFDataService.collect) : ce composant est un confort, pas la
 * garantie, même principe que arDerogationPanel.
 *
 * Génération en deux appels Apex synchrones successifs (session 20b, cf.
 * docs/20-generation-ptf.md §4.5) : `generatePTF` insère le snapshot (rapide), puis
 * `renderAndStorePTF` rend le PDF et le stocke (plus lent, plusieurs secondes) — chacun dans sa
 * propre transaction serveur. Pas de sondage (polling) : le second appel renvoie directement le
 * résultat final (Généré ou Échec), `isGenerating` couvre les deux appels côté UI.
 */
export default class ArPtfPanel extends NavigationMixin(LightningElement) {
  i18n = I18N;

  @api recordId;
  // Session 113 : arrivée par le bouton PTF de « Mes matrices ». Au premier chargement seulement :
  // défilement jusqu'au panneau, et ouverture directe du formulaire si l'historique est vide. Un
  // historique en échec (documentsLoadError) n'ouvre rien : « vide » n'est pas prouvé.
  @api openOnArrival = false;
  // Session 282 : matrice partagée en lecture (agence du propriétaire). Consultation, ouverture et
  // téléchargement seulement : aucune génération, reprise, modification d'historique ni avenant.
  @api readOnly = false;
  // Session 180c : « Créer un avenant » ouvre désormais arAvenantModal (avenant piloté par la matrice,
  // docs/180-avenant-depuis-la-matrice.md). L'ancien formulaire (session 37) est conservé, non supprimé,
  // derrière ce drapeau ; 180d le branchera sur un réglage administrable (§9bis Q7).
  @api legacyAvenantForm = false;
  // Session 180d (Q7 A) : l'ancien formulaire est aussi réactivable par le réglage administrable
  // AR_General_Setting__c.AR_Legacy_Avenant_Form_Enabled__c, lu à chaque ouverture du panneau.
  legacyAvenantFormSetting = false;
  // Session 180d : état « avenant » de la matrice ouverte (AR_PTFGenerationService.getAvenantState).
  // Sur une matrice avenant, le panneau propose « Générer l'avenant » (et non « Générer la PTF ») et cite
  // la PTF amendée ; le formulaire court se réduit aux contacts et aux surcharges de lots.
  avenantState;
  showAvenantModal = false;
  avenantModalPtfId;
  _arrivalHandled = false;
  _scrollPending = false;

  isLoading = true;
  isGenerating = false;
  isPreviewing = false;
  errorMessage;
  // Session 110 : échec du chargement de l'historique, distinct des erreurs du formulaire.
  documentsLoadError;
  showForm = false;
  // Session 140 — historique des PTF : tableau visible/masqué pendant la génération.
  isHistoryOpen = false;
  documents = [];
  // Session 139 — historique des PTF. Aucune règle de rang ni de libellé ici : tout vient d'Apex
  // (AR_PTFHistoryService), le LWC ne fait qu'afficher et relayer les actions.
  // Lignes dont la case est en cours d'enregistrement (la case est désactivée le temps de l'appel).
  togglingIds = [];
  // Popover de modification ancré à une cellule du tableau (une seule ouverte à la fois).
  editingDocId;
  editType = "";
  editDetail = "";
  editValid = false;
  editError;
  isSavingModification = false;
  _focusPickerPending = false;
  // Fenêtre « quelle modification ? » à la génération (rang ≥ 2).
  isCheckingRank = false;
  showModificationDialog = false;
  dialogRank;
  dialogType = "";
  dialogDetail = "";
  dialogValid = false;
  form = { ...EMPTY_FORM };
  resolvedTemplateCode;
  templateTexts = {};
  // Avertissements non bloquants servis avec les valeurs par défaut (AR_PTFData.warnings, session
  // 142b) — conservés ici car applyDefaults ne garde que `form` ; jamais lus depuis `form`.
  generationWarnings = [];
  // Session 279 : documents des versions précédentes de la chaîne (lecture seule), et erreur de chargement.
  previousVersionGroups = [];
  previousVersionsError;
  // Session 279 : adresse du compte client (formulaires PTF et avenant), pour signaler une saisie.
  ptfAccountAddress = "";
  avenantAccountAddress = "";
  // Provenance de la résolution automatique ('Manuel' | 'Compte' | 'Entité' | 'Générique') :
  // l'utilisateur doit comprendre CE QU'IL SURCHARGE avant de le surcharger.
  resolvedTemplateSource;
  // Codes valides servis par le serveur (AR_PTFDataService.TEMPLATE_LABELS) — jamais une liste en
  // dur ici : c'est la même liste qui contrôle la résolution et le rendu, une copie divergerait.
  templateOptions = [];
  // Préparation de l'entité de la matrice, par gabarit (session 47) : { [templateCode]: "champs
  // manquants" } — vide pour un gabarit prêt. Chargé une fois (getEntityReadinessByTemplate
  // interroge les 4 gabarits en un seul appel), relu localement à chaque changement de gabarit
  // sans nouvel aller-retour serveur. Permet de désactiver "Confirmer et générer" AVANT que
  // l'utilisateur ne heurte le blocage serveur (cf. prompts/session-47-blocages-en-amont.md §2).
  entityReadinessByTemplate = {};
  // Entité de la matrice et gabarit qui lui est propre ({ entityName, templateCode, templateLabel }),
  // vide si la matrice n'a pas d'entité : sert à signaler un gabarit choisi qui n'est pas le sien.
  entityTemplateInfo = {};
  // Lots de l'échéancier + surcharges de montant saisies (C44). `lotOverrides` est indexé par rang
  // de lot ; un lot absent reste calculé.
  lots = [];
  lotOverrides = {};
  // Données de marge figées au snapshot, lues pour chiffrer l'impact d'une surcharge de lot.
  coutTotalJour;
  rfaPercent;
  plancherPercent;
  tjmOriginal;
  currencyCode = "EUR";
  // Distinction visible "prévisualisé" vs "généré" (session 30) : un aperçu ouvert n'a produit
  // aucune trace serveur — ce label est purement informatif côté client, jamais lu depuis une
  // donnée persistée, et il est réinitialisé à chaque changement de champ ou fermeture du
  // formulaire pour ne jamais laisser croire qu'un aperçu obsolète correspond encore à la saisie
  // courante.
  lastPreviewedAt;

  // Session 148 — brouillon du formulaire PTF / avenant. `formDraft` = { version, ptf?, avenant? }
  // servi par getGenerationDefaults (AR_Price_Matrix__c.AR_PTF_Form_Draft__c) ; les valeurs non vides
  // sont appliquées PAR-DESSUS les défauts, jamais fusionnées côté serveur. Le snapshot du document
  // généré reste la seule source de vérité du PDF : un brouillon n'est qu'un point de départ de saisie.
  formDraft;
  // TJM par périodes (docs/254d) : périodes servies (jours, TJM, date estimée), bornes de la mission.
  tjmPeriodInfo = [];
  missionStart = null;
  missionEnd = null;
  tjmPeriodsShowErrors = false;
  // Brouillon illisible/entrée écartée côté serveur, ou JSON non analysable ici : affiché dans le bandeau.
  formDraftWarning;
  isSavingDraft = false;
  isSavingAvenantDraft = false;
  // Confirmation inline de « Revenir aux valeurs par défaut » (pas de confirm() navigateur).
  isConfirmingDraftReset = false;
  isConfirmingAvenantDraftReset = false;
  isClearingDraft = false;
  _pendingAvenantLotOverrides;

  // Session 37 — création d'un avenant depuis une PTF existante (le SEUL parcours d'entrée, cf.
  // prompt de session : c'est ce qui garantit que la référence/date citées sont justes). Formulaire
  // court, séparé du formulaire de génération PTF ci-dessus : PTF d'origine pré-remplie et non
  // modifiable, date de prolongation, case « le prix change » et, si cochée, la date d'effet + le
  // tableau de lots (réutilise `this.lots`, déjà chargé pour la PTF courante — même matrice, même
  // échéancier de référence que ce que le serveur reconstruira pour l'avenant).
  avenantForOriginId;
  avenantForOriginReference;
  isCreatingAvenant = false;
  avenantForm = {
    prolongationJusquAu: "",
    revisionPrix: false,
    revisionPrixADateDu: "",
    nouveauTjm: null
  };
  avenantLotOverrides = {};
  // Session 145 : message du serveur (ou d'échec de chargement) sur les contacts d'origine, et champs
  // de contact déjà saisis à la main (non écrasés par la réponse tardive des défauts).
  avenantDefaultsWarning;
  avenantTouched = new Set();
  // Valideurs proposables (RA/DA/DD/Directeur du propriétaire de la matrice), lus par le serveur.
  valideurOptions = [];
  // Session 126b : lots révisés de l'avenant (date d'effet, prolongation, nouveau TJM)
  // rechargés avec debounce 300 ms dès que l'un des trois change.
  avenantLots = [];
  avenantLotsError;
  _avenantLotsRefreshTimer;

  connectedCallback() {
    this.load();
  }

  /** Relit entité, préparation et gabarit attendu après un changement d'entité de la matrice. */
  @api
  refresh() {
    return this.load();
  }

  /**
   * Session 110 : les quatre appels sont indépendants — un échec de l'un ne doit jamais masquer le
   * résultat des autres. Avec l'ancien Promise.all, une exception du pré-remplissage (valideur
   * absent sur une matrice validée sans dérogation) vidait aussi l'historique des PTF déjà
   * générées, réapparu seulement après une nouvelle génération (constaté le 24/09/2026).
   * Classement des échecs (règle session 34) : tous AFFICHÉS — l'historique garde son propre
   * message (documentsLoadError), les trois autres, qui ne servent qu'au formulaire, alimentent
   * errorMessage. Aucun n'est remplacé par un état par défaut silencieux.
   */
  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    this.documentsLoadError = undefined;
    // Session 279 : indépendant des autres appels, jamais bloquant pour le panneau.
    this.loadPreviousVersions();
    const [
      defaultsRes,
      docsRes,
      templatesRes,
      readinessRes,
      entityInfoRes,
      avenantStateRes,
      legacyFormRes,
      valideurOptionsRes
    ] = await Promise.allSettled([
      getGenerationDefaults({ matrixId: this.recordId }),
      listPTFDocuments({ matrixId: this.recordId }),
      getTemplateOptions(),
      getEntityReadinessByTemplate({ matrixId: this.recordId }),
      getEntityTemplateInfo({ matrixId: this.recordId }),
      getAvenantStateApex({ matrixId: this.recordId }),
      isLegacyAvenantFormEnabledApex(),
      listValideurOptionsApex({ matrixId: this.recordId })
    ]);

    // Session 180d. État avenant : AFFICHÉ s'il échoue (sans lui le panneau proposerait « Générer la
    // PTF » sur une matrice avenant). Réglage de l'ancien formulaire : JOURNALISÉ — repli sur le
    // parcours piloté par la matrice (le réglage ne fait que ré-ouvrir l'ancien formulaire).
    this.avenantState = undefined;
    const avenantStateErrors = [];
    if (avenantStateRes.status === "fulfilled") {
      this.avenantState = avenantStateRes.value || undefined;
    } else {
      avenantStateErrors.push(
        formatLabel(
          I18N.AR_PTF_AvenantStateUnavailable,
          this.reduceError(avenantStateRes.reason)
        )
      );
    }
    if (legacyFormRes.status === "fulfilled") {
      this.legacyAvenantFormSetting = legacyFormRes.value === true;
    } else {
      this.legacyAvenantFormSetting = false;
      // eslint-disable-next-line no-console
      console.error(
        "arPtfPanel : réglage de l'ancien formulaire d'avenant illisible.",
        legacyFormRes.reason
      );
    }

    if (docsRes.status === "fulfilled") {
      this.documents = docsRes.value || [];
    } else {
      this.documents = [];
      this.documentsLoadError = formatLabel(
        I18N.AR_PTF_HistoryUnavailable,
        this.reduceError(docsRes.reason)
      );
    }

    const formErrors = [];
    // Afficher : sans options, le sélecteur de valideur serait vide sans explication.
    if (valideurOptionsRes.status === "fulfilled") {
      this.valideurOptions = (valideurOptionsRes.value || []).map((o) => ({
        value: o.id,
        label: o.label,
        name: o.name,
        title: o.title || "",
        isDefault: o.isDefault === true
      }));
    } else {
      this.valideurOptions = [];
      formErrors.push(this.reduceError(valideurOptionsRes.reason));
    }
    if (defaultsRes.status === "fulfilled") {
      this.applyDefaults(defaultsRes.value);
    } else {
      formErrors.push(this.reduceError(defaultsRes.reason));
    }
    if (templatesRes.status === "fulfilled") {
      this.templateOptions = (templatesRes.value || []).map((t) => ({
        label: t.label,
        value: t.value
      }));
    } else {
      formErrors.push(this.reduceError(templatesRes.reason));
    }
    if (readinessRes.status === "fulfilled") {
      this.entityReadinessByTemplate = readinessRes.value || {};
    } else {
      formErrors.push(this.reduceError(readinessRes.reason));
    }
    // Avertissement d'aide seulement : un échec est journalisé, il n'empêche ni l'écran ni la génération.
    if (entityInfoRes.status === "fulfilled") {
      this.entityTemplateInfo = entityInfoRes.value || {};
    } else {
      this.entityTemplateInfo = {};
      // eslint-disable-next-line no-console
      console.error(
        "arPtfPanel : gabarit propre à l'entité illisible.",
        entityInfoRes.reason
      );
    }
    // Sur une matrice avenant le formulaire de génération PTF n'est pas proposé : ses défauts, qui
    // peuvent légitimement échouer sur une version avenant, n'ont pas à bloquer l'écran.
    // Lecture seule (session 282) : le formulaire n'est jamais proposé, ses défauts sont seulement journalisés.
    if (this.readOnly && formErrors.length) {
      // eslint-disable-next-line no-console
      console.error(
        "arPtfPanel : défauts du formulaire PTF (lecture seule).",
        formErrors
      );
    }
    const visibleFormErrors =
      this.isAvenantMatrix || this.readOnly ? [] : formErrors;
    const allErrors = [...visibleFormErrors, ...avenantStateErrors];
    if (allErrors.length) {
      this.errorMessage = allErrors.join(" ");
    }
    this.isLoading = false;
    this.handleArrival();
  }

  handleArrival() {
    if (this.readOnly || !this.openOnArrival || this._arrivalHandled) {
      return;
    }
    this._arrivalHandled = true;
    if (!this.documentsLoadError && this.documents.length === 0) {
      this.handleOpenForm();
    }
    this._scrollPending = true;
  }

  renderedCallback() {
    if (this._focusPickerPending) {
      const picker = this.template.querySelector(
        ".ptf-popover c-ar-ptf-modification-picker"
      );
      if (picker) {
        this._focusPickerPending = false;
        picker.focus();
      }
    }
    if (!this._scrollPending) {
      return;
    }
    const panel = this.template.querySelector(".ptf-panel");
    if (panel && typeof panel.scrollIntoView === "function") {
      this._scrollPending = false;
      panel.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  /** Option du valideur par défaut : celle du nom renvoyé par le serveur, sinon celle marquée par défaut. */
  defaultValideurOption(nom) {
    return (
      this.valideurOptions.find((o) => nom && o.name === nom) ||
      this.valideurOptions.find((o) => o.isDefault) ||
      null
    );
  }

  /** Reprend le valideur et la fonction d'un brouillon si la personne est toujours proposable. */
  applyValideurDraft(target, source) {
    const option = this.valideurOptions.find(
      (o) => o.value === source.valideurId
    );
    if (!option) {
      return false;
    }
    target.valideurId = option.value;
    target.valideurNom = option.name;
    target.valideurFonction =
      typeof source.valideurFonction === "string" &&
      source.valideurFonction.trim() !== ""
        ? source.valideurFonction
        : option.title;
    return true;
  }

  get valideurComboOptions() {
    return this.valideurOptions.map((o) => ({
      value: o.value,
      label: o.label
    }));
  }

  handleValideurChange(event) {
    const option = this.valideurOptions.find(
      (o) => o.value === event.detail.value
    );
    if (!option) {
      return;
    }
    this.form = {
      ...this.form,
      valideurId: option.value,
      valideurNom: option.name,
      valideurFonction: option.title
    };
    this.lastPreviewedAt = undefined;
  }

  handleAvenantValideurChange(event) {
    const option = this.valideurOptions.find(
      (o) => o.value === event.detail.value
    );
    if (!option) {
      return;
    }
    this.avenantForm = {
      ...this.avenantForm,
      valideurId: option.value,
      valideurNom: option.name,
      valideurFonction: option.title
    };
    this.avenantTouched.add("valideurId");
    this.avenantTouched.add("valideurFonction");
  }

  applyDefaults(defaults) {
    const d = defaults || {};
    // Régie sans régule active sur la matrice (docs/265c) : case imposée, quel que soit le brouillon.
    this.rplsrActive = d.rplsrActive === true;
    this.valideurBlocage = d.valideurBlocage || "";
    const defaultValideur = this.defaultValideurOption(d.valideurNom);
    // Session 279 : adresse du compte, référence de la pastille « Modifiée » et du lien « Rétablir ».
    this.ptfAccountAddress = d.adresseClientCompte || d.adresseClient || "";
    this.templateTexts = {
      objetParGabarit: d.objetParGabarit || {},
      evolutionPrixParGabarit: d.evolutionPrixParGabarit || {}
    };
    this.form = {
      objet: d.objet || "",
      adresseClient: d.adresseClient || "",
      contexte: d.contexte || "",
      domaineExpertise: d.domaineExpertise || "",
      livrables: d.livrables || "",
      redacteurNom: d.redacteurNom || "",
      redacteurFonction: d.redacteurFonction || "",
      valideurId: defaultValideur ? defaultValideur.value : "",
      valideurNom: d.valideurNom || "",
      valideurFonction: d.valideurFonction || "",
      freqReunions: d.freqReunions || "",
      materielClient: !!d.materielClient,
      fraisDepl: !!d.fraisDepl,
      facturationMensuelleLissee: false,
      tjmPeriodStarts: periodStartsFromServer(d.tjmPeriodes),
      conditionsReglement: d.conditionsReglement || "",
      tribunalCompetent: d.tribunalCompetent || "",
      evolutionPrix: d.evolutionPrix || "",
      interTel: d.interTel || "",
      interEmail: d.interEmail || "",
      materielItems: (d.materielItems || []).join(", "),
      // Le sélecteur est pré-positionné sur le gabarit RÉSOLU, pas sur « vide » : l'utilisateur
      // voit ce qui s'appliquera, et le changer est une action délibérée.
      templateCode: d.templateCode || "ABYLSEN_AT_V11",
      // ABMI_DQ012 (session 39) : les signataires sont pré-remplis par le serveur (rédacteur/
      // valideur, cf. AR_PTFDataService.applyAbmiFields) — repris tels quels ; les huit sections en
      // saisie libre pure et le paragraphe de proposition financière restent vides par défaut, sans
      // aucun texte hérité du .docx source.
      abmiNosReferences: d.abmiNosReferences || "",
      abmiAttentionDe: d.abmiAttentionDe || "",
      abmiSignataire1Nom: d.abmiSignataire1Nom || "",
      abmiSignataire1Fonction: d.abmiSignataire1Fonction || "",
      abmiSignataire1Tel: d.abmiSignataire1Tel || "",
      abmiSignataire1Mobile: d.abmiSignataire1Mobile || "",
      abmiSignataire1Email: d.abmiSignataire1Email || "",
      abmiSignataire2Nom: d.abmiSignataire2Nom || "",
      abmiSignataire2Fonction: d.abmiSignataire2Fonction || "",
      abmiSignataire2Tel: d.abmiSignataire2Tel || "",
      abmiSignataire2Email: d.abmiSignataire2Email || "",
      abmiDescriptionTravaux: d.abmiDescriptionTravaux || "",
      abmiDonneesEntree: d.abmiDonneesEntree || "",
      abmiDescriptionSolution: d.abmiDescriptionSolution || "",
      abmiAvantages: d.abmiAvantages || "",
      abmiRessources: d.abmiRessources || "",
      abmiOrganisationProjet: d.abmiOrganisationProjet || "",
      abmiHabilitations: d.abmiHabilitations || "",
      abmiAnalyseRisques: d.abmiAnalyseRisques || "",
      abmiPropositionFinanciereTexte: d.abmiPropositionFinanciereTexte || ""
    };
    // Gabarit résolu automatiquement (manuel > compte > entité > générique) avant toute surcharge,
    // cf. AR_PTFDataService.resolveTemplate.
    this.resolvedTemplateCode = d.templateCode || "GENERIQUE";
    this.generationWarnings = Array.isArray(d.warnings) ? d.warnings : [];
    this.resolvedTemplateSource = d.templateCodeSource || "Générique";
    this.lots = d.lots || [];
    this.lotOverrides = {};
    // Données de marge figées : servent à chiffrer l'impact d'une surcharge de lot sans relire la
    // matrice. Jamais imprimées sur le document.
    this.coutTotalJour = d.coutTotalJour;
    this.rfaPercent = d.rfaPercent;
    // Plancher figé de la matrice (grand compte compris), écrit à chaque sauvegarde
    // (AR_PricingMatrixService). Jamais de valeur en dur (session 123b) : plancher inconnu → pas d'alerte.
    this.plancherPercent = d.plancherPercent;
    this.tjmOriginal = d.tjm;
    this.currencyCode = d.currencyCode || "EUR";
    // Périodes de TJM (docs/254d) : jours/TJM pour le libellé des lignes, bornes pour la validation.
    this.tjmPeriodInfo = Array.isArray(d.tjmPeriodes) ? d.tjmPeriodes : [];
    this.missionStart = d.dateDebut || null;
    this.missionEnd = d.dateFin || null;
    this.tjmPeriodsShowErrors = false;
    this.isConfirmingDraftReset = false;
    this.applyServedDraft(d);
  }

  /**
   * Session 148 : lit le brouillon servi avec les défauts et l'applique par-dessus le formulaire PTF
   * — seulement s'il a été enregistré pour le gabarit actuellement sélectionné. Un brouillon d'un
   * autre gabarit n'est JAMAIS appliqué en silence : le bandeau le signale et propose de l'appliquer.
   */
  applyServedDraft(d) {
    this.formDraftWarning = d.formDraftWarning || undefined;
    this.formDraft = undefined;
    if (!d.formDraft) {
      return;
    }
    try {
      this.formDraft = JSON.parse(d.formDraft);
    } catch (error) {
      // Afficher (doctrine session 34) : le serveur renvoie un JSON qu'il a lui-même validé, donc ceci
      // ne devrait pas arriver — mais ce serait un brouillon perdu, pas un état « sans brouillon ».
      console.error("Brouillon PTF illisible côté client :", error);
      const detail = this.reduceError(error);
      this.formDraftWarning = formatLabel(I18N.AR_PTF_DraftUnreadable, detail);
      return;
    }
    const entry = this.formDraft && this.formDraft[DRAFT_MODE_PTF];
    if (entry && !this.isPtfDraftTemplateMismatch(entry)) {
      this.applyPtfDraftInput(entry.input);
      // Le brouillon porte la facturation lissée : l'échéancier servi avec les défauts est au réel.
      if (this.isMensualisationChecked || this.hasTjmPeriods) {
        this.refreshPtfLots();
      }
    }
  }

  templateTextDefault(mapName, templateCode) {
    const texts = (this.templateTexts && this.templateTexts[mapName]) || {};
    return texts[templateCode] || texts[GENERIC_TEXT_KEY];
  }

  /** Vrai si la valeur est un texte par défaut (d'un gabarit ou l'ancien défaut générique). */
  isTemplateTextDefault(field, value) {
    const trimmed = (value || "").trim();
    if (field === "objet" && trimmed.startsWith(LEGACY_OBJET_PREFIX)) {
      return true;
    }
    const entry = TEMPLATE_TEXT_FIELDS.find(([name]) => name === field);
    if (!entry) {
      return false;
    }
    const texts = (this.templateTexts && this.templateTexts[entry[1]]) || {};
    return Object.values(texts).some((text) => (text || "").trim() === trimmed);
  }

  isPtfDraftTemplateMismatch(entry) {
    return (
      !!entry.templateCode && entry.templateCode !== this.form.templateCode
    );
  }

  /** Valeurs non vides du brouillon par-dessus le formulaire ; booléens toujours repris. */
  applyPtfDraftInput(input) {
    const source = input || {};
    const next = { ...this.form };
    Object.keys(EMPTY_FORM).forEach((key) => {
      if (key === "templateCode" || VALIDEUR_FIELDS.includes(key)) {
        return;
      }
      const value = source[key];
      if (typeof EMPTY_FORM[key] === "boolean") {
        if (typeof value === "boolean") {
          next[key] = value;
        }
      } else if (key === "tjmPeriodStarts") {
        // Dates saisies à la main : reprises par rang, jamais écrasées par une estimation. Un rang
        // absent ou vide du brouillon garde la date estimée du serveur.
        if (Array.isArray(value)) {
          next.tjmPeriodStarts = (next.tjmPeriodStarts || []).map(
            (estimated, i) => {
              const saved = value[i];
              return typeof saved === "string" && saved.trim() !== ""
                ? saved
                : estimated;
            }
          );
        }
      } else if (typeof value === "string" && value.trim() !== "") {
        // Une valeur égale à un texte par défaut n'est pas une saisie : le pré-remplissage du gabarit reste.
        if (!this.isTemplateTextDefault(key, value)) {
          next[key] = value;
        }
      }
    });
    this.applyValideurDraft(next, source);
    this.form = next;
    const overrides = lotOverridesFromDraft(
      source.lotOverrides,
      this.lots.length
    );
    if (Object.keys(overrides).length) {
      this.lotOverrides = { ...this.lotOverrides, ...overrides };
    }
  }

  handleOpenForm() {
    this.showForm = true;
    this.isHistoryOpen = false;
    this.lastPreviewedAt = undefined;
  }

  handleCancelForm() {
    this.showForm = false;
    this.isHistoryOpen = false;
    this.lastPreviewedAt = undefined;
  }

  // ------------------------------------------------------------------------------------------
  // Session 148 — brouillon du formulaire PTF
  // ------------------------------------------------------------------------------------------

  get ptfDraftEntry() {
    return (this.formDraft && this.formDraft[DRAFT_MODE_PTF]) || null;
  }

  get showDraftBanner() {
    return !!this.ptfDraftEntry || !!this.formDraftWarning;
  }

  get hasPtfDraft() {
    return !!this.ptfDraftEntry;
  }

  get ptfDraftStamp() {
    return this.ptfDraftEntry ? formatDraftStamp(this.ptfDraftEntry) : "";
  }

  get isPtfDraftOtherTemplate() {
    const entry = this.ptfDraftEntry;
    return !!entry && this.isPtfDraftTemplateMismatch(entry);
  }

  templateLabelFor(code) {
    const option = (this.templateOptions || []).find((o) => o.value === code);
    return option ? option.label : code;
  }

  get ptfDraftOtherTemplateText() {
    const entry = this.ptfDraftEntry;
    if (!entry || !this.isPtfDraftOtherTemplate) {
      return "";
    }
    return formatLabel(
      I18N.AR_PTF_DraftOtherTemplate,
      this.templateLabelFor(entry.templateCode),
      this.templateLabelFor(this.form.templateCode)
    );
  }

  get ptfDraftApplyLabel() {
    const entry = this.ptfDraftEntry;
    return entry
      ? formatLabel(
          I18N.AR_PTF_ApplyDraftTemplate,
          this.templateLabelFor(entry.templateCode)
        )
      : "";
  }

  get isSaveDraftDisabled() {
    return (
      this.isSavingDraft ||
      this.isGenerating ||
      this.isCheckingRank ||
      this.isClearingDraft
    );
  }

  /** Enregistre la saisie courante (même payload que l'aperçu et la génération). Jamais automatique. */
  async handleSaveDraft() {
    // Dates relues avant l'envoi ; un brouillon peut rester incomplet, donc aucune validation bloquante.
    this.syncTjmPeriodDates();
    this.isSavingDraft = true;
    try {
      const raw = await savePtfFormDraftApex({
        matrixId: this.recordId,
        mode: DRAFT_MODE_PTF,
        inputJson: this.buildPayload()
      });
      this.rememberSavedDraft(DRAFT_MODE_PTF, raw);
      this.showToast(I18N.AR_PTF_DraftSaved, "", "success");
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSavingDraft = false;
    }
  }

  /** Garde localement l'entrée que le serveur vient d'écrire (date et auteur réels, pas un relevé client). */
  rememberSavedDraft(mode, rawEntry) {
    const entry = JSON.parse(rawEntry);
    this.formDraft = { version: 1, ...(this.formDraft || {}), [mode]: entry };
    this.formDraftWarning = undefined;
  }

  handleApplyDraftTemplate() {
    const entry = this.ptfDraftEntry;
    if (!entry) {
      return;
    }
    this.form = { ...this.form, templateCode: entry.templateCode };
    this.applyPtfDraftInput(entry.input);
    this.lastPreviewedAt = undefined;
  }

  handleAskDraftReset() {
    this.isConfirmingDraftReset = true;
  }

  handleCancelDraftReset() {
    this.isConfirmingDraftReset = false;
  }

  /** Efface le brouillon PTF côté serveur puis recharge les défauts : on revient aux valeurs initiales. */
  async handleConfirmDraftReset() {
    this.isClearingDraft = true;
    try {
      await clearPtfFormDraftApex({
        matrixId: this.recordId,
        mode: DRAFT_MODE_PTF
      });
      const defaults = await getGenerationDefaults({ matrixId: this.recordId });
      this.applyDefaults(defaults);
      this.lastPreviewedAt = undefined;
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isClearingDraft = false;
      this.isConfirmingDraftReset = false;
    }
  }

  handleToggleHistory() {
    this.isHistoryOpen = !this.isHistoryOpen;
  }

  get chevronIcon() {
    return this.isHistoryOpen ? "▾" : "▴";
  }

  handleFieldChange(event) {
    const { field } = event.target.dataset;
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;
    this.form = { ...this.form, [field]: value };
    // Toute modification de la saisie invalide l'aperçu déjà ouvert : il ne correspondrait plus à
    // ce que "Confirmer et générer" produirait maintenant.
    this.lastPreviewedAt = undefined;
  }

  // ------------------------------------------------------------------------------------------
  // TJM par périodes (docs/254d) — une date de début par période à partir de la 2ᵉ
  // ------------------------------------------------------------------------------------------

  get hasTjmPeriods() {
    return (
      Array.isArray(this.form.tjmPeriodStarts) &&
      this.form.tjmPeriodStarts.length > 0
    );
  }

  /** Erreur de chaque date (chaîne vide = valide) : obligatoire, strictement croissante, dans la mission. */
  get tjmPeriodErrors() {
    const starts = this.form.tjmPeriodStarts || [];
    return starts.map((value, i) => {
      const index = i + 2;
      if (!value) {
        return formatLabel(I18N.AR_PTF_TjmPeriodDateRequired, index);
      }
      const previous = i === 0 ? this.missionStart : starts[i - 1];
      if (previous && value <= previous) {
        return formatLabel(I18N.AR_PTF_TjmPeriodDateOrder, index);
      }
      if (this.missionEnd && value > this.missionEnd) {
        return formatLabel(I18N.AR_PTF_TjmPeriodDateOutside, index);
      }
      return "";
    });
  }

  get tjmPeriodDateRows() {
    const errors = this.tjmPeriodErrors;
    return (this.form.tjmPeriodStarts || []).map((value, i) => {
      const index = i + 2;
      const info = this.tjmPeriodInfo[i + 1] || {};
      return {
        key: index,
        index,
        inputId: `tjm-period-date-${index}`,
        label: formatLabel(I18N.AR_PTF_TjmPeriodDateLabel, index),
        summary: formatLabel(
          I18N.AR_PTF_TjmPeriodRow,
          index,
          info.jours,
          formatMoney(info.tjm, this.currencyCode)
        ),
        value,
        error: errors[i],
        showError: !!errors[i] && (this.tjmPeriodsShowErrors || !!value),
        inputClass: errors[i] ? "slds-input slds-has-error" : "slds-input"
      };
    });
  }

  get hasTjmPeriodErrors() {
    return this.tjmPeriodErrors.some((e) => e);
  }

  /**
   * Relit les champs date dans le DOM avant tout envoi : une date tapée puis un clic direct sur
   * « Prévisualiser » / « Générer » / « Enregistrer le brouillon » n'a pas toujours émis son événement
   * (même garde que la 254c). Retourne true si toutes les dates sont valides ; sinon affiche les messages.
   */
  syncTjmPeriodDates() {
    if (!this.hasTjmPeriods) {
      return true;
    }
    const starts = [...this.form.tjmPeriodStarts];
    let changed = false;
    this.template.querySelectorAll("[data-tjm-period-date]").forEach((el) => {
      const i = Number(el.dataset.tjmPeriodDate) - 2;
      if (i >= 0 && i < starts.length && (el.value || "") !== starts[i]) {
        starts[i] = el.value || "";
        changed = true;
      }
    });
    if (changed) {
      this.form = { ...this.form, tjmPeriodStarts: starts };
    }
    if (this.hasTjmPeriodErrors) {
      this.tjmPeriodsShowErrors = true;
      return false;
    }
    return true;
  }

  handleTjmPeriodDateChange(event) {
    const i = Number(event.target.dataset.tjmPeriodDate) - 2;
    const starts = [...this.form.tjmPeriodStarts];
    starts[i] = event.target.value || "";
    this.form = { ...this.form, tjmPeriodStarts: starts };
    this.lastPreviewedAt = undefined;
    if (!this.hasTjmPeriodErrors) {
      this.refreshPtfLots();
    }
  }

  /** Case « Régie sans régule » : l'échéancier est relu côté serveur. Verrouillée si la matrice est en mode actif. */
  async handleMensualisationChange(event) {
    if (this.rplsrActive) {
      return;
    }
    this.form = {
      ...this.form,
      facturationMensuelleLissee: event.target.checked
    };
    this.lastPreviewedAt = undefined;
    await this.refreshPtfLots();
  }

  /** Coché : saisie du formulaire, ou imposé par la régie sans régule de la matrice (le serveur l'impose aussi). */
  get isMensualisationChecked() {
    return (
      this.rplsrActive === true || this.form.facturationMensuelleLissee === true
    );
  }

  get mensualisationHelp() {
    return this.rplsrActive
      ? I18N.AR_PTF_RplsrPtfHelp
      : I18N.AR_PTF_MonthlyLissedHelp;
  }

  /** Relit les lots selon le mode lissé ; les surcharges saisies restent par rang (même nombre de mois). */
  async refreshPtfLots() {
    try {
      // La clé tjmPeriodStarts n'est envoyée que pour une matrice à périodes : appel inchangé sinon.
      const params = {
        matrixId: this.recordId,
        facturationMensuelleLissee: this.isMensualisationChecked
      };
      if (this.hasTjmPeriods) {
        params.tjmPeriodStarts = [...this.form.tjmPeriodStarts];
      }
      this.lots = await previewPtfLotsApex(params);
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    }
  }

  /**
   * Prévisualisation par clé serveur (session 124) : crée un enregistrement AR_PTF_Preview__c
   * contenant les données sérialisées, puis ouvre la page Visualforce avec previewId en paramètre.
   * Même calcul de données que buildPreviewData (peek du numéro de version, ne le consomme pas),
   * mais voyage par le serveur plutôt que dans l'URL — aucune limite de taille de saisie.
   */
  async handlePreview() {
    if (!this.syncTjmPeriodDates()) {
      return;
    }
    this.isPreviewing = true;
    try {
      const result = await createPreviewApex({
        inputJson: this.buildPayload()
      });
      const url = `${result.pageUrl}?previewId=${encodeURIComponent(result.previewId)}`;
      window.open(url, "_blank");
      this.lastPreviewedAt = new Date();
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isPreviewing = false;
    }
  }

  /**
   * Sélecteur de gabarit (session 35) : liste de valeurs servie par le serveur, en remplacement de
   * la saisie libre d'un code texte. Une faute de frappe donnait un code inconnu, qui retombait
   * silencieusement sur le générique — acceptable pour un développeur, pas pour un commercial qui
   * envoie un document contractuel.
   *
   * Comme tout changement de saisie, il invalide l'aperçu déjà ouvert : prévisualiser avec un
   * gabarit puis générer avec un autre reste impossible sans une action explicite (session 30 §2).
   */
  handleTemplateChange(event) {
    const previousCode = this.form.templateCode;
    const nextCode = event.detail.value;
    const next = { ...this.form, templateCode: nextCode };
    // Un champ que l'utilisateur n'a pas touché suit le gabarit ; une saisie est conservée.
    TEMPLATE_TEXT_FIELDS.forEach(([field, mapName]) => {
      const current = (next[field] || "").trim();
      const previousDefault = this.templateTextDefault(mapName, previousCode);
      if (
        current === "" ||
        current === (previousDefault || "").trim() ||
        this.isTemplateTextDefault(field, current)
      ) {
        next[field] = this.templateTextDefault(mapName, nextCode) || "";
      }
    });
    this.form = next;
    this.lastPreviewedAt = undefined;
  }

  get templateSourceLabel() {
    const source = this.resolvedTemplateSource || "Générique";
    const origins = {
      Manuel: I18N.AR_PTF_TemplateSourceManual,
      Compte: I18N.AR_PTF_TemplateSourceAccount,
      Entité: I18N.AR_PTF_TemplateSourceEntity,
      Générique: I18N.AR_PTF_TemplateSourceGeneric
    };
    const origin =
      origins[source] || formatLabel(I18N.AR_PTF_TemplateSourceOther, source);
    if (this.form.templateCode !== this.resolvedTemplateCode) {
      return formatLabel(
        I18N.AR_PTF_TemplateOriginOverridden,
        origin,
        this.templateLabelFor(this.resolvedTemplateCode)
      );
    }
    return formatLabel(I18N.AR_PTF_TemplateOrigin, origin);
  }

  /**
   * Gabarit choisi différent de celui de l'entité (et non du gabarit attendu compte > entité) :
   * un compte qui impose un autre gabarit déclenche aussi l'avertissement, c'est le cas où il faut
   * vérifier l'entité de la matrice. Jamais bloquant.
   */
  get entityTemplateWarning() {
    const info = this.entityTemplateInfo || {};
    if (
      !info.templateCode ||
      !this.form.templateCode ||
      this.form.templateCode === info.templateCode
    ) {
      return null;
    }
    return formatLabel(
      I18N.AR_PTF_TemplateNotEntityTemplate,
      info.entityName,
      info.templateLabel
    );
  }

  get isTemplateOverridden() {
    return this.form.templateCode !== this.resolvedTemplateCode;
  }

  // Gabarit RÉSOLU ou SURCHARGÉ (session 39, prompts/session-39-...md §3) : `form.templateCode`
  // porte déjà l'un ou l'autre selon qu'une surcharge a eu lieu (cf. applyDefaults/
  // handleTemplateChange) — un seul champ à lire, jamais besoin de distinguer les deux cas ici.
  get isAbmiTemplate() {
    return this.form.templateCode === "ABMI_DQ012";
  }

  get contexteLabel() {
    const templateCode =
      this.form.templateCode || this.resolvedTemplateCode || "GENERIQUE";
    switch (templateCode) {
      case "ABYLSEN_AT_V11":
      case "AVENANT_AT_V11":
        return I18N.AR_PTF_ClientNeedsSection;
      case "ABMI_DQ012":
        return I18N.AR_PTF_ProjectDefinitionSection;
      case "GENERIQUE":
      default:
        return I18N.AR_PTF_ProjectContextSection;
    }
  }

  /** Session 279 : l'avertissement « adresse client manquante » disparaît dès qu'une adresse est saisie. */
  get displayedGenerationWarnings() {
    if (normalizeAddress(this.form.adresseClient) === "") {
      return this.generationWarnings;
    }
    return this.generationWarnings.filter(
      (w) => w !== LBL_AR_Msg_PTF_ClientAddressMissing
    );
  }

  get hasGenerationWarnings() {
    return this.displayedGenerationWarnings.length > 0;
  }

  get isPtfClientAddressModified() {
    const typed = normalizeAddress(this.form.adresseClient);
    return typed !== "" && typed !== normalizeAddress(this.ptfAccountAddress);
  }

  get canRestorePtfClientAddress() {
    return (
      normalizeAddress(this.form.adresseClient) !==
      normalizeAddress(this.ptfAccountAddress)
    );
  }

  handleRestoreClientAddress() {
    this.form = { ...this.form, adresseClient: this.ptfAccountAddress };
    this.lastPreviewedAt = undefined;
  }

  get isAvenantClientAddressModified() {
    const typed = normalizeAddress(this.avenantForm.adresseClient);
    return (
      typed !== "" && typed !== normalizeAddress(this.avenantAccountAddress)
    );
  }

  get canRestoreAvenantClientAddress() {
    return (
      normalizeAddress(this.avenantForm.adresseClient) !==
      normalizeAddress(this.avenantAccountAddress)
    );
  }

  handleRestoreAvenantClientAddress() {
    this.avenantForm = {
      ...this.avenantForm,
      adresseClient: this.avenantAccountAddress
    };
    this.avenantTouched.add("adresseClient");
  }

  /**
   * Session 47 : l'entité de la matrice n'est pas prête pour le gabarit actuellement sélectionné —
   * message en registre commercial (pas de nom d'objet ni de champ), le détail technique reste
   * réservé à l'écran d'administration (arAdminPtfEntities). Utilisé pour désactiver "Confirmer et
   * générer" avant que l'utilisateur ne heurte le blocage serveur.
   */
  get isEntityNotReady() {
    return !!this.entityReadinessByTemplate[this.form.templateCode];
  }

  get entityNotReadyMessage() {
    return this.isEntityNotReady ? I18N.AR_PTF_EntityNotConfigured : null;
  }

  /** C1 (session 47) : le valideur est un champ obligatoire du formulaire — plus une condition
   * vérifiée seulement à la génération, cf. prompts/session-47-blocages-en-amont.md §1. */
  get isValideurMissing() {
    return !this.form.valideurNom || !this.form.valideurNom.trim();
  }

  get isGenerateDisabled() {
    return (
      this.isGenerating ||
      this.isCheckingRank ||
      this.isEntityNotReady ||
      this.isValideurMissing
    );
  }

  /**
   * C44 — surcharge du montant d'un lot. Optionnelle et par lot : un lot non surchargé reste
   * calculé et le reste, même si les données de la matrice changent ensuite. Un lot surchargé est
   * marqué visiblement et son impact sur la marge est chiffré à côté du champ.
   *
   * ⚠️ Aucune dérogation n'est câblée ici, même sur une surcharge à la baisse qui dégrade la marge
   * sous le plancher : c'est un arbitrage Matthieu (question 1 de docs/34-plan-avant-prochaine-
   * reunion.md), pas une décision d'implémentation. On calcule, on affiche, on ne bloque pas.
   */
  handleLotMontantChange(event) {
    const index = Number(event.target.dataset.index);
    const raw = event.target.value;
    const overrides = { ...this.lotOverrides };
    if (raw === "" || raw === null || raw === undefined) {
      delete overrides[index];
    } else {
      overrides[index] = Number(raw);
    }
    this.lotOverrides = overrides;
    this.lastPreviewedAt = undefined;
  }

  get lotRows() {
    return this.lots.map((lot, index) => {
      const overridden = Object.prototype.hasOwnProperty.call(
        this.lotOverrides,
        index
      );
      const montant = overridden
        ? this.lotOverrides[index]
        : lot.montantCalcule;
      return {
        key: `lot-${index}`,
        index,
        libelle: lot.libelle,
        mois: lot.mois,
        joursLabel: `${FR_DAYS_FORMATTER.format(lot.jours)} j`,
        echeanceLabel: lot.echeance
          ? new Date(lot.echeance).toLocaleDateString("fr-FR")
          : "—",
        montantCalculeLabel: formatMoney(lot.montantCalcule, this.currencyCode),
        montantValue: overridden ? this.lotOverrides[index] : undefined,
        montantPlaceholder: String(lot.montantCalcule),
        isOverridden: overridden,
        rowClass: overridden
          ? "ptf-lot-row ptf-lot-row-overridden"
          : "ptf-lot-row",
        marginImpactLabel: overridden
          ? this.buildMarginImpactLabel(lot, montant)
          : null
      };
    });
  }

  /**
   * Impact sur la marge d'un montant de lot surchargé : le TJM implicite du lot (montant / jours)
   * donne une MC2 % différente de celle de la matrice. On l'affiche, on ne bloque pas.
   * Sans coût journalier figé au snapshot, on ne peut pas calculer honnêtement une MC2 : on le dit,
   * plutôt que d'afficher un pourcentage inventé.
   */
  buildMarginImpactLabel(lot, montant) {
    const ecart = montant - lot.montantCalcule;
    const ecartLabel = `${ecart >= 0 ? "+" : ""}${formatMoney(ecart, this.currencyCode)}`;
    if (
      !lot.jours ||
      this.coutTotalJour === null ||
      this.coutTotalJour === undefined
    ) {
      return formatLabel(I18N.AR_PTF_LotGapNoMargin, ecartLabel);
    }
    const tjmImplicite = montant / lot.jours;
    const { mc2PercentFraction } = calcMC2(
      tjmImplicite,
      this.coutTotalJour,
      this.rfaPercent
    );
    const mc2Label = formatPercent(mc2PercentFraction * 100);
    return formatLabel(
      I18N.AR_PTF_LotGapWithMargin,
      ecartLabel,
      formatMoney(tjmImplicite, this.currencyCode),
      mc2Label
    );
  }

  /** Champs affichés pour le gabarit sélectionné (cf. TEMPLATE_FIELDS). */
  get fieldVisible() {
    const known = TEMPLATE_FIELDS[this.form.templateCode];
    const visible = {};
    ALL_FIELD_KEYS.forEach((key) => {
      visible[key] = !known || known.includes(key);
    });
    return visible;
  }

  get showLots() {
    return this.hasLots && this.fieldVisible.lots;
  }

  get hasLots() {
    return this.lots.length > 0;
  }

  get lotsTotalsWarning() {
    return formatLabel(
      I18N.AR_PTF_LotsTotals,
      this.lotsTotalLabel,
      this.lotsTheoreticalTotalLabel
    );
  }

  get avenantOriginReadonlyLabel() {
    return formatLabel(
      I18N.AR_PTF_AvenantOfOriginReadonly,
      this.avenantForOriginReference
    );
  }

  get lotsTotalLabel() {
    const total = this.lots.reduce((sum, lot, index) => {
      const overridden = Object.prototype.hasOwnProperty.call(
        this.lotOverrides,
        index
      );
      return sum + (overridden ? this.lotOverrides[index] : lot.montantCalcule);
    }, 0);
    return formatMoney(total, this.currencyCode);
  }

  get lotsTheoreticalTotalLabel() {
    const total = this.lots.reduce((sum, lot) => sum + lot.montantCalcule, 0);
    return formatMoney(total, this.currencyCode);
  }

  get hasLotOverride() {
    return Object.keys(this.lotOverrides).length > 0;
  }

  /**
   * Payload commun à la prévisualisation et à la génération — une seule construction, pour qu'un
   * aperçu ne puisse jamais reposer sur des données différentes de celles qui seront imprimées.
   */
  buildPayload(extra = {}) {
    const { tjmPeriodStarts, ...formWithoutPeriods } = this.form;
    return JSON.stringify({
      matrixId: this.recordId,
      ...formWithoutPeriods,
      // Clé absente (et non vide) sans période de TJM : charge utile identique à celle d'avant.
      ...(this.hasTjmPeriods ? { tjmPeriodStarts } : {}),
      ...extra,
      lotOverrides: Object.keys(this.lotOverrides).map((index) => ({
        index: Number(index),
        montant: this.lotOverrides[index]
      }))
    });
  }

  get previewStatusLabel() {
    if (!this.lastPreviewedAt) {
      return null;
    }
    return formatLabel(
      I18N.AR_PTF_PreviewOpenedAt,
      this.lastPreviewedAt.toLocaleTimeString("fr-FR")
    );
  }

  /**
   * Clic sur « Confirmer et générer » (session 139) : Apex dit quel rang prendra la prochaine PTF.
   * Rang 1 → génération directe ; rang ≥ 2 → fenêtre « quelle modification ? » d'abord. Si le rang
   * ne peut pas être lu, on NE génère PAS (échec affiché, jamais un repli silencieux sur « rang 1 »
   * qui contournerait la question) — le serveur refuserait de toute façon sans type de modification.
   */
  async handleGenerate() {
    if (!this.syncTjmPeriodDates()) {
      return;
    }
    this.isCheckingRank = true;
    let rank;
    try {
      rank = await getNextDisplayRankApex({
        matrixId: this.recordId,
        templateCode: this.form.templateCode
      });
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
      return;
    } finally {
      this.isCheckingRank = false;
    }
    if (typeof rank !== "number") {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        I18N.AR_PTF_NextVersionUnknown,
        "error"
      );
      return;
    }
    if (rank >= 2) {
      this.dialogRank = rank;
      this.dialogType = "";
      this.dialogDetail = "";
      this.dialogValid = false;
      this.showModificationDialog = true;
      return;
    }
    await this.runGeneration();
  }

  get dialogTitle() {
    return formatLabel(I18N.AR_PTF_NewVersionDialogTitle, this.dialogRank);
  }

  get isDialogConfirmDisabled() {
    return !this.dialogValid;
  }

  handleDialogChange(event) {
    const { type, detail, valid } = event.detail;
    this.dialogType = type;
    this.dialogDetail = detail;
    this.dialogValid = valid;
  }

  handleDialogSubmit() {
    this.handleDialogConfirm();
  }

  handleDialogCancel() {
    this.showModificationDialog = false;
  }

  handleDialogKeydown(event) {
    if (event.key === "Escape") {
      this.handleDialogCancel();
    }
  }

  async handleDialogConfirm() {
    if (!this.dialogValid) {
      return;
    }
    this.showModificationDialog = false;
    await this.runGeneration({
      modificationType: this.dialogType,
      modificationDetail: this.dialogType === "Autre" ? this.dialogDetail : ""
    });
  }

  async runGeneration(extra = {}) {
    this.isGenerating = true;
    try {
      const started = await generatePTFApex({
        inputJson: this.buildPayload(extra)
      });
      this.showForm = false;
      this.isHistoryOpen = false;
      this.lastPreviewedAt = undefined;
      await this.refreshDocumentsOnly();

      await this.renderStep(started.ptfDocumentId, (finished) =>
        formatLabel(I18N.AR_PTF_PtfGenerated, finished.reference)
      );
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isGenerating = false;
    }
  }

  /**
   * Second appel de la génération (rendu du PDF), commun à la PTF et à l'avenant, et reprise d'un
   * document « En cours » abandonné (`retry`, session 153b).
   *
   * Un échec que le serveur a lui-même capturé revient en `status === "Échec"` avec son motif (le
   * document est déjà « Échec » en base). Ce qui sort en exception ici est ce que le serveur n'a
   * pas pu écrire : limite plateforme, réseau, session expirée. Classement session 34 : on AFFICHE
   * (toast d'erreur, jamais muet), et on tente de passer le document en « Échec » pour qu'il ne
   * reste pas « En cours » sans trace ; cette écriture-là est JOURNALISÉE si elle échoue aussi (le
   * toast porte déjà l'erreur d'origine). Pas d'écriture « Échec » sur une reprise : un refus de
   * garde serveur (document trop récent, déjà généré) ne doit jamais marquer un document sain.
   */
  async renderStep(ptfDocumentId, successMessage, { retry = false } = {}) {
    let finished;
    try {
      finished = await (retry ? retryRenderPTFApex : renderAndStorePTFApex)({
        ptfDocumentId
      });
    } catch (error) {
      const reason = this.reduceError(error);
      if (!retry) {
        try {
          await markRenderFailedApex({ ptfDocumentId, reason });
        } catch (markError) {
          // eslint-disable-next-line no-console
          console.error(markError);
        }
      }
      await this.refreshDocumentsOnly();
      this.showToast(
        retry ? I18N.AR_PTF_ResumeImpossible : I18N.AR_PTF_GenerationFailed,
        retry ? reason : formatLabel(I18N.AR_PTF_PdfRenderFailed, reason),
        "error"
      );
      return;
    }
    await this.refreshDocumentsOnly();

    if (finished.status === "Échec") {
      this.showToast(
        I18N.AR_PTF_GenerationFailed,
        finished.errorMessage || I18N.AR_PTF_PdfRenderUnknownError,
        "error"
      );
    } else {
      await this.showGenerationSuccessToast(finished, successMessage(finished));
      // Session 180d : document généré mais réserve à connaître (fichier non rattaché au besoin
      // Connexys faute de droits) — durable, jamais avalée.
      if (finished.warning) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: I18N.AR_PTF_GeneratedWithWarning,
            message: finished.warning,
            variant: "warning",
            mode: "sticky"
          })
        );
      }
    }
  }

  /** Bouton « Réessayer le rendu » d'un document « En cours » depuis plus de 2 minutes. */
  async handleRetryRender(event) {
    const { id } = event.currentTarget.dataset;
    if (!id || this.isGenerating) {
      return;
    }
    this.isGenerating = true;
    try {
      await this.renderStep(
        id,
        (finished) =>
          formatLabel(I18N.AR_PTF_DocumentGenerated, finished.reference),
        {
          retry: true
        }
      );
    } finally {
      this.isGenerating = false;
    }
  }

  handleRefresh() {
    this.refreshDocumentsOnly({ silent: false });
    this.loadPreviousVersions();
  }

  /**
   * Session 279 : documents des versions précédentes de la chaîne (V1 d'une V2 dupliquée), rattachés
   * à leur propre matrice. Échec AFFICHÉ (doctrine session 34) : une liste vide laisserait croire les
   * PTF perdues, précisément le constat qui a motivé ce groupe.
   */
  async loadPreviousVersions() {
    try {
      const groups = await getPreviousVersionDocumentsApex({
        matrixId: this.recordId
      });
      this.previousVersionGroups = Array.isArray(groups) ? groups : [];
      this.previousVersionsError = undefined;
    } catch (error) {
      this.previousVersionGroups = [];
      this.previousVersionsError = formatLabel(
        I18N.AR_PTF_HistoryUnavailable,
        this.reduceError(error)
      );
    }
  }

  get hasPreviousVersionGroups() {
    return this.previousVersionGroups.length > 0;
  }

  /** Groupes en lecture seule : titre « Matrice V1 — validée le … », documents téléchargeables. */
  get previousVersionGroupRows() {
    return this.previousVersionGroups.map((grp) => {
      const version = `V${grp.negotiationVersion}`;
      const title = grp.validatedAt
        ? formatLabel(
            I18N.AR_PTF_PreviousVersionGroup,
            version,
            new Date(grp.validatedAt).toLocaleDateString("fr-FR")
          )
        : formatLabel(I18N.AR_PTF_PreviousVersionGroupNoDate, version);
      return {
        matrixId: grp.matrixId,
        title,
        documents: (grp.documents || []).map((doc) => ({
          ...doc,
          kindLabel:
            doc.documentType === "Avenant" ? `AV${doc.avenantNumber}` : "PTF",
          generatedAtLabel: doc.generatedAt
            ? new Date(doc.generatedAt).toLocaleString("fr-FR")
            : "",
          hasNoFile: !doc.contentDocumentId
        }))
      };
    });
  }

  async refreshDocumentsOnly({ silent = true } = {}) {
    try {
      const docs = await listPTFDocuments({ matrixId: this.recordId });
      this.documents = docs || [];
      this.documentsLoadError = undefined;
    } catch (error) {
      if (silent) {
        // Rafraîchissement automatique en arrière-plan, après génération (classement session 34) :
        // le résultat est indifférent à l'utilisateur — la liste affichée reste celle d'avant.
        // Journalisé, jamais avalé sans trace (doctrine session 34 : journaliser, pas muet).
        // eslint-disable-next-line no-console
        console.error(error);
      } else {
        // Rafraîchissement demandé explicitement par l'utilisateur (bouton Actualiser, session 51) :
        // un échec ici produit un bouton mort, indiscernable du défaut de cache corrigé cette même
        // session — doit remonter à l'utilisateur (doctrine session 34 : afficher).
        this.showToast(
          I18N.AR_Common_ErrorTitle,
          this.reduceError(error),
          "error"
        );
      }
    }
  }

  handleDownload(event) {
    const { id } = event.currentTarget.dataset;
    if (!id) {
      return;
    }
    window.open(DOWNLOAD_BASE_URL + id, "_blank");
  }

  /**
   * Aperçu de fichier standard de la plateforme (session 52 §3), pas un téléchargement : navigue
   * vers la page nommée `filePreview`, la voie supportée par la plateforme pour afficher un
   * ContentDocument plutôt que le télécharger. N'AJOUTE pas au bouton Télécharger existant, ne le
   * remplace pas — deux gestes distincts (lire vs joindre à un e-mail).
   *
   * ⚠️ Non vérifié dans un navigateur réel dans cet environnement d'exécution (cf.
   * docs/52-acces-immediat-au-pdf.md) : l'aperçu peut s'ouvrir dans une modale de l'application
   * plutôt que dans un onglet séparé selon le contexte (app Lightning, console, communauté). Si ce
   * n'est pas ce que produit `filePreview` en réel, remplacer l'URL générée ici — ne pas dupliquer
   * cette résolution ailleurs.
   */
  buildPreviewUrl(contentDocumentId) {
    return this[NavigationMixin.GenerateUrl]({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: contentDocumentId }
    });
  }

  /**
   * Bouton "Ouvrir" d'une ligne du tableau (session 52 §2.1) : appelle GenerateUrl directement
   * depuis le clic, jamais après l'attente de plusieurs secondes de la génération — c'est ce qui
   * distingue ce geste du §2.2 (ouverture automatique après renderAndStorePTF), volontairement pas
   * implémenté cette session faute d'accès navigateur pour prouver qu'il n'est pas bloqué.
   */
  async handleOpenDocument(event) {
    const { id } = event.currentTarget.dataset;
    if (!id) {
      return;
    }
    try {
      const url = await this.buildPreviewUrl(id);
      const opened = window.open(url, "_blank");
      if (!opened) {
        this.showToast(
          I18N.AR_PTF_PopupBlockedTitle,
          I18N.AR_PTF_PopupBlockedMessage,
          "warning"
        );
      }
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    }
  }

  /**
   * Toast de succès portant un lien direct vers l'aperçu du document (session 52 §2.1) : évite à
   * l'utilisateur de repérer la bonne ligne du tableau pour cliquer Télécharger — qui télécharge,
   * n'affiche pas (§3). Le lien est rendu par lightning/platformShowToastEvent comme un <a> standard
   * (`messageData`) : l'ouvrir est un NOUVEAU clic explicite de l'utilisateur, jamais soumis au
   * bloqueur de fenêtres — à la différence d'une ouverture automatique juste après l'attente longue
   * de la génération (§2.2, non implémentée cette session). Partagé entre handleGenerate et
   * handleCreateAvenant (§4 : même traitement pour l'avenant).
   */
  async showGenerationSuccessToast(finished, baseMessage) {
    let url;
    try {
      url = finished.contentDocumentId
        ? await this.buildPreviewUrl(finished.contentDocumentId)
        : null;
    } catch (error) {
      // Le lien est un confort, pas la garantie de génération (déjà annoncée par le toast lui-même) :
      // on retombe sur le toast simple plutôt que de bloquer l'utilisateur, mais on journalise —
      // doctrine session 34, un échec de GenerateUrl ne doit jamais rester complètement muet.
      // eslint-disable-next-line no-console
      console.error(error);
      url = null;
    }
    if (url) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: I18N.AR_Common_SuccessTitle,
          message: `${baseMessage} {0}`,
          messageData: [{ url, label: I18N.AR_PTF_OpenDocument }],
          variant: "success"
        })
      );
    } else {
      this.showToast(I18N.AR_Common_SuccessTitle, baseMessage, "success");
    }
  }

  get documentRows() {
    return this.documents.map((doc) => {
      const isAvenant = doc.documentType === "Avenant";
      const isSuccess = doc.status === "Généré";
      const isPending = doc.status === "En cours";
      const isFailed = doc.status === "Échec";
      // « En cours » depuis trop longtemps (session 153b) : le second appel n'a vraisemblablement
      // jamais abouti — l'écran propose la reprise au lieu d'attendre indéfiniment. Évalué à
      // chaque rendu de la liste (ouverture, Actualiser), sans minuteur.
      const isStalePending =
        isPending &&
        !!doc.generatedAt &&
        Date.now() - new Date(doc.generatedAt).getTime() >
          RENDER_RETRY_AFTER_MS;
      // Compte dans l'historique : même critère qu'Apex (cochée, hors avenant, hors Échec/En cours).
      const countsStatus = !isAvenant && !isPending && !isFailed;
      const isIncluded = !!doc.includedInHistory;
      const isExcluded = countsStatus && !isIncluded;
      const isRanked = countsStatus && isIncluded && doc.displayRank != null;
      const isFirst = isRanked && doc.displayRank === 1;
      const isEditable = !this.readOnly && isRanked && doc.displayRank >= 2;
      const modificationText = doc.modificationLabel || "";
      const isToggling = this.togglingIds.includes(doc.ptfDocumentId);

      let toggleTitle = I18N.AR_PTF_IncludeInHistory;
      if (isAvenant) {
        toggleTitle = I18N.AR_PTF_AvenantNotInHistory;
      } else if (isPending) {
        toggleTitle = I18N.AR_PTF_PendingNotInHistory;
      } else if (isFailed) {
        toggleTitle = I18N.AR_PTF_FailedNotInHistory;
      } else if (isIncluded) {
        toggleTitle = I18N.AR_PTF_RemoveFromHistory;
      }

      let versionLabel;
      let versionTitle;
      if (isAvenant) {
        // Un avenant ne consomme pas AR_Version_Number__c de la PTF : son libellé porte AV{n}.
        versionLabel = `AV${doc.avenantNumber}`;
      } else if (isRanked) {
        versionLabel = `V${doc.displayRank}`;
      } else {
        versionLabel = "—";
        versionTitle = isExcluded
          ? I18N.AR_PTF_ExcludedFromHistory
          : I18N.AR_PTF_NoRankNotGenerated;
      }

      let modificationTitle = modificationText;
      if (isFirst) {
        modificationTitle = I18N.AR_PTF_FirstVersionNoModification;
      } else if (isEditable) {
        modificationTitle = modificationText || I18N.AR_PTF_ClickToSpecify;
      }

      return {
        ...doc,
        generatedAtLabel: doc.generatedAt
          ? new Date(doc.generatedAt).toLocaleString("fr-FR")
          : "",
        versionLabel,
        versionTitle,
        rowClass: isExcluded ? "ptf-row-excluded" : "",
        isChecked: countsStatus && isIncluded,
        isToggleDisabled: this.readOnly || !countsStatus || isToggling,
        toggleTitle,
        isFirst,
        isEditable,
        isModReadonly: !isFirst && !isEditable,
        modificationText,
        modificationTitle,
        isEditing: this.editingDocId === doc.ptfDocumentId,
        isAvenant,
        isPending,
        isStalePending,
        canRetryRender: isStalePending && !this.readOnly,
        isRetryDisabled: this.isGenerating,
        isFailed,
        isSuccess,
        // Documents créés avant l'introduction du statut (session 20b) : ni un échec, ni une
        // génération en cours, ni un succès confirmé — ne jamais les faire passer pour "Généré".
        isUnknownStatus: !isPending && !isFailed && !isSuccess,
        hasNoFile: !doc.contentDocumentId,
        // « Créer un avenant » : seulement depuis une PTF déjà générée avec succès, jamais depuis un
        // avenant (le parcours de la 180c rattache de toute façon l'avenant d'un avenant à la PTF
        // initiale, cf. docs/180 Q8).
        canCreateAvenant: !this.readOnly && !isAvenant && isSuccess,
        // Session 180d : sur la matrice d'origine, l'avenant piloté par une matrice avenant porte un
        // renvoi « Avenant AV1 → V3 » vers cette matrice.
        hasAvenantLink: isAvenant && !!doc.avenantMatrixId,
        avenantLinkLabel:
          isAvenant && doc.avenantMatrixId
            ? formatLabel(
                I18N.AR_PTF_AvenantRowLabel,
                doc.avenantNumber,
                doc.avenantMatrixLabel
              )
            : ""
      };
    });
  }

  // ------------------------------------------------------------------------------------------
  // Session 139 — historique des PTF : case « Dans l'historique » et libellé de modification.
  // ------------------------------------------------------------------------------------------

  /**
   * Mise à jour optimiste : la case bascule tout de suite ; la réponse d'Apex (lignes recalculées,
   * donc rangs et libellés) remplace ensuite la liste. En cas d'erreur, SEULE cette ligne revient à
   * son état d'avant (deux bascules en vol sur des lignes différentes ne s'annulent pas) et le motif
   * s'affiche — jamais un retour silencieux.
   */
  async handleToggleIncluded(event) {
    const { id } = event.currentTarget.dataset;
    const checked = event.currentTarget.checked;
    const row = this.documents.find((d) => d.ptfDocumentId === id);
    if (!row || this.togglingIds.includes(id)) {
      return;
    }
    const previous = !!row.includedInHistory;
    this.togglingIds = [...this.togglingIds, id];
    this.documents = this.withIncluded(id, checked);
    try {
      const rows = await setIncludedInHistoryApex({
        ptfDocumentId: id,
        included: checked
      });
      this.documents = rows || [];
    } catch (error) {
      this.documents = this.withIncluded(id, previous);
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.togglingIds = this.togglingIds.filter((x) => x !== id);
    }
  }

  withIncluded(id, included) {
    return this.documents.map((d) => {
      if (d.ptfDocumentId !== id) {
        return d;
      }
      return { ...d, includedInHistory: included };
    });
  }

  handleOpenModification(event) {
    const { id } = event.currentTarget.dataset;
    const row = this.documents.find((d) => d.ptfDocumentId === id);
    if (!row) {
      return;
    }
    this.editingDocId = id;
    this.editType = row.modificationType || "";
    this.editDetail = row.modificationDetail || "";
    this.editValid =
      !!this.editType &&
      (this.editType !== "Autre" || !!this.editDetail.trim());
    this.editError = undefined;
    this._focusPickerPending = true;
  }

  handleEditChange(event) {
    const { type, detail, valid } = event.detail;
    this.editType = type;
    this.editDetail = detail;
    this.editValid = valid;
  }

  get isEditSaveDisabled() {
    return !this.editValid || this.isSavingModification;
  }

  handleCancelModification() {
    if (this.isSavingModification) {
      return;
    }
    this.editingDocId = undefined;
    this.editError = undefined;
  }

  handlePopoverKeydown(event) {
    if (event.key === "Escape") {
      this.handleCancelModification();
    }
  }

  async handleSaveModification() {
    if (this.isEditSaveDisabled) {
      return;
    }
    this.isSavingModification = true;
    this.editError = undefined;
    try {
      const rows = await setModificationApex({
        ptfDocumentId: this.editingDocId,
        type: this.editType,
        detail: this.editType === "Autre" ? this.editDetail : ""
      });
      this.documents = rows || [];
      this.editingDocId = undefined;
    } catch (error) {
      // Le popover reste ouvert avec le motif : la saisie n'est pas perdue.
      this.editError = this.reduceError(error);
    } finally {
      this.isSavingModification = false;
    }
  }

  get hasDocuments() {
    return this.documents.length > 0;
  }

  get generateButtonLabel() {
    return this.hasDocuments
      ? I18N.AR_PTF_RegeneratePtf
      : I18N.AR_PTF_GeneratePtf;
  }

  // ------------------------------------------------------------------------------------------
  // Session 37 — création d'un avenant. Formulaire séparé du formulaire PTF ci-dessus : ouvert
  // depuis la ligne d'une PTF déjà générée (le seul point d'entrée), jamais depuis un formulaire
  // vierge — c'est ce qui garantit que la référence/date citées par l'avenant sont justes.
  // ------------------------------------------------------------------------------------------

  async handleOpenAvenantForm(event) {
    const { id, reference } = event.currentTarget.dataset;
    if (!this.isLegacyAvenantFormActive) {
      this.avenantModalPtfId = id;
      this.showAvenantModal = true;
      return;
    }
    await this.openAvenantFormFor(id, reference);
  }

  get isLegacyAvenantFormActive() {
    return this.legacyAvenantForm === true || this.legacyAvenantFormSetting;
  }

  // ------------------------------------------------------------------------------------------
  // Session 180d — matrice avenant : « Générer l'avenant », PTF amendée en lien, formulaire court.
  // ------------------------------------------------------------------------------------------

  get isAvenantMatrix() {
    return !!this.avenantState && this.avenantState.isAvenant === true;
  }

  get isAvenantMatrixValidated() {
    return (
      this.isAvenantMatrix &&
      ["Validée", "Validée par dérogation"].includes(
        this.avenantState.matrixStatus
      )
    );
  }

  get showGeneratePtfButton() {
    return !this.readOnly && !this.isAvenantMatrix;
  }

  get canGenerateAvenantDocument() {
    return (
      !this.readOnly &&
      this.isAvenantMatrixValidated &&
      !!this.avenantState.amendedPtfId &&
      !this.showAvenantForm
    );
  }

  get avenantAwaitsDecision() {
    return this.isAvenantMatrix && !this.isAvenantMatrixValidated;
  }

  get avenantGenerateLabel() {
    return this.documents.some(
      (d) => d.documentType === "Avenant" && d.status === "Généré"
    )
      ? I18N.AR_PTF_RegenerateAvenant
      : I18N.AR_PTF_GenerateAvenant;
  }

  get hasAmendedPtfFile() {
    return (
      this.isAvenantMatrix && !!this.avenantState.amendedPtfContentDocumentId
    );
  }

  /** Formulaire court ouvert sur une matrice avenant : tarif, dates et échéancier viennent de la matrice. */
  get isAvenantMatrixForm() {
    return this.showAvenantForm && this.isAvenantMatrix;
  }

  get isAvenantLegacyForm() {
    return !this.isAvenantMatrixForm;
  }

  get avenantMatrixSummary() {
    const s = this.avenantState;
    if (!s) return "";
    const parts = [];
    if (s.effectiveDate) {
      parts.push(
        formatLabel(
          I18N.AR_PTF_SummaryEffectiveDate,
          formatIsoDateFr(s.effectiveDate)
        )
      );
    }
    if (s.endDate) {
      parts.push(
        formatLabel(I18N.AR_PTF_SummaryEndDate, formatIsoDateFr(s.endDate))
      );
    }
    if (s.proposedTjm != null) {
      parts.push(
        formatLabel(
          I18N.AR_PTF_SummaryDailyRate,
          formatMoney(s.proposedTjm, s.currencyCode || "EUR")
        )
      );
    }
    return parts.join(" · ");
  }

  async handleOpenAvenantDocumentForm() {
    const s = this.avenantState;
    if (!s || !s.amendedPtfId) {
      return;
    }
    await this.openAvenantFormFor(s.amendedPtfId, s.amendedPtfReference);
  }

  handleOpenAmendedPtf() {
    const id =
      this.avenantState && this.avenantState.amendedPtfContentDocumentId;
    if (id) {
      window.open(DOWNLOAD_BASE_URL + id, "_blank");
    }
  }

  /** Renvoi « Avenant AV1 → V3 » de la matrice d'origine vers la matrice avenant (même contrat que le shell). */
  handleOpenAvenantMatrix(event) {
    const { matrixId } = event.currentTarget.dataset;
    if (!matrixId) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: { matrixId },
        bubbles: true,
        composed: true
      })
    );
  }

  handleAvenantModalCancel() {
    this.showAvenantModal = false;
  }

  handleAvenantCreated(event) {
    const { matrixId, derogationRequired } = event.detail;
    this.showAvenantModal = false;
    const toast = avenantCreatedToast(event.detail);
    this.dispatchEvent(
      new ShowToastEvent({
        title: toast.title,
        message: toast.message,
        variant: toast.variant,
        mode: toast.mode
      })
    );
    // Même contrat que arMatrixList / le simulateur : le shell (arPricingApp) remonte le simulateur sur la
    // nouvelle matrice (piège session 117 : sans cela l'écran restait sur la matrice source).
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: {
          matrixId,
          focusSection: derogationRequired ? "derogation" : null
        },
        bubbles: true,
        composed: true
      })
    );
  }

  async openAvenantFormFor(id, reference) {
    this.avenantForOriginId = id;
    this.isConfirmingAvenantDraftReset = false;
    this._pendingAvenantLotOverrides = undefined;
    this.avenantForOriginReference = reference;
    this.avenantDefaultsWarning = undefined;
    this.avenantValideurBlocage = "";
    this.avenantTouched = new Set();
    // Session 145 : contacts (interlocuteur CLIENT, rédacteur, valideur) pré-remplis depuis la PTF
    // d'origine par le serveur (AR_PTFDataService.getAvenantDefaults, même règle que la génération),
    // modifiables. Avant, seul le valideur de la matrice était repris (this.form) : les contacts de
    // la PTF d'origine étaient perdus. Le formulaire s'ouvre tout de suite (valideur de repli issu
    // de this.form) puis se complète à la réponse du serveur.
    this.avenantForm = {
      prolongationJusquAu: "",
      revisionPrix: false,
      revisionPrixADateDu: "",
      valideurId: this.form.valideurId || "",
      valideurNom: this.form.valideurNom || "",
      valideurFonction: this.form.valideurFonction || "",
      redacteurNom: "",
      redacteurFonction: "",
      interNom: "",
      interFonction: "",
      interTel: "",
      interEmail: "",
      adresseClient: ""
    };
    this.avenantAccountAddress = "";
    this.avenantLotOverrides = {};
    this.isCreatingAvenant = true;
    this.applyAvenantDraft(id);
    if (this.isAvenantMatrixForm && this.showAvenantPriceBlock) {
      // Matrice avenant : l'échéancier à surcharger est connu dès l'ouverture (lu sur la matrice).
      this._refreshAvenantLots();
    }
    try {
      const defaults = await getAvenantDefaultsApex({ parentDocId: id });
      // Le formulaire a pu être fermé ou rouvert sur une autre PTF pendant l'appel.
      if (this.avenantForOriginId !== id) {
        return;
      }
      // Afficher (doctrine session 34) : le repli depuis le besoin est signalé, jamais silencieux.
      this.avenantDefaultsWarning = defaults.warning;
      this.avenantValideurBlocage = defaults.valideurBlocage || "";
      // Ne pas écraser ce que l'utilisateur a déjà tapé pendant l'attente.
      const next = { ...this.avenantForm };
      AVENANT_CONTACT_FIELDS.forEach((field) => {
        if (defaults[field] && !this.avenantTouched.has(field)) {
          next[field] = defaults[field];
        }
      });
      // Valideur : valeur du serveur (PTF d'origine si encore proposable, sinon défaut), sauf si
      // l'utilisateur ou le brouillon l'a déjà posée ; absente, le repli reste celui du formulaire PTF.
      if (!this.avenantTouched.has("valideurId")) {
        ["valideurId", "valideurNom"].forEach((field) => {
          if (defaults[field]) {
            next[field] = defaults[field];
          }
        });
      }
      if (
        defaults.valideurFonction &&
        !this.avenantTouched.has("valideurFonction")
      ) {
        next.valideurFonction = defaults.valideurFonction;
      }
      // Session 279 : adresse du compte ; pré-remplit le champ sauf saisie ou brouillon déjà posés.
      this.avenantAccountAddress = defaults.adresseClient || "";
      if (
        !this.avenantTouched.has("adresseClient") &&
        normalizeAddress(next.adresseClient) === ""
      ) {
        next.adresseClient = this.avenantAccountAddress;
      }
      this.avenantForm = next;
    } catch (error) {
      // Afficher : sans les défauts serveur, le formulaire reste utilisable mais les contacts de la
      // PTF d'origine ne sont pas affichés — la génération les reprendra tout de même côté serveur.
      this.avenantDefaultsWarning = formatLabel(
        I18N.AR_PTF_OriginContactsNotLoaded,
        this.reduceError(error)
      );
    }
  }

  handleCancelAvenantForm() {
    this._pendingAvenantLotOverrides = undefined;
    this.isCreatingAvenant = false;
    this.avenantForOriginId = undefined;
    this.avenantForOriginReference = undefined;
  }

  get showAvenantForm() {
    return !!this.avenantForOriginId;
  }

  handleAvenantFieldChange(event) {
    const { field } = event.target.dataset;
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;
    this.avenantForm = { ...this.avenantForm, [field]: value };
    this.avenantTouched.add(field);
    // Session 126b : rafraîchir les lots révisés si l'un des trois paramètres change.
    if (
      ["revisionPrixADateDu", "prolongationJusquAu", "nouveauTjm"].includes(
        field
      )
    ) {
      this._refreshAvenantLots();
    }
  }

  get showAvenantPriceBlock() {
    // Matrice avenant : le bloc (tableau de lots) suit ce que le document imprimera, lu sur la matrice.
    return this.isAvenantMatrixForm
      ? this.avenantState.printsPriceBlock === true
      : this.avenantForm.revisionPrix;
  }

  get avenantPriceInfo() {
    if (!this.showAvenantPriceBlock || !this.avenantForm.nouveauTjm) {
      return null;
    }
    const ancienTjm = this.tjmOriginal;
    const nouveauTjm = this.avenantForm.nouveauTjm;

    if (!ancienTjm || ancienTjm <= 0) {
      return {
        ancienTjmLabel: "—",
        ecartLabel: "—",
        hasMarginImpact: false,
        noMarginImpactLabel: I18N.AR_PTF_OldRateUnavailable
      };
    }

    const ecart = nouveauTjm - ancienTjm;
    const ecartPercent = (ecart / ancienTjm) * 100;
    const ecartLabel = `${ecart >= 0 ? "+" : ""}${formatMoney(
      ecart,
      this.currencyCode
    )} (${ecartPercent >= 0 ? "+" : ""}${formatPercent(ecartPercent)})`;

    if (
      this.coutTotalJour === null ||
      this.coutTotalJour === undefined ||
      this.rfaPercent === null ||
      this.rfaPercent === undefined
    ) {
      return {
        ancienTjmLabel: formatMoney(ancienTjm, this.currencyCode),
        ecartLabel,
        hasMarginImpact: false,
        noMarginImpactLabel: I18N.AR_PTF_MarginImpactUnavailable
      };
    }

    const { mc2PercentFraction: ancienneMc2 } = calcMC2(
      ancienTjm,
      this.coutTotalJour,
      this.rfaPercent
    );
    const { mc2PercentFraction: nouvelleMc2 } = calcMC2(
      nouveauTjm,
      this.coutTotalJour,
      this.rfaPercent
    );

    const ancienneMc2Label = formatPercent(ancienneMc2 * 100);
    const nouvelleMc2Label = formatPercent(nouvelleMc2 * 100);
    const ecartMc2 = (nouvelleMc2 - ancienneMc2) * 100;

    let marginWarning = null;
    // Session 123b : plancher figé de la matrice (grand compte compris), jamais 20 % en dur. Plancher
    // inconnu (ancienne matrice) : pas d'avertissement plutôt qu'un seuil inventé.
    const PLANCHER_MC2 = this.plancherPercent;
    if (PLANCHER_MC2 != null && nouvelleMc2 * 100 < PLANCHER_MC2) {
      marginWarning = formatLabel(
        I18N.AR_PTF_AvenantBelowFloor,
        nouvelleMc2Label,
        PLANCHER_MC2
      );
    }

    return {
      ancienTjmLabel: formatMoney(ancienTjm, this.currencyCode),
      ecartLabel,
      hasMarginImpact: true,
      marginImpactLabel: `MC2 ${ancienneMc2Label} → ${nouvelleMc2Label} (${ecartMc2 >= 0 ? "+" : ""}${formatPercent(
        ecartMc2
      )})`,
      marginWarning
    };
  }

  get isAvenantValideurMissing() {
    return (
      !this.avenantForm.valideurNom || !this.avenantForm.valideurNom.trim()
    );
  }

  get isCreateAvenantDisabled() {
    const isTjmMissing =
      this.avenantForm.revisionPrix &&
      (!this.avenantForm.nouveauTjm || this.avenantForm.nouveauTjm <= 0);
    return this.isGenerating || this.isAvenantValideurMissing || isTjmMissing;
  }

  get hasAvenantLots() {
    return this.avenantLots && this.avenantLots.length > 0;
  }

  /**
   * Tableau de lots de l'avenant révisés (session 126b). Affiche `avenantLots` (calculé par le
   * serveur via previewAvenantLots, puis mis à jour avec les surcharges locales
   * `avenantLotOverrides`). Vide tant que la date d'effet, la prolongation ou le nouveau TJM ne
   * sont pas renseignés ; message utilisateur affiché par le template.
   */
  get avenantLotRows() {
    return this.avenantLots.map((lot, index) => {
      const overridden = Object.prototype.hasOwnProperty.call(
        this.avenantLotOverrides,
        index
      );
      return {
        key: `avenant-lot-${index}`,
        index,
        libelle: lot.libelle,
        mois: lot.mois,
        jours: lot.jours,
        montantCalculeLabel: formatMoney(lot.montantCalcule, this.currencyCode),
        montantValue: overridden ? this.avenantLotOverrides[index] : undefined,
        montantPlaceholder: String(lot.montantCalcule),
        isOverridden: overridden
      };
    });
  }

  handleAvenantLotMontantChange(event) {
    const index = Number(event.target.dataset.index);
    const raw = event.target.value;
    const overrides = { ...this.avenantLotOverrides };
    if (raw === "" || raw === null || raw === undefined) {
      delete overrides[index];
    } else {
      overrides[index] = Number(raw);
    }
    this.avenantLotOverrides = overrides;
  }

  /**
   * Session 126b : rechargement des lots révisés via previewAvenantLots (debounce 300 ms).
   * Appelé dès que l'un des trois paramètres change : date d'effet, prolongation, nouveau TJM.
   * Vide avenantLotOverrides quand le nombre de lots change (les indices ne correspondent plus).
   */
  async _refreshAvenantLots() {
    if (this._avenantLotsRefreshTimer) {
      clearTimeout(this._avenantLotsRefreshTimer);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce de 300 ms (session 126b).
    this._avenantLotsRefreshTimer = setTimeout(async () => {
      try {
        const lots = await previewAvenantLotsApex(
          this.isAvenantMatrixForm
            ? {
                dateEffet: this.avenantState.effectiveDate || null,
                prolongation: this.avenantState.endDate || null,
                nouveauTjm: Number(this.avenantState.proposedTjm) || null,
                parentDocId: this.avenantForOriginId || null
              }
            : {
                dateEffet: this.avenantForm.revisionPrixADateDu || null,
                prolongation: this.avenantForm.prolongationJusquAu || null,
                nouveauTjm: Number(this.avenantForm.nouveauTjm) || null,
                parentDocId: this.avenantForOriginId || null
              }
        );
        const oldCount = this.avenantLots.length;
        const newCount = lots.length;
        if (this._pendingAvenantLotOverrides) {
          // Brouillon d'avenant (session 148) : les montants surchargés ne peuvent être replacés
          // qu'une fois l'échéancier révisé connu — sinon le changement du nombre de lots les effacerait.
          this.avenantLotOverrides = lotOverridesFromDraft(
            this._pendingAvenantLotOverrides,
            newCount
          );
          this._pendingAvenantLotOverrides = undefined;
        } else if (oldCount !== newCount) {
          this.avenantLotOverrides = {};
        }
        this.avenantLots = lots || [];
        this.avenantLotsError = undefined;
      } catch (error) {
        this.avenantLots = [];
        this.avenantLotsError = formatLabel(
          I18N.AR_PTF_RevisedScheduleUnavailable,
          (error && error.body && error.body.message) ||
            I18N.AR_Common_UnknownErrorLower
        );
        // Erreur serveur lors de la preview : affichée au-dessus du tableau (message utilisateur
        // distinct du formulaire). Ne pas bloquer la génération, l'utilisateur peut créer
        // l'avenant sans aperçu des lots.
        console.error("Erreur aperçu lots avenant:", error);
      }
    }, 300);
  }

  handleAvenantFormFieldChange() {
    // Redémarrer le debounce lors de tout changement du formulaire avenant.
    this._refreshAvenantLots();
  }

  // ------------------------------------------------------------------------------------------
  // Session 148 — brouillon du formulaire d'avenant (un seul par matrice, rattaché à UNE PTF d'origine)
  // ------------------------------------------------------------------------------------------

  get avenantDraftEntry() {
    return (this.formDraft && this.formDraft[DRAFT_MODE_AVENANT]) || null;
  }

  get hasAvenantDraft() {
    return !!this.avenantDraftEntry;
  }

  get isAvenantDraftOtherOrigin() {
    const entry = this.avenantDraftEntry;
    return !!entry && entry.parentDocumentId !== this.avenantForOriginId;
  }

  get avenantDraftStamp() {
    return this.avenantDraftEntry
      ? formatDraftStamp(this.avenantDraftEntry)
      : "";
  }

  get isSaveAvenantDraftDisabled() {
    return (
      this.isSavingAvenantDraft || this.isGenerating || this.isClearingDraft
    );
  }

  /** Reprend le brouillon d'avenant par-dessus le formulaire, s'il concerne cette PTF d'origine. */
  applyAvenantDraft(originId) {
    const entry = this.avenantDraftEntry;
    if (!entry || entry.parentDocumentId !== originId) {
      return;
    }
    const input = entry.input || {};
    const next = { ...this.avenantForm };
    AVENANT_DRAFT_TEXT_FIELDS.forEach((field) => {
      if (typeof input[field] === "string" && input[field].trim() !== "") {
        next[field] = input[field];
        // Posé par l'utilisateur : la réponse tardive des contacts d'origine ne l'écrase pas.
        this.avenantTouched.add(field);
      }
    });
    // Matrice avenant (180d) : prix et dates viennent de la matrice, un ancien brouillon de formulaire
    // n'en reprend que les contacts et les surcharges de lots (valeurs de prix du brouillon ignorées).
    if (!this.isAvenantMatrixForm) {
      if (typeof input.revisionPrix === "boolean") {
        next.revisionPrix = input.revisionPrix;
      }
      if (input.nouveauTjm !== null && input.nouveauTjm !== undefined) {
        const tjm = Number(input.nouveauTjm);
        if (Number.isFinite(tjm)) {
          next.nouveauTjm = tjm;
        }
      }
    }
    if (this.applyValideurDraft(next, input)) {
      this.avenantTouched.add("valideurId");
      this.avenantTouched.add("valideurFonction");
    }
    this.avenantForm = next;
    const lotsApply = this.isAvenantMatrixForm
      ? this.showAvenantPriceBlock
      : next.revisionPrix;
    if (
      lotsApply &&
      Array.isArray(input.lotOverrides) &&
      input.lotOverrides.length
    ) {
      this._pendingAvenantLotOverrides = input.lotOverrides;
    }
    if (
      this.isAvenantMatrixForm
        ? this.showAvenantPriceBlock
        : next.revisionPrix && (next.revisionPrixADateDu || next.nouveauTjm)
    ) {
      this._refreshAvenantLots();
    }
  }

  async handleSaveAvenantDraft() {
    this.isSavingAvenantDraft = true;
    try {
      const raw = await savePtfFormDraftApex({
        matrixId: this.recordId,
        mode: DRAFT_MODE_AVENANT,
        inputJson: this.buildAvenantPayload()
      });
      this.rememberSavedDraft(DRAFT_MODE_AVENANT, raw);
      this.showToast(I18N.AR_PTF_DraftSaved, "", "success");
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSavingAvenantDraft = false;
    }
  }

  handleAskAvenantDraftReset() {
    this.isConfirmingAvenantDraftReset = true;
  }

  handleCancelAvenantDraftReset() {
    this.isConfirmingAvenantDraftReset = false;
  }

  async handleConfirmAvenantDraftReset() {
    this.isClearingDraft = true;
    try {
      await clearPtfFormDraftApex({
        matrixId: this.recordId,
        mode: DRAFT_MODE_AVENANT
      });
      const { [DRAFT_MODE_AVENANT]: removed, ...rest } = this.formDraft || {};
      this.formDraft = removed ? rest : this.formDraft;
      const id = this.avenantForOriginId;
      const reference = this.avenantForOriginReference;
      await this.openAvenantFormFor(id, reference);
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isClearingDraft = false;
      this.isConfirmingAvenantDraftReset = false;
    }
  }

  buildAvenantPayload() {
    if (this.isAvenantMatrixForm) {
      // Matrice avenant : tarif, dates et échéancier sont lus sur la matrice par le serveur ; le
      // formulaire n'envoie que les contacts et les surcharges de lots.
      return JSON.stringify({
        matrixId: this.recordId,
        ptfDocumentId: this.avenantForOriginId,
        valideurId: this.avenantForm.valideurId,
        valideurNom: this.avenantForm.valideurNom,
        valideurFonction: this.avenantForm.valideurFonction,
        redacteurNom: this.avenantForm.redacteurNom,
        redacteurFonction: this.avenantForm.redacteurFonction,
        interNom: this.avenantForm.interNom,
        interFonction: this.avenantForm.interFonction,
        interTel: this.avenantForm.interTel,
        interEmail: this.avenantForm.interEmail,
        adresseClient: this.avenantForm.adresseClient,
        lotOverrides: this.showAvenantPriceBlock
          ? Object.keys(this.avenantLotOverrides).map((index) => ({
              index: Number(index),
              montant: this.avenantLotOverrides[index]
            }))
          : []
      });
    }
    return JSON.stringify({
      ptfDocumentId: this.avenantForOriginId,
      valideurId: this.avenantForm.valideurId,
      valideurNom: this.avenantForm.valideurNom,
      valideurFonction: this.avenantForm.valideurFonction,
      redacteurNom: this.avenantForm.redacteurNom,
      redacteurFonction: this.avenantForm.redacteurFonction,
      interNom: this.avenantForm.interNom,
      interFonction: this.avenantForm.interFonction,
      interTel: this.avenantForm.interTel,
      interEmail: this.avenantForm.interEmail,
      adresseClient: this.avenantForm.adresseClient,
      prolongationJusquAu: this.avenantForm.prolongationJusquAu,
      revisionPrix: this.avenantForm.revisionPrix,
      revisionPrixADateDu: this.avenantForm.revisionPrix
        ? this.avenantForm.revisionPrixADateDu
        : null,
      nouveauTjm: this.avenantForm.revisionPrix
        ? this.avenantForm.nouveauTjm
        : null,
      lotOverrides: this.avenantForm.revisionPrix
        ? Object.keys(this.avenantLotOverrides).map((index) => ({
            index: Number(index),
            montant: this.avenantLotOverrides[index]
          }))
        : []
    });
  }

  async handleCreateAvenant() {
    this.isGenerating = true;
    try {
      const started = await generateAvenantApex({
        inputJson: this.buildAvenantPayload()
      });
      this.handleCancelAvenantForm();
      await this.refreshDocumentsOnly();

      await this.renderStep(started.ptfDocumentId, (finished) =>
        formatLabel(I18N.AR_PTF_AvenantGenerated, finished.reference)
      );
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isGenerating = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }
}