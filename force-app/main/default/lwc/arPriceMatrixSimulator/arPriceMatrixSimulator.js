import { LightningElement, api, wire } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import resolveRecordContext from "@salesforce/apex/AR_PricingMatrixService.resolveRecordContext";
import countMatricesForPosition from "@salesforce/apex/AR_PricingMatrixService.countMatricesForPosition";
import getPositionContext from "@salesforce/apex/AR_PricingMatrixService.getPositionContext";
import getMatrixInput from "@salesforce/apex/AR_PricingMatrixService.getMatrixInput";
import loadWonDeal from "@salesforce/apex/AR_WonDealService.loadWonDeal";
import LBL_AR_Won_Badge from "@salesforce/label/c.AR_Won_Badge";
import LBL_AR_Won_Dlg_Price1 from "@salesforce/label/c.AR_Won_Dlg_Price1";
import LBL_AR_Won_Dlg_Price2 from "@salesforce/label/c.AR_Won_Dlg_Price2";
import LBL_AR_Won_Dlg_Price3 from "@salesforce/label/c.AR_Won_Dlg_Price3";
import LBL_AR_Won_Dlg_OffGrid from "@salesforce/label/c.AR_Won_Dlg_OffGrid";
import getAccountCorridorPercents from "@salesforce/apex/AR_PricingMatrixService.getAccountCorridorPercents";
import getPricingSettings from "@salesforce/apex/AR_PricingMatrixService.getPricingSettings";
import getValidatorOptionsForMatrix from "@salesforce/apex/AR_PricingMatrixService.getValidatorOptionsForMatrix";
import saveDraftApex from "@salesforce/apex/AR_PricingMatrixService.saveDraft";
import validateApex from "@salesforce/apex/AR_PricingMatrixService.validate";
import { logNotificationFailure } from "c/arNotificationLog";
import requestDerogationApex from "@salesforce/apex/AR_PricingMatrixService.requestDerogation";
import getValidationPrerequisites from "@salesforce/apex/AR_PricingMatrixService.getValidationPrerequisites";
import searchPositions from "@salesforce/apex/AR_PricingMatrixService.searchPositions";
import searchConsultants from "@salesforce/apex/AR_PricingMatrixService.searchConsultants";
import getConsultantContext from "@salesforce/apex/AR_PricingMatrixService.getConsultantContext";
import getCreationPrefill from "@salesforce/apex/AR_PricingMatrixService.getCreationPrefill";
import getCurrentUserName from "@salesforce/apex/AR_PricingMatrixService.getCurrentUserName";
import getRecentDraftForCurrentUser from "@salesforce/apex/AR_PricingMatrixService.getRecentDraftForCurrentUser";
// Session 47 : variante dédiée qui signale, dans le libellé, une entité pas encore prête pour un
// gabarit PTF (getEntityOptions() reste la version neutre, aussi consommée par
// arAdminGeneralSettings sans rapport avec la PTF — ne jamais y mélanger les deux).
import getEntityOptions from "@salesforce/apex/AR_PricingMatrixService.getEntityOptionsWithPtfReadiness";
// Session 48 : coefficient/jours travaillés par entité, pour que ce miroir JS applique la même
// cascade entité → paramètre général → constante que AR_PricingMatrixService.calculateAndPopulate.
import getEntityPricingDefaults from "@salesforce/apex/AR_PricingMatrixService.getEntityPricingDefaults";
import changeValidatedMatrixEntityApex from "@salesforce/apex/AR_PricingMatrixService.changeValidatedMatrixEntity";
import getVieReferentialOptions from "@salesforce/apex/AR_PricingMatrixService.getVieReferentialOptions";
import getNearshoreReferentialOptions from "@salesforce/apex/AR_PricingMatrixService.getNearshoreReferentialOptions";
import getPendingDerogationForCurrentUser from "@salesforce/apex/AR_DerogationService.getPendingDerogationForCurrentUser";
import getDefaultRfaPercentWithProvenance from "@salesforce/apex/AR_AdminCommercialService.getDefaultRfaPercentWithProvenance";
import { getPicklistValuesByRecordType } from "lightning/uiObjectInfoApi";
import getMarketReference from "@salesforce/apex/AR_ComparablesService.getMarketReference";
import getCurrentRates from "@salesforce/apex/AR_CurrencyRateService.getCurrentRates";
import { buildSalesArguments } from "c/arSalesArgumentsEngine";
import { avenantCreatedToast } from "c/arAvenantGeneration";
import {
  compute,
  computeOfiiTax,
  calcGaugePosition,
  calcMc2ForTjm,
  isGaugePositionOutOfScale,
  calcBusinessDays,
  calcBillableDays,
  currencySymbol,
  formatMoney,
  formatMoneyPrecise,
  formatPercent,
  formatMoneyWithDecimalBreakdown,
  resolveRateToEur,
  FLOOR_PERCENT_DEFAULT,
  TARGET_PERCENT_DEFAULT,
  IDEAL_PERCENT_DEFAULT
} from "c/arPricingEngine";
import {
  monthsOf,
  balance,
  totalSold,
  totalProduced,
  defaultDaysPerMonth
} from "c/arWorkingCalendar";

// --- i18n : Custom Labels (session 86, cf. docs/86-inventaire-i18n.md) ---
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Duplicate from "@salesforce/label/c.AR_Common_Duplicate";
import LBL_AR_Common_Resume from "@salesforce/label/c.AR_Common_Resume";
import LBL_AR_Common_Dismiss from "@salesforce/label/c.AR_Common_Dismiss";
import LBL_AR_Common_Country from "@salesforce/label/c.AR_Common_Country";
import LBL_AR_Common_ContractTypeField from "@salesforce/label/c.AR_Common_ContractTypeField";
import LBL_AR_Common_Contact from "@salesforce/label/c.AR_Common_Contact";
import LBL_AR_Common_CreatedOn from "@salesforce/label/c.AR_Common_CreatedOn";
import LBL_AR_Common_View from "@salesforce/label/c.AR_Common_View";
import LBL_AR_Common_OpenRecord from "@salesforce/label/c.AR_Common_OpenRecord";
import LBL_AR_Common_Consultant from "@salesforce/label/c.AR_Common_Consultant";
import LBL_AR_Common_Use from "@salesforce/label/c.AR_Common_Use";
import LBL_AR_Common_Close from "@salesforce/label/c.AR_Common_Close";
import LBL_AR_Common_AccountName from "@salesforce/label/c.AR_Common_AccountName";
import LBL_AR_Common_Position from "@salesforce/label/c.AR_Common_Position";
import LBL_AR_Common_Owner from "@salesforce/label/c.AR_Common_Owner";
import LBL_AR_Common_Confidence from "@salesforce/label/c.AR_Common_Confidence";
import LBL_AR_Common_Currency from "@salesforce/label/c.AR_Common_Currency";
import LBL_AR_Common_Other from "@salesforce/label/c.AR_Common_Other";
import LBL_AR_Common_Validator from "@salesforce/label/c.AR_Common_Validator";
import LBL_AR_Common_Cancel from "@salesforce/label/c.AR_Common_Cancel";
import LBL_AR_Common_Empty from "@salesforce/label/c.AR_Common_Empty";
import LBL_AR_Common_NotProvided_Fem from "@salesforce/label/c.AR_Common_NotProvided_Fem";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_UnknownError from "@salesforce/label/c.AR_Common_UnknownError";
import LBL_AR_Common_PerDaySuffix from "@salesforce/label/c.AR_Common_PerDaySuffix";
import LBL_AR_Common_PerDayLong from "@salesforce/label/c.AR_Common_PerDayLong";
import LBL_AR_PMS_PositionSelectorTitle from "@salesforce/label/c.AR_PMS_PositionSelectorTitle";
import LBL_AR_PMS_PositionSelectorSubtitle from "@salesforce/label/c.AR_PMS_PositionSelectorSubtitle";
import LBL_AR_PMS_SearchPositionLabel from "@salesforce/label/c.AR_PMS_SearchPositionLabel";
import LBL_AR_PMS_SearchPositionPlaceholder from "@salesforce/label/c.AR_PMS_SearchPositionPlaceholder";
import LBL_AR_PMS_NoPositionResults from "@salesforce/label/c.AR_PMS_NoPositionResults";
import LBL_AR_PMS_LoadingPreview from "@salesforce/label/c.AR_PMS_LoadingPreview";
import LBL_AR_PMS_OpenAccountRecordAriaLabel from "@salesforce/label/c.AR_PMS_OpenAccountRecordAriaLabel";
import LBL_AR_PMS_BusinessSector from "@salesforce/label/c.AR_PMS_BusinessSector";
import LBL_AR_PMS_Perimeter from "@salesforce/label/c.AR_PMS_Perimeter";
import LBL_AR_PMS_CreateMatrixFromPosition from "@salesforce/label/c.AR_PMS_CreateMatrixFromPosition";
import LBL_AR_PMS_NoPositionSelectedTitle from "@salesforce/label/c.AR_PMS_NoPositionSelectedTitle";
import LBL_AR_PMS_NoPositionSelectedHelp from "@salesforce/label/c.AR_PMS_NoPositionSelectedHelp";
import LBL_AR_PMS_ZoneContextTitle from "@salesforce/label/c.AR_PMS_ZoneContextTitle";
import LBL_AR_PMS_ZoneContextSubtitle from "@salesforce/label/c.AR_PMS_ZoneContextSubtitle";
import LBL_AR_PMS_EntityLabel from "@salesforce/label/c.AR_PMS_EntityLabel";
import LBL_AR_PMS_SelectEntityPlaceholder from "@salesforce/label/c.AR_PMS_SelectEntityPlaceholder";
import LBL_AR_PMS_ChangeConsultant from "@salesforce/label/c.AR_PMS_ChangeConsultant";
import LBL_AR_PMS_SearchConsultantPlaceholder from "@salesforce/label/c.AR_PMS_SearchConsultantPlaceholder";
import LBL_AR_PMS_NoConsultantResults from "@salesforce/label/c.AR_PMS_NoConsultantResults";
import LBL_AR_PMS_SuggestedFromApplication from "@salesforce/label/c.AR_PMS_SuggestedFromApplication";
import LBL_AR_PMS_LegacyTextPrefix from "@salesforce/label/c.AR_PMS_LegacyTextPrefix";
import LBL_AR_PMS_ClickForDetails from "@salesforce/label/c.AR_PMS_ClickForDetails";
import LBL_AR_PMS_PrefillSuccess from "@salesforce/label/c.AR_PMS_PrefillSuccess";
import LBL_AR_PMS_PrefillFromRecord from "@salesforce/label/c.AR_PMS_PrefillFromRecord";
import LBL_AR_PMS_UndoPrefill from "@salesforce/label/c.AR_PMS_UndoPrefill";
import LBL_AR_PMS_ManagerName from "@salesforce/label/c.AR_PMS_ManagerName";
import LBL_AR_PMS_ClientSite from "@salesforce/label/c.AR_PMS_ClientSite";
import LBL_AR_PMS_ClientSitePlaceholder from "@salesforce/label/c.AR_PMS_ClientSitePlaceholder";
import LBL_AR_PMS_StartDate from "@salesforce/label/c.AR_PMS_StartDate";
import LBL_AR_PMS_ExpectedEndDate from "@salesforce/label/c.AR_PMS_ExpectedEndDate";
import LBL_AR_PMS_MarketReferenceTitle from "@salesforce/label/c.AR_PMS_MarketReferenceTitle";
import LBL_AR_PMS_MarketInfoAriaLabel from "@salesforce/label/c.AR_PMS_MarketInfoAriaLabel";
import LBL_AR_PMS_MarketInfoModalAriaLabel from "@salesforce/label/c.AR_PMS_MarketInfoModalAriaLabel";
import LBL_AR_PMS_MarketInfoModalTitle from "@salesforce/label/c.AR_PMS_MarketInfoModalTitle";
import LBL_AR_PMS_Pool from "@salesforce/label/c.AR_PMS_Pool";
import LBL_AR_PMS_Last12Months from "@salesforce/label/c.AR_PMS_Last12Months";
import LBL_AR_PMS_WeightedEffective from "@salesforce/label/c.AR_PMS_WeightedEffective";
import LBL_AR_PMS_PipelineHistoryTitle from "@salesforce/label/c.AR_PMS_PipelineHistoryTitle";
import LBL_AR_PMS_PipelineHistoryPrefix from "@salesforce/label/c.AR_PMS_PipelineHistoryPrefix";
import LBL_AR_PMS_Won from "@salesforce/label/c.AR_PMS_Won";
import LBL_AR_PMS_PipelineHistorySuffix from "@salesforce/label/c.AR_PMS_PipelineHistorySuffix";
import LBL_AR_PMS_PipelineFiltersTitle from "@salesforce/label/c.AR_PMS_PipelineFiltersTitle";
import LBL_AR_PMS_NoCountryNoComparables from "@salesforce/label/c.AR_PMS_NoCountryNoComparables";
import LBL_AR_PMS_PipelineAlgorithmTitle from "@salesforce/label/c.AR_PMS_PipelineAlgorithmTitle";
import LBL_AR_PMS_Metier from "@salesforce/label/c.AR_PMS_Metier";
import LBL_AR_PMS_Secteur from "@salesforce/label/c.AR_PMS_Secteur";
import LBL_AR_PMS_Client from "@salesforce/label/c.AR_PMS_Client";
import LBL_AR_PMS_PipelineThresholdTitle from "@salesforce/label/c.AR_PMS_PipelineThresholdTitle";
import LBL_AR_PMS_HighConfidenceSuffix from "@salesforce/label/c.AR_PMS_HighConfidenceSuffix";
import LBL_AR_PMS_MediumConfidenceSuffix from "@salesforce/label/c.AR_PMS_MediumConfidenceSuffix";
import LBL_AR_PMS_LowConfidenceSuffix from "@salesforce/label/c.AR_PMS_LowConfidenceSuffix";
import LBL_AR_PMS_EffectiveWeightedLine from "@salesforce/label/c.AR_PMS_EffectiveWeightedLine";
import LBL_AR_PMS_PipelineFinalCalcTitle from "@salesforce/label/c.AR_PMS_PipelineFinalCalcTitle";
import LBL_AR_PMS_PipelineFinalCalcText from "@salesforce/label/c.AR_PMS_PipelineFinalCalcText";
import LBL_AR_PMS_SeniorityNote from "@salesforce/label/c.AR_PMS_SeniorityNote";
import LBL_AR_PMS_ModalFooterNote from "@salesforce/label/c.AR_PMS_ModalFooterNote";
import LBL_AR_PMS_LoadingMarketRefs from "@salesforce/label/c.AR_PMS_LoadingMarketRefs";
import LBL_AR_PMS_Comparables from "@salesforce/label/c.AR_PMS_Comparables";
import LBL_AR_PMS_MedianTjm from "@salesforce/label/c.AR_PMS_MedianTjm";
import LBL_AR_PMS_Top10Percent from "@salesforce/label/c.AR_PMS_Top10Percent";
import LBL_AR_PMS_ZoneFinancialContextTitle from "@salesforce/label/c.AR_PMS_ZoneFinancialContextTitle";
import LBL_AR_PMS_ThresholdsInfoAriaLabel from "@salesforce/label/c.AR_PMS_ThresholdsInfoAriaLabel";
import LBL_AR_PMS_CostPerDayTerm from "@salesforce/label/c.AR_PMS_CostPerDayTerm";
import LBL_AR_PMS_TotalDailyCost from "@salesforce/label/c.AR_PMS_TotalDailyCost";
import LBL_AR_PMS_TjmThresholdsTerm from "@salesforce/label/c.AR_PMS_TjmThresholdsTerm";
import LBL_AR_PMS_RfaAndFreeTerm from "@salesforce/label/c.AR_PMS_RfaAndFreeTerm";
import LBL_AR_PMS_ContractStatus from "@salesforce/label/c.AR_PMS_ContractStatus";
import LBL_AR_PMS_SeniorityLevel from "@salesforce/label/c.AR_PMS_SeniorityLevel";
import LBL_AR_PMS_AnnualSalary from "@salesforce/label/c.AR_PMS_AnnualSalary";
import LBL_AR_Common_DecimalStepError from "@salesforce/label/c.AR_Common_DecimalStepError";
import LBL_AR_PMS_CjmBeforeMarkup from "@salesforce/label/c.AR_PMS_CjmBeforeMarkup";
import LBL_AR_PMS_MarkupCalculated from "@salesforce/label/c.AR_PMS_MarkupCalculated";
import LBL_AR_PMS_MarkupApplied from "@salesforce/label/c.AR_PMS_MarkupApplied";
import LBL_AR_PMS_VieCountry from "@salesforce/label/c.AR_PMS_VieCountry";
import LBL_AR_PMS_SelectCountryPlaceholder from "@salesforce/label/c.AR_PMS_SelectCountryPlaceholder";
import LBL_AR_PMS_RfaInheritedFrom from "@salesforce/label/c.AR_PMS_RfaInheritedFrom";
import LBL_AR_PMS_RfaReadFailed from "@salesforce/label/c.AR_PMS_RfaReadFailed";
import LBL_AR_PMS_VieCountryWarning from "@salesforce/label/c.AR_PMS_VieCountryWarning";
import LBL_AR_PMS_NearshoreCountry from "@salesforce/label/c.AR_PMS_NearshoreCountry";
import LBL_AR_PMS_NearshoreCountryWarning from "@salesforce/label/c.AR_PMS_NearshoreCountryWarning";
import LBL_AR_PMS_FeesOmToggle from "@salesforce/label/c.AR_PMS_FeesOmToggle";
import LBL_AR_PMS_FeeIK from "@salesforce/label/c.AR_PMS_FeeIK";
import LBL_AR_PMS_FeePeriodAdd from "@salesforce/label/c.AR_PMS_FeePeriodAdd";
import LBL_AR_PMS_SalaryPeriodAdd from "@salesforce/label/c.AR_PMS_SalaryPeriodAdd";
import LBL_AR_PMS_SalaryPeriodSalary from "@salesforce/label/c.AR_PMS_SalaryPeriodSalary";
import LBL_AR_PMS_CjmWeightedLabel from "@salesforce/label/c.AR_PMS_CjmWeightedLabel";
import LBL_AR_PMS_CostBreakdownCjmWeighted from "@salesforce/label/c.AR_PMS_CostBreakdownCjmWeighted";
import LBL_AR_PMS_SalaryPeriodTooltipLine from "@salesforce/label/c.AR_PMS_SalaryPeriodTooltipLine";
import LBL_AR_PMS_FeePeriodRemove from "@salesforce/label/c.AR_PMS_FeePeriodRemove";
import LBL_AR_PMS_FeePeriodTitle from "@salesforce/label/c.AR_PMS_FeePeriodTitle";
import LBL_AR_PMS_FeePeriodDays from "@salesforce/label/c.AR_PMS_FeePeriodDays";
import LBL_AR_PMS_FeePeriodFirstCalc from "@salesforce/label/c.AR_PMS_FeePeriodFirstCalc";
import LBL_AR_PMS_FeePeriodFirstUnknown from "@salesforce/label/c.AR_PMS_FeePeriodFirstUnknown";
import LBL_AR_PMS_FeePeriodExceed from "@salesforce/label/c.AR_PMS_FeePeriodExceed";
import LBL_AR_PMS_FeePeriodRecapLabel from "@salesforce/label/c.AR_PMS_FeePeriodRecapLabel";
import LBL_AR_PMS_FeePeriodShort from "@salesforce/label/c.AR_PMS_FeePeriodShort";
import LBL_AR_PMS_FeePeriodCaption from "@salesforce/label/c.AR_PMS_FeePeriodCaption";
import LBL_AR_PMS_TjmPeriodsOpenLink from "@salesforce/label/c.AR_PMS_TjmPeriodsOpenLink";
import LBL_AR_PMS_TjmPeriodsEdit from "@salesforce/label/c.AR_PMS_TjmPeriodsEdit";
import LBL_AR_PMS_RplsrProductionGap from "@salesforce/label/c.AR_PMS_RplsrProductionGap";
import LBL_AR_PMS_RplsrGapCaption from "@salesforce/label/c.AR_PMS_RplsrGapCaption";
import LBL_AR_PMS_RplsrClassic from "@salesforce/label/c.AR_PMS_RplsrClassic";
import LBL_AR_PMS_RplsrClassicTitle from "@salesforce/label/c.AR_PMS_RplsrClassicTitle";
import LBL_AR_Msg_PM_RplsrPlanInvalid from "@salesforce/label/c.AR_Msg_PM_RplsrPlanInvalid";
import LBL_AR_PMS_TjmPeriodsCloseLink from "@salesforce/label/c.AR_PMS_TjmPeriodsCloseLink";
import LBL_AR_PMS_TjmTimelineStart from "@salesforce/label/c.AR_PMS_TjmTimelineStart";
import LBL_AR_PMS_TjmTimelineEnd from "@salesforce/label/c.AR_PMS_TjmTimelineEnd";
import LBL_AR_PMS_TjmPeriodFirstRow from "@salesforce/label/c.AR_PMS_TjmPeriodFirstRow";
import LBL_AR_PMS_TjmPeriodFirstRowUnknown from "@salesforce/label/c.AR_PMS_TjmPeriodFirstRowUnknown";
import LBL_AR_PMS_TjmPeriodRowTitle from "@salesforce/label/c.AR_PMS_TjmPeriodRowTitle";
import LBL_AR_PMS_TjmPeriodRemove from "@salesforce/label/c.AR_PMS_TjmPeriodRemove";
import LBL_AR_PMS_TjmPeriodAdd from "@salesforce/label/c.AR_PMS_TjmPeriodAdd";
import LBL_AR_PMS_TjmPeriodTjmAria from "@salesforce/label/c.AR_PMS_TjmPeriodTjmAria";
import LBL_AR_PMS_TjmPeriodDaysAria from "@salesforce/label/c.AR_PMS_TjmPeriodDaysAria";
import LBL_AR_PMS_TjmPeriodDaysUnit from "@salesforce/label/c.AR_PMS_TjmPeriodDaysUnit";
import LBL_AR_PMS_TjmWeightedFooter from "@salesforce/label/c.AR_PMS_TjmWeightedFooter";
import LBL_AR_PMS_TjmWeightedGaugeTitle from "@salesforce/label/c.AR_PMS_TjmWeightedGaugeTitle";
import LBL_AR_PMS_TjmPeriodsMissionUnknown from "@salesforce/label/c.AR_PMS_TjmPeriodsMissionUnknown";
import LBL_AR_PMS_TjmPeriodsExceed from "@salesforce/label/c.AR_PMS_TjmPeriodsExceed";
import LBL_AR_PMS_ThresholdCorridorEntity from "@salesforce/label/c.AR_PMS_ThresholdCorridorEntity";
import LBL_AR_PMS_FeeSmoothedSuffix from "@salesforce/label/c.AR_PMS_FeeSmoothedSuffix";
import LBL_AR_PMS_FeeMeals from "@salesforce/label/c.AR_PMS_FeeMeals";
import LBL_AR_PMS_FeeLodging from "@salesforce/label/c.AR_PMS_FeeLodging";
import LBL_AR_PMS_GratuityDays from "@salesforce/label/c.AR_PMS_GratuityDays";
import LBL_AR_PMS_FeeComputerPhone from "@salesforce/label/c.AR_PMS_FeeComputerPhone";
import LBL_AR_PMS_FeeTraining from "@salesforce/label/c.AR_PMS_FeeTraining";
import LBL_AR_PMS_FeeEPI from "@salesforce/label/c.AR_PMS_FeeEPI";
import LBL_AR_PMS_FeeOfiiTax from "@salesforce/label/c.AR_PMS_FeeOfiiTax";
import LBL_AR_PMS_RfaPercentLabel from "@salesforce/label/c.AR_PMS_RfaPercentLabel";
import LBL_AR_PMS_MissionDaysLabel from "@salesforce/label/c.AR_PMS_MissionDaysLabel";
import LBL_AR_PMS_AutoCalculatedTag from "@salesforce/label/c.AR_PMS_AutoCalculatedTag";
import LBL_AR_PMS_WorkingDaysHelper from "@salesforce/label/c.AR_PMS_WorkingDaysHelper";
import LBL_AR_PMS_CjmMc2Label from "@salesforce/label/c.AR_PMS_CjmMc2Label";
import LBL_AR_PMS_FeesOmDailyLabel from "@salesforce/label/c.AR_PMS_FeesOmDailyLabel";
import LBL_AR_PMS_ZoneDecisionTitle from "@salesforce/label/c.AR_PMS_ZoneDecisionTitle";
import LBL_AR_PMS_ProposedTjmLabel from "@salesforce/label/c.AR_PMS_ProposedTjmLabel";
import LBL_AR_PMS_NegoPrice2Label from "@salesforce/label/c.AR_PMS_NegoPrice2Label";
import LBL_AR_PMS_NegoPrice3Label from "@salesforce/label/c.AR_PMS_NegoPrice3Label";
import LBL_AR_PMS_NegoPriceHelp from "@salesforce/label/c.AR_PMS_NegoPriceHelp";
import LBL_AR_PMS_ClientGridLabel from "@salesforce/label/c.AR_PMS_ClientGridLabel";
import LBL_AR_PMS_ClientGridHelp from "@salesforce/label/c.AR_PMS_ClientGridHelp";
import LBL_AR_PMS_NegoPriceNotLower from "@salesforce/label/c.AR_PMS_NegoPriceNotLower";
import LBL_AR_PMS_NegoPriceNotLowerInter from "@salesforce/label/c.AR_PMS_NegoPriceNotLowerInter";
import LBL_AR_PMS_NegoPriceBelowFloor from "@salesforce/label/c.AR_PMS_NegoPriceBelowFloor";
import LBL_AR_PMS_NegoColPrice1 from "@salesforce/label/c.AR_PMS_NegoColPrice1";
import LBL_AR_PMS_NegoColPrice2 from "@salesforce/label/c.AR_PMS_NegoColPrice2";
import LBL_AR_PMS_NegoColPrice3 from "@salesforce/label/c.AR_PMS_NegoColPrice3";
import LBL_AR_PMS_NegoGaugeMarker2 from "@salesforce/label/c.AR_PMS_NegoGaugeMarker2";
import LBL_AR_PMS_NegoGaugeMarker3 from "@salesforce/label/c.AR_PMS_NegoGaugeMarker3";
import LBL_AR_PMS_NegoGaugeHover from "@salesforce/label/c.AR_PMS_NegoGaugeHover";
import LBL_AR_PMS_Mc2PerDayLabel from "@salesforce/label/c.AR_PMS_Mc2PerDayLabel";
import LBL_AR_PMS_InvoicedTjm from "@salesforce/label/c.AR_PMS_InvoicedTjm";
import LBL_AR_PMS_NetRevenueAfterRfa from "@salesforce/label/c.AR_PMS_NetRevenueAfterRfa";
import LBL_AR_PMS_MC2InsufficientTitle from "@salesforce/label/c.AR_PMS_MC2InsufficientTitle";
import LBL_AR_PMS_GaugeTitle from "@salesforce/label/c.AR_PMS_GaugeTitle";
import LBL_AR_PMS_GaugeNotPositionable from "@salesforce/label/c.AR_PMS_GaugeNotPositionable";
import LBL_AR_PMS_SaveDraftButton from "@salesforce/label/c.AR_PMS_SaveDraftButton";
import LBL_AR_PMS_EnterTjmToContinue from "@salesforce/label/c.AR_PMS_EnterTjmToContinue";
import LBL_AR_PMS_RequestDerogation from "@salesforce/label/c.AR_PMS_RequestDerogation";
import LBL_AR_PMS_ValidateMatrixButton from "@salesforce/label/c.AR_PMS_ValidateMatrixButton";
import LBL_AR_PMS_ValidatorFieldHelp from "@salesforce/label/c.AR_PMS_ValidatorFieldHelp";
import LBL_AR_PMS_SelectValidatorPlaceholder from "@salesforce/label/c.AR_PMS_SelectValidatorPlaceholder";
import LBL_AR_PMS_DerogationReasonsLabel from "@salesforce/label/c.AR_PMS_DerogationReasonsLabel";
import LBL_AR_PMS_FreeCommentLabel from "@salesforce/label/c.AR_PMS_FreeCommentLabel";
import LBL_AR_PMS_SendRequest from "@salesforce/label/c.AR_PMS_SendRequest";
import LBL_AR_PMS_ConfidenceHigh from "@salesforce/label/c.AR_PMS_ConfidenceHigh";
import LBL_AR_PMS_ConfidenceMedium from "@salesforce/label/c.AR_PMS_ConfidenceMedium";
import LBL_AR_PMS_ConfidenceLow from "@salesforce/label/c.AR_PMS_ConfidenceLow";
import LBL_AR_PMS_ContractTypeCDI from "@salesforce/label/c.AR_PMS_ContractTypeCDI";
import LBL_AR_PMS_ContractTypeCDD from "@salesforce/label/c.AR_PMS_ContractTypeCDD";
import LBL_AR_PMS_ContractTypeINDEP from "@salesforce/label/c.AR_PMS_ContractTypeINDEP";
import LBL_AR_PMS_ContractTypeVIE from "@salesforce/label/c.AR_PMS_ContractTypeVIE";
import LBL_AR_PMS_ContractTypeNEARSHORE from "@salesforce/label/c.AR_PMS_ContractTypeNEARSHORE";
import LBL_AR_PMS_SegmentBelowFloor from "@salesforce/label/c.AR_PMS_SegmentBelowFloor";
import LBL_AR_PMS_SegmentLowMargin from "@salesforce/label/c.AR_PMS_SegmentLowMargin";
import LBL_AR_PMS_SegmentRecommended from "@salesforce/label/c.AR_PMS_SegmentRecommended";
import LBL_AR_PMS_SegmentSuperstar from "@salesforce/label/c.AR_PMS_SegmentSuperstar";
import LBL_AR_PMS_ErrorOpeningRecord from "@salesforce/label/c.AR_PMS_ErrorOpeningRecord";
import LBL_AR_PMS_ErrorReadingConsultant from "@salesforce/label/c.AR_PMS_ErrorReadingConsultant";
import LBL_AR_PMS_Entity from "@salesforce/label/c.AR_PMS_Entity";
import LBL_AR_PMS_EntityChangeConfirmTitle from "@salesforce/label/c.AR_PMS_EntityChangeConfirmTitle";
import LBL_AR_PMS_EntityChangeConfirm from "@salesforce/label/c.AR_PMS_EntityChangeConfirm";
import LBL_AR_PMS_EntityChanged from "@salesforce/label/c.AR_PMS_EntityChanged";
import LBL_AR_PMS_Seniority from "@salesforce/label/c.AR_PMS_Seniority";
import LBL_AR_PMS_EndDate from "@salesforce/label/c.AR_PMS_EndDate";
import LBL_AR_PMS_NotFilledOnRecord from "@salesforce/label/c.AR_PMS_NotFilledOnRecord";
import LBL_AR_PMS_StatusNotRecognized from "@salesforce/label/c.AR_PMS_StatusNotRecognized";
import LBL_AR_PMS_EndDateMustBeAfterStart from "@salesforce/label/c.AR_PMS_EndDateMustBeAfterStart";
import LBL_AR_PMS_DateUnreadable from "@salesforce/label/c.AR_PMS_DateUnreadable";
import LBL_AR_PMS_DraftSaved from "@salesforce/label/c.AR_PMS_DraftSaved";
import LBL_AR_PMS_MatrixValidated from "@salesforce/label/c.AR_PMS_MatrixValidated";
import LBL_AR_PMS_MatrixNotFoundSaveFirst from "@salesforce/label/c.AR_PMS_MatrixNotFoundSaveFirst";
import LBL_AR_PMS_ErrorLoadingValidators from "@salesforce/label/c.AR_PMS_ErrorLoadingValidators";
import LBL_AR_PMS_NoPositionSelectedError from "@salesforce/label/c.AR_PMS_NoPositionSelectedError";
import LBL_AR_PMS_PositionAccessDeniedBanner from "@salesforce/label/c.AR_PMS_PositionAccessDeniedBanner";
import LBL_AR_PMS_ReadOnlyBanner from "@salesforce/label/c.AR_PMS_ReadOnlyBanner";
import LBL_AR_PMS_PositionAccessDeniedSaveError from "@salesforce/label/c.AR_PMS_PositionAccessDeniedSaveError";
import LBL_AR_PMS_DerogationRequiredFields from "@salesforce/label/c.AR_PMS_DerogationRequiredFields";
import LBL_AR_PMS_DerogationRequested from "@salesforce/label/c.AR_PMS_DerogationRequested";
import LBL_AR_PMS_MatrixDuplicated from "@salesforce/label/c.AR_PMS_MatrixDuplicated";
import LBL_AR_PMS_ResumeDraftBanner from "@salesforce/label/c.AR_PMS_ResumeDraftBanner";
import LBL_AR_PMS_Saving from "@salesforce/label/c.AR_PMS_Saving";
import LBL_AR_PMS_SavedAt from "@salesforce/label/c.AR_PMS_SavedAt";
import LBL_AR_PMS_Modified from "@salesforce/label/c.AR_PMS_Modified";
import LBL_AR_PMS_FieldFilled_Singular from "@salesforce/label/c.AR_PMS_FieldFilled_Singular";
import LBL_AR_PMS_FieldFilled_Plural from "@salesforce/label/c.AR_PMS_FieldFilled_Plural";
import LBL_AR_PMS_WeightMetier from "@salesforce/label/c.AR_PMS_WeightMetier";
import LBL_AR_PMS_WeightSecteur from "@salesforce/label/c.AR_PMS_WeightSecteur";
import LBL_AR_PMS_WeightClientPct from "@salesforce/label/c.AR_PMS_WeightClientPct";
import LBL_AR_PMS_NoCountrySpecified from "@salesforce/label/c.AR_PMS_NoCountrySpecified";
import LBL_AR_PMS_EntityCountryMissing from "@salesforce/label/c.AR_PMS_EntityCountryMissing";
import LBL_AR_PMS_EntityCountryMissingHelp from "@salesforce/label/c.AR_PMS_EntityCountryMissingHelp";
import LBL_AR_PMS_WeightedExplanation from "@salesforce/label/c.AR_PMS_WeightedExplanation";
import LBL_AR_PMS_Comparable_Singular from "@salesforce/label/c.AR_PMS_Comparable_Singular";
import LBL_AR_PMS_Comparable_Plural from "@salesforce/label/c.AR_PMS_Comparable_Plural";
import LBL_AR_PMS_Placement_Singular from "@salesforce/label/c.AR_PMS_Placement_Singular";
import LBL_AR_PMS_Placement_Plural from "@salesforce/label/c.AR_PMS_Placement_Plural";
import LBL_AR_PMS_ConfidenceExplanationNotEnough from "@salesforce/label/c.AR_PMS_ConfidenceExplanationNotEnough";
import LBL_AR_PMS_ConfidenceExplanationEnough from "@salesforce/label/c.AR_PMS_ConfidenceExplanationEnough";
import LBL_AR_PMS_ConfidenceDowngradedNote from "@salesforce/label/c.AR_PMS_ConfidenceDowngradedNote";
import LBL_AR_PMS_NoComparablePlacement from "@salesforce/label/c.AR_PMS_NoComparablePlacement";
import LBL_AR_PMS_LowConfidenceMessage from "@salesforce/label/c.AR_PMS_LowConfidenceMessage";
import LBL_AR_PMS_ConversionNote from "@salesforce/label/c.AR_PMS_ConversionNote";
import LBL_AR_PMS_Weighting from "@salesforce/label/c.AR_PMS_Weighting";
import LBL_AR_PMS_CjmCalculatedHelper from "@salesforce/label/c.AR_PMS_CjmCalculatedHelper";
import LBL_AR_PMS_MarkupFormulaLegend from "@salesforce/label/c.AR_PMS_MarkupFormulaLegend";
import LBL_AR_PMS_CjmTotalIndepPrefix from "@salesforce/label/c.AR_PMS_CjmTotalIndepPrefix";
import LBL_AR_PMS_CjmTotalIndepSuffix from "@salesforce/label/c.AR_PMS_CjmTotalIndepSuffix";
import LBL_AR_PMS_VieCjmEditableLabel from "@salesforce/label/c.AR_PMS_VieCjmEditableLabel";
import LBL_AR_PMS_VieCjmReadOnlyLabel from "@salesforce/label/c.AR_PMS_VieCjmReadOnlyLabel";
import LBL_AR_PMS_NearshoreCjmEditableLabel from "@salesforce/label/c.AR_PMS_NearshoreCjmEditableLabel";
import LBL_AR_PMS_NearshoreCjmReadOnlyLabel from "@salesforce/label/c.AR_PMS_NearshoreCjmReadOnlyLabel";
import LBL_AR_PMS_CjmRetainedPrefix from "@salesforce/label/c.AR_PMS_CjmRetainedPrefix";
import LBL_AR_PMS_NoMarkupCoeffSuffix from "@salesforce/label/c.AR_PMS_NoMarkupCoeffSuffix";
import LBL_AR_PMS_ReferentialNote from "@salesforce/label/c.AR_PMS_ReferentialNote";
import LBL_AR_PMS_ReferentialNoteNearshore from "@salesforce/label/c.AR_PMS_ReferentialNoteNearshore";
import LBL_AR_PMS_ReferentialGapLabel from "@salesforce/label/c.AR_PMS_ReferentialGapLabel";
import LBL_AR_PMS_ReferentialCurrencyMismatch from "@salesforce/label/c.AR_PMS_ReferentialCurrencyMismatch";
import LBL_AR_PMS_GratuityDetail from "@salesforce/label/c.AR_PMS_GratuityDetail";
import LBL_AR_PMS_FeePonctuelsIndep from "@salesforce/label/c.AR_PMS_FeePonctuelsIndep";
import LBL_AR_PMS_FeePonctuelsOther from "@salesforce/label/c.AR_PMS_FeePonctuelsOther";
import LBL_AR_PMS_FraisPonctuelsAnnuels from "@salesforce/label/c.AR_PMS_FraisPonctuelsAnnuels";
import LBL_AR_PMS_GratuiteClientAnnuelle from "@salesforce/label/c.AR_PMS_GratuiteClientAnnuelle";
import LBL_AR_PMS_OneTimeFeesYearFallback from "@salesforce/label/c.AR_PMS_OneTimeFeesYearFallback";
import LBL_AR_PMS_CostNotCalculableIndep from "@salesforce/label/c.AR_PMS_CostNotCalculableIndep";
import LBL_AR_PMS_CostNotCalculableVie from "@salesforce/label/c.AR_PMS_CostNotCalculableVie";
import LBL_AR_PMS_CostNotCalculableNearshore from "@salesforce/label/c.AR_PMS_CostNotCalculableNearshore";
import LBL_AR_PMS_CostNotCalculableDefault from "@salesforce/label/c.AR_PMS_CostNotCalculableDefault";
import LBL_AR_PMS_CostNotCalculableMessage from "@salesforce/label/c.AR_PMS_CostNotCalculableMessage";
import LBL_AR_PMS_DiscountVsTargetOver from "@salesforce/label/c.AR_PMS_DiscountVsTargetOver";
import LBL_AR_PMS_DiscountVsTargetUnder from "@salesforce/label/c.AR_PMS_DiscountVsTargetUnder";
import LBL_AR_PMS_BelowFloorMessage from "@salesforce/label/c.AR_PMS_BelowFloorMessage";
import LBL_AR_PMS_LowMarginMessage from "@salesforce/label/c.AR_PMS_LowMarginMessage";
import LBL_AR_PMS_RecommendedMessage from "@salesforce/label/c.AR_PMS_RecommendedMessage";
import LBL_AR_PMS_SuperstarMessage from "@salesforce/label/c.AR_PMS_SuperstarMessage";
import LBL_AR_PMS_FloorPercentLabel from "@salesforce/label/c.AR_PMS_FloorPercentLabel";
import LBL_AR_PMS_TargetPercentLabel from "@salesforce/label/c.AR_PMS_TargetPercentLabel";
import LBL_AR_PMS_IdealPercentLabel from "@salesforce/label/c.AR_PMS_IdealPercentLabel";
import LBL_AR_PMS_GrandCompteBanner from "@salesforce/label/c.AR_PMS_GrandCompteBanner";
import LBL_AR_PMS_ThresholdCjmLineCDI from "@salesforce/label/c.AR_PMS_ThresholdCjmLineCDI";
import LBL_AR_PMS_ThresholdCjmLineIndep from "@salesforce/label/c.AR_PMS_ThresholdCjmLineIndep";
import LBL_AR_PMS_ThresholdCjmLineVie from "@salesforce/label/c.AR_PMS_ThresholdCjmLineVie";
import LBL_AR_PMS_ThresholdCjmLineNearshore from "@salesforce/label/c.AR_PMS_ThresholdCjmLineNearshore";
import LBL_AR_PMS_ThresholdCostLineStandard from "@salesforce/label/c.AR_PMS_ThresholdCostLineStandard";
import LBL_AR_PMS_ThresholdCostLineOther from "@salesforce/label/c.AR_PMS_ThresholdCostLineOther";
import LBL_AR_PMS_ThresholdCorridorGrandCompte from "@salesforce/label/c.AR_PMS_ThresholdCorridorGrandCompte";
import LBL_AR_PMS_ThresholdCorridorStandard from "@salesforce/label/c.AR_PMS_ThresholdCorridorStandard";
import LBL_AR_PMS_ThresholdCorridorLine from "@salesforce/label/c.AR_PMS_ThresholdCorridorLine";
import LBL_AR_PMS_RfaImpact from "@salesforce/label/c.AR_PMS_RfaImpact";
import LBL_AR_PMS_GratuityImpact_Singular from "@salesforce/label/c.AR_PMS_GratuityImpact_Singular";
import LBL_AR_PMS_GratuityImpact_Plural from "@salesforce/label/c.AR_PMS_GratuityImpact_Plural";
import LBL_AR_PMS_NoRfaNoGratuity from "@salesforce/label/c.AR_PMS_NoRfaNoGratuity";
import LBL_AR_PMS_ThresholdsFormulaNote from "@salesforce/label/c.AR_PMS_ThresholdsFormulaNote";
import LBL_AR_PMS_GaugeActualLabel from "@salesforce/label/c.AR_PMS_GaugeActualLabel";
import LBL_AR_PMS_GaugeOutOfScaleSuffix from "@salesforce/label/c.AR_PMS_GaugeOutOfScaleSuffix";
import LBL_AR_PMS_GaugeTitleTjmSuffix from "@salesforce/label/c.AR_PMS_GaugeTitleTjmSuffix";
import LBL_AR_PMS_GradFloor from "@salesforce/label/c.AR_PMS_GradFloor";
import LBL_AR_PMS_GradTarget from "@salesforce/label/c.AR_PMS_GradTarget";
import LBL_AR_PMS_GradIdeal from "@salesforce/label/c.AR_PMS_GradIdeal";
import LBL_AR_PMS_GradCeiling from "@salesforce/label/c.AR_PMS_GradCeiling";
import LBL_AR_PMS_GaugeCostLabel from "@salesforce/label/c.AR_PMS_GaugeCostLabel";
import LBL_AR_PMS_GaugeMc2 from "@salesforce/label/c.AR_PMS_GaugeMc2";
import LBL_AR_PMS_GaugeZoneBelowFloor from "@salesforce/label/c.AR_PMS_GaugeZoneBelowFloor";
import LBL_AR_PMS_GaugeZoneLowMargin from "@salesforce/label/c.AR_PMS_GaugeZoneLowMargin";
import LBL_AR_PMS_GaugeZoneRecommended from "@salesforce/label/c.AR_PMS_GaugeZoneRecommended";
import LBL_AR_PMS_GaugeZoneSuperstar from "@salesforce/label/c.AR_PMS_GaugeZoneSuperstar";
import LBL_AR_PMS_GaugeLegendPrice from "@salesforce/label/c.AR_PMS_GaugeLegendPrice";
import LBL_AR_PMS_GaugeLegendNego from "@salesforce/label/c.AR_PMS_GaugeLegendNego";
import LBL_AR_PMS_GaugeLegendFloor from "@salesforce/label/c.AR_PMS_GaugeLegendFloor";
import LBL_AR_PMS_GaugeLegendTarget from "@salesforce/label/c.AR_PMS_GaugeLegendTarget";
import LBL_AR_PMS_GaugeLegendIdeal from "@salesforce/label/c.AR_PMS_GaugeLegendIdeal";
import LBL_AR_PMS_GaugeLegendSuperstar from "@salesforce/label/c.AR_PMS_GaugeLegendSuperstar";
import LBL_AR_PMS_GaugeCeilingNoMarketRef from "@salesforce/label/c.AR_PMS_GaugeCeilingNoMarketRef";
import LBL_AR_PMS_GaugeCeilingCurrencyMismatch from "@salesforce/label/c.AR_PMS_GaugeCeilingCurrencyMismatch";
import LBL_AR_PMS_GaugeCeilingBothAvailable from "@salesforce/label/c.AR_PMS_GaugeCeilingBothAvailable";
import LBL_AR_PMS_MarkupMismatch from "@salesforce/label/c.AR_PMS_MarkupMismatch";
import LBL_AR_PMS_StatusBannerLocked from "@salesforce/label/c.AR_PMS_StatusBannerLocked";
import LBL_AR_PMS_StatusBannerValidated from "@salesforce/label/c.AR_PMS_StatusBannerValidated";
import LBL_AR_Common_StatusValidated from "@salesforce/label/c.AR_Common_StatusValidated";
import LBL_AR_Common_StatusValidatedByDerogation from "@salesforce/label/c.AR_Common_StatusValidatedByDerogation";
import LBL_AR_Common_StatusInDerogation from "@salesforce/label/c.AR_Common_StatusInDerogation";
import LBL_AR_Common_StatusRejected from "@salesforce/label/c.AR_Common_StatusRejected";
import LBL_AR_PMS_DerogationRecall from "@salesforce/label/c.AR_PMS_DerogationRecall";
import LBL_AR_PMS_NoRateBanner from "@salesforce/label/c.AR_PMS_NoRateBanner";
import LBL_AR_PMS_MissingVieReferentialNoCountry from "@salesforce/label/c.AR_PMS_MissingVieReferentialNoCountry";
import LBL_AR_PMS_MissingVieReferentialWithCountry from "@salesforce/label/c.AR_PMS_MissingVieReferentialWithCountry";
import LBL_AR_PMS_MissingNearshoreReferentialNoCountry from "@salesforce/label/c.AR_PMS_MissingNearshoreReferentialNoCountry";
import LBL_AR_PMS_MissingNearshoreReferentialWithCountry from "@salesforce/label/c.AR_PMS_MissingNearshoreReferentialWithCountry";
import LBL_AR_PMS_CurrencyRateHelp from "@salesforce/label/c.AR_PMS_CurrencyRateHelp";
import LBL_AR_PMS_GrandCompteThresholdsLabel from "@salesforce/label/c.AR_PMS_GrandCompteThresholdsLabel";
import LBL_AR_PMS_EntityThresholdsLabel from "@salesforce/label/c.AR_PMS_EntityThresholdsLabel";
import LBL_AR_PMS_RecapFeeComputerMission from "@salesforce/label/c.AR_PMS_RecapFeeComputerMission";
import LBL_AR_PMS_NoAccountFallback from "@salesforce/label/c.AR_PMS_NoAccountFallback";
import LBL_AR_PMS_DuplicateSourcePositionLabel from "@salesforce/label/c.AR_PMS_DuplicateSourcePositionLabel";
import LBL_AR_PMS_MarketNoRateNote from "@salesforce/label/c.AR_PMS_MarketNoRateNote";
import LBL_AR_PMS_Mc2CostNotCalculable from "@salesforce/label/c.AR_PMS_Mc2CostNotCalculable";
import LBL_AR_PMS_Mc2AboveThreshold from "@salesforce/label/c.AR_PMS_Mc2AboveThreshold";
import LBL_AR_PMS_Mc2BelowThreshold from "@salesforce/label/c.AR_PMS_Mc2BelowThreshold";
import LBL_AR_PMS_Mc2ContextLine from "@salesforce/label/c.AR_PMS_Mc2ContextLine";
import LBL_AR_PMS_FeeComputer from "@salesforce/label/c.AR_PMS_FeeComputer";
import LBL_AR_PMS_FeePhone from "@salesforce/label/c.AR_PMS_FeePhone";
import LBL_AR_PMS_FeeOtherPerMission from "@salesforce/label/c.AR_PMS_FeeOtherPerMission";
import LBL_AR_PMS_RecapFeeComputer from "@salesforce/label/c.AR_PMS_RecapFeeComputer";
import LBL_AR_PMS_RecapFeePhone from "@salesforce/label/c.AR_PMS_RecapFeePhone";
import LBL_AR_PMS_RecapFeeMonthlyOther from "@salesforce/label/c.AR_PMS_RecapFeeMonthlyOther";
import LBL_AR_PMS_FeeMonthlyOther from "@salesforce/label/c.AR_PMS_FeeMonthlyOther";
import LBL_AR_PMS_FeeMonthlyOtherHelp from "@salesforce/label/c.AR_PMS_FeeMonthlyOtherHelp";
import LBL_AR_PMS_PlannedLeaveLabel from "@salesforce/label/c.AR_PMS_PlannedLeaveLabel";
import LBL_AR_PMS_BillableDays from "@salesforce/label/c.AR_PMS_BillableDays";
import LBL_AR_PMS_BillableDaysHelp from "@salesforce/label/c.AR_PMS_BillableDaysHelp";
import LBL_AR_PMS_LeaveExceedsMission from "@salesforce/label/c.AR_PMS_LeaveExceedsMission";
import LBL_AR_PMS_RecapFeeTraining from "@salesforce/label/c.AR_PMS_RecapFeeTraining";
import LBL_AR_PMS_RecapFeeMeals from "@salesforce/label/c.AR_PMS_RecapFeeMeals";
import LBL_AR_PMS_RecapFeeLodging from "@salesforce/label/c.AR_PMS_RecapFeeLodging";
import LBL_AR_PMS_RecapFeeOfiiTax from "@salesforce/label/c.AR_PMS_RecapFeeOfiiTax";
import LBL_AR_PMS_AnnualSalaryCdi from "@salesforce/label/c.AR_PMS_AnnualSalaryCdi";
import LBL_AR_PMS_FeeOtherDaily from "@salesforce/label/c.AR_PMS_FeeOtherDaily";
import LBL_AR_PMS_RecapFeeEpi from "@salesforce/label/c.AR_PMS_RecapFeeEpi";
import LBL_AR_PMS_RecapFeeOther from "@salesforce/label/c.AR_PMS_RecapFeeOther";
import LBL_AR_PMS_RecapFeeDay from "@salesforce/label/c.AR_PMS_RecapFeeDay";
import LBL_AR_PMS_RecapFeeMonth from "@salesforce/label/c.AR_PMS_RecapFeeMonth";
import LBL_AR_PMS_RecapFeeMission from "@salesforce/label/c.AR_PMS_RecapFeeMission";
import LBL_AR_PMS_RecapFeeMissionFallback from "@salesforce/label/c.AR_PMS_RecapFeeMissionFallback";
import LBL_AR_PMS_RecapFeeYear from "@salesforce/label/c.AR_PMS_RecapFeeYear";
import LBL_AR_PMS_RecapOfiiConversion from "@salesforce/label/c.AR_PMS_RecapOfiiConversion";
import LBL_AR_PMS_OfiiTaxHelp from "@salesforce/label/c.AR_PMS_OfiiTaxHelp";
import LBL_AR_PMS_OfiiTaxNotSet from "@salesforce/label/c.AR_PMS_OfiiTaxNotSet";
import LBL_AR_PMS_OfiiTaxMethod from "@salesforce/label/c.AR_PMS_OfiiTaxMethod";
import LBL_AR_PMS_OfiiTaxNoSalary from "@salesforce/label/c.AR_PMS_OfiiTaxNoSalary";
import LBL_AR_PMS_PositionPreviewStartDate from "@salesforce/label/c.AR_PMS_PositionPreviewStartDate";
import LBL_AR_PMS_CostBreakdownCjm from "@salesforce/label/c.AR_PMS_CostBreakdownCjm";
import LBL_AR_PMS_CostBreakdownFeeIk from "@salesforce/label/c.AR_PMS_CostBreakdownFeeIk";
import LBL_AR_PMS_OtherMissionFees from "@salesforce/label/c.AR_PMS_OtherMissionFees";
import LBL_AR_PMS_OtherFees from "@salesforce/label/c.AR_PMS_OtherFees";
import LBL_AR_PMS_GratuityDaysLabel from "@salesforce/label/c.AR_PMS_GratuityDaysLabel";
import LBL_AR_Common_PerYearSuffix from "@salesforce/label/c.AR_Common_PerYearSuffix";
import LBL_AR_PMS_CostOfSalesConfirmationTitle from "@salesforce/label/c.AR_PMS_CostOfSalesConfirmationTitle";
import LBL_AR_PMS_CostOfSalesDialogTitle from "@salesforce/label/c.AR_PMS_CostOfSalesDialogTitle";

import LBL_AR_Common_WarningTitle from "@salesforce/label/c.AR_Common_WarningTitle";
import LBL_AR_DRG_PanelTitle from "@salesforce/label/c.AR_DRG_PanelTitle";
import LBL_AR_PMS_ClosePanel from "@salesforce/label/c.AR_PMS_ClosePanel";
import LBL_AR_PMS_ConfidenceHighShort from "@salesforce/label/c.AR_PMS_ConfidenceHighShort";
import LBL_AR_PMS_ConfidenceMediumShort from "@salesforce/label/c.AR_PMS_ConfidenceMediumShort";
import LBL_AR_PMS_DerogationPending from "@salesforce/label/c.AR_PMS_DerogationPending";
import LBL_AR_PMS_DerogationPendingOpenQueue from "@salesforce/label/c.AR_PMS_DerogationPendingOpenQueue";
import LBL_AR_PMS_ExistingMatrixMany from "@salesforce/label/c.AR_PMS_ExistingMatrixMany";
import LBL_AR_PMS_ExistingMatrixOne from "@salesforce/label/c.AR_PMS_ExistingMatrixOne";
import LBL_AR_PMS_FieldsToComplete from "@salesforce/label/c.AR_PMS_FieldsToComplete";
import LBL_AR_PMS_HideNotification from "@salesforce/label/c.AR_PMS_HideNotification";
import LBL_AR_PMS_IndepTotalCostHelp from "@salesforce/label/c.AR_PMS_IndepTotalCostHelp";
import LBL_AR_PMS_IndepTotalCostPrefix from "@salesforce/label/c.AR_PMS_IndepTotalCostPrefix";
import LBL_AR_PMS_NearshoreReferentialNote from "@salesforce/label/c.AR_PMS_NearshoreReferentialNote";
import LBL_AR_PMS_NearshoreRateMissing from "@salesforce/label/c.AR_PMS_NearshoreRateMissing";
import LBL_AR_PMS_NearshoreRateApplied from "@salesforce/label/c.AR_PMS_NearshoreRateApplied";
import LBL_AR_PMS_NearshoreRateAppliedDefault from "@salesforce/label/c.AR_PMS_NearshoreRateAppliedDefault";
import LBL_AR_PMS_NearshoreRateAppliedDefaultOnly from "@salesforce/label/c.AR_PMS_NearshoreRateAppliedDefaultOnly";
import LBL_AR_ANR_SeniorityDefault from "@salesforce/label/c.AR_ANR_SeniorityDefault";
import LBL_AR_PMS_NeedAlreadyHasMatrix from "@salesforce/label/c.AR_PMS_NeedAlreadyHasMatrix";
import LBL_AR_PMS_PrerequisitesBlockingTitle from "@salesforce/label/c.AR_PMS_PrerequisitesBlockingTitle";
import LBL_AR_PMS_PrerequisitesWarningTitle from "@salesforce/label/c.AR_PMS_PrerequisitesWarningTitle";
import LBL_AR_PMS_PtfMightBeBlocked from "@salesforce/label/c.AR_PMS_PtfMightBeBlocked";
import LBL_AR_Msg_PM_MatrixGone from "@salesforce/label/c.AR_Msg_PM_MatrixGone";
import LBL_AR_PMS_PtfOnlyForValidated from "@salesforce/label/c.AR_PMS_PtfOnlyForValidated";
import LBL_AR_PMS_PtfUnavailableTitle from "@salesforce/label/c.AR_PMS_PtfUnavailableTitle";
import LBL_AR_PMS_RetainedCostPrefix from "@salesforce/label/c.AR_PMS_RetainedCostPrefix";
import LBL_AR_PMS_RfaLine from "@salesforce/label/c.AR_PMS_RfaLine";
import LBL_AR_PMS_StandardCorridor from "@salesforce/label/c.AR_PMS_StandardCorridor";
import LBL_AR_PMS_ValidationImpossible from "@salesforce/label/c.AR_PMS_ValidationImpossible";
import LBL_AR_PMS_VieReferentialNote from "@salesforce/label/c.AR_PMS_VieReferentialNote";
import LBL_AR_PMS_WithoutCoeffX2 from "@salesforce/label/c.AR_PMS_WithoutCoeffX2";
import LBL_AR_PTF_CreateAvenant from "@salesforce/label/c.AR_PTF_CreateAvenant";

const I18N = {
  AR_Common_Close: LBL_AR_Common_Close,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_WarningTitle: LBL_AR_Common_WarningTitle,
  AR_DRG_PanelTitle: LBL_AR_DRG_PanelTitle,
  AR_PMS_ClosePanel: LBL_AR_PMS_ClosePanel,
  AR_PMS_ConfidenceHighShort: LBL_AR_PMS_ConfidenceHighShort,
  AR_PMS_ConfidenceMediumShort: LBL_AR_PMS_ConfidenceMediumShort,
  AR_PMS_DerogationPending: LBL_AR_PMS_DerogationPending,
  AR_PMS_DerogationPendingOpenQueue: LBL_AR_PMS_DerogationPendingOpenQueue,
  AR_PMS_ExistingMatrixMany: LBL_AR_PMS_ExistingMatrixMany,
  AR_PMS_ExistingMatrixOne: LBL_AR_PMS_ExistingMatrixOne,
  AR_PMS_FieldsToComplete: LBL_AR_PMS_FieldsToComplete,
  AR_PMS_HideNotification: LBL_AR_PMS_HideNotification,
  AR_PMS_IndepTotalCostHelp: LBL_AR_PMS_IndepTotalCostHelp,
  AR_PMS_IndepTotalCostPrefix: LBL_AR_PMS_IndepTotalCostPrefix,
  AR_PMS_NearshoreReferentialNote: LBL_AR_PMS_NearshoreReferentialNote,
  AR_PMS_NearshoreRateMissing: LBL_AR_PMS_NearshoreRateMissing,
  AR_PMS_NearshoreRateApplied: LBL_AR_PMS_NearshoreRateApplied,
  AR_PMS_NearshoreRateAppliedDefault: LBL_AR_PMS_NearshoreRateAppliedDefault,
  AR_PMS_NearshoreRateAppliedDefaultOnly:
    LBL_AR_PMS_NearshoreRateAppliedDefaultOnly,
  AR_ANR_SeniorityDefault: LBL_AR_ANR_SeniorityDefault,
  AR_PMS_NeedAlreadyHasMatrix: LBL_AR_PMS_NeedAlreadyHasMatrix,
  AR_PMS_PrerequisitesBlockingTitle: LBL_AR_PMS_PrerequisitesBlockingTitle,
  AR_PMS_PrerequisitesWarningTitle: LBL_AR_PMS_PrerequisitesWarningTitle,
  AR_PMS_PtfMightBeBlocked: LBL_AR_PMS_PtfMightBeBlocked,
  AR_Msg_PM_MatrixGone: LBL_AR_Msg_PM_MatrixGone,
  AR_PMS_PtfOnlyForValidated: LBL_AR_PMS_PtfOnlyForValidated,
  AR_PMS_PtfUnavailableTitle: LBL_AR_PMS_PtfUnavailableTitle,
  AR_PMS_RetainedCostPrefix: LBL_AR_PMS_RetainedCostPrefix,
  AR_PMS_RfaLine: LBL_AR_PMS_RfaLine,
  AR_PMS_StandardCorridor: LBL_AR_PMS_StandardCorridor,
  AR_PMS_ValidationImpossible: LBL_AR_PMS_ValidationImpossible,
  AR_PMS_VieReferentialNote: LBL_AR_PMS_VieReferentialNote,
  AR_PMS_WithoutCoeffX2: LBL_AR_PMS_WithoutCoeffX2,
  AR_PTF_CreateAvenant: LBL_AR_PTF_CreateAvenant
};
const LABELS = {
  loading: LBL_AR_Common_Loading,
  duplicate: LBL_AR_Common_Duplicate,
  resume: LBL_AR_Common_Resume,
  dismiss: LBL_AR_Common_Dismiss,
  country: LBL_AR_Common_Country,
  contractTypeField: LBL_AR_Common_ContractTypeField,
  contact: LBL_AR_Common_Contact,
  createdOn: LBL_AR_Common_CreatedOn,
  view: LBL_AR_Common_View,
  openRecord: LBL_AR_Common_OpenRecord,
  consultant: LBL_AR_Common_Consultant,
  use: LBL_AR_Common_Use,
  close: LBL_AR_Common_Close,
  accountName: LBL_AR_Common_AccountName,
  position: LBL_AR_Common_Position,
  owner: LBL_AR_Common_Owner,
  confidence: LBL_AR_Common_Confidence,
  currency: LBL_AR_Common_Currency,
  other: LBL_AR_Common_Other,
  validator: LBL_AR_Common_Validator,
  cancel: LBL_AR_Common_Cancel,
  empty: LBL_AR_Common_Empty,
  notProvidedFem: LBL_AR_Common_NotProvided_Fem,
  errorTitle: LBL_AR_Common_ErrorTitle,
  successTitle: LBL_AR_Common_SuccessTitle,
  unknownError: LBL_AR_Common_UnknownError,
  perDaySuffix: LBL_AR_Common_PerDaySuffix,
  perDayLong: LBL_AR_Common_PerDayLong,
  positionSelectorTitle: LBL_AR_PMS_PositionSelectorTitle,
  positionSelectorSubtitle: LBL_AR_PMS_PositionSelectorSubtitle,
  searchPositionLabel: LBL_AR_PMS_SearchPositionLabel,
  searchPositionPlaceholder: LBL_AR_PMS_SearchPositionPlaceholder,
  noPositionResults: LBL_AR_PMS_NoPositionResults,
  loadingPreview: LBL_AR_PMS_LoadingPreview,
  openAccountRecordAriaLabel: LBL_AR_PMS_OpenAccountRecordAriaLabel,
  businessSector: LBL_AR_PMS_BusinessSector,
  perimeter: LBL_AR_PMS_Perimeter,
  createMatrixFromPosition: LBL_AR_PMS_CreateMatrixFromPosition,
  noPositionSelectedTitle: LBL_AR_PMS_NoPositionSelectedTitle,
  noPositionSelectedHelp: LBL_AR_PMS_NoPositionSelectedHelp,
  zoneContextTitle: LBL_AR_PMS_ZoneContextTitle,
  zoneContextSubtitle: LBL_AR_PMS_ZoneContextSubtitle,
  entityLabel: LBL_AR_PMS_EntityLabel,
  selectEntityPlaceholder: LBL_AR_PMS_SelectEntityPlaceholder,
  changeConsultant: LBL_AR_PMS_ChangeConsultant,
  searchConsultantPlaceholder: LBL_AR_PMS_SearchConsultantPlaceholder,
  noConsultantResults: LBL_AR_PMS_NoConsultantResults,
  suggestedFromApplication: LBL_AR_PMS_SuggestedFromApplication,
  legacyTextPrefix: LBL_AR_PMS_LegacyTextPrefix,
  clickForDetails: LBL_AR_PMS_ClickForDetails,
  prefillSuccess: LBL_AR_PMS_PrefillSuccess,
  prefillFromRecord: LBL_AR_PMS_PrefillFromRecord,
  undoPrefill: LBL_AR_PMS_UndoPrefill,
  managerName: LBL_AR_PMS_ManagerName,
  clientSite: LBL_AR_PMS_ClientSite,
  clientSitePlaceholder: LBL_AR_PMS_ClientSitePlaceholder,
  startDate: LBL_AR_PMS_StartDate,
  expectedEndDate: LBL_AR_PMS_ExpectedEndDate,
  marketReferenceTitle: LBL_AR_PMS_MarketReferenceTitle,
  marketInfoAriaLabel: LBL_AR_PMS_MarketInfoAriaLabel,
  marketInfoModalAriaLabel: LBL_AR_PMS_MarketInfoModalAriaLabel,
  marketInfoModalTitle: LBL_AR_PMS_MarketInfoModalTitle,
  pool: LBL_AR_PMS_Pool,
  last12Months: LBL_AR_PMS_Last12Months,
  weightedEffective: LBL_AR_PMS_WeightedEffective,
  pipelineHistoryTitle: LBL_AR_PMS_PipelineHistoryTitle,
  pipelineHistoryPrefix: LBL_AR_PMS_PipelineHistoryPrefix,
  won: LBL_AR_PMS_Won,
  pipelineHistorySuffix: LBL_AR_PMS_PipelineHistorySuffix,
  pipelineFiltersTitle: LBL_AR_PMS_PipelineFiltersTitle,
  noCountryNoComparables: LBL_AR_PMS_NoCountryNoComparables,
  pipelineAlgorithmTitle: LBL_AR_PMS_PipelineAlgorithmTitle,
  metier: LBL_AR_PMS_Metier,
  secteur: LBL_AR_PMS_Secteur,
  client: LBL_AR_PMS_Client,
  pipelineThresholdTitle: LBL_AR_PMS_PipelineThresholdTitle,
  highConfidenceSuffix: LBL_AR_PMS_HighConfidenceSuffix,
  mediumConfidenceSuffix: LBL_AR_PMS_MediumConfidenceSuffix,
  lowConfidenceSuffix: LBL_AR_PMS_LowConfidenceSuffix,
  effectiveWeightedLine: LBL_AR_PMS_EffectiveWeightedLine,
  pipelineFinalCalcTitle: LBL_AR_PMS_PipelineFinalCalcTitle,
  pipelineFinalCalcText: LBL_AR_PMS_PipelineFinalCalcText,
  seniorityNote: LBL_AR_PMS_SeniorityNote,
  modalFooterNote: LBL_AR_PMS_ModalFooterNote,
  loadingMarketRefs: LBL_AR_PMS_LoadingMarketRefs,
  comparables: LBL_AR_PMS_Comparables,
  medianTjm: LBL_AR_PMS_MedianTjm,
  top10Percent: LBL_AR_PMS_Top10Percent,
  zoneFinancialContextTitle: LBL_AR_PMS_ZoneFinancialContextTitle,
  thresholdsInfoAriaLabel: LBL_AR_PMS_ThresholdsInfoAriaLabel,
  costPerDayTerm: LBL_AR_PMS_CostPerDayTerm,
  totalDailyCost: LBL_AR_PMS_TotalDailyCost,
  tjmThresholdsTerm: LBL_AR_PMS_TjmThresholdsTerm,
  rfaAndFreeTerm: LBL_AR_PMS_RfaAndFreeTerm,
  contractStatus: LBL_AR_PMS_ContractStatus,
  seniorityLevel: LBL_AR_PMS_SeniorityLevel,
  annualSalary: LBL_AR_PMS_AnnualSalary,
  annualSalaryCdi: LBL_AR_PMS_AnnualSalaryCdi,
  decimalStepError: LBL_AR_Common_DecimalStepError,
  cjmBeforeMarkup: LBL_AR_PMS_CjmBeforeMarkup,
  markupCalculated: LBL_AR_PMS_MarkupCalculated,
  markupApplied: LBL_AR_PMS_MarkupApplied,
  vieCountry: LBL_AR_PMS_VieCountry,
  selectCountryPlaceholder: LBL_AR_PMS_SelectCountryPlaceholder,
  rfaInheritedFrom: LBL_AR_PMS_RfaInheritedFrom,
  rfaReadFailed: LBL_AR_PMS_RfaReadFailed,
  vieCountryWarning: LBL_AR_PMS_VieCountryWarning,
  nearshoreCountry: LBL_AR_PMS_NearshoreCountry,
  nearshoreCountryWarning: LBL_AR_PMS_NearshoreCountryWarning,
  feesOmToggle: LBL_AR_PMS_FeesOmToggle,
  feeIK: LBL_AR_PMS_FeeIK,
  feePeriodAdd: LBL_AR_PMS_FeePeriodAdd,
  salaryPeriodAdd: LBL_AR_PMS_SalaryPeriodAdd,
  salaryPeriodSalary: LBL_AR_PMS_SalaryPeriodSalary,
  cjmWeightedLabel: LBL_AR_PMS_CjmWeightedLabel,
  costBreakdownCjmWeighted: LBL_AR_PMS_CostBreakdownCjmWeighted,
  salaryPeriodTooltipLine: LBL_AR_PMS_SalaryPeriodTooltipLine,
  feePeriodRemove: LBL_AR_PMS_FeePeriodRemove,
  feePeriodTitle: LBL_AR_PMS_FeePeriodTitle,
  feePeriodDays: LBL_AR_PMS_FeePeriodDays,
  feePeriodFirstCalc: LBL_AR_PMS_FeePeriodFirstCalc,
  feePeriodFirstUnknown: LBL_AR_PMS_FeePeriodFirstUnknown,
  feePeriodExceed: LBL_AR_PMS_FeePeriodExceed,
  feePeriodRecapLabel: LBL_AR_PMS_FeePeriodRecapLabel,
  feePeriodShort: LBL_AR_PMS_FeePeriodShort,
  feePeriodCaption: LBL_AR_PMS_FeePeriodCaption,
  tjmPeriodsOpenLink: LBL_AR_PMS_TjmPeriodsOpenLink,
  tjmPeriodsEdit: LBL_AR_PMS_TjmPeriodsEdit,
  rplsrProductionGap: LBL_AR_PMS_RplsrProductionGap,
  rplsrGapCaption: LBL_AR_PMS_RplsrGapCaption,
  rplsrClassic: LBL_AR_PMS_RplsrClassic,
  rplsrClassicTitle: LBL_AR_PMS_RplsrClassicTitle,
  rplsrPlanInvalid: LBL_AR_Msg_PM_RplsrPlanInvalid,
  tjmPeriodsCloseLink: LBL_AR_PMS_TjmPeriodsCloseLink,
  tjmTimelineStart: LBL_AR_PMS_TjmTimelineStart,
  tjmTimelineEnd: LBL_AR_PMS_TjmTimelineEnd,
  tjmPeriodFirstRow: LBL_AR_PMS_TjmPeriodFirstRow,
  tjmPeriodFirstRowUnknown: LBL_AR_PMS_TjmPeriodFirstRowUnknown,
  tjmPeriodRowTitle: LBL_AR_PMS_TjmPeriodRowTitle,
  tjmPeriodRemove: LBL_AR_PMS_TjmPeriodRemove,
  tjmPeriodAdd: LBL_AR_PMS_TjmPeriodAdd,
  tjmPeriodTjmAria: LBL_AR_PMS_TjmPeriodTjmAria,
  tjmPeriodDaysAria: LBL_AR_PMS_TjmPeriodDaysAria,
  tjmPeriodDaysUnit: LBL_AR_PMS_TjmPeriodDaysUnit,
  tjmWeightedFooter: LBL_AR_PMS_TjmWeightedFooter,
  tjmWeightedGaugeTitle: LBL_AR_PMS_TjmWeightedGaugeTitle,
  tjmPeriodsMissionUnknown: LBL_AR_PMS_TjmPeriodsMissionUnknown,
  tjmPeriodsExceed: LBL_AR_PMS_TjmPeriodsExceed,
  thresholdCorridorEntity: LBL_AR_PMS_ThresholdCorridorEntity,
  feeSmoothedSuffix: LBL_AR_PMS_FeeSmoothedSuffix,
  feeMeals: LBL_AR_PMS_FeeMeals,
  feeLodging: LBL_AR_PMS_FeeLodging,
  gratuityDays: LBL_AR_PMS_GratuityDays,
  feeComputerPhone: LBL_AR_PMS_FeeComputerPhone,
  feeTraining: LBL_AR_PMS_FeeTraining,
  feeEPI: LBL_AR_PMS_FeeEPI,
  feeOfiiTax: LBL_AR_PMS_FeeOfiiTax,
  rfaPercentLabel: LBL_AR_PMS_RfaPercentLabel,
  missionDaysLabel: LBL_AR_PMS_MissionDaysLabel,
  autoCalculatedTag: LBL_AR_PMS_AutoCalculatedTag,
  workingDaysHelper: LBL_AR_PMS_WorkingDaysHelper,
  cjmMc2Label: LBL_AR_PMS_CjmMc2Label,
  feesOmDailyLabel: LBL_AR_PMS_FeesOmDailyLabel,
  zoneDecisionTitle: LBL_AR_PMS_ZoneDecisionTitle,
  proposedTjmLabel: LBL_AR_PMS_ProposedTjmLabel,
  negoPrice2Label: LBL_AR_PMS_NegoPrice2Label,
  negoPrice3Label: LBL_AR_PMS_NegoPrice3Label,
  negoPriceHelp: LBL_AR_PMS_NegoPriceHelp,
  clientGridLabel: LBL_AR_PMS_ClientGridLabel,
  clientGridHelp: LBL_AR_PMS_ClientGridHelp,
  negoPriceNotLower: LBL_AR_PMS_NegoPriceNotLower,
  negoPriceNotLowerInter: LBL_AR_PMS_NegoPriceNotLowerInter,
  negoPriceBelowFloor: LBL_AR_PMS_NegoPriceBelowFloor,
  negoColPrice1: LBL_AR_PMS_NegoColPrice1,
  negoColPrice2: LBL_AR_PMS_NegoColPrice2,
  negoColPrice3: LBL_AR_PMS_NegoColPrice3,
  negoGaugeMarker2: LBL_AR_PMS_NegoGaugeMarker2,
  negoGaugeMarker3: LBL_AR_PMS_NegoGaugeMarker3,
  negoGaugeHover: LBL_AR_PMS_NegoGaugeHover,
  mc2PerDayLabel: LBL_AR_PMS_Mc2PerDayLabel,
  invoicedTjm: LBL_AR_PMS_InvoicedTjm,
  netRevenueAfterRfa: LBL_AR_PMS_NetRevenueAfterRfa,
  mc2InsufficientTitle: LBL_AR_PMS_MC2InsufficientTitle,
  gaugeTitle: LBL_AR_PMS_GaugeTitle,
  gaugeNotPositionable: LBL_AR_PMS_GaugeNotPositionable,
  saveDraftButton: LBL_AR_PMS_SaveDraftButton,
  enterTjmToContinue: LBL_AR_PMS_EnterTjmToContinue,
  requestDerogation: LBL_AR_PMS_RequestDerogation,
  validateMatrixButton: LBL_AR_PMS_ValidateMatrixButton,
  validatorFieldHelp: LBL_AR_PMS_ValidatorFieldHelp,
  selectValidatorPlaceholder: LBL_AR_PMS_SelectValidatorPlaceholder,
  derogationReasonsLabel: LBL_AR_PMS_DerogationReasonsLabel,
  freeCommentLabel: LBL_AR_PMS_FreeCommentLabel,
  sendRequest: LBL_AR_PMS_SendRequest,
  confidenceHigh: LBL_AR_PMS_ConfidenceHigh,
  confidenceMedium: LBL_AR_PMS_ConfidenceMedium,
  confidenceLow: LBL_AR_PMS_ConfidenceLow,
  contractTypeCDI: LBL_AR_PMS_ContractTypeCDI,
  contractTypeCDD: LBL_AR_PMS_ContractTypeCDD,
  contractTypeINDEP: LBL_AR_PMS_ContractTypeINDEP,
  contractTypeVIE: LBL_AR_PMS_ContractTypeVIE,
  contractTypeNEARSHORE: LBL_AR_PMS_ContractTypeNEARSHORE,
  segmentBelowFloor: LBL_AR_PMS_SegmentBelowFloor,
  segmentLowMargin: LBL_AR_PMS_SegmentLowMargin,
  segmentRecommended: LBL_AR_PMS_SegmentRecommended,
  segmentSuperstar: LBL_AR_PMS_SegmentSuperstar,
  errorOpeningRecord: LBL_AR_PMS_ErrorOpeningRecord,
  errorReadingConsultant: LBL_AR_PMS_ErrorReadingConsultant,
  entity: LBL_AR_PMS_Entity,
  entityChangeConfirmTitle: LBL_AR_PMS_EntityChangeConfirmTitle,
  entityChangeConfirm: LBL_AR_PMS_EntityChangeConfirm,
  entityChanged: LBL_AR_PMS_EntityChanged,
  seniority: LBL_AR_PMS_Seniority,
  endDate: LBL_AR_PMS_EndDate,
  notFilledOnRecord: LBL_AR_PMS_NotFilledOnRecord,
  statusNotRecognized: LBL_AR_PMS_StatusNotRecognized,
  endDateMustBeAfterStart: LBL_AR_PMS_EndDateMustBeAfterStart,
  dateUnreadable: LBL_AR_PMS_DateUnreadable,
  draftSaved: LBL_AR_PMS_DraftSaved,
  matrixValidated: LBL_AR_PMS_MatrixValidated,
  matrixNotFoundSaveFirst: LBL_AR_PMS_MatrixNotFoundSaveFirst,
  errorLoadingValidators: LBL_AR_PMS_ErrorLoadingValidators,
  noPositionSelectedError: LBL_AR_PMS_NoPositionSelectedError,
  positionAccessDeniedBanner: LBL_AR_PMS_PositionAccessDeniedBanner,
  readOnlyBanner: LBL_AR_PMS_ReadOnlyBanner,
  positionAccessDeniedSaveError: LBL_AR_PMS_PositionAccessDeniedSaveError,
  derogationRequiredFields: LBL_AR_PMS_DerogationRequiredFields,
  derogationRequested: LBL_AR_PMS_DerogationRequested,
  matrixDuplicated: LBL_AR_PMS_MatrixDuplicated,
  resumeDraftBanner: LBL_AR_PMS_ResumeDraftBanner,
  saving: LBL_AR_PMS_Saving,
  savedAt: LBL_AR_PMS_SavedAt,
  modified: LBL_AR_PMS_Modified,
  fieldFilledSingular: LBL_AR_PMS_FieldFilled_Singular,
  fieldFilledPlural: LBL_AR_PMS_FieldFilled_Plural,
  weightMetier: LBL_AR_PMS_WeightMetier,
  weightSecteur: LBL_AR_PMS_WeightSecteur,
  weightClientPct: LBL_AR_PMS_WeightClientPct,
  noCountrySpecified: LBL_AR_PMS_NoCountrySpecified,
  entityCountryMissing: LBL_AR_PMS_EntityCountryMissing,
  entityCountryMissingHelp: LBL_AR_PMS_EntityCountryMissingHelp,
  weightedExplanation: LBL_AR_PMS_WeightedExplanation,
  comparableSingular: LBL_AR_PMS_Comparable_Singular,
  comparablePlural: LBL_AR_PMS_Comparable_Plural,
  placementSingular: LBL_AR_PMS_Placement_Singular,
  placementPlural: LBL_AR_PMS_Placement_Plural,
  confidenceExplanationNotEnough: LBL_AR_PMS_ConfidenceExplanationNotEnough,
  confidenceExplanationEnough: LBL_AR_PMS_ConfidenceExplanationEnough,
  confidenceDowngradedNote: LBL_AR_PMS_ConfidenceDowngradedNote,
  noComparablePlacement: LBL_AR_PMS_NoComparablePlacement,
  lowConfidenceMessage: LBL_AR_PMS_LowConfidenceMessage,
  conversionNote: LBL_AR_PMS_ConversionNote,
  weighting: LBL_AR_PMS_Weighting,
  cjmCalculatedHelper: LBL_AR_PMS_CjmCalculatedHelper,
  markupFormulaLegend: LBL_AR_PMS_MarkupFormulaLegend,
  cjmTotalIndepPrefix: LBL_AR_PMS_CjmTotalIndepPrefix,
  cjmTotalIndepSuffix: LBL_AR_PMS_CjmTotalIndepSuffix,
  vieCjmEditableLabel: LBL_AR_PMS_VieCjmEditableLabel,
  vieCjmReadOnlyLabel: LBL_AR_PMS_VieCjmReadOnlyLabel,
  nearshoreCjmEditableLabel: LBL_AR_PMS_NearshoreCjmEditableLabel,
  nearshoreCjmReadOnlyLabel: LBL_AR_PMS_NearshoreCjmReadOnlyLabel,
  cjmRetainedPrefix: LBL_AR_PMS_CjmRetainedPrefix,
  noMarkupCoeffSuffix: LBL_AR_PMS_NoMarkupCoeffSuffix,
  referentialNote: LBL_AR_PMS_ReferentialNote,
  referentialNoteNearshore: LBL_AR_PMS_ReferentialNoteNearshore,
  referentialGapLabel: LBL_AR_PMS_ReferentialGapLabel,
  referentialCurrencyMismatch: LBL_AR_PMS_ReferentialCurrencyMismatch,
  gratuityDetail: LBL_AR_PMS_GratuityDetail,
  feePonctuelsIndep: LBL_AR_PMS_FeePonctuelsIndep,
  feePonctuelsOther: LBL_AR_PMS_FeePonctuelsOther,
  fraisPonctuelsAnnuels: LBL_AR_PMS_FraisPonctuelsAnnuels,
  gratuiteClientAnnuelle: LBL_AR_PMS_GratuiteClientAnnuelle,
  oneTimeFeesYearFallback: LBL_AR_PMS_OneTimeFeesYearFallback,
  costNotCalculableIndep: LBL_AR_PMS_CostNotCalculableIndep,
  costNotCalculableVie: LBL_AR_PMS_CostNotCalculableVie,
  costNotCalculableNearshore: LBL_AR_PMS_CostNotCalculableNearshore,
  costNotCalculableDefault: LBL_AR_PMS_CostNotCalculableDefault,
  costNotCalculableMessage: LBL_AR_PMS_CostNotCalculableMessage,
  discountVsTargetOver: LBL_AR_PMS_DiscountVsTargetOver,
  discountVsTargetUnder: LBL_AR_PMS_DiscountVsTargetUnder,
  belowFloorMessage: LBL_AR_PMS_BelowFloorMessage,
  lowMarginMessage: LBL_AR_PMS_LowMarginMessage,
  recommendedMessage: LBL_AR_PMS_RecommendedMessage,
  superstarMessage: LBL_AR_PMS_SuperstarMessage,
  floorPercentLabel: LBL_AR_PMS_FloorPercentLabel,
  targetPercentLabel: LBL_AR_PMS_TargetPercentLabel,
  idealPercentLabel: LBL_AR_PMS_IdealPercentLabel,
  grandCompteBanner: LBL_AR_PMS_GrandCompteBanner,
  thresholdCjmLineCDI: LBL_AR_PMS_ThresholdCjmLineCDI,
  thresholdCjmLineIndep: LBL_AR_PMS_ThresholdCjmLineIndep,
  thresholdCjmLineVie: LBL_AR_PMS_ThresholdCjmLineVie,
  thresholdCjmLineNearshore: LBL_AR_PMS_ThresholdCjmLineNearshore,
  thresholdCostLineStandard: LBL_AR_PMS_ThresholdCostLineStandard,
  thresholdCostLineOther: LBL_AR_PMS_ThresholdCostLineOther,
  thresholdCorridorGrandCompte: LBL_AR_PMS_ThresholdCorridorGrandCompte,
  thresholdCorridorStandard: LBL_AR_PMS_ThresholdCorridorStandard,
  thresholdCorridorLine: LBL_AR_PMS_ThresholdCorridorLine,
  rfaImpact: LBL_AR_PMS_RfaImpact,
  gratuityImpactSingular: LBL_AR_PMS_GratuityImpact_Singular,
  gratuityImpactPlural: LBL_AR_PMS_GratuityImpact_Plural,
  noRfaNoGratuity: LBL_AR_PMS_NoRfaNoGratuity,
  thresholdsFormulaNote: LBL_AR_PMS_ThresholdsFormulaNote,
  gaugeActualLabel: LBL_AR_PMS_GaugeActualLabel,
  gaugeOutOfScaleSuffix: LBL_AR_PMS_GaugeOutOfScaleSuffix,
  gaugeTitleTjmSuffix: LBL_AR_PMS_GaugeTitleTjmSuffix,
  gradFloor: LBL_AR_PMS_GradFloor,
  gradTarget: LBL_AR_PMS_GradTarget,
  gradIdeal: LBL_AR_PMS_GradIdeal,
  gradCeiling: LBL_AR_PMS_GradCeiling,
  gaugeCostLabel: LBL_AR_PMS_GaugeCostLabel,
  gaugeMc2: LBL_AR_PMS_GaugeMc2,
  gaugeZoneBelowFloor: LBL_AR_PMS_GaugeZoneBelowFloor,
  gaugeZoneLowMargin: LBL_AR_PMS_GaugeZoneLowMargin,
  gaugeZoneRecommended: LBL_AR_PMS_GaugeZoneRecommended,
  gaugeZoneSuperstar: LBL_AR_PMS_GaugeZoneSuperstar,
  gaugeLegendPrice: LBL_AR_PMS_GaugeLegendPrice,
  gaugeLegendNego: LBL_AR_PMS_GaugeLegendNego,
  gaugeLegendFloor: LBL_AR_PMS_GaugeLegendFloor,
  gaugeLegendTarget: LBL_AR_PMS_GaugeLegendTarget,
  gaugeLegendIdeal: LBL_AR_PMS_GaugeLegendIdeal,
  gaugeLegendSuperstar: LBL_AR_PMS_GaugeLegendSuperstar,
  gaugeCeilingNoMarketRef: LBL_AR_PMS_GaugeCeilingNoMarketRef,
  gaugeCeilingCurrencyMismatch: LBL_AR_PMS_GaugeCeilingCurrencyMismatch,
  gaugeCeilingBothAvailable: LBL_AR_PMS_GaugeCeilingBothAvailable,
  markupMismatch: LBL_AR_PMS_MarkupMismatch,
  statusBannerLocked: LBL_AR_PMS_StatusBannerLocked,
  statusBannerValidated: LBL_AR_PMS_StatusBannerValidated,
  statusValidated: LBL_AR_Common_StatusValidated,
  statusValidatedByDerogation: LBL_AR_Common_StatusValidatedByDerogation,
  statusInDerogation: LBL_AR_Common_StatusInDerogation,
  statusRejected: LBL_AR_Common_StatusRejected,
  derogationRecall: LBL_AR_PMS_DerogationRecall,
  noRateBanner: LBL_AR_PMS_NoRateBanner,
  missingVieReferentialNoCountry: LBL_AR_PMS_MissingVieReferentialNoCountry,
  missingVieReferentialWithCountry: LBL_AR_PMS_MissingVieReferentialWithCountry,
  missingNearshoreReferentialNoCountry:
    LBL_AR_PMS_MissingNearshoreReferentialNoCountry,
  missingNearshoreReferentialWithCountry:
    LBL_AR_PMS_MissingNearshoreReferentialWithCountry,
  currencyRateHelp: LBL_AR_PMS_CurrencyRateHelp,
  grandCompteThresholdsLabel: LBL_AR_PMS_GrandCompteThresholdsLabel,
  entityThresholdsLabel: LBL_AR_PMS_EntityThresholdsLabel,
  noAccountFallback: LBL_AR_PMS_NoAccountFallback,
  duplicateSourcePositionLabel: LBL_AR_PMS_DuplicateSourcePositionLabel,
  marketNoRateNote: LBL_AR_PMS_MarketNoRateNote,
  mc2CostNotCalculable: LBL_AR_PMS_Mc2CostNotCalculable,
  mc2AboveThreshold: LBL_AR_PMS_Mc2AboveThreshold,
  mc2BelowThreshold: LBL_AR_PMS_Mc2BelowThreshold,
  mc2ContextLine: LBL_AR_PMS_Mc2ContextLine,
  feeComputer: LBL_AR_PMS_FeeComputer,
  feePhone: LBL_AR_PMS_FeePhone,
  feeOtherPerMission: LBL_AR_PMS_FeeOtherPerMission,
  feeOtherDaily: LBL_AR_PMS_FeeOtherDaily,
  recapFeeComputer: LBL_AR_PMS_RecapFeeComputer,
  recapFeePhone: LBL_AR_PMS_RecapFeePhone,
  recapFeeMonthlyOther: LBL_AR_PMS_RecapFeeMonthlyOther,
  feeMonthlyOther: LBL_AR_PMS_FeeMonthlyOther,
  feeMonthlyOtherHelp: LBL_AR_PMS_FeeMonthlyOtherHelp,
  plannedLeaveLabel: LBL_AR_PMS_PlannedLeaveLabel,
  billableDays: LBL_AR_PMS_BillableDays,
  billableDaysHelp: LBL_AR_PMS_BillableDaysHelp,
  leaveExceedsMission: LBL_AR_PMS_LeaveExceedsMission,
  recapFeeTraining: LBL_AR_PMS_RecapFeeTraining,
  recapFeeMeals: LBL_AR_PMS_RecapFeeMeals,
  recapFeeLodging: LBL_AR_PMS_RecapFeeLodging,
  recapFeeOfiiTax: LBL_AR_PMS_RecapFeeOfiiTax,
  recapFeeEpi: LBL_AR_PMS_RecapFeeEpi,
  recapFeeOther: LBL_AR_PMS_RecapFeeOther,
  recapFeeDay: LBL_AR_PMS_RecapFeeDay,
  recapFeeComputerMission: LBL_AR_PMS_RecapFeeComputerMission,
  recapFeeMonth: LBL_AR_PMS_RecapFeeMonth,
  recapFeeMission: LBL_AR_PMS_RecapFeeMission,
  recapFeeMissionFallback: LBL_AR_PMS_RecapFeeMissionFallback,
  recapFeeYear: LBL_AR_PMS_RecapFeeYear,
  recapOfiiConversion: LBL_AR_PMS_RecapOfiiConversion,
  ofiiTaxHelp: LBL_AR_PMS_OfiiTaxHelp,
  ofiiTaxNotSet: LBL_AR_PMS_OfiiTaxNotSet,
  ofiiTaxMethod: LBL_AR_PMS_OfiiTaxMethod,
  ofiiTaxNoSalary: LBL_AR_PMS_OfiiTaxNoSalary,
  positionPreviewStartDate: LBL_AR_PMS_PositionPreviewStartDate,
  costBreakdownCjm: LBL_AR_PMS_CostBreakdownCjm,
  costBreakdownFeeIk: LBL_AR_PMS_CostBreakdownFeeIk,
  otherMissionFees: LBL_AR_PMS_OtherMissionFees,
  otherFees: LBL_AR_PMS_OtherFees,
  gratuityDaysLabel: LBL_AR_PMS_GratuityDaysLabel,
  perYearSuffix: LBL_AR_Common_PerYearSuffix,
  costOfSalesConfirmationTitle: LBL_AR_PMS_CostOfSalesConfirmationTitle,
  costOfSalesDialogTitle: LBL_AR_PMS_CostOfSalesDialogTitle
};

function formatLabel(template, ...args) {
  return args.reduce((acc, val, i) => acc.split(`{${i}}`).join(val), template);
}

// Montant saisi dans le récapitulatif : sans décimales quand il est entier (« 1 650 € »), sinon à 2 décimales.
function formatEnteredAmount(value, currencyCode) {
  return Number.isInteger(Number(value))
    ? formatMoney(value, currencyCode)
    : formatMoneyPrecise(value, currencyCode);
}

// Nombre de jours affiché sans décimale inutile (« 218 », « 21,5 »).
function formatDays(value) {
  return Number(value).toLocaleString("fr-FR", { maximumFractionDigits: 2 });
}

// Périodes de TJM (docs/254) : au plus 3 périodes ajoutées (4 TJM au total, P1 comprise) ; au-delà, un avenant.
const MAX_ADDED_TJM_PERIODS = 3;
// Panneau de périodes compact : délai d'intention avant dépliage au survol, délai hors du bloc avant repli,
// durée du dépliage rapide (compact → ouvert).
const TJM_HOVER_INTENT_MS = 100;
const TJM_HOVER_LEAVE_MS = 8000;
const TJM_QUICK_EXPAND_MS = 300;

// Débounce de l'autosauvegarde silencieuse (session 13) : 20s après la dernière frappe, jamais de toast.
const AUTOSAVE_DEBOUNCE_MS = 20000;

// Palier de séniorité : source de vérité unique = cxsrec__cxsCandidate__c.TP_Seniority__c, filtré au
// record type Consultant (seules ces valeurs sont proposées, jamais le picklist complet non filtré).
// Séniorité « Défaut » d'une ligne du référentiel Nearshore : valeur technique, cf. AR_PricingMatrixService.
const NEARSHORE_DEFAULT_SENIORITY = "DEFAULT";
const SENIORITY_OBJECT_API_NAME = "cxsrec__cxsCandidate__c";
const SENIORITY_RECORD_TYPE_ID = "01209000000NPmDAAW";

// Jauge : mise en page en pixels réels (étage des prix au-dessus de la piste, étage des seuils dessous).
const GAUGE_FALLBACK_TRACK_WIDTH_PX = 1000;
const GAUGE_FALLBACK_CHAR_WIDTH_PX = 7;
const GAUGE_LABEL_GAP_PX = 8;
const GAUGE_PILL_HEIGHT_PX = 24;
const GAUGE_PILL_LEVEL_STEP_PX = 30;
const GAUGE_PILL_LANE_PADDING_PX = 16;
const GAUGE_PILL_PADDING_PX = 22;
const GAUGE_TRACK_HEIGHT_PX = 12;
const GAUGE_RULER_LEVEL_STEP_PX = 38;
const GAUGE_RULER_TICK_PX = 8;
const GAUGE_RULER_LABEL_PADDING_PX = 8;
const GAUGE_RULER_HELP_ICON_PX = 18;

const GAUGE_ZONE_PILL_CLASS = {
  below_floor: "gauge-zone-pill gauge-zone-pill-below-floor",
  low_margin: "gauge-zone-pill gauge-zone-pill-low-margin",
  recommended: "gauge-zone-pill gauge-zone-pill-recommended",
  superstar: "gauge-zone-pill gauge-zone-pill-superstar"
};

const STATUS_BANNER_META = {
  Validée: "status-banner-validated",
  "En dérogation": "status-banner-pending",
  "Validée par dérogation": "status-banner-derog",
  Refusée: "status-banner-rejected"
};

// Statuts reconnus (session 28b §1) : un statut absent/inconnu venu du serveur (trouvé sur
// AR_PricingMatrixService.saveDraftInput, qui ne renvoyait pas AR_Status__c pour un Brouillon
// existant resauvegardé) est une anomalie technique, jamais une décision métier — il ne doit jamais
// verrouiller le formulaire ni s'afficher tel quel à l'utilisateur (cf. isEditable/
// setStatusFromServer). Dérivé de STATUS_BANNER_META pour ne jamais lister les statuts décidés à
// deux endroits qui pourraient diverger.
const KNOWN_STATUSES = ["Brouillon", ...Object.keys(STATUS_BANNER_META)];

/**
 * Date de fin proposée par défaut (session 141) : le 31/12 de l'année de la date de début. Calcul sur
 * la chaîne `YYYY-MM-DD`, jamais via un objet Date JS (décalage de fuseau : `new Date("2026-12-31")`
 * est minuit UTC, donc le 30/12 en soirée côté Amériques). Retourne null si la date de début est
 * absente ou illisible — rien n'est alors proposé.
 */
function defaultEndDateFor(startDate) {
  if (typeof startDate !== "string" || !/^\d{4}-\d{2}-\d{2}/.test(startDate)) {
    return null;
  }
  return `${startDate.slice(0, 4)}-12-31`;
}

const CONFIDENCE_LABELS = {
  high: LABELS.confidenceHigh,
  medium: LABELS.confidenceMedium,
  low: LABELS.confidenceLow
};

const CONTRACT_TYPE_OPTIONS = [
  { label: LABELS.contractTypeCDI, value: "CDI" },
  { label: LABELS.contractTypeCDD, value: "CDD" },
  { label: LABELS.contractTypeINDEP, value: "INDEP" },
  { label: LABELS.contractTypeVIE, value: "VIE" },
  { label: LABELS.contractTypeNEARSHORE, value: "NEARSHORE" }
];

const CURRENCY_OPTIONS = [
  { label: "EUR", value: "EUR" },
  { label: "GBP", value: "GBP" },
  { label: "CHF", value: "CHF" },
  { label: "CAD", value: "CAD" },
  { label: "MAD", value: "MAD" }
];

const SEGMENT_META = {
  below_floor: {
    label: LABELS.segmentBelowFloor,
    cssClass: "segment-pill segment-pill-red",
    valueClass: "value-red"
  },
  low_margin: {
    label: LABELS.segmentLowMargin,
    cssClass: "segment-pill segment-pill-amber",
    valueClass: "value-amber"
  },
  recommended: {
    label: LABELS.segmentRecommended,
    cssClass: "segment-pill segment-pill-green",
    valueClass: "value-green"
  },
  // Session 155 : vert foncé distinct du vert clair de « recommended » (retour client 07/10 : rouge /
  // orange / vert clair / vert foncé).
  superstar: {
    label: LABELS.segmentSuperstar,
    cssClass: "segment-pill segment-pill-green-dark",
    valueClass: "value-green-dark"
  }
};

/** Classe de couleur d'un repère P2/P3 : même segment que la MC2 du panier (sources : SEGMENT_META). */
function negoSegmentSuffix(segment) {
  if (segment === "below_floor") {
    return " gauge-nego-below-floor";
  }
  return segment === "low_margin" ? " gauge-nego-low-margin" : "";
}

let gaugeMeasureContext;

/** Largeur d'un texte en pixels : canvas 2D quand la piste est mesurée, 7 px par caractère sinon (Jest). */
function measureGaugeText(text, weight, sizePx, fontFamily, useCanvas) {
  const fallback = text.length * GAUGE_FALLBACK_CHAR_WIDTH_PX;
  if (!useCanvas || typeof document === "undefined") {
    return fallback;
  }
  if (gaugeMeasureContext === undefined) {
    const canvas = document.createElement("canvas");
    gaugeMeasureContext = canvas.getContext ? canvas.getContext("2d") : null;
  }
  if (!gaugeMeasureContext) {
    return fallback;
  }
  gaugeMeasureContext.font = `${weight} ${sizePx}px ${fontFamily}`;
  return gaugeMeasureContext.measureText(text).width;
}

/**
 * Étagement d'étiquettes sur une piste de `trackWidth` px : chaque boîte est centrée sur son repère
 * (ou collée au bord demandé), bornée à [0, trackWidth], puis prend le premier niveau où elle ne
 * chevauche aucune boîte déjà placée (écart mini `gap`). Renvoie les éléments triés par position,
 * enrichis de `boxLeft`, `boxRight`, `level`, et le nombre de niveaux occupés (au moins 1).
 */
function stageGaugeLabels(items, trackWidth, gap) {
  const rows = [];
  const placed = items
    .map((item) => {
      const width = Math.min(item.width, trackWidth);
      const boxLeft = Math.max(
        0,
        Math.min(trackWidth - width, item.x - width / 2)
      );
      return { ...item, width, boxLeft, boxRight: boxLeft + width };
    })
    .sort((a, b) => a.x - b.x);
  placed.forEach((item) => {
    let level = 0;
    while (
      rows[level] &&
      rows[level].some(
        (other) =>
          item.boxLeft < other.boxRight + gap &&
          item.boxRight + gap > other.boxLeft
      )
    ) {
      level++;
    }
    rows[level] = rows[level] || [];
    rows[level].push(item);
    item.level = level;
  });
  return { placed, levelCount: Math.max(1, rows.length) };
}

const FEE_FIELDS = [
  "annualSalary",
  "cjmBeforeMarkup",
  "markupApplied",
  "cjmVie",
  "cjmNearshore",
  "feeIk",
  "feeMeals",
  "feeLodging",
  "feeOmOther",
  "gratuityDays",
  "feeComputer",
  "feePhone",
  "feeMonthlyOther",
  "feeTraining",
  "feeEpi",
  "feeOfiiTax",
  "feeOther",
  "rfaPercent",
  "proposedTjm",
  "negoPrice2",
  "negoPrice3",
  "clientGrid"
];

// Zone 1 — champs mission (session 17, cf. docs/17-contexte-affaire.md) : synchronisés avec FEE_FIELDS
// dans buildMatrixInput, distingués ici pour que leur origine (Zone 1, pas Zone 2) reste lisible.
// Session 54 : "consultantName" (texte libre) remplacé par "consultantId" (Lookup) — seul le second
// est désormais envoyé à la sauvegarde. consultantName reste un champ de classe, mais purement en
// lecture (écho de l'ancienne valeur, cf. applyInput), jamais renvoyé au serveur.
const MISSION_FIELDS = [
  "entity",
  "consultantId",
  "clientSite",
  "startDate",
  "endDate",
  "numberOfDays",
  "plannedLeaveDays"
];

// Pays retenus dans les référentiels VIE/Nearshore (session 18) : traçabilité, cf. docs/18-referentiels-statuts.md.
// Palier de séniorité (session 28) ajouté à ce même groupe : traçabilité identique.
const REFERENTIAL_FIELDS = [
  "vieCountryId",
  "nearshoreCountryId",
  "seniorityLevel"
];

// Drapeaux des sélecteurs pays VIE/Nearshore (session 18, maquette pricing-tool.html:1925/1954) :
// décoration côté client uniquement — ni AR_VIE_Referential__c ni AR_Nearshore_Referential__c n'ont
// de champ drapeau (seuls Name et le montant journalier existent, cf. session 2 et
// docs/18-referentiels-statuts.md). Couvre les pays actuellement seedés ; tout pays absent de cette
// liste retombe sur 🌍 plutôt que de casser l'affichage.
const COUNTRY_FLAGS = {
  France: "🇫🇷",
  Italie: "🇮🇹",
  Suisse: "🇨🇭",
  Espagne: "🇪🇸",
  Belgique: "🇧🇪",
  "Pays-Bas": "🇳🇱",
  Allemagne: "🇩🇪",
  "Royaume-Uni": "🇬🇧",
  Maroc: "🇲🇦",
  Tunisie: "🇹🇳",
  Roumanie: "🇷🇴",
  Pologne: "🇵🇱",
  Portugal: "🇵🇹",
  Inde: "🇮🇳",
  Bulgarie: "🇧🇬",
  Ukraine: "🇺🇦"
};

function countryFlag(country) {
  return COUNTRY_FLAGS[country] || "🌍";
}

// Statuts « décidés » (session 22) : dupliquer depuis l'un de ces statuts enregistre la filiation
// et exige un motif (AR_MatrixChainService.duplicateMatrix) — jamais depuis un Brouillon, où la
// duplication reste une copie libre. Le refus n'est pas laissé orphelin : la chaîne 480 € refusé
// → 520 € validé est la donnée la plus utile du dispositif.
const CHAIN_SOURCE_STATUSES = ["Validée", "Validée par dérogation", "Refusée"];

/** « Repas (€/jour) » → { main: "Repas", unit: " (€/jour)" } ; sans parenthèse finale, tout va dans main. */
function splitUnitLabel(text) {
  const m = /^(.*?)(\s*\([^()]*\))$/.exec(text || "");
  return m ? { main: m[1], unit: m[2] } : { main: text || "", unit: "" };
}

export default class ArPriceMatrixSimulator extends NavigationMixin(
  LightningElement
) {
  i18n = I18N;

  @api recordId;
  // Session 113 : "ptf" = arrivée par le bouton PTF de « Mes matrices » → arPtfPanel défile jusqu'à
  // lui et ouvre le formulaire de génération si aucune PTF n'existe encore.
  @api focusSection;

  labels = LABELS;

  uniqueComponentId;
  _modalPortaled = false;

  contractTypeOptions = CONTRACT_TYPE_OPTIONS;
  currencyOptions = CURRENCY_OPTIONS;

  isLoading = true;
  errorMessage;

  matrixId;
  positionId;
  positionLocked = false;
  status = "Brouillon";

  positionSearchTerm = "";
  positionSearchResults = [];
  showPositionDropdown = false;
  isSearchingPositions = false;
  selectedPositionPreview = null;
  selectedPositionId = null;
  isLoadingPositionPreview = false;

  positionContext = {};
  // Session 167 : le besoin lié n'est pas visible de l'utilisateur (partage) — bandeau d'accès partiel
  // et toute écriture bloquée. Le serveur refuse de toute façon (requireAccessiblePositionContext).
  positionAccessDenied = false;
  // Session 282 : matrice vue sans droit de modification (partage d'agence, viewAll) — lecture seule.
  // Lu sur le serveur (UserRecordAccess.HasEditAccess via getMatrixInput), jamais déduit ici.
  readOnlyAccess = false;
  readOnlyOwnerName;
  creatorName;
  settings = { workingDaysPerYear: 218, markupPercent: 18, markupMax: 60 };
  // Session 48 : Map<Id de la fiche d'entité (session 132, plus le nom), { coefficient, workingDays }> — niveau entité de la cascade,
  // fusionné avec `settings` ci-dessus dans recompute(), jamais utilisé seul.
  entityPricingDefaults = new Map();
  corridorPercents = null;
  // Dernier calcul persisté sur l'enregistrement (session 23b, cf. AR_PricingMatrixService.MatrixInput.storedResult).
  // `null` pour une matrice pas encore créée ; jamais réutilisé sur un Brouillon (cf. applyFrozenCalculationIfDecided).
  _storedResult = null;
  // MC2 % de la matrice amendée, pour un avenant en Brouillon seulement (AR_PricingMatrixService.MatrixInput.
  // avenantMc2Before) : la dérogation d'un avenant se décide sur une baisse de MC2, pas sur le plancher.
  _avenantMc2Before = null;
  marketReference;
  isLoadingMarketReference = false;

  // Taux de change courants (session 24, non-EUR uniquement — cf. AR_CurrencyRateService).
  // `rateResolution` : dernière résolution pour `currencyCode` (rateToEur/effectiveDate), ou `null`
  // si la devise n'a aucun taux — auquel cas `noRateAvailable` bloque la saisie côté client, même
  // garde-fou que le blocage serveur dans AR_PricingMatrixService.calculateAndPopulate.
  currentRates = [];
  rateResolution = { rateToEur: 1, effectiveDate: null };
  noRateAvailable = false;

  currencyCode = "EUR";
  contractType = "CDI";
  annualSalary;
  cjmBeforeMarkup;
  markupApplied;
  cjmVie;
  cjmNearshore;
  feeIk;
  feeMeals;
  feeLodging;
  feeOmOther;
  // Périodes de frais OM ajoutées à la période 1 (docs/239) : une ligne par période, clé stable pour le rendu.
  feePeriods = [];
  nextFeePeriodKey = 1;
  // Périodes de salaire ajoutées (CDI/CDD) : la période 1 reste le champ Salaire annuel.
  salaryPeriods = [];
  nextSalaryPeriodKey = 1;
  // Périodes de TJM ajoutées à la période 1 (docs/254) : `proposedTjm` reste le TJM de la période 1.
  tjmPeriods = [];
  nextTjmPeriodKey = 1;
  tjmPeriodsOpen = false;
  // Régie sans régule (docs/265) : mode, jours facturés par mois et jours produits par mois ({"2027-02": 9}) ;
  // `rplsrProduced` null = répartition équilibrée. `_rplsrStoredPlan` : plan enregistré, seul affiché en lecture seule.
  rplsrEnabled = false;
  rplsrDaysPerMonth = null;
  rplsrProduced = null;
  _rplsrStoredPlan = null;
  // Phase transitoire de l'animation du cadre (« opening » / « closing »), vide hors animation.
  tjmPhase = "";
  _tjmPhaseTimer;
  _tjmMeasuredLabel;
  // Sous-état de l'état ouvert : frise seule, lignes et barre Début/Fin repliées.
  tjmCompact = false;
  tjmQuick = false;
  _tjmExpandedByHover = false;
  _tjmFieldFocused = false;
  _tjmPointerInside = false;
  _tjmIntentTimer;
  _tjmLeaveTimer;
  // Colonnes P2/P3 du panier (session 268) : même mécanique que le panneau des périodes de TJM.
  negoOpen = false;
  _negoPointerInside = false;
  _negoFieldFocused = false;
  _negoIntentTimer;
  _negoLeaveTimer;
  gratuityDays;
  feeComputer;
  feePhone;
  feeMonthlyOther;
  feeTraining;
  feeEpi;
  feeOfiiTax;
  feeOther;
  rfaPercent = 0;
  rfaInheritanceNote; // Session 146b : affichée si la RFA est héritée du parent
  rfaReadWarning; // Session 146c : échec de lecture de la RFA par défaut (non bloquant)
  proposedTjm;
  // Prix de négociation 2 et 3 : indicatifs, jamais validés ni envoyés au calcul serveur.
  negoPrice2;
  negoPrice3;
  // Saisies en cours (session 276) : liées au template tant que le champ n'est pas validé, pour qu'un rendu
  // déclenché par le repli du panier (pointerdown avant blur) ne réécrive pas la valeur DOM.
  _negoDraft = {};
  // Tarif imposé par une grille client : prix intermédiaire et plancher non demandés.
  clientGrid = false;

  // Zone 1 — champs mission (session 17).
  entityOptions = [];
  entity;
  isChangingEntity = false;
  entityName;
  // Session 54 : consultantName reste l'écho en LECTURE SEULE de l'ancien texte libre
  // (AR_Consultant_Name__c, jamais réécrit) — affiché seulement pour les quelques matrices qui le
  // portaient déjà (cf. displayConsultantName). consultantId/consultantLabel sont la paire éditable
  // (Lookup), alimentée par la recherche ci-dessous.
  consultantName;
  consultantId;
  consultantLabel;
  // Suggestion de pré-remplissage depuis la candidature pressentie (AR_Job_Application__c) —
  // jamais appliquée automatiquement, cf. handleUseSuggestedConsultant.
  suggestedConsultantId;
  suggestedConsultantLabel;
  consultantSearchTerm = "";
  consultantSearchResults = [];
  showConsultantDropdown = false;
  isSearchingConsultants = false;
  // Session 65 : pré-remplissage à la sélection du consultant — snapshot de l'état avant remplissage
  // pour permettre l'annulation, et bandeau listant les champs modifiés avec anciennes/nouvelles valeurs.
  prefillSnapshot;
  showPrefillBanner = false;
  showPrefillDetails = false;
  prefillBannerItems = [];
  prefillConsultantLabel;
  // Session 118 : URLs générées pour les liens cliquables (consultant, client, manager, besoin)
  consultantUrl;
  clientUrl;
  managerUrl;
  besoinUrl;
  clientSite;
  startDate;
  endDate;
  numberOfDays;
  // Congés prévus : retranchés des jours de mission (jours facturables), ignorés en régie sans régule.
  plannedLeaveDays;
  // `true` uniquement quand numberOfDays vient d'être recalculé depuis les dates (pas au chargement
  // d'une matrice existante : une valeur enregistrée est traitée comme fixée par l'utilisateur tant
  // qu'il ne retouche pas les dates, sinon un F5 écraserait silencieusement une saisie manuelle).
  numberOfDaysAuto = false;
  // Session 117 : drapeau pour éviter de recalculer les jours ouvrés si l'utilisateur a saisi le
  // nombre manuellement dans la session courante. Réinitialisé à chaque chargement de brouillon.
  numberOfDaysManuallyEdited = false;
  // Session 141 : saisies manuelles de la session courante, jamais écrasées par un pré-remplissage
  // (même mécanique que numberOfDaysManuallyEdited).
  endDateManuallyEdited = false;
  clientSiteManuallyEdited = false;
  missionDateError = "";
  // Date de mission vide ou illisible : message sous les champs (cf. readDateInput).
  dateInputError = "";

  // Référentiels VIE/Nearshore (session 18) : options brutes (id/pays/cjm) conservées pour
  // retrouver le pays sélectionné (label, montant de référence, écart), pas seulement pour peupler
  // le combobox.
  vieReferentialOptions = [];
  nearshoreReferentialOptions = [];
  vieCountryId;
  nearshoreCountryId;
  // Pays Nearshore choisi (le référentiel porte une ligne par pays et séniorité : l'id appliqué en
  // découle). nearshoreRateMissing : message bloquant quand aucune ligne ne s'applique.
  nearshoreChosenCountry = null;
  nearshoreRateMissing = null;

  // Palier de séniorité : {label, value} au format lightning-combobox, peuplé depuis le picklist
  // cxsrec__cxsCandidate__c.TP_Seniority__c filtré au record type Consultant (wiredSeniorityPicklist
  // ci-dessous) — jamais le picklist complet non filtré. `seniorityLevel` porte directement la
  // valeur du picklist (plus d'Id à résoudre en libellé séparément, contrairement à l'ancien
  // référentiel AR_ : ici value/label du picklist sont la même donnée) — transmise telle quelle à
  // AR_ComparablesService.getMarketReference, sans dépendre de seniorityLevelOptions déjà chargé.
  seniorityLevelOptions = [];
  seniorityLevel = null;

  // Session 112 : dérogation en attente (panel "Traiter la dérogation")
  pendingDerogation = null;
  pendingDerogationDate = "";

  // getPicklistValuesByRecordType est un wire adapter UI API (ESLint @salesforce/eslint-config-lwc
  // interdit son appel impératif) : ne peuple que la liste d'options affichées, jamais une donnée
  // dont un autre appel dépendrait — pas de couplage d'ordre avec connectedCallback à gérer ici.
  @wire(getPicklistValuesByRecordType, {
    objectApiName: SENIORITY_OBJECT_API_NAME,
    recordTypeId: SENIORITY_RECORD_TYPE_ID
  })
  wiredSeniorityPicklist({ data }) {
    if (data) {
      this.seniorityLevelOptions = (
        data.picklistFieldValues.TP_Seniority__c.values || []
      ).map((v) => ({ label: v.label, value: v.value }));
    }
  }

  calc = {
    cjm: 0,
    feeOmPerDay: 0,
    feePonctuelsPerDay: 0,
    totalDailyCost: 0,
    tjmFloor: 0,
    tjmTarget: 0,
    tjmIdeal: 0,
    tjmTop10: 0,
    mc2PerDay: 0,
    mc2PercentHuman: 0,
    corridorSegment: null
  };
  get gaugePosition() {
    return calcGaugePosition(
      this.effectiveTjm || 0,
      this.gaugeThresholdsContext
    );
  }

  set gaugePosition(_value) {
    // Ignore assignment attempts - gaugePosition is computed dynamically
    // This setter exists to prevent "Cannot set property" errors from legacy code
  }

  showDerogationModal = false;
  // Session 156 : _derogationReasonDraft stocke la saisie de commentaire sans déclencher
  // de re-rendu (> 4500 lignes) — ne se lit qu'au clic (Envoyer).
  _derogationReasonDraft = "";
  // Session 220 : vrai dès que le commentaire contient du texte (espaces seuls = vide). Mis à jour
  // seulement au passage vide ↔ rempli, jamais à chaque frappe.
  hasDerogationComment = false;
  // Session 156b : derogationReasonIds (réactif) remplace _derogationReasonIdsDraft pour que
  // le getter isDerogationSendDisabled() se réévalue au changement de sélection.
  derogationReasonIds = [];
  derogationValidatorId;
  validatorOptions = [];
  derogationValidationError; // Session 79 : message d'erreur de blocage DA/DD
  isDerogationButtonDisabled = false; // Session 79 : désactive le bouton si blocage
  isSaving = false;
  // Session 157 : « calcul en attente » levé dès qu'une saisie entre dans le calcul, baissé par
  // recompute(). Tant qu'il est levé, Valider est désactivé (fail-safe : si recompute() lève, il reste levé).
  _calcPending = false;
  // Session 157 : compteur de saisies utilisateur (setDirty(true)). Une réponse de sauvegarde dont le
  // compteur d'envoi diffère du compteur courant porte un calcul périmé : elle ne remplace pas le local.
  _inputRevision = 0;
  // Vrai quand la taxe OFII suivait le calcul mais qu'il est devenu impossible (salaire vidé) : elle reprend la valeur calculée dès que le salaire revient.
  _ofiiFollowsWhenCalculable = false;

  // Duplication / chaîne de négociation (session 22).
  showDuplicateModal = false;
  // Avenant piloté par la matrice (session 180c).
  showAvenantModal = false;

  // Protection des saisies (session 13, cf. docs/13-navigation-etat.md).
  _isDirty = false;
  _beforeUnloadRegistered = false;
  lastAutosaveAt;
  // État affiché par l'indicateur d'autosauvegarde (session 39, cf. prompts/session-39-...md §1) :
  // "dirty" (modifié, pas encore enregistré) / "saving" (appel en cours) / "saved" (dernier
  // enregistrement réussi, avec lastAutosaveAt). `undefined` tant qu'aucune modification n'a eu
  // lieu depuis l'ouverture du composant — l'indicateur reste alors masqué (cf. showAutosaveIndicator).
  // Ne survit jamais à un rechargement de page (pas de source serveur pour "dernier enregistrement",
  // cf. le constat de session 39 : un F5 réinitialise légitimement cet état, ce n'est pas le défaut).
  _autosaveState;
  draftResumeInfo;

  // Explicabilité du calcul (session 14, cf. docs/14-seuils-explicabilite.md).
  showMarketInfoPopover = false;
  showThresholdsInfoPopover = false;
  _popoverListenersRegistered = false;
  _marketPopoverFocused = false;
  _thresholdsPopoverFocused = false;
  _lastFocusedTrigger;
  draftBannerDismissed = false;

  // Session 107 : vérification des prérequis avant validation/dérogation PTF
  validationPrerequisitesMissing = []; // Liste des Prerequisite manquants
  validationPrerequisitesWarnings = []; // Session 108 : besoin/entité, non bloquants
  showValidationPrerequisitesPanel = false; // Affiche le panneau de blocage

  // Session 184a2 : avertissement « le besoin a déjà des matrices » — bandeau dans la page, fermé
  // uniquement par l'utilisateur (le toast sticky d'origine n'était pas visible en navigateur).
  existingMatricesMessage = null;

  async connectedCallback() {
    document.addEventListener("pointerdown", this.handleDocumentPointerDown);
    window.addEventListener("resize", this.handleWindowResize);
    try {
      // Session 74 : ID unique pour le portage optionnel du DOM de la popup
      this.uniqueComponentId = crypto.randomUUID();

      this.settings = await getPricingSettings();
      this.currentRates = await getCurrentRates();
      this.entityOptions = (await getEntityOptions()).map((opt) => ({
        label: opt.label,
        value: opt.value,
        country: opt.country
      }));
      this.entityPricingDefaults = new Map(
        (await getEntityPricingDefaults()).map((d) => [
          d.entityId,
          {
            coefficient: d.coefficient,
            workingDays: d.workingDays,
            country: d.country
          }
        ])
      );
      this.vieReferentialOptions = await getVieReferentialOptions();
      this.nearshoreReferentialOptions = await getNearshoreReferentialOptions();
      if (this.recordId) {
        // Arrivée avec un contexte explicite (quick action besoin ou matrice existante,
        // via "Mes matrices") : le besoin est déjà déterminé et non modifiable ici.
        const ctx = await resolveRecordContext({ anyId: this.recordId });
        this.positionId = ctx.positionId;
        this.updateBesoinUrl();
        this.announceMatrixId(ctx.matrixId);
        this.positionLocked = true;
        if (!ctx.matrixId) {
          // Non attendu : l'avertissement ne retarde pas l'ouverture de la matrice.
          this.warnIfPositionHasMatrices(ctx.positionId);
        }
      }

      // Réhydratation AVANT le chargement des repères marché (session 28b §2) : applyInput() fixe
      // contractType/seniorityLevel/currencyCode depuis la matrice réellement chargée.
      // loadPositionContext() ci-dessous appelle loadMarketReference(), qui lit ces trois champs sur
      // `this` — dans l'ordre inverse (constaté en navigateur), une matrice CDD rouverte affichait
      // les repères CDI par défaut du composant (jamais rafraîchis ensuite, une seule fois par
      // ouverture) : un CDD réel montrait "271 comparables, confiance élevée" au lieu de
      // "historique insuffisant". Aucune dépendance en sens inverse : loadPositionContext() ne lit
      // que positionId/matrixId (déjà résolus ci-dessus), jamais un champ posé par applyInput().
      if (this.matrixId) {
        const input = await getMatrixInput({ matrixId: this.matrixId });
        this.applyInput(input);
        this.applyAccess(input);
        this._storedResult = input.storedResult || null;
        this.loadWonBadge();
      } else {
        // Matrice pas encore créée : Zone 1 "Propriétaire" = le créateur à venir, l'utilisateur courant.
        this.creatorName = await getCurrentUserName();
        this._storedResult = null;
      }

      if (this.positionId) {
        await this.loadPositionContext();
      }

      // Bandeau de reprise : uniquement à l'arrivée sans aucun contexte (ni besoin, ni matrice
      // déjà déterminés) — une quick action ou un lien vers une matrice précise a la priorité.
      if (!this.recordId) {
        await this.loadDraftResumeInfo();
      }

      this.recompute();
      this.applyFrozenCalculationIfDecided();
      // Session 112 : encart « Traiter la dérogation ». Volontairement NON attendu : l'encart est
      // accessoire et ne doit ni retarder la fin du chargement de la matrice (isLoading) ni la faire
      // échouer — loadPendingDerogation gère seul ses erreurs (repli fail-closed, console.error).
      if (this.matrixId) {
        this.loadPendingDerogation();
      }
      // Session 113 : le bouton PTF de la liste n'est actif que sur une matrice validée, mais le
      // statut a pu changer depuis le chargement de la liste — le dire plutôt que d'ouvrir la
      // matrice sans la zone attendue.
      // Session 180c : arrivée depuis la création d'un avenant sous le plancher — la demande de
      // dérogation s'ouvre d'elle-même (même chemin que le bouton, prérequis compris). Non attendu :
      // la fin du chargement ne dépend pas de la modale.
      if (this.focusSection === "derogation" && this.showDerogationButton) {
        this.handleOpenDerogationModal().catch((error) => {
          // Afficher : la demande ne s'ouvre pas, l'utilisateur garde le bouton « Demander une dérogation ».
          this.showToast(
            I18N.AR_DRG_PanelTitle,
            this.reduceError(error),
            "error"
          );
        });
      }
      if (this.focusSection === "ptf" && !this.isValidatedStatus) {
        this.showToast(
          I18N.AR_PMS_PtfUnavailableTitle,
          I18N.AR_PMS_PtfOnlyForValidated,
          "warning"
        );
      }
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.leaveGoneMatrix();
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Session 291c : la matrice demandée (lien, favori, reprise) n'existe plus ou n'est plus accessible. Le message
   * serveur reste affiché ; l'identifiant est retiré de l'URL (le shell réécrit l'adresse) et l'écran revient à la
   * sélection du besoin, sans attendre un rechargement. Les autres erreurs ne touchent à rien.
   */
  leaveGoneMatrix() {
    if (this.errorMessage !== I18N.AR_Msg_PM_MatrixGone) {
      return;
    }
    this.matrixId = null;
    this.positionId = null;
    this.positionLocked = false;
    this.besoinUrl = null;
    this._storedResult = null;
    this.draftResumeInfo = undefined;
    this.dispatchEvent(new CustomEvent("matrixunavailable"));
    // Avaler délibérément : le nom du créateur est un affichage accessoire de la zone 1, il ne doit pas masquer le message.
    getCurrentUserName()
      .then((name) => {
        this.creatorName = name;
      })
      .catch(() => {});
  }

  get openPtfOnArrival() {
    return this.focusSection === "ptf";
  }

  disconnectedCallback() {
    document.removeEventListener("pointerdown", this.handleDocumentPointerDown);
    window.removeEventListener("resize", this.handleWindowResize);
    this.disconnectGaugeObserver();
    this.clearTjmTimers();
    this.clearNegoTimers();
    clearTimeout(this._tjmQuickTimer);
    clearTimeout(this._tjmPhaseTimer);
    clearTimeout(this._searchDebounce);
    clearTimeout(this._consultantSearchDebounce);
    clearTimeout(this._autosaveTimer);
    if (this._beforeUnloadRegistered) {
      window.removeEventListener("beforeunload", this.handleBeforeUnload);
    }
    if (this._popoverListenersRegistered) {
      document.removeEventListener("click", this.handleDocumentClick);
      document.removeEventListener("keydown", this.handleDocumentKeydown);
    }
  }

  /** Focus géré à l'ouverture d'un popover (session 14) : bascule le focus clavier sur le panneau. */
  renderedCallback() {
    this.measureTjmLink();
    this.observeGaugeTrack();
    // Session 74 : portage optionnel de la popup au body (à implémenter après vérification navigateur)
    // Avant toute chose : ouvrir la popup en navigateur et vérifier que le scrim assombrit toute
    // la fenêtre y compris la nav du haut. Si non, c'est que un ancêtre a une transform.
    // Code de portage préparé ci-dessous, commenté en attente de confirmation du défaut réel.
    /*
    if (this.showMarketInfoPopover && !this._modalPortaled) {
      const modalRoot = this.template.querySelector('.market-info-modal-root');
      if (modalRoot) {
        document.body.appendChild(modalRoot);
        this._modalPortaled = true;
      }
    } else if (!this.showMarketInfoPopover && this._modalPortaled) {
      const modalRoot = document.body.querySelector(
        `.market-info-modal-root[data-owner="${this.uniqueComponentId}"]`
      );
      if (modalRoot) {
        modalRoot.remove();
        this._modalPortaled = false;
      }
    }
    */

    if (this.showMarketInfoPopover && !this._marketPopoverFocused) {
      this.focusPopoverPanel("market");
      this._marketPopoverFocused = true;
    } else if (!this.showMarketInfoPopover) {
      this._marketPopoverFocused = false;
    }
    if (this.showThresholdsInfoPopover && !this._thresholdsPopoverFocused) {
      this.focusPopoverPanel("thresholds");
      this._thresholdsPopoverFocused = true;
    } else if (!this.showThresholdsInfoPopover) {
      this._thresholdsPopoverFocused = false;
    }
  }

  focusPopoverPanel(name) {
    const panel = this.template.querySelector(`[data-popover-panel="${name}"]`);
    if (panel) {
      panel.focus();
    }
  }

  /**
   * Session 184a : arrivée depuis le bouton du besoin — si le besoin porte déjà des matrices, le
   * dire (jamais de doublon silencieux). Un échec est journalisé sans bloquer : le serveur ne
   * dépend pas de cet avertissement et l'écran reste utilisable.
   */
  async warnIfPositionHasMatrices(positionId) {
    this.existingMatricesMessage = null;
    try {
      const count = await countMatricesForPosition({ positionId });
      if (count > 0) {
        this.existingMatricesMessage =
          count === 1
            ? I18N.AR_PMS_ExistingMatrixOne
            : formatLabel(I18N.AR_PMS_ExistingMatrixMany, count);
      }
    } catch (error) {
      console.error("countMatricesForPosition", error);
    }
  }

  async loadDraftResumeInfo() {
    try {
      this.draftResumeInfo = await getRecentDraftForCurrentUser();
    } catch {
      this.draftResumeInfo = undefined;
    }
  }

  async loadPositionContext() {
    this.positionContext = await getPositionContext({
      positionId: this.positionId
    });
    this.positionAccessDenied = this.positionContext.accessible === false;
    // Session 166 : le shell affiche ce libellé dans le fil d'Ariane (« Besoin — Client »).
    this.dispatchEvent(
      new CustomEvent("matrixlabelchange", {
        detail: { label: this.duplicateSourcePositionLabel }
      })
    );
    this.updateClientUrl();
    this.updateManagerUrl();
    if (!this.startDate && this.positionContext.startDate) {
      this.startDate = this.positionContext.startDate;
    }
    // Session 141 : pré-remplissages explicites d'un NOUVEAU Brouillon uniquement — jamais à la
    // réouverture d'une matrice déjà sauvegardée (matrixId posé), ni sur une matrice décidée, et
    // jamais par-dessus une valeur déjà présente ou saisie à la main dans la session.
    const canPrefill = !this.matrixId && this.isEditable;
    if (
      canPrefill &&
      !this.clientSite &&
      !this.clientSiteManuallyEdited &&
      this.positionContext.accountCity
    ) {
      this.clientSite = this.positionContext.accountCity;
    }
    // Date de fin = « Estimated End Date » du besoin si renseignée (session 184b), sinon 31/12 de
    // l'année de début (plus la date de fin de DIFFUSION de l'annonce Connexys, qui n'a aucun
    // rapport avec la mission). Le pré-remplissage depuis la fiche consultant
    // (applyConsultantContext) reste prioritaire : sélection explicite, non écrasée ici.
    if (canPrefill && !this.endDate && !this.endDateManuallyEdited) {
      const defaultEnd =
        this.positionContext.estimatedEndDate ||
        defaultEndDateFor(this.startDate);
      if (defaultEnd) {
        this.endDate = defaultEnd;
      }
    }
    if (canPrefill) {
      await this.applyCreationPrefill();
    }
    // Session 117 : recalculer les jours ouvrés après affectation des dates du besoin, sauf si
    // l'utilisateur a saisi manuellement le nombre de jours dans la session courante.
    // Session 146 : jamais sur une matrice enregistrée qui porte déjà son nombre de jours (V2/V3,
    // copie, réouverture) — il est « fixé » par applyInput et ne doit pas être recalculé en silence
    // à l'ouverture (puis réécrit à la sauvegarde suivante). Seul un nombre absent est calculé.
    const storedDaysKept =
      !!this.matrixId &&
      this.numberOfDays !== null &&
      this.numberOfDays !== undefined;
    if (!this.numberOfDaysManuallyEdited && !storedDaysKept) {
      this.recomputeBusinessDays();
    }
    this.recompute();
    // Session 252 : seuils effectifs avec l'entité (grand compte, sinon entité, sinon défauts).
    await this.refreshCorridorPercents();
    // Préremplissage Zone 2 (session 23) : seulement à la création d'une nouvelle matrice, jamais
    // en réédition d'un Brouillon existant (getMatrixInput écrase rfaPercent avec la valeur
    // sauvegardée juste après, pour ce second cas — cf. connectedCallback).
    if (this.positionContext.accountId && !this.matrixId) {
      await this.prefillDefaultRfaPercent(this.positionContext.accountId);
    }
    await this.loadMarketReference();
    // Session 184e : corridor grand compte, RFA par défaut et repère marché arrivent après le
    // recompute() ci-dessus ; handleConfirmPositionSelection n'attend pas cette méthode, donc rien
    // ne recalculait ensuite — seuils, piste et segment restaient sur le corridor de base alors que
    // la légende affichait déjà le corridor du compte.
    this.recompute();
  }

  /**
   * Création simple d'une matrice depuis un besoin : TJM proposé (tarif journalier du besoin) et
   * consultant (candidat unique du besoin), décidés côté serveur. Valeurs posées sans toucher à l'état
   * « modifié » (comme les autres pré-remplissages de la création), jamais par-dessus une saisie.
   * Un échec est journalisé et ne remplit rien : la matrice reste utilisable à la main.
   * L'entité est posée comme le sélecteur le fait, sans marquer la matrice modifiée ; le recalcul qui
   * suit (jours ouvrés, coefficient) lit donc l'entité pré-remplie.
   */
  async applyCreationPrefill() {
    let prefill;
    try {
      prefill = await getCreationPrefill({ positionId: this.positionId });
    } catch (error) {
      console.error("getCreationPrefill error:", error);
      return;
    }
    if (
      prefill.entityId &&
      !this.entity &&
      this.entityOptions.some((opt) => opt.value === prefill.entityId)
    ) {
      this.entity = prefill.entityId;
    }
    if (
      prefill.proposedTjm &&
      !this.proposedTjm &&
      this.currencyCode === prefill.tjmCurrency
    ) {
      this.proposedTjm = prefill.proposedTjm;
    }
    if (prefill.consultantId && !this.consultantId) {
      this.consultantId = prefill.consultantId;
      this.updateConsultantUrl();
      this.consultantLabel = prefill.consultantLabel;
      this.prefillConsultantLabel = prefill.consultantLabel;
      try {
        const context = await getConsultantContext({
          consultantId: prefill.consultantId
        });
        this.applyConsultantContext(context, { silent: true });
      } catch (error) {
        this.errorMessage = formatLabel(
          this.labels.errorReadingConsultant,
          error.body?.message || error.message
        );
        console.error("getConsultantContext error:", error);
      }
    }
  }

  async prefillDefaultRfaPercent(accountId) {
    this.rfaInheritanceNote = null;
    this.rfaReadWarning = null;
    try {
      const rfaResult = await getDefaultRfaPercentWithProvenance({ accountId });
      // null = aucune RFA dans la chaîne du compte : la RFA reste à 0, sans légende.
      if (rfaResult !== null && rfaResult !== undefined) {
        this.rfaPercent = rfaResult.percent;
        if (rfaResult.inherited) {
          this.rfaInheritanceNote = formatLabel(
            this.labels.rfaInheritedFrom,
            rfaResult.sourceAccountName
          );
        }
      }
    } catch (error) {
      // AFFICHER : avertissement visible non bloquant (la saisie reste possible), jamais muet — un
      // échec de lecture ne doit pas passer pour « ce compte n'a pas de RFA ».
      this.rfaReadWarning = formatLabel(
        this.labels.rfaReadFailed,
        error.body?.message || error.message
      );
      console.error("getDefaultRfaPercentWithProvenance error:", error);
    }
  }

  /**
   * Repères marché (session 9) : dépend du besoin et du type de contrat simulé. Convertis dans la
   * devise de la matrice (session 24b) — l'historique de comparables est intégralement en EUR ; le
   * taux résolu localement (même logique que recompute(), cf. resolveRateToEur) est transmis à
   * l'Apex, jamais recalculé côté serveur à partir de rien.
   */
  async loadMarketReference() {
    if (!this.positionId) {
      this.marketReference = undefined;
      return;
    }
    this.isLoadingMarketReference = true;
    try {
      const resolved = resolveRateToEur(this.currencyCode, this.currentRates);
      this.marketReference = await getMarketReference({
        positionId: this.positionId,
        contractType: this.contractType,
        targetCurrencyCode: this.currencyCode,
        rateToEur: resolved ? resolved.rateToEur : null,
        seniorityLevelName: this.seniorityLevel
      });
    } catch {
      this.marketReference = undefined;
    } finally {
      this.isLoadingMarketReference = false;
    }
  }

  /** Sélecteur de besoin (vue « Matrice AT » ouverte sans contexte) : recherche dès 1 caractère, 300 ms de debounce. */
  handlePositionSearchChange(event) {
    const term = event.target.value;
    this.positionSearchTerm = term;
    clearTimeout(this._searchDebounce);

    if (term.length < 1) {
      this.positionSearchResults = [];
      this.showPositionDropdown = false;
      this.isSearchingPositions = false;
      return;
    }

    this.showPositionDropdown = true;
    this.isSearchingPositions = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce de recherche, pas un pattern Locker à risque.
    this._searchDebounce = setTimeout(() => {
      searchPositions({ searchTerm: term })
        .then((results) => {
          this.positionSearchResults = results;
        })
        .catch((error) => {
          this.positionSearchResults = [];
          this.errorMessage = this.reduceError(error);
        })
        .finally(() => {
          this.isSearchingPositions = false;
        });
    }, 300);
  }

  async handleSelectPosition(event) {
    const positionId = event.currentTarget.dataset.id;
    // Session 83 §1 : surbrillance immédiate avant l'appel Apex (selectedPositionId posé avant await),
    // liste de résultats persistante après clic, les autres résultats restent cliquables pour essayer
    // plusieurs aperçus de suite.
    this.selectedPositionId = positionId;
    // Session 84 §3 : utiliser isLoadingPositionPreview au lieu de isLoading pour ne pas démonter
    // toute la recherche/liste pendant le chargement du preview (le flash blanc).
    this.isLoadingPositionPreview = true;
    try {
      // Les objets renvoyés par un appel Apex impératif passent par la Lightning Web Security
      // membrane et arrivent non-extensibles en runtime réel (jamais en mock Jest, d'où le fait que
      // ce bug n'apparaissait qu'au test manuel navigateur) : on construit un nouvel objet plutôt
      // que de muter celui renvoyé par getPositionContext (sinon "Cannot add property positionId,
      // object is not extensible").
      const context = await getPositionContext({ positionId });
      if (context.accessible === false) {
        this.selectedPositionPreview = null;
        this.selectedPositionId = null;
        this.showToast(
          this.labels.errorTitle,
          this.labels.positionAccessDeniedBanner,
          "warning"
        );
        return;
      }
      this.selectedPositionPreview = { ...context, positionId };
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.selectedPositionPreview = null;
      this.selectedPositionId = null;
    } finally {
      this.isLoadingPositionPreview = false;
    }
  }

  handleConfirmPositionSelection() {
    if (!this.selectedPositionPreview) {
      return;
    }
    this.positionId = this.selectedPositionPreview.positionId;
    this.updateBesoinUrl();
    this.positionSearchTerm = "";
    this.selectedPositionPreview = null;
    this.isLoading = true;
    try {
      this.loadPositionContext();
      this.recompute();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleViewPosition() {
    // Session 84 §4 : ouvrir la fiche du besoin (cxsrec__cxsPosition__c) en nouvel onglet
    if (!this.selectedPositionPreview) {
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.selectedPositionPreview.positionId,
        objectApiName: "cxsrec__cxsPosition__c",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        window.open(url, "_blank");
      })
      .catch((error) => {
        this.errorMessage = formatLabel(
          this.labels.errorOpeningRecord,
          error.body?.message || error.message
        );
      });
  }

  handleViewAccount() {
    // Session 85 : ouvrir la fiche du compte (Account) depuis l'aperçu du besoin
    if (
      !this.selectedPositionPreview ||
      !this.selectedPositionPreview.accountId
    ) {
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.selectedPositionPreview.accountId,
        objectApiName: "Account",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        window.open(url, "_blank");
      })
      .catch((error) => {
        this.errorMessage = formatLabel(
          this.labels.errorOpeningRecord,
          error.body?.message || error.message
        );
      });
  }

  // Session 118 : Génération des URLs pour les liens cliquables Zone 1
  updateConsultantUrl() {
    if (!this.consultantId) {
      this.consultantUrl = null;
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.consultantId,
        objectApiName: "cxsrec__cxsCandidate__c",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        this.consultantUrl = url;
      })
      .catch(() => {
        this.consultantUrl = null;
      });
  }

  updateClientUrl() {
    if (!this.positionContext?.accountId) {
      this.clientUrl = null;
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.positionContext.accountId,
        objectApiName: "Account",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        this.clientUrl = url;
      })
      .catch(() => {
        this.clientUrl = null;
      });
  }

  updateManagerUrl() {
    if (!this.positionContext?.managerContactId) {
      this.managerUrl = null;
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.positionContext.managerContactId,
        objectApiName: "Contact",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        this.managerUrl = url;
      })
      .catch(() => {
        this.managerUrl = null;
      });
  }

  updateBesoinUrl() {
    if (!this.positionId) {
      this.besoinUrl = null;
      return;
    }
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: this.positionId,
        objectApiName: "cxsrec__cxsPosition__c",
        actionName: "view"
      }
    };
    this[NavigationMixin.GenerateUrl](pageReference)
      .then((url) => {
        this.besoinUrl = url;
      })
      .catch(() => {
        this.besoinUrl = null;
      });
  }

  /**
   * Recherche de consultant (Zone 1, session 54, remplace la saisie libre AR_Consultant_Name__c) —
   * même mécanique que le sélecteur de besoin ci-dessus (debounce 300 ms, 1 caractère minimum,
   * session 99).
   */
  handleConsultantSearchChange(event) {
    const term = event.target.value;
    this.consultantSearchTerm = term;
    clearTimeout(this._consultantSearchDebounce);

    if (term.length < 1) {
      this.consultantSearchResults = [];
      this.showConsultantDropdown = false;
      this.isSearchingConsultants = false;
      return;
    }

    this.showConsultantDropdown = true;
    this.isSearchingConsultants = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce de recherche, cf. handlePositionSearchChange.
    this._consultantSearchDebounce = setTimeout(() => {
      searchConsultants({ searchTerm: term })
        .then((results) => {
          this.consultantSearchResults = results;
        })
        .catch((error) => {
          this.consultantSearchResults = [];
          this.errorMessage = this.reduceError(error);
        })
        .finally(() => {
          this.isSearchingConsultants = false;
        });
    }, 300);
  }

  /**
   * Sélection d'un consultant : le palier de séniorité renvoyé par la recherche est LU dans le
   * combobox (session 54, docs/54-lookup-consultant.md §7 : "lookup renseigné → séniorité lue") —
   * une suggestion visible et surchargeable, jamais un recalcul silencieux (l'utilisateur peut la
   * changer ensuite comme n'importe quelle valeur du combobox). Ne s'applique qu'à la sélection
   * elle-même, jamais rejoué automatiquement sur une matrice déjà chargée.
   */
  async handleSelectConsultant(event) {
    const consultantId = event.currentTarget.dataset.id;
    const option = this.consultantSearchResults.find(
      (opt) => opt.consultantId === consultantId
    );
    this.consultantId = consultantId;
    this.updateConsultantUrl();
    this.consultantLabel = option ? option.label : null;
    this.prefillConsultantLabel = option ? option.label : null;
    this.showConsultantDropdown = false;
    this.consultantSearchResults = [];
    this.consultantSearchTerm = "";
    this.suggestedConsultantId = null;
    this.suggestedConsultantLabel = null;

    // Session 65 : pré-remplissage depuis la fiche consultant — appel serveur à la sélection, jamais
    // avant, jamais automatique.
    if (!consultantId) {
      return;
    }

    try {
      const context = await getConsultantContext({ consultantId });
      this.applyConsultantContext(context);
    } catch (error) {
      this.errorMessage = formatLabel(
        this.labels.errorReadingConsultant,
        error.body?.message || error.message
      );
      console.error("getConsultantContext error:", error);
    }
  }

  /** Applique les valeurs pré-remplies depuis la fiche consultant et affiche le bandeau de
   * confirmation avec undo. Prend d'abord un snapshot de l'état courant pour pouvoir annuler. */
  applyConsultantContext(context, { silent = false } = {}) {
    // Snapshot : avant application, pour l'annulation (session 65 §1, borne 3 : réversibilité).
    this.prefillSnapshot = {
      contractType: this.contractType,
      seniorityLevel: this.seniorityLevel,
      dirty: this.isDirty
    };

    // Construire le bandeau avant d'appliquer, pour l'afficher aussitôt avec les changements.
    const bannerItems = [];
    let seniorityChanged = false;

    // Contrat
    if (context.contractType != null) {
      if (this.contractType !== context.contractType) {
        bannerItems.push({
          field: this.labels.contractTypeField,
          oldValue: this.contractType,
          newValue: context.contractType
        });
      }
      this.contractType = context.contractType;
    } else if (context.sourceEmpty.includes("contractType")) {
      bannerItems.push({
        field: this.labels.contractTypeField,
        oldValue: this.contractType,
        newValue: this.labels.statusNotRecognized
      });
    }

    // Entité : jamais pré-remplie depuis la fiche consultant (session 132) — choisie par l'utilisateur.

    // Séniorité : changement détecté pour déclencher loadMarketReference
    if (context.seniorityLevel != null) {
      if (this.seniorityLevel !== context.seniorityLevel) {
        seniorityChanged = true;
        bannerItems.push({
          field: this.labels.seniority,
          oldValue: this.seniorityLevel || this.labels.notProvidedFem,
          newValue: context.seniorityLevel
        });
      }
      this.seniorityLevel = context.seniorityLevel;
    }

    // Dates : jamais reprises de la fiche consultant (session 146c, décision d'Alexis du 06/10/2026) —
    // elles sont souvent périmées (ex. 2012 → 2017). Début = date du besoin, fin = 31/12, ou dates de la
    // source pour une duplication : sélectionner un consultant n'y touche jamais.

    // Afficher le badge de succès (boîte détaillée cachée par défaut, ouverte au clic)
    this.prefillBannerItems = bannerItems;
    this.showPrefillBanner = bannerItems.length > 0;
    this.showPrefillDetails = false;

    // Déclenchement : market ref si séniorité changée (le salaire n'est plus pré-rempli, session 136)
    if (seniorityChanged) {
      this.loadMarketReference();
    }

    // Marquer comme sale (l'utilisateur a fait un geste explicite) ; le pré-remplissage automatique
    // de la création n'en est pas un.
    if (!silent) {
      this.setDirty(true);
    }
  }

  handleClearConsultant() {
    this.consultantId = null;
    this.updateConsultantUrl();
    this.consultantLabel = null;
    this.setDirty(true);
  }

  /** Annule le pré-remplissage en restaurant exactement l'état d'avant la sélection du consultant
   * (snapshot mémoriel, pas un rechargement serveur) — session 65 §1, borne 3 : réversibilité. */
  handleUndoPrefill() {
    if (!this.prefillSnapshot) {
      return;
    }
    this.contractType = this.prefillSnapshot.contractType;
    this.seniorityLevel = this.prefillSnapshot.seniorityLevel;
    this.setDirty(this.prefillSnapshot.dirty);
    this.showPrefillBanner = false;
    this.prefillBannerItems = [];
    this.prefillSnapshot = null;
    // Recalc le corridor depuis l'état restauré
    this.recompute();
    this.showPrefillDetails = false;
  }

  handleShowPrefillDetails() {
    this.showPrefillDetails = true;
  }

  handleClosePrefillDetails() {
    this.showPrefillDetails = false;
  }

  /** Applique la suggestion issue de la candidature pressentie (AR_Job_Application__c) — jamais
   * automatique, seulement sur action explicite de l'utilisateur (docs/54-lookup-consultant.md §0bis). */
  handleUseSuggestedConsultant() {
    this.consultantId = this.suggestedConsultantId;
    this.updateConsultantUrl();
    this.consultantLabel = this.suggestedConsultantLabel;
    this.suggestedConsultantId = null;
    this.suggestedConsultantLabel = null;
    this.setDirty(true);
  }

  applyInput(input) {
    this._ofiiFollowsWhenCalculable = false;
    this.currencyCode = input.currencyCode || "EUR";
    this.contractType = input.contractType || "CDI";
    this.annualSalary = input.annualSalary;
    this.cjmBeforeMarkup = input.cjmBeforeMarkup;
    this.markupApplied = input.markupApplied;
    this.cjmVie = input.cjmVie;
    this.cjmNearshore = input.cjmNearshore;
    this.feeIk = input.feeIk;
    this.feeMeals = input.feeMeals;
    this.feeLodging = input.feeLodging;
    this.feeOmOther = input.feeOmOther;
    this.feePeriods = JSON.parse(input.feePeriods || "[]").map((p) =>
      this.newFeePeriod(p)
    );
    this.tjmPeriods = JSON.parse(input.tjmPeriods || "[]").map((p) =>
      this.newTjmPeriod(p)
    );
    this.salaryPeriods = JSON.parse(input.salaryPeriods || "[]").map((p) =>
      this.newSalaryPeriod(p)
    );
    // Ouvert d'office dès que la matrice a des périodes ; replié sinon (nouvelle matrice, rechargement).
    this.tjmPeriodsOpen = this.tjmPeriods.length > 0;
    this.tjmCompact = this.tjmPeriods.length > 0;
    this._tjmExpandedByHover = false;
    this._tjmFieldFocused = false;
    // État d'affichage seulement : le panier s'ouvre toujours replié.
    this.collapseNegoColumns();
    this._negoFieldFocused = false;
    this.applyRplsrInput(input);
    this.gratuityDays = input.gratuityDays;
    this.feeComputer = input.feeComputer;
    this.feePhone = input.feePhone;
    this.feeMonthlyOther = input.feeMonthlyOther;
    this.feeTraining = input.feeTraining;
    this.feeEpi = input.feeEpi;
    this.feeOfiiTax = input.feeOfiiTax;
    this.feeOther = input.feeOther;
    this.rfaPercent = input.rfaPercent;
    this.proposedTjm = input.proposedTjm;
    this.negoPrice2 = input.negoPrice2;
    this.negoPrice3 = input.negoPrice3;
    this.clientGrid = input.clientGrid === true;
    this.entity = input.entity;
    // Session 132 : une fiche d'entité désactivée n'est plus proposée à la sélection mais reste
    // affichée (et conservée à l'enregistrement) sur la matrice qui la porte déjà.
    this.entityName = input.entityName;
    if (
      input.entity &&
      !this.entityOptions.some((o) => o.value === input.entity)
    ) {
      this.entityOptions = [
        ...this.entityOptions,
        { label: input.entityName || input.entity, value: input.entity }
      ];
    }
    // Session 54 : consultantName = écho lecture seule, consultantId/Label = la valeur éditable.
    this.consultantName = input.consultantName;
    this.consultantId = input.consultantId;
    this.consultantLabel = input.consultantLabel;
    this.suggestedConsultantId = input.suggestedConsultantId;
    this.suggestedConsultantLabel = input.suggestedConsultantLabel;
    this.clientSite = input.clientSite;
    this.startDate = input.startDate;
    this.endDate = input.endDate;
    this.numberOfDays = input.numberOfDays;
    this.plannedLeaveDays = input.plannedLeaveDays;
    // Une valeur chargée depuis une matrice existante est traitée comme fixée, jamais recalculée
    // silencieusement au chargement (cf. commentaire sur numberOfDaysAuto) : seule une modification
    // ultérieure des dates réactive le calcul auto.
    this.numberOfDaysAuto = false;
    this.numberOfDaysManuallyEdited = false;
    this.endDateManuallyEdited = false;
    this.clientSiteManuallyEdited = false;
    this.missionDateError = "";
    this.dateInputError = "";
    this.vieCountryId = input.vieCountryId;
    this.nearshoreCountryId = input.nearshoreCountryId;
    this.nearshoreChosenCountry = null;
    this.nearshoreRateMissing = null;
    this.seniorityLevel = input.seniorityLevel;
    this.setStatusFromServer(input.status);
    this.creatorName = input.creatorName;
    this._avenantMc2Before =
      input.avenantMc2Before === undefined ? null : input.avenantMc2Before;
    this.updateConsultantUrl();
  }

  recompute() {
    // Cascade entité → paramètre général → constante moteur (session 48) : une entité sans
    // surcharge (ou aucune entité sélectionnée) laisse `entityDefaults` vide, et engineCtx retombe
    // alors sur `this.settings`/le défaut du moteur exactement comme avant cette session.
    const entityDefaults = this.entityPricingDefaults.get(this.entity) || {};
    const engineCtx = {
      contractType: this.contractType,
      annualSalary: this.annualSalary,
      cjmBeforeMarkup: this.cjmBeforeMarkup,
      markupApplied: this.markupApplied,
      cjmVie: this.cjmVie,
      cjmNearshore: this.cjmNearshore,
      feeIk: this.feeIk,
      feeMeals: this.feeMeals,
      feeLodging: this.feeLodging,
      feeOmOther: this.feeOmOther,
      feePeriods: this.feePeriodsPayload,
      tjmPeriods: this.tjmPeriodsPayload,
      salaryPeriods: this.salaryPeriodsPayload,
      gratuityDays: this.gratuityDays,
      feeComputer: this.feeComputer,
      feePhone: this.feePhone,
      feeMonthlyOther: this.feeMonthlyOther,
      feeTraining: this.feeTraining,
      feeEpi: this.feeEpi,
      feeOfiiTax: this.feeOfiiTax,
      feeOther: this.feeOther,
      workingDaysPerYear:
        entityDefaults.workingDays != null
          ? entityDefaults.workingDays
          : this.settings.workingDaysPerYear,
      missionDays:
        this.rplsrPlan && this.rplsrPlan.enabled
          ? totalSold(this.rplsrPlan.months)
          : this.numberOfDays,
      // Régie sans régule : congés masqués et comptés pour 0.
      plannedLeaveDays: this.rplsrEnabled ? 0 : this.plannedLeaveDays,
      rplsrRatio: this.rplsrRatio,
      markupPercentSetting: this.settings.markupPercent,
      markupMaxSetting: this.settings.markupMax,
      // Coefficient CDI/CDD (session 28) : undefined pour tout autre statut, num() du moteur
      // retombe alors sur CONTRACT_COEFFICIENT_DEFAULT (2,02) — même défaut que côté Apex.
      // Coefficient d'entité (session 48) prioritaire sur le coefficient global CDI/CDD.
      contractCoefficient:
        entityDefaults.coefficient != null
          ? entityDefaults.coefficient
          : this.contractType === "CDI"
            ? this.settings.cdiCoefficient
            : this.contractType === "CDD"
              ? this.settings.cddCoefficient
              : undefined
    };
    // Défaut multi-devises (session 26) : `marketReference` n'est PAS toujours dans la devise de la
    // matrice — `AR_ComparablesService` reste en EUR (`SOURCE_CURRENCY`) quand il n'y a pas de taux
    // pour convertir (cf. `marketReferenceUsableForGauge`). Un plafond de jauge ne peut jamais
    // mélanger deux devises : `top10Value` (arPricingEngine.calcThresholds) compare ce nombre à
    // `idealValue * 1.1`, calculé dans la devise de la matrice. N'alimenter la comparaison qu'avec un
    // repère déjà dans cette même devise ; sinon retomber sur `idealValue * 1.1` seul (même repli que
    // « pas assez de comparables », déjà correct).
    const top10Comparables = this.marketReferenceUsableForGauge
      ? this.marketReference.p90Tjm
      : 0;
    const resolved = resolveRateToEur(this.currencyCode, this.currentRates);
    this.noRateAvailable = !resolved;
    this.rateResolution = resolved || { rateToEur: 1, effectiveDate: null };
    this.calc = compute(
      engineCtx,
      this.rfaPercent,
      this.proposedTjm,
      top10Comparables,
      this.appliedCorridorPercents,
      this.rateResolution.rateToEur
    );
    this._calcPending = false;
  }

  /** Session 157 : à appeler AVANT de modifier un champ entrant dans le calcul ; recompute() le baisse. */
  markCalcPending() {
    this._calcPending = true;
  }

  /**
   * Session 252 : seuils effectifs du calcul en cours — grand compte (`accountId`), sinon entité PTF
   * (`entity`) si ses trois seuils sont renseignés, sinon null = paramètres généraux. Appelé à
   * l'ouverture et à chaque changement d'entité d'un brouillon ; jamais sur une matrice décidée, dont
   * les seuils figés priment (cf. applyFrozenCalculationIfDecided).
   */
  async refreshCorridorPercents() {
    this.corridorPercents = await getAccountCorridorPercents({
      accountId: this.positionContext.accountId ?? null,
      entityId: this.entity ?? null
    });
  }

  /**
   * Correctif de dérive rétroactive (session 23b, cf. prompts/session-23b-derive-retroactive-seuils.md
   * §1) : `recompute()` calcule toujours avec `corridorPercents`, chargé depuis le corridor COURANT
   * du compte (`getAccountCorridorPercents`) — correct pour un Brouillon en cours de saisie, faux
   * pour une matrice déjà décidée si le corridor grand compte a été modifié depuis. Sur un statut
   * décidé (`!isEditable`), on écrase seuils/segment/MC2 par le dernier calcul persisté
   * (`_storedResult`, cf. AR_PricingMatrixService.getMatrixInput) : la donnée fait foi, jamais un
   * recalcul à l'affichage. cjm/feeOmPerDay/feePonctuelsPerDay/markupCalcule/markupMismatch restent
   * ceux de `recompute()` (non stockés sur la matrice, hors périmètre de ce correctif).
   *
   * `corridorPercents` est aligné sur les pourcentages réellement appliqués au calcul d'origine
   * (`floorPercentApplied`/…) plutôt que sur le corridor courant, pour que les libellés en % (bandeau
   * Grand Compte, légende de jauge, messages de bandeau) restent cohérents avec les € affichés. Sur
   * une matrice décidée AVANT ce correctif (percentages non encore stockés), `corridorPercents`
   * repasse à `null` plutôt que d'afficher un pourcentage potentiellement faux — le bandeau Grand
   * Compte disparaît alors silencieusement pour cette matrice historique, préférable à une valeur
   * trompeuse.
   */
  applyFrozenCalculationIfDecided() {
    if (this.isEditable || !this._storedResult) {
      return;
    }
    const r = this._storedResult;
    this.calc = {
      ...this.calc,
      totalDailyCost: r.totalDailyCost,
      tjmFloor: r.tjmFloor,
      tjmTarget: r.tjmTarget,
      tjmIdeal: r.tjmIdeal,
      tjmTop10: r.tjmTop10,
      mc2PerDay: r.mc2PerDay,
      mc2PercentHuman: r.mc2PercentHuman,
      corridorSegment: r.corridorSegment,
      // Régie sans régule : sorties figées (null hors mode), pour la ligne d'écart, la MC2 barrée et le repère fantôme.
      rplsrRatio: r.rplsrRatio ?? null,
      totalDailyCostPiloted: r.totalDailyCostPiloted ?? null,
      mc2PerDayTheoretical: r.mc2PerDayTheoretical ?? null,
      mc2PercentTheoretical: r.mc2PercentTheoretical ?? null
    };
    // Origine figée avec les seuils (session 252) ; null sur une matrice calculée avant son introduction.
    this.corridorPercents =
      r.floorPercentApplied !== null && r.floorPercentApplied !== undefined
        ? {
            floorPercent: r.floorPercentApplied,
            targetPercent: r.targetPercentApplied,
            idealPercent: r.idealPercentApplied,
            source: r.corridorSource ?? null,
            entityName: r.corridorEntityName ?? null
          }
        : null;
  }

  // Périodes de frais OM (docs/239) : une ligne de saisie par période ajoutée, la période 1 restant
  // les quatre champs de la rangée Frais OM.
  newFeePeriod(values = {}) {
    return {
      key: this.nextFeePeriodKey++,
      days: values.days ?? null,
      feeIk: values.feeIk ?? null,
      feeMeals: values.feeMeals ?? null,
      feeLodging: values.feeLodging ?? null,
      feeOmOther: values.feeOmOther ?? null
    };
  }

  get feePeriodsPayload() {
    return this.feePeriods.map(
      ({ days, feeIk, feeMeals, feeLodging, feeOmOther }) => ({
        days,
        feeIk,
        feeMeals,
        feeLodging,
        feeOmOther
      })
    );
  }

  handleAddFeePeriod() {
    this.markCalcPending();
    this.feePeriods = [...this.feePeriods, this.newFeePeriod()];
    this.recompute();
    this.setDirty(true);
  }

  handleRemoveFeePeriod(event) {
    const periodKey = Number(event.currentTarget.dataset.key);
    this.markCalcPending();
    this.feePeriods = this.feePeriods.filter((p) => p.key !== periodKey);
    this.recompute();
    this.setDirty(true);
  }

  handleFeePeriodChange(event) {
    this.markCalcPending();
    const periodKey = Number(event.target.dataset.key);
    const field = event.target.dataset.field;
    const raw = event.target.value;
    const value =
      raw === "" || raw === null || raw === undefined ? null : Number(raw);
    this.feePeriods = this.feePeriods.map((p) => {
      if (p.key !== periodKey) {
        return p;
      }
      return { ...p, [field]: value };
    });
    this.recompute();
    this.setDirty(true);
  }

  // Périodes de salaire : une ligne {days, salary} par période ajoutée ; le brouillon accepte une période
  // incomplète, la validation la refuse (serveur).
  newSalaryPeriod(values = {}) {
    return {
      key: this.nextSalaryPeriodKey++,
      days: values.days ?? null,
      salary: values.salary ?? null
    };
  }

  get salaryPeriodsPayload() {
    return this.salaryPeriods.map(({ days, salary }) => ({ days, salary }));
  }

  handleAddSalaryPeriod() {
    if (this.salaryPeriods.length >= MAX_ADDED_TJM_PERIODS) {
      return;
    }
    this.markCalcPending();
    this.salaryPeriods = [...this.salaryPeriods, this.newSalaryPeriod()];
    this.recompute();
    this.setDirty(true);
  }

  handleRemoveSalaryPeriod(event) {
    const periodKey = Number(event.currentTarget.dataset.key);
    this.markCalcPending();
    this.salaryPeriods = this.salaryPeriods.filter((p) => p.key !== periodKey);
    this.recompute();
    this.setDirty(true);
  }

  handleSalaryPeriodChange(event) {
    this.markCalcPending();
    const periodKey = Number(event.target.dataset.key);
    const field = event.target.dataset.field;
    const raw = event.target.value;
    const value =
      raw === "" || raw === null || raw === undefined ? null : Number(raw);
    this.salaryPeriods = this.salaryPeriods.map((p) => {
      return p.key === periodKey ? { ...p, [field]: value } : p;
    });
    this.recompute();
    this.setDirty(true);
  }

  // Périodes de TJM (docs/254) : une ligne {days, tjm} par période ajoutée, la période 1 restant le
  // champ « TJM proposé ». Le brouillon accepte une période incomplète ; la validation la refuse (serveur).
  newTjmPeriod(values = {}) {
    return {
      key: this.nextTjmPeriodKey++,
      days: values.days ?? null,
      tjm: values.tjm ?? null
    };
  }

  get tjmPeriodsPayload() {
    return this.tjmPeriods.map(({ days, tjm }) => ({ days, tjm }));
  }

  get hasTjmPeriods() {
    return this.tjmPeriods.length > 0;
  }

  // --- Régie sans régule (docs/265 §5) : carte c-ar-rplsr-plan, panier et jauge ---

  applyRplsrInput(input) {
    this.rplsrEnabled = input.rplsrEnabled === true;
    this.rplsrDaysPerMonth =
      input.rplsrDaysPerMonth === undefined ? null : input.rplsrDaysPerMonth;
    this.adoptRplsrPlan(input.rplsrPlan);
  }

  /** Plan renvoyé par le serveur (JSON versionné) : jours produits repris tels quels. JSON illisible → erreur levée. */
  adoptRplsrPlan(planJson) {
    if (!planJson) {
      this._rplsrStoredPlan = null;
      this.rplsrProduced = null;
      return;
    }
    const rows = JSON.parse(planJson).mois;
    if (!Array.isArray(rows)) {
      throw new Error(this.labels.rplsrPlanInvalid);
    }
    this._rplsrStoredPlan = rows
      .map((r) => ({
        m: r.m,
        ouvres: Number(r.ouvres),
        vendus: Number(r.vendus),
        produits: Number(r.produits)
      }))
      .sort((a, b) => (a.m < b.m ? -1 : 1));
    this.rplsrProduced = Object.fromEntries(
      this._rplsrStoredPlan.map((r) => [r.m, r.produits])
    );
  }

  get rplsrWorkingDaysPerYear() {
    const entityDefaults = this.entityPricingDefaults.get(this.entity) || {};
    return (
      entityDefaults.workingDays ?? this.settings.workingDaysPerYear ?? 218
    );
  }

  /**
   * Plan affiché et calculé : mois de la mission (jours ouvrés du pays de l'entité), jours vendus au prorata et jours
   * produits saisis — répartition équilibrée tant qu'aucune saisie ne couvre exactement ces mois. Matrice non
   * modifiable : le plan enregistré, jamais recalculé.
   */
  get rplsrMonths() {
    if (!this.rplsrEnabled) {
      return [];
    }
    if (!this.isEditable && this._rplsrStoredPlan) {
      return this._rplsrStoredPlan;
    }
    const base = Number(this.rplsrDaysPerMonth);
    if (!(base > 0)) {
      return [];
    }
    const months = monthsOf(
      this.startDate,
      this.endDate,
      this.entityCountry,
      base
    );
    const produced = this.rplsrProduced;
    const covered =
      !!produced &&
      Object.keys(produced).length === months.length &&
      months.every((m) => Number.isInteger(produced[m.m]));
    return covered
      ? months.map((m) => ({ ...m, produits: produced[m.m] }))
      : balance(months);
  }

  /** Σ produits ÷ Σ vendus ; null = mode éteint (ou aucun jour vendu). Un ratio de 0 est une vraie valeur. */
  get rplsrRatio() {
    const months = this.rplsrMonths;
    const sold = totalSold(months);
    return sold > 0 ? totalProduced(months) / sold : null;
  }

  get showRplsrCard() {
    return this.isEditable || this.rplsrEnabled;
  }

  handleRplsrToggle(event) {
    this.markCalcPending();
    this.rplsrEnabled = event.detail.enabled;
    if (this.rplsrEnabled && !(Number(this.rplsrDaysPerMonth) > 0)) {
      this.rplsrDaysPerMonth = defaultDaysPerMonth(
        this.rplsrWorkingDaysPerYear
      );
    }
    this.rplsrProduced = null;
    this.recompute();
    this.setDirty(true);
  }

  /** Nouvelle base : appliquée tout de suite à tous les mois, jours produits répartis à nouveau. */
  handleRplsrBaseChange(event) {
    this.markCalcPending();
    this.rplsrDaysPerMonth = event.detail.daysPerMonth;
    this.rplsrProduced = null;
    this.recompute();
    this.setDirty(true);
  }

  handleRplsrProducedChange(event) {
    const { month, produced } = event.detail;
    this.markCalcPending();
    this.rplsrProduced = {
      ...Object.fromEntries(this.rplsrMonths.map((m) => [m.m, m.produits])),
      [month]: produced
    };
    this.recompute();
    this.setDirty(true);
  }

  /** Mode actif et calcul piloté disponible : ligne d'écart, MC2 barrée, repère fantôme. Mode éteint : rien. */
  get isRplsrActive() {
    return (
      this.rplsrEnabled &&
      this.calc?.rplsrRatio !== null &&
      this.calc?.rplsrRatio !== undefined
    );
  }

  get rplsrGapPerDay() {
    return this.calc.totalDailyCost - this.calc.totalDailyCostPiloted;
  }

  get rplsrGapBreakdown() {
    const gap = this.rplsrGapPerDay;
    const breakdown = this.addDecimalClass(
      formatMoneyWithDecimalBreakdown(Math.abs(gap), this.currencyCode)
    );
    return {
      ...breakdown,
      sign: gap < -0.005 ? "-" : "+",
      amountClass:
        gap < -0.005
          ? "mc2-breakdown-amount mc2-breakdown-amount-rplsr-negative"
          : "mc2-breakdown-amount"
    };
  }

  get rplsrGapCaption() {
    const months = this.rplsrMonths;
    return formatLabel(
      this.labels.rplsrGapCaption,
      formatDays(totalProduced(months)),
      formatDays(totalSold(months))
    );
  }

  get showRplsrClassicStrike() {
    return (
      this.isRplsrActive &&
      Math.abs(this.calc.mc2PercentHuman - this.calc.mc2PercentTheoretical) >
        0.05
    );
  }

  get rplsrClassicMc2Percent() {
    return formatPercent(this.calc.mc2PercentTheoretical);
  }

  /** Position qui donne, sur l'échelle pilotée, la MC2 du mode éteint : TJM × ratio. */
  get rplsrGhostPosition() {
    return calcGaugePosition(
      (this.effectiveTjm || 0) * this.calc.rplsrRatio,
      this.gaugeThresholdsContext
    );
  }

  get showRplsrGhost() {
    return (
      this.isRplsrActive &&
      this.hasProposedTjm &&
      Math.abs(this.calc.mc2PercentHuman - this.calc.mc2PercentTheoretical) >
        0.3
    );
  }

  get rplsrGhostStyle() {
    return `left: ${this.rplsrGhostPosition}%;`;
  }

  get rplsrGhostTitle() {
    return `${this.labels.rplsrClassicTitle} : ${this.rplsrClassicMc2Percent}`;
  }

  handleToggleTjmPeriods(event) {
    event.currentTarget.classList.add("just-clicked");
    if (this.tjmPeriodsOpen) {
      this.tjmPeriodsOpen = false;
      this.startTjmPhase("closing");
    } else {
      this.openTjmPeriods();
    }
  }

  openTjmPeriods() {
    this.tjmPeriodsOpen = true;
    this.startTjmPhase("opening");
    this.expandTjmPanel({ quick: false });
  }

  // Le pied ouvre le panneau fermé (même animation que le lien) ou déplie le mode compact ; ouvert, rien.
  get isTjmFooterClickable() {
    return (
      this.showTjmPeriodsLink && (!this.tjmPeriodsOpen || this.isTjmCompact)
    );
  }

  get tjmFooterClass() {
    return this.isTjmFooterClickable
      ? "tjm-weighted-footer tjm-weighted-footer_clickable"
      : "tjm-weighted-footer";
  }

  get tjmFooterRole() {
    return this.isTjmFooterClickable ? "button" : null;
  }

  get tjmFooterTabindex() {
    return this.isTjmFooterClickable ? "0" : null;
  }

  get tjmFooterAriaExpanded() {
    return this.isTjmFooterClickable ? "false" : null;
  }

  handleTjmFooterClick() {
    if (!this.isTjmFooterClickable) {
      return;
    }
    if (this.tjmPeriodsOpen) {
      this.expandTjmPanel();
    } else {
      this.openTjmPeriods();
    }
  }

  handleTjmFooterKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleTjmFooterClick();
    }
  }

  // Le bouton redevient gris tout de suite après un clic ; le bleu ne revient qu'au survol suivant.
  handleTjmTextButtonLeave(event) {
    event.currentTarget.classList.remove("just-clicked");
  }

  startTjmPhase(phase) {
    clearTimeout(this._tjmPhaseTimer);
    this.tjmPhase = phase;
    const block = this.template.querySelector(".tjm-block");
    const k =
      parseFloat(block && getComputedStyle(block).getPropertyValue("--k")) || 1;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- fin de la phase d'animation du cadre, nettoyée au démontage.
    this._tjmPhaseTimer = setTimeout(() => {
      this.tjmPhase = "";
    }, 900 * k);
  }

  handleWindowResize = () => {
    this.measureTjmLink(true);
    this.observeGaugeTrack();
  };

  // Début et fin du soulignement : position du libellé dans le bloc, relevée quand le libellé change.
  measureTjmLink = (force = false) => {
    const block = this.template.querySelector(".tjm-block");
    const label = this.template.querySelector(".tjm-toggle-label");
    if (!block || !label) {
      return;
    }
    if (!force && this._tjmMeasuredLabel === label.textContent) {
      return;
    }
    this._tjmMeasuredLabel = label.textContent;
    const b = block.getBoundingClientRect();
    const l = label.getBoundingClientRect();
    block.style.setProperty("--l", `${l.left - b.left}px`);
    block.style.setProperty("--r", `${b.right - l.right}px`);
  };

  get isTjmCompact() {
    return this.tjmCompact && this.hasTjmPeriods;
  }

  // Une période sans TJM ou sans durée valide : on ne replie pas, l'utilisateur est en pleine saisie.
  get hasIncompleteTjmPeriod() {
    return this.tjmPeriods.some((p) => {
      const tjm = Number(p.tjm);
      const days = Number(p.days);
      return (
        p.tjm == null ||
        p.days == null ||
        !(tjm > 0) ||
        !Number.isInteger(days) ||
        days < 1
      );
    });
  }

  clearTjmTimers() {
    clearTimeout(this._tjmIntentTimer);
    clearTimeout(this._tjmLeaveTimer);
  }

  // Compact → ouvert : timings courts et sans retard (classe is-quick), retirée une fois le dépliage fini.
  expandTjmPanel({ quick = true } = {}) {
    this.clearTjmTimers();
    const wasCompact = this.tjmCompact;
    this.tjmCompact = false;
    this._tjmFieldFocused = false;
    if (quick && wasCompact) {
      clearTimeout(this._tjmQuickTimer);
      this.tjmQuick = true;
      // eslint-disable-next-line @lwc/lwc/no-async-operation -- fin du dépliage rapide, nettoyée au démontage.
      this._tjmQuickTimer = setTimeout(() => {
        this.tjmQuick = false;
      }, TJM_QUICK_EXPAND_MS);
    }
  }

  collapseTjmPanel({ force = false } = {}) {
    this.clearTjmTimers();
    if (!force && this.hasIncompleteTjmPeriod) {
      return;
    }
    this.tjmCompact = true;
    this._tjmFieldFocused = false;
  }

  // Posé au pointerdown dans le panneau (ou sur le lien) : l'écouteur document passe après et l'ignore,
  // même si le clic a retiré son propre élément du DOM (✕ de suppression).
  handleTjmPanelPointerDown() {
    this._tjmPointerInside = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- drapeau de pointerdown remis à zéro après la propagation.
    setTimeout(() => {
      this._tjmPointerInside = false;
    }, 0);
  }

  handleDocumentPointerDown = () => {
    const negoInside = this._negoPointerInside;
    this._negoPointerInside = false;
    if (!negoInside && this.negoOpen) {
      this.collapseNegoColumns();
    }
    if (this._tjmPointerInside) {
      this._tjmPointerInside = false;
      return;
    }
    if (this.tjmPeriodsOpen && this.hasTjmPeriods && !this.tjmCompact) {
      this.collapseTjmPanel();
    }
  };

  // --- Panier : colonnes P2/P3 rétractables (session 268) ---

  clearNegoTimers() {
    clearTimeout(this._negoIntentTimer);
    clearTimeout(this._negoLeaveTimer);
  }

  expandNegoColumns() {
    this.clearNegoTimers();
    this.negoOpen = true;
  }

  collapseNegoColumns() {
    this.clearNegoTimers();
    this.negoOpen = false;
  }

  // Posé au pointerdown dans le panier ou la rangée des champs P2/P3 ; l'écouteur document l'ignore.
  handleNegoPointerDown() {
    this._negoPointerInside = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- drapeau de pointerdown remis à zéro après la propagation.
    setTimeout(() => {
      this._negoPointerInside = false;
    }, 0);
  }

  handleNegoMouseEnter() {
    clearTimeout(this._negoLeaveTimer);
    if (this.negoOpen || !this.hasNegoColumns) {
      return;
    }
    clearTimeout(this._negoIntentTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai d'intention du panier, nettoyé au démontage.
    this._negoIntentTimer = setTimeout(
      () => this.expandNegoColumns(),
      TJM_HOVER_INTENT_MS
    );
  }

  handleNegoMouseLeave() {
    clearTimeout(this._negoIntentTimer);
    if (!this.negoOpen) {
      return;
    }
    clearTimeout(this._negoLeaveTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai de repli du panier, nettoyé au démontage.
    this._negoLeaveTimer = setTimeout(() => {
      if (!this._negoFieldFocused) {
        this.collapseNegoColumns();
      }
    }, TJM_HOVER_LEAVE_MS);
  }

  handleNegoFieldFocusIn() {
    this._negoFieldFocused = true;
  }

  handleNegoFieldFocusOut() {
    this._negoFieldFocused = false;
  }

  handleToggleNegoColumns() {
    if (this.negoOpen) {
      this.collapseNegoColumns();
    } else {
      this.expandNegoColumns();
    }
  }

  get negoToggleLabel() {
    return this.negoEntries.map((e) => `P${e.rank}`).join(" · ");
  }

  get negoControlsIds() {
    return this.negoEntries.map((e) => `nego-tjm-p${e.rank}`).join(" ");
  }

  get negoToggleExpanded() {
    return this.negoOpen ? "true" : "false";
  }

  handleTjmTimelineMouseEnter() {
    if (!this.isTjmCompact) {
      return;
    }
    clearTimeout(this._tjmIntentTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai d'intention du panneau de périodes, nettoyé au démontage.
    this._tjmIntentTimer = setTimeout(
      () => this.expandTjmPanel(),
      TJM_HOVER_INTENT_MS
    );
  }

  handleTjmTimelineMouseLeave() {
    clearTimeout(this._tjmIntentTimer);
  }

  handleTjmTimelineClick() {
    if (this.isTjmCompact) {
      this.expandTjmPanel();
    }
  }

  handleTjmTimelineKeydown(event) {
    if (this.isTjmCompact && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault();
      this.expandTjmPanel();
    }
  }

  handleTjmBlockMouseEnter() {
    clearTimeout(this._tjmLeaveTimer);
  }

  // Seul repli au pointeur : 8 s hors du bloc (lien + cadre + pied), annulé dès son retour.
  handleTjmBlockMouseLeave() {
    clearTimeout(this._tjmIntentTimer);
    if (this.isTjmCompact || !this.tjmPeriodsOpen || !this.hasTjmPeriods) {
      return;
    }
    clearTimeout(this._tjmLeaveTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- délai d'intention du panneau de périodes, nettoyé au démontage.
    this._tjmLeaveTimer = setTimeout(() => {
      if (!this._tjmFieldFocused) {
        this.collapseTjmPanel();
      }
    }, TJM_HOVER_LEAVE_MS);
  }

  handleTjmPanelFocusIn(event) {
    if (this.isTjmCompact) {
      this.expandTjmPanel();
    }
    if (event.target?.tagName === "INPUT") {
      this._tjmFieldFocused = true;
    }
  }

  handleTjmPanelFocusOut(event) {
    if (event.target?.tagName === "INPUT") {
      this._tjmFieldFocused = false;
    }
  }

  handleTjmPanelKeydown(event) {
    if (event.key === "Escape" && !this.isTjmCompact) {
      this.collapseTjmPanel({ force: true });
    }
  }

  handleAddTjmPeriod(event) {
    event.currentTarget.classList.add("just-clicked");
    if (this.tjmPeriods.length >= MAX_ADDED_TJM_PERIODS) {
      return;
    }
    this.markCalcPending();
    this.tjmPeriods = [...this.tjmPeriods, this.newTjmPeriod()];
    this.recompute();
    this.setDirty(true);
  }

  handleRemoveTjmPeriod(event) {
    const periodKey = Number(event.currentTarget.dataset.key);
    this.markCalcPending();
    this.tjmPeriods = this.tjmPeriods.filter((p) => p.key !== periodKey);
    this.recompute();
    this.setDirty(true);
  }

  // Branché sur `input` (pas `change`) : frise et pondéré suivent chaque frappe.
  handleTjmPeriodChange(event) {
    this.markCalcPending();
    const periodKey = Number(event.target.dataset.key);
    const field = event.target.dataset.field;
    const raw = event.target.value;
    const value =
      raw === "" || raw === null || raw === undefined ? null : Number(raw);
    this.tjmPeriods = this.tjmPeriods.map((p) => {
      return p.key === periodKey ? { ...p, [field]: value } : p;
    });
    this.recompute();
    this.setDirty(true);
  }

  get negoPrice2Input() {
    return this._negoDraft.negoPrice2 !== undefined
      ? this._negoDraft.negoPrice2
      : this.negoPrice2;
  }

  get negoPrice3Input() {
    return this._negoDraft.negoPrice3 !== undefined
      ? this._negoDraft.negoPrice3
      : this.negoPrice3;
  }

  handleNegoInput(event) {
    this._negoDraft = {
      ...this._negoDraft,
      [event.target.name]: event.target.value
    };
  }

  // Le change natif part avant le blur et efface le brouillon : un blur sans brouillon n'a rien à enregistrer.
  handleNegoBlur(event) {
    if (this._negoDraft[event.target.name] !== undefined) {
      this.handleFieldChange(event);
    }
  }

  handleNegoKey(event) {
    const name = event.target.name;
    if (event.key === "Escape" && this._negoDraft[name] !== undefined) {
      this.dropNegoDraft(name);
      event.target.value = this[name] === null ? "" : this[name];
    }
  }

  dropNegoDraft(name) {
    const rest = { ...this._negoDraft };
    delete rest[name];
    this._negoDraft = rest;
  }

  handleFieldChange(event) {
    if (event.target.name in this._negoDraft) {
      this.dropNegoDraft(event.target.name);
    }
    this.markCalcPending();
    const field = event.target.name;
    const raw = event.target.value;
    // Une taxe OFII posée à la valeur calculée suit le salaire annuel (cf. followOfiiCalculation).
    const followsOfiiCalculation =
      field === "annualSalary" && this.ofiiTaxIsFollowingCalculation();
    this[field] =
      raw === "" || raw === null || raw === undefined ? null : Number(raw);
    if (field === "negoPrice2" || field === "negoPrice3") {
      this.expandNegoColumns();
    }
    if (field === "annualSalary") {
      this.followOfiiCalculation(followsOfiiCalculation);
    }
    this.recompute();
    this.setDirty(true);
  }

  // Cocher « Grille » vide les deux prix indicatifs ; décocher les laisse vides et saisissables.
  handleClientGridChange(event) {
    this.markCalcPending();
    this.clientGrid = event.target.checked;
    if (this.clientGrid) {
      this.negoPrice2 = null;
      this.negoPrice3 = null;
    }
    this.recompute();
    this.setDirty(true);
  }

  get isNegoInputDisabled() {
    return this.isNotEditable || this.clientGrid;
  }

  async handleContractTypeChange(event) {
    this.markCalcPending();
    this.contractType = event.detail.value;
    this.recompute();
    this.setDirty(true);
    // Le cercle de comparables dépend du type de contrat : recharge puis recalcule avec le vrai p90.
    await this.loadMarketReference();
    this.recompute();
  }

  async handleCurrencyChange(event) {
    this.markCalcPending();
    // Une taxe OFII posée à la valeur calculée suit la devise (plafond converti au taux de la nouvelle
    // devise) ; une valeur qui n'est pas la valeur calculée est conservée telle quelle.
    const followsOfiiCalculation = this.ofiiTaxIsFollowingCalculation();
    this.currencyCode = event.detail.value;
    // Manquant avant la session 24 (la devise ne changeait alors jamais le calcul) : le taux
    // résolu dépend de currencyCode, recompute() doit tourner immédiatement — sinon le bandeau de
    // blocage / les équivalents EUR restent sur l'ancienne devise jusqu'à la prochaine frappe.
    this.recompute();
    if (followsOfiiCalculation && this.followOfiiCalculation(true)) {
      this.recompute();
    }
    this.setDirty(true);
    // Session 24b : les repères marché sont convertis dans la devise de la matrice, il faut donc
    // les recharger — la conversion est faite côté serveur (cacheable, clé de cache par devise).
    await this.loadMarketReference();
  }

  /**
   * Matrice validée : l'entité est la seule donnée modifiable, enregistrée tout de suite par le
   * serveur (changeValidatedMatrixEntity), après confirmation. Aucun recalcul : coefficient, jours
   * travaillés et montants restent ceux figés à la validation, contrairement à handleEntityChange
   * sur un brouillon. Le panneau PTF relit l'entité, sa préparation et son gabarit.
   */
  async handleValidatedEntityChange(event) {
    const combobox = event.target;
    const previous = this.entity;
    const next = event.detail.value;
    if (!next || next === previous) {
      return;
    }
    const confirmed = await LightningConfirm.open({
      message: this.labels.entityChangeConfirm,
      variant: "header",
      label: this.labels.entityChangeConfirmTitle,
      theme: "warning"
    });
    if (!confirmed) {
      combobox.value = previous;
      return;
    }
    this.isChangingEntity = true;
    try {
      await changeValidatedMatrixEntityApex({
        matrixId: this.matrixId,
        entityRefId: next
      });
      const option = this.entityOptions.find((o) => o.value === next);
      this.entity = next;
      this.entityName = option ? option.label : this.entityName;
      this.showToast(
        this.labels.successTitle,
        this.labels.entityChanged,
        "success"
      );
      const ptfPanel = this.template.querySelector("c-ar-ptf-panel");
      if (ptfPanel) {
        await ptfPanel.refresh();
      }
    } catch (error) {
      combobox.value = previous;
      this.showToast(this.labels.errorTitle, this.reduceError(error), "error");
    } finally {
      this.isChangingEntity = false;
    }
  }

  async handleEntityChange(event) {
    this.markCalcPending();
    this.entity = event.detail.value;
    // Le pays de l'entité fixe les jours ouvrés du plan de régie sans régule : plan reconstruit.
    this.rplsrProduced = null;
    // Session 274 : le pays de l'entité fixe aussi les jours fériés du nombre de jours mission — recalculé
    // seulement en mode auto, une saisie manuelle n'est jamais écrasée.
    if (this.isEditable && this.numberOfDaysAuto) {
      this.recomputeBusinessDays();
    }
    // Session 252 : les seuils de l'entité entrent dans le corridor du brouillon — jauge, segment et
    // panier suivent le changement immédiatement.
    if (this.isEditable) {
      await this.refreshCorridorPercents();
    }
    // Session 48 : l'entité peut porter son propre coefficient/jours travaillés — sans ce
    // recalcul, l'aperçu resterait sur les valeurs de l'entité précédente jusqu'à la prochaine
    // saisie, en désaccord silencieux avec ce que saveDraftInput calculera réellement.
    this.recompute();
    this.setDirty(true);
  }

  /**
   * Sélecteur pays VIE/Nearshore (session 18, maquette pricing-tool.html:1918-1929/1946-1957) : le
   * choix d'un pays pré-remplit l'indemnité/CJM depuis le référentiel. Une saisie manuelle ultérieure
   * du CJM (`handleFieldChange`) ne touche jamais `vieCountryId`/`nearshoreCountryId` : le lookup est
   * conservé même après surcharge (prompt §3) — c'est `showVieReferentialMismatch`/
   * `showNearshoreReferentialMismatch` qui signale l'écart, pas un nettoyage du lookup.
   */
  handleVieCountryChange(event) {
    this.vieCountryId = event.detail.value || null;
    const match = this.vieReferentialOptions.find(
      (opt) => opt.id === this.vieCountryId
    );
    if (match) {
      this.cjmVie = match.cjm;
    }
    this.recompute();
    this.setDirty(true);
  }

  handleNearshoreCountryChange(event) {
    this.nearshoreChosenCountry = event.detail.value || null;
    this.applyNearshoreRate(this.nearshoreChosenCountry);
    this.recompute();
    this.setDirty(true);
  }

  /**
   * Ligne du référentiel Nearshore pour un pays et une séniorité : la ligne exacte, à défaut la
   * ligne « Défaut » du pays, sinon null (jamais un tarif substitué). Même règle que
   * AR_PricingMatrixService.resolveNearshoreRow.
   */
  resolveNearshoreRow(country, seniority) {
    const rows = this.nearshoreReferentialOptions.filter(
      (opt) => opt.country === country
    );
    const exact = seniority
      ? rows.find((opt) => opt.seniority === seniority)
      : null;
    return (
      exact ||
      rows.find((opt) => opt.seniority === NEARSHORE_DEFAULT_SENIORITY) ||
      null
    );
  }

  /** Applique la ligne retenue : lookup et CJM, ou état bloquant si aucune ne correspond. */
  applyNearshoreRate(country) {
    if (!country) {
      this.nearshoreCountryId = null;
      this.nearshoreRateMissing = null;
      return;
    }
    const row = this.resolveNearshoreRow(country, this.seniorityLevel);
    if (row) {
      this.nearshoreCountryId = row.id;
      this.cjmNearshore = row.cjm;
      this.nearshoreRateMissing = null;
    } else {
      this.nearshoreCountryId = null;
      this.cjmNearshore = null;
      this.nearshoreRateMissing = formatLabel(
        I18N.AR_PMS_NearshoreRateMissing,
        country,
        this.seniorityLevel || I18N.AR_ANR_SeniorityDefault
      );
    }
  }

  /**
   * Palier de séniorité (session 28) : contrairement aux pays VIE/Nearshore, ne modifie aucun champ
   * de calcul — seul le cercle de comparables en dépend, d'où le rechargement immédiat (même logique
   * que handleContractTypeChange, qui recharge aussi loadMarketReference pour la même raison).
   */
  async handleSeniorityLevelChange(event) {
    this.seniorityLevel = event.detail.value || null;
    if (this.isNEARSHORE && this.isEditable && this.nearshoreCountryValue) {
      this.applyNearshoreRate(this.nearshoreCountryValue);
      this.recompute();
    }
    this.setDirty(true);
    await this.loadMarketReference();
  }

  /** Nom prénom consultant / Site client (Zone 1, session 17) : saisie libre, pas de conversion numérique. */
  handleMissionTextChange(event) {
    const field = event.target.name;
    const raw = event.target.value;
    this[field] = raw === "" ? null : raw;
    if (field === "clientSite") {
      this.clientSiteManuallyEdited = true;
    }
    this.setDirty(true);
  }

  /**
   * Valeur d'un champ date + message quand elle est vide. Constaté en navigateur (session 256) : un
   * `lightning-input` type date vide lui-même le champ et renvoie "" pour un texte qu'il ne sait pas
   * lire (« 32/13/2027 »), sans `validity.badInput` — impossible de distinguer cette saisie d'un champ
   * effacé. Les deux dates sont obligatoires : une date vide s'accompagne toujours d'un message, jamais
   * d'une valeur ignorée en silence.
   */
  readDateInput(event) {
    const value = event.target.value || null;
    this.dateInputError = value ? "" : this.labels.dateUnreadable;
    return value;
  }

  /**
   * Relit la valeur courante des deux champs date avant tout enregistrement ou validation : une date
   * tapée puis un clic direct sur « Enregistrer » / « Valider » (sans quitter le champ) n'a pas encore
   * émis son `change`. Une valeur différente passe par le même gestionnaire que la saisie ; retourne
   * false si une date est illisible (le message est alors affiché sous le champ).
   */
  syncDateInputs() {
    [
      ["startDate", (el) => this.handleStartDateChange({ target: el })],
      ["endDate", (el) => this.handleEndDateChange({ target: el })]
    ].forEach(([name, apply]) => {
      const el = this.template.querySelector(`[data-date-field="${name}"]`);
      if (el && (el.value || null) !== (this[name] || null)) {
        apply(el);
      }
    });
    return !this.dateInputError;
  }

  handleStartDateChange(event) {
    this.markCalcPending();
    const previousStart = this.startDate;
    this.startDate = this.readDateInput(event);
    // Session 141 : la fin suit l'année de début tant qu'elle est vide ou qu'elle vaut encore le 31/12
    // proposé pour l'ancienne année — une date de fin saisie à la main (cette session), reprise de
    // la fiche consultant ou sauvegardée avec une autre valeur n'est jamais écrasée.
    if (this.isEditable && !this.endDateManuallyEdited && this.startDate) {
      const previousDefault = defaultEndDateFor(previousStart);
      const isEstimatedEnd =
        !!this.endDate &&
        this.endDate === this.positionContext?.estimatedEndDate;
      if (
        !isEstimatedEnd &&
        (!this.endDate || this.endDate === previousDefault)
      ) {
        this.endDate = defaultEndDateFor(this.startDate);
      }
    }
    this.rplsrProduced = null;
    this.recomputeBusinessDays();
    this.recompute();
    this.setDirty(true);
  }

  handleEndDateChange(event) {
    this.markCalcPending();
    this.endDate = this.readDateInput(event);
    this.endDateManuallyEdited = true;
    // Régie sans régule : nouvelles dates = plan reconstruit (répartition équilibrée), comme le serveur.
    this.rplsrProduced = null;
    this.recomputeBusinessDays();
    this.recompute();
    this.setDirty(true);
  }

  /**
   * Jours ouvrés (Zone 1, session 17, pricing-tool.html:1748-1753) : recalculés dès que les deux
   * dates sont renseignées, hors week-ends et (session 274) hors jours fériés du pays de l'entité
   * (calendrier unique c/arWorkingCalendar, même que la régie par lot). Fin < début : erreur affichée, jamais un nombre de jours négatif
   * (déviation volontaire de la maquette, qui retombe silencieusement sur 0).
   */
  recomputeBusinessDays() {
    if (!this.startDate || !this.endDate) {
      this.missionDateError = "";
      return;
    }
    if (this.endDate < this.startDate) {
      this.missionDateError = this.labels.endDateMustBeAfterStart;
      this.numberOfDaysAuto = false;
      return;
    }
    this.missionDateError = "";
    this.numberOfDays = calcBusinessDays(
      this.startDate,
      this.endDate,
      this.entityCountry
    );
    this.numberOfDaysAuto = true;
  }

  /** Édition manuelle du nombre de jours (Zone 1, session 17) : désactive le mode auto, cf. maquette. */
  handleNumberOfDaysChange(event) {
    const raw = event.target.value;
    this.numberOfDays = raw === "" || raw === null ? null : Number(raw);
    this.numberOfDaysAuto = false;
    this.numberOfDaysManuallyEdited = true;
    this.setDirty(true);
    this.recompute();
  }

  /**
   * Session 44 (cf. docs/44-url-matrice-creee.md §1-§2) : point de passage unique de tout endroit où
   * ce composant apprend l'Id de matrice depuis le serveur (arrivée avec contexte, persist(),
   * dérogation, autosauvegarde, reprise de brouillon). Annonce l'Id au shell par événement — jamais
   * par navigation — pour qu'il réécrive l'URL sans démonter ce composant. Ne jamais émettre à null
   * (arrivée sans matrice encore créée) ni quand l'Id n'a pas changé, sans quoi l'autosauvegarde
   * (20s) redéclencherait le même événement indéfiniment une fois la matrice créée.
   */
  announceMatrixId(newMatrixId) {
    const changed = !!newMatrixId && this.matrixId !== newMatrixId;
    this.matrixId = newMatrixId;
    if (changed) {
      this.dispatchEvent(
        new CustomEvent("matrixidchange", { detail: { matrixId: newMatrixId } })
      );
    }
  }

  buildMatrixInput() {
    const input = {
      matrixId: this.matrixId,
      positionId: this.positionId,
      currencyCode: this.currencyCode,
      contractType: this.contractType
    };
    [...FEE_FIELDS, ...MISSION_FIELDS, ...REFERENTIAL_FIELDS].forEach(
      (field) => {
        input[field] = this[field];
      }
    );
    // String JSON : Aura n'alimente pas une classe Apex en paramètre (cf. CLAUDE.md, AR_PricingMatrixService.MatrixInput).
    input.feePeriods = JSON.stringify(this.feePeriodsPayload);
    input.tjmPeriods = JSON.stringify(this.tjmPeriodsPayload);
    input.salaryPeriods = JSON.stringify(this.salaryPeriodsPayload);
    // Régie sans régule : seuls les jours produits partent ; le serveur recalcule ouvrés et vendus.
    input.rplsrEnabled = this.rplsrEnabled;
    input.rplsrDaysPerMonth = this.rplsrDaysPerMonth;
    input.rplsrProduced = this.rplsrEnabled
      ? JSON.stringify(
          Object.fromEntries(this.rplsrMonths.map((m) => [m.m, m.produits]))
        )
      : null;
    return input;
  }

  async handleSaveDraft() {
    await this.persist(saveDraftApex, this.labels.draftSaved);
  }

  /**
   * Session 107 : vérification des prérequis avant validation/dérogation. Retourne true si tout est
   * présent, false si des champs manquent (et affiche le panneau).
   */
  async checkValidationPrerequisites() {
    // Session 108 : contrôle aussi sur une matrice neuve ; échec du contrôle = pas de feu vert.
    // Seules les données de la MATRICE bloquent (blocking=true) ; besoin et entité produisent des
    // avertissements affichés sans empêcher la validation (décision d'Alexis, 23/09/2026).
    this.showValidationPrerequisitesPanel = false;
    this.validationPrerequisitesMissing = [];
    this.validationPrerequisitesWarnings = [];
    let prerequisites;
    try {
      prerequisites = await getValidationPrerequisites({
        inputJson: JSON.stringify(this.buildMatrixInput())
      });
    } catch (error) {
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        this.reduceError(error),
        "error"
      );
      return false;
    }
    const all = prerequisites || [];
    const blocking = all.filter((p) => p.blocking === true);
    const warnings = all.filter((p) => p.blocking !== true);
    this.validationPrerequisitesMissing = blocking;
    this.validationPrerequisitesWarnings = warnings;
    this.showValidationPrerequisitesPanel =
      blocking.length > 0 || warnings.length > 0;
    if (blocking.length > 0) {
      this.showToast(
        I18N.AR_PMS_ValidationImpossible,
        formatLabel(
          I18N.AR_PMS_FieldsToComplete,
          blocking.map((p) => p.label).join(", ")
        ),
        "warning"
      );
      return false;
    }
    if (warnings.length > 0) {
      this.showToast(
        I18N.AR_Common_WarningTitle,
        formatLabel(
          I18N.AR_PMS_PtfMightBeBlocked,
          warnings.map((p) => p.label).join(" ; ")
        ),
        "warning"
      );
    }
    return true;
  }

  get hasBlockingPrerequisites() {
    return this.validationPrerequisitesMissing.length > 0;
  }

  get hasPrerequisiteWarnings() {
    return this.validationPrerequisitesWarnings.length > 0;
  }

  async handleValidate() {
    // Session 157 : le clic repart toujours du calcul local courant, jamais d'un affichage antérieur ;
    // sous le plancher, le bouton se remplace par la demande de dérogation et rien n'est envoyé.
    if (this.isValidateDisabled || !this.syncDateInputs()) {
      return;
    }
    this.recompute();
    if (this.isDerogationRequired) {
      return;
    }
    const canProceed = await this.checkValidationPrerequisites();
    if (!canProceed) {
      return;
    }
    // Session 184b : confirmation cost of sales à chaque validation, quel que soit le nombre de
    // champs de frais remplis (session 178 : seulement sous 4 champs).
    const shouldContinue = await LightningConfirm.open({
      message: this.labels.costOfSalesConfirmationTitle,
      variant: "header",
      label: this.labels.costOfSalesDialogTitle,
      theme: "warning"
    });
    if (!shouldContinue) {
      return;
    }
    await this.persist(validateApex, this.labels.matrixValidated);
  }

  /**
   * Suivi dirty (session 13) : toute modification non sauvegardée marque l'état sale, ce qui
   * active le handler `beforeunload` et (re)planifie l'autosauvegarde débouncée. Remis à `false`
   * après toute sauvegarde réussie (brouillon manuel, validation, dérogation, autosave).
   */
  setDirty(value) {
    this._isDirty = value;
    this.syncBeforeUnloadListener();
    if (value) {
      this._inputRevision += 1;
      this._autosaveState = "dirty";
      this.scheduleAutosave();
    } else {
      clearTimeout(this._autosaveTimer);
    }
  }

  @api
  get isDirty() {
    return this._isDirty;
  }

  /**
   * Session 26 §2 : le shell (arPricingApp) affichait « Enregistrer le brouillon » dans la modale de
   * navigation même quand le bandeau rouge venait d'annoncer que le calcul ne peut pas être
   * enregistré (`noRateAvailable`, cf. `persist()`) — le clic échouait systématiquement. Exposé pour
   * que le shell retire l'option plutôt que d'offrir un bouton voué à l'échec.
   */
  @api
  get canSaveDraft() {
    return !this.hasBlockingCondition && !this.positionAccessDenied;
  }

  /** Appelé par le shell (arPricingApp, ref `simulator`) quand l'utilisateur choisit « Enregistrer le brouillon » depuis la modale de navigation. */
  @api
  saveDraftForNavigation() {
    // Session 167 : rien à sauvegarder (écriture impossible) — la navigation n'est pas bloquée.
    // `canSaveDraft` retire déjà l'option « Enregistrer » de la modale du shell.
    if (this.positionAccessDenied) {
      return Promise.resolve();
    }
    return this.persist(saveDraftApex, this.labels.draftSaved, {
      rethrow: true
    });
  }

  handleBeforeUnload = (event) => {
    event.preventDefault();
    event.returnValue = "";
  };

  syncBeforeUnloadListener() {
    try {
      if (this._isDirty && !this._beforeUnloadRegistered) {
        window.addEventListener("beforeunload", this.handleBeforeUnload);
        this._beforeUnloadRegistered = true;
      } else if (!this._isDirty && this._beforeUnloadRegistered) {
        window.removeEventListener("beforeunload", this.handleBeforeUnload);
        this._beforeUnloadRegistered = false;
      }
    } catch (error) {
      // LWS peut bloquer l'accès à window.addEventListener('beforeunload', ...) selon le contexte
      // d'exécution : dégradation documentée (docs/13-navigation-etat.md), pas d'erreur remontée à l'utilisateur.
      console.error(
        "arPriceMatrixSimulator : handler beforeunload indisponible.",
        error
      );
    }
  }

  /** Jamais d'autosave sans besoin sélectionné ni sur une matrice décidée (le trigger la refuserait
   * de toute façon), ni sans taux disponible pour la devise courante (session 24 — échouerait
   * silencieusement contre le blocage serveur, autant ne pas tenter l'appel). */
  scheduleAutosave() {
    if (
      !this.positionId ||
      !this.isEditable ||
      this.hasBlockingCondition ||
      this.positionAccessDenied
    ) {
      return;
    }
    clearTimeout(this._autosaveTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- débounce d'autosauvegarde (session 13), pas un pattern Locker à risque.
    this._autosaveTimer = setTimeout(() => {
      this.runAutosave();
    }, AUTOSAVE_DEBOUNCE_MS);
  }

  /** Sauvegarde silencieuse : jamais de toast (spec session 13), seul l'indicateur discret sous le header change. */
  runAutosave() {
    return this.enqueueSave(() => this.doAutosave());
  }

  async doAutosave() {
    if (
      !this._isDirty ||
      !this.positionId ||
      !this.isEditable ||
      this.positionAccessDenied
    ) {
      return;
    }
    this._autosaveState = "saving";
    const revisionAtSend = this._inputRevision;
    try {
      const result = await saveDraftApex({
        inputJson: JSON.stringify(this.buildMatrixInput())
      });
      this.announceMatrixId(result.matrixId);
      this.setStatusFromServer(result.status);
      if (this.applySavedCalculation(result, revisionAtSend)) {
        this._isDirty = false;
        this.syncBeforeUnloadListener();
        this.lastAutosaveAt = new Date();
        this._autosaveState = "saved";
      } else {
        // Saisie pendant l'enregistrement : le serveur a enregistré l'état d'AVANT, la saisie la
        // plus récente reste à enregistrer.
        this._autosaveState = "dirty";
        this.scheduleAutosave();
      }
    } catch {
      // Échec silencieux : la prochaine modification reprogrammera un essai, une sauvegarde manuelle
      // reste possible. L'indicateur retombe sur "Modifié" — l'état réel (rien n'a été enregistré).
      this._autosaveState = "dirty";
    }
  }

  async handleResumeDraft() {
    if (!this.draftResumeInfo) {
      return;
    }
    this.isLoading = true;
    try {
      const ctx = await resolveRecordContext({
        anyId: this.draftResumeInfo.matrixId
      });
      this.positionId = ctx.positionId;
      this.updateBesoinUrl();
      // Cinquième point appris depuis le serveur, non listé dans l'audit initial (prompts/session-44
      // §1) mais de même nature que les quatre autres : sans lui, un F5 après reprise d'un brouillon
      // rouvrirait à nouveau un formulaire vierge — exactement le défaut que cette session corrige.
      this.announceMatrixId(ctx.matrixId);
      this.positionLocked = true;
      this.draftResumeInfo = undefined;
      // Même ordre que connectedCallback (session 28b §2) : applyInput() avant loadPositionContext(),
      // pour que loadMarketReference() lise le contractType/seniorityLevel/currencyCode réels de
      // la matrice reprise, jamais les valeurs par défaut du composant.
      const input = await getMatrixInput({ matrixId: this.matrixId });
      this.applyInput(input);
      this.applyAccess(input);
      this._storedResult = input.storedResult || null;
      if (this.positionId) {
        await this.loadPositionContext();
      }
      this.recompute();
      this.applyFrozenCalculationIfDecided();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.leaveGoneMatrix();
    } finally {
      this.isLoading = false;
    }
  }

  handleDismissExistingMatrices() {
    this.existingMatricesMessage = null;
  }

  handleDismissDraftBanner() {
    this.draftBannerDismissed = true;
  }

  /**
   * Popovers d'explicabilité (session 14) : icônes discrètes utility:info sur « Repères marché » et
   * sur le bloc seuils. Aucun appel serveur — tout le contenu est dérivé de `marketReference`/`calc`
   * déjà chargés. Écouteurs document (clic extérieur, Escape) posés/retirés uniquement pendant
   * qu'un popover est ouvert, focus basculé sur le panneau à l'ouverture et rendu au déclencheur à
   * la fermeture — même mécanique que `beforeunload` (session 13), scopée à ce composant.
   */
  handleToggleMarketInfo(event) {
    event.stopPropagation();
    if (this.showMarketInfoPopover) {
      this.closePopovers();
      return;
    }
    this._lastFocusedTrigger = event.currentTarget;
    this.showThresholdsInfoPopover = false;
    this.showMarketInfoPopover = true;
    this.syncPopoverListeners();
  }

  handleToggleThresholdsInfo(event) {
    event.stopPropagation();
    if (this.showThresholdsInfoPopover) {
      this.closePopovers();
      return;
    }
    this._lastFocusedTrigger = event.currentTarget;
    this.showMarketInfoPopover = false;
    this.showThresholdsInfoPopover = true;
    this.syncPopoverListeners();
  }

  // Un clic à l'intérieur du panneau ne doit pas remonter jusqu'au document (sinon il se refermerait
  // immédiatement) : seul un clic hors du popover/déclencheur doit le fermer.
  stopPopoverClick(event) {
    event.stopPropagation();
  }

  closePopovers() {
    this.showMarketInfoPopover = false;
    this.showThresholdsInfoPopover = false;
    this.syncPopoverListeners();
    if (this._lastFocusedTrigger) {
      this._lastFocusedTrigger.focus();
      this._lastFocusedTrigger = undefined;
    }
  }

  get anyPopoverOpen() {
    return this.showMarketInfoPopover || this.showThresholdsInfoPopover;
  }

  syncPopoverListeners() {
    if (this.anyPopoverOpen && !this._popoverListenersRegistered) {
      document.addEventListener("click", this.handleDocumentClick);
      document.addEventListener("keydown", this.handleDocumentKeydown);
      this._popoverListenersRegistered = true;
    } else if (!this.anyPopoverOpen && this._popoverListenersRegistered) {
      document.removeEventListener("click", this.handleDocumentClick);
      document.removeEventListener("keydown", this.handleDocumentKeydown);
      this._popoverListenersRegistered = false;
    }
  }

  handleDocumentClick = () => {
    this.closePopovers();
  };

  handleDocumentKeydown = (event) => {
    if (event.key === "Escape") {
      this.closePopovers();
    }
  };

  /**
   * Garde manquante identifiée en session (ticket utilisateur, 10/08) : `scheduleAutosave`/
   * `runAutosave` refusent déjà de sauvegarder sans `positionId`, mais le bouton « Sauvegarder
   * Brouillon » (`handleSaveDraft`) n'a aucune garde équivalente — le bouton reste actif dès
   * l'arrivée sur une matrice vierge (`isEditable` ne dépend que du statut, pas de la présence
   * d'un besoin). Sans cette garde, `saveDraftApex` part avec `positionId: null`, et
   * `AR_PricingMatrixService.getPositionContext` lève `List has no rows for assignment to
   * SObject` — une erreur Apex interne incompréhensible au lieu d'un message actionnable.
   * Centralisée ici (pas dans chaque handler) : `persist` est le point d'entrée commun à
   * Sauvegarder Brouillon, Valider et `saveDraftForNavigation`, qui peuvent tous être atteints
   * sans besoin sélectionné (ex. champs remplis avant sélection du besoin, puis navigation).
   */
  /**
   * Session 157 : une réponse de sauvegarde ne remplace le calcul affiché que si l'utilisateur n'a
   * rien saisi depuis l'envoi. Sinon `result.calculation` décrit l'input d'AVANT la dernière saisie :
   * l'adopter affichait un corridor et un statut périmés (« validable ») jusqu'à la sauvegarde
   * suivante, et `_isDirty = false` masquait en plus la saisie non enregistrée. Une matrice devenue
   * décidée fait exception : la donnée stockée fait foi. Retourne true si l'input est inchangé.
   */
  applySavedCalculation(result, revisionAtSend) {
    const inputUnchanged = revisionAtSend === this._inputRevision;
    if (inputUnchanged || !this.isEditable) {
      this.calc = result.calculation;
      this._calcPending = false;
      this.adoptRplsrPlan(result.rplsrPlan);
    } else {
      this.recompute();
    }
    return inputUnchanged;
  }

  /**
   * Une seule sauvegarde à la fois : chaque appel attend la précédente puis reconstruit son input
   * à l'exécution, donc repart avec l'Id de matrice obtenu. Sans cela, deux sauvegardes concurrentes
   * sur une matrice neuve partent toutes deux sans Id et créent deux matrices.
   */
  enqueueSave(task) {
    const previous = this._saveTail;
    const run = previous ? previous.then(task) : task();
    const tail = run
      .catch(() => {})
      .then(() => {
        if (this._saveTail === tail) {
          this._saveTail = undefined;
        }
      });
    this._saveTail = tail;
    return run;
  }

  persist(apexMethod, successMessage, options = {}) {
    return this.enqueueSave(() =>
      this.doPersist(apexMethod, successMessage, options)
    );
  }

  /**
   * Avant d'ouvrir la modale de dérogation : annule l'autosave programmée, attend celle en cours,
   * puis enregistre le brouillon s'il n'existe pas encore ou s'il a des modifications en attente.
   * Sans toast de succès (la modale tient lieu de retour) ; un échec est affiché par `doPersist` et
   * relancé pour que la modale ne s'ouvre pas.
   */
  async ensureDraftSaved() {
    clearTimeout(this._autosaveTimer);
    await this.enqueueSave(async () => {
      if (!this.isEditable || (this.matrixId && !this._isDirty)) {
        return;
      }
      await this.doPersist(saveDraftApex, undefined, {
        rethrow: true,
        silent: true
      });
    });
  }

  async doPersist(
    apexMethod,
    successMessage,
    { rethrow = false, silent = false } = {}
  ) {
    if (!this.syncDateInputs()) {
      const error = new Error(this.labels.dateUnreadable);
      this.showToast(this.labels.errorTitle, error.message, "error");
      if (rethrow) {
        throw error;
      }
      return;
    }
    if (!this.positionId) {
      const error = new Error(this.labels.noPositionSelectedError);
      this.showToast(this.labels.errorTitle, error.message, "error");
      if (rethrow) {
        throw error;
      }
      return;
    }
    // Session 167 : besoin non visible → aucune écriture (même modèle que la garde ci-dessus).
    if (this.positionAccessDenied) {
      const error = new Error(this.labels.positionAccessDeniedSaveError);
      this.showToast(this.labels.errorTitle, error.message, "error");
      if (rethrow) {
        throw error;
      }
      return;
    }
    // Même garde que le serveur (session 24, généralisée en session 28, cf. blockingConditions) :
    // évite un aller-retour pour un blocage déjà connu côté client.
    if (this.hasBlockingCondition) {
      this.showToast(
        this.labels.errorTitle,
        this.blockingConditionsMessage,
        "error"
      );
      if (rethrow) {
        throw new Error(this.blockingConditionsMessage);
      }
      return;
    }
    this.isSaving = true;
    this._autosaveState = "saving";
    const revisionAtSend = this._inputRevision;
    try {
      const result = await apexMethod({
        inputJson: JSON.stringify(this.buildMatrixInput())
      });
      this.announceMatrixId(result.matrixId);
      this.setStatusFromServer(result.status);
      const inputUnchanged = this.applySavedCalculation(result, revisionAtSend);
      if (!silent) {
        this.showToast(this.labels.successTitle, successMessage, "success");
      }
      logNotificationFailure("validation", result.notificationWarningDetail);
      if (inputUnchanged) {
        this._isDirty = false;
        this.syncBeforeUnloadListener();
        this.lastAutosaveAt = new Date();
        this._autosaveState = "saved";
      } else {
        this._autosaveState = "dirty";
      }
    } catch (error) {
      this.showToast(this.labels.errorTitle, this.reduceError(error), "error");
      this._autosaveState = "dirty";
      if (rethrow) {
        throw error;
      }
    } finally {
      this.isSaving = false;
    }
  }

  /** Recharge la liste des valideurs pour la matrice courante (session 79 : résout le DA/DD du
   * créateur au lieu de lister tous les valideurs par entité). Appelé au clic « Demander une
   * dérogation » ou quand l'entité change. Gère l'état bloquant explicite (ni DA ni DD du créateur).
   */
  async loadValidatorOptions() {
    try {
      if (!this.matrixId) {
        this.validatorOptions = [];
        this.derogationValidationError = this.labels.matrixNotFoundSaveFirst;
        return;
      }

      const result = await getValidatorOptionsForMatrix({
        matrixId: this.matrixId
      });

      if (result.blocked) {
        // État bloquant explicite : ni DA ni DD du créateur
        this.validatorOptions = [];
        this.derogationValidationError = result.blockedReason;
        this.isDerogationButtonDisabled = true;
        return;
      }

      this.isDerogationButtonDisabled = false;
      this.derogationValidationError = undefined;
      this.validatorOptions = result.options.map((opt) => ({
        label: opt.role ? `${opt.userName} — ${opt.role}` : opt.userName,
        value: opt.userId
      }));

      // Session 79 : si une seule option, la présélectionner automatiquement
      if (this.validatorOptions.length === 1) {
        this.derogationValidatorId = this.validatorOptions[0].value;
      } else {
        // Invalider le valideur sélectionné s'il n'appartient plus à la nouvelle liste
        if (this.derogationValidatorId) {
          const stillValid = this.validatorOptions.some(
            (opt) => opt.value === this.derogationValidatorId
          );
          if (!stillValid) {
            this.derogationValidatorId = undefined;
          }
        }
      }
    } catch (error) {
      console.error("loadValidatorOptions error:", error);
      this.derogationValidationError = this.labels.errorLoadingValidators;
      this.isDerogationButtonDisabled = true;
    }
  }

  async handleOpenDerogationModal() {
    // Session 107 : vérifier les prérequis avant d'ouvrir la modale de dérogation
    const canProceed = await this.checkValidationPrerequisites();
    if (!canProceed) {
      return;
    }

    try {
      await this.ensureDraftSaved();
    } catch {
      // Le toast d'erreur a déjà été affiché par la sauvegarde : la modale reste fermée.
      return;
    }

    this._derogationReasonDraft = "";
    this.hasDerogationComment = false;
    this.derogationReasonIds = [];
    this.derogationValidatorId = undefined;
    this.derogationValidationError = undefined;

    // Session 79 : charger les options DA/DD du créateur pour cette matrice spécifique
    await this.loadValidatorOptions();

    this.showDerogationModal = true;
  }

  handleCloseDerogationModal() {
    this.showDerogationModal = false;
  }

  handleCloseValidationPrerequisitesPanel() {
    this.showValidationPrerequisitesPanel = false;
  }

  derogationToastDismissed = false;

  get showDerogationToast() {
    return !!this.pendingDerogation && !this.derogationToastDismissed;
  }

  handleDismissDerogationToast(event) {
    event.stopPropagation();
    this.derogationToastDismissed = true;
  }

  handleOpenDerogationDecision() {
    if (!this.pendingDerogation) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("opendecision", {
        detail: {
          derogationId: this.pendingDerogation.derogationId
        }
      })
    );
  }

  // Session 156 : mutation directe sans réassignment — évite le re-rendu du simulateur.
  handleDerogationReasonChange(event) {
    const textarea = event.target;
    this._derogationReasonDraft = textarea.value || "";
    // Session 220 : réactif uniquement au passage vide ↔ rempli, pour le bouton « Envoyer ».
    const hasComment = this._derogationReasonDraft.trim() !== "";
    if (hasComment !== this.hasDerogationComment) {
      this.hasDerogationComment = hasComment;
    }
    // `required` pose l'astérisque, mais son message natif restait affiché après
    // saisie. Revalidation à chaque changement : efface le message dès que le champ est rempli.
    textarea.setCustomValidity("");
    textarea.reportValidity();
  }

  handleDerogationReasonsChange(event) {
    this.derogationReasonIds = Array.isArray(event.detail.selectedIds)
      ? event.detail.selectedIds
      : [];
  }

  handleDerogationValidatorChange(event) {
    this.derogationValidatorId = event.detail.value;
  }

  async handleConfirmDerogation() {
    // Session 167 : la demande de dérogation écrit la matrice — bloquée comme Sauvegarder/Valider.
    if (this.positionAccessDenied) {
      this.showToast(
        this.labels.errorTitle,
        this.labels.positionAccessDeniedSaveError,
        "error"
      );
      return;
    }
    if (
      (this.derogationReasonIds || []).length === 0 ||
      !this.derogationValidatorId ||
      !this.hasDerogationComment
    ) {
      this.showToast(
        this.labels.errorTitle,
        this.labels.derogationRequiredFields,
        "error"
      );
      return;
    }
    if (this.hasBlockingCondition) {
      this.showToast(
        this.labels.errorTitle,
        this.blockingConditionsMessage,
        "error"
      );
      return;
    }
    this.isSaving = true;
    try {
      const result = await requestDerogationApex({
        reqJson: JSON.stringify({
          matrixInput: this.buildMatrixInput(),
          reason: this._derogationReasonDraft,
          selectedValidatorId: this.derogationValidatorId,
          derogationReasonIds: this.derogationReasonIds
        })
      });
      this.announceMatrixId(result.matrixId);
      this.setStatusFromServer(result.status);
      this.showDerogationModal = false;
      this.showToast(
        this.labels.successTitle,
        this.labels.derogationRequested,
        "success"
      );
      logNotificationFailure("request", result.notificationWarningDetail);
      this._isDirty = false;
      this.syncBeforeUnloadListener();
    } catch (error) {
      this.showToast(this.labels.errorTitle, this.reduceError(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    return reduceErrors(error);
  }

  get showDraftBanner() {
    return !this.draftBannerDismissed && !!this.draftResumeInfo;
  }

  get draftBannerLabel() {
    if (!this.draftResumeInfo) {
      return "";
    }
    const time = new Date(
      this.draftResumeInfo.lastModifiedDate
    ).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
    return formatLabel(
      this.labels.resumeDraftBanner,
      this.draftResumeInfo.name,
      this.draftResumeInfo.accountName || "—",
      time
    );
  }

  // Trois états visibles (session 39, remplace l'unique état "enregistré" — jugé illisible au
  // contrôle navigateur du 31/08 : couleur trop peu contrastée et aucun signal pendant la saisie ou
  // l'appel serveur, cf. autosaveIndicatorStateClass pour la couleur du point associé à chaque état).
  get showAutosaveIndicator() {
    return this.hasPosition && this.isEditable && !!this._autosaveState;
  }

  get autosaveIndicatorLabel() {
    if (this._autosaveState === "saving") {
      return this.labels.saving;
    }
    if (this._autosaveState === "saved" && this.lastAutosaveAt) {
      const time = this.lastAutosaveAt.toLocaleTimeString("fr-FR", {
        hour: "2-digit",
        minute: "2-digit"
      });
      return formatLabel(this.labels.savedAt, time);
    }
    if (this._autosaveState === "dirty") {
      return this.labels.modified;
    }
    return "";
  }

  get autosaveIndicatorStateClass() {
    return `autosave-indicator autosave-indicator-${this._autosaveState || "none"}`;
  }

  get hasPosition() {
    return !!this.positionId;
  }

  get showPositionSelector() {
    return !this.positionLocked && !this.hasPosition;
  }

  // Session 83 §1 : enrichir les résultats de recherche avec une classe CSS pour surbrillancer le
  // résultat sélectionné (positionId correspondant à selectedPositionId). Le template ne peut pas
  // faire de comparaison inline dans for:each, donc on recalcule un getter qui pose la classe sur
  // chaque item et itère sur cette version enrichie.
  get enrichedPositionSearchResults() {
    return this.positionSearchResults.map((opt) => {
      const isSelected = opt.positionId === this.selectedPositionId;
      return {
        ...opt,
        isSelected,
        rowClass: isSelected
          ? "besoin-result-item position-dropdown-selected"
          : "besoin-result-item"
      };
    });
  }

  get showNoPositionResults() {
    // Session 85 : aligner le seuil au seuil de déclenchement de la recherche (1 caractère, session 83)
    return (
      this.showPositionDropdown &&
      !this.isSearchingPositions &&
      this.positionSearchTerm.length >= 1 &&
      this.positionSearchResults.length === 0
    );
  }

  get hasPositionPreview() {
    return !!this.selectedPositionPreview;
  }

  get hasPreviewAccount() {
    // Session 85 : vérifier si un compte est disponible pour le lien cliquable
    return (
      this.selectedPositionPreview && !!this.selectedPositionPreview.accountId
    );
  }

  // Session 86 (i18n) : aria-label paramétré, composé ici plutôt que dans le template — un template
  // LWC ne peut pas appeler formatLabel() avec un argument.
  get openAccountRecordAriaLabel() {
    return this.selectedPositionPreview
      ? formatLabel(
          this.labels.openAccountRecordAriaLabel,
          this.selectedPositionPreview.accountName
        )
      : "";
  }

  get positionPreviewCreatedDateFormatted() {
    if (
      !this.selectedPositionPreview ||
      !this.selectedPositionPreview.createdDate
    ) {
      return "";
    }
    const date = new Date(this.selectedPositionPreview.createdDate);
    return date.toLocaleDateString("fr-FR", {
      day: "numeric",
      month: "long",
      year: "numeric"
    });
  }

  get positionPreviewStartDateFormatted() {
    if (
      !this.selectedPositionPreview ||
      !this.selectedPositionPreview.startDate
    ) {
      return "";
    }
    const date = new Date(this.selectedPositionPreview.startDate);
    return date.toLocaleDateString("fr-FR", {
      day: "numeric",
      month: "long",
      year: "numeric"
    });
  }

  get hasMarketReference() {
    return !!this.marketReference;
  }

  get prefillBannerCount() {
    const count = this.prefillBannerItems.length;
    return count === 1
      ? this.labels.fieldFilledSingular
      : this.labels.fieldFilledPlural;
  }

  // Session 86 (i18n) : même raison que openAccountRecordAriaLabel ci-dessus.
  get prefillFromRecordLabel() {
    return formatLabel(
      this.labels.prefillFromRecord,
      this.prefillConsultantLabel
    );
  }

  /**
   * Arguments de vente (session 28, spec §5.1/§6.4) : recalculés à chaque rendu à partir de
   * `calc`/`marketReference`/`rfaPercent` déjà chargés — aucun appel serveur dédié, le producteur
   * algorithmique (arSalesArgumentsEngine) est une fonction pure. `corridorPercents` reprend celui
   * effectivement affiché (grand compte, défaut, ou figé sur une matrice décidée), jamais recalculé
   * séparément.
   */
  get salesArgumentsResult() {
    return buildSalesArguments({
      proposedTjm: this.effectiveTjm,
      currencyCode: this.currencyCode,
      totalDailyCost: this.calc.totalDailyCost,
      mc2PerDay: this.calc.mc2PerDay,
      mc2PercentHuman: this.calc.mc2PercentHuman,
      corridorSegment: this.calc.corridorSegment,
      corridorPercents: this.corridorPercents,
      marketReference: this.marketReference,
      rfaPercent: this.rfaPercent
    });
  }

  get salesArguments() {
    return this.salesArgumentsResult.arguments;
  }

  get salesArgumentsUnavailableNotes() {
    return this.salesArgumentsResult.unavailableNotes;
  }

  /** Signale que le cercle retenu a été resserré par séniorité (session 28) — TOUJOURS qualifié
   * d'approximatif à l'écran, jamais présenté comme une donnée fiable (cf. AR_ComparablesService). */
  get showMarketSeniorityNote() {
    return !!(this.marketReference && this.marketReference.seniorityNarrowed);
  }

  get marketConfidenceClass() {
    return this.marketReference
      ? `confidence-badge confidence-${this.marketReference.confidenceLevel}`
      : "confidence-badge";
  }

  get marketConfidenceLabel() {
    return this.marketReference
      ? CONFIDENCE_LABELS[this.marketReference.confidenceLevel]
      : "";
  }

  get marketConfidenceValueClass() {
    const level = this.marketReference?.confidenceLevel;
    return `market-stat-value ${level ? `confidence-${level}` : ""}`.trim();
  }

  get vieReferentialNote() {
    return formatLabel(I18N.AR_PMS_VieReferentialNote, this.vieCountryLabel);
  }

  /** Quelle ligne du référentiel Nearshore est appliquée : exacte ou par défaut. */
  get nearshoreReferentialNote() {
    const row = this.selectedNearshoreReferential;
    if (!row) {
      return "";
    }
    if (row.seniority === NEARSHORE_DEFAULT_SENIORITY) {
      return this.seniorityLevel
        ? formatLabel(
            I18N.AR_PMS_NearshoreRateAppliedDefault,
            row.country,
            this.seniorityLevel
          )
        : formatLabel(I18N.AR_PMS_NearshoreRateAppliedDefaultOnly, row.country);
    }
    return formatLabel(
      I18N.AR_PMS_NearshoreRateApplied,
      row.country,
      row.seniority
    );
  }

  get rfaBreakdownLabel() {
    return formatLabel(I18N.AR_PMS_RfaLine, this.rfaPercent);
  }

  get marketConfidenceShortLabel() {
    const level = this.marketReference?.confidenceLevel;
    if (level === "high") return I18N.AR_PMS_ConfidenceHighShort;
    if (level === "medium") return I18N.AR_PMS_ConfidenceMediumShort;
    return this.marketConfidenceLabel;
  }

  get showMarketStats() {
    return (
      !this.isLoadingMarketReference &&
      !!this.marketReference &&
      this.marketReference.hasEnoughData
    );
  }

  get showMarketLowConfidence() {
    return (
      !this.isLoadingMarketReference &&
      !!this.marketReference &&
      !this.marketReference.hasEnoughData
    );
  }

  /**
   * Défaut multi-devises (session 26, cf. prompts/session-26-devise-reperes-et-finitions.md §1) :
   * `AR_ComparablesService.getMarketReference` **annonce** la devise dans laquelle il répond
   * (`marketReference.currencyCode`) — EUR quand il n'a pas pu convertir (pas de taux disponible, ou
   * devise cible déjà EUR), la devise de la matrice quand la conversion a réussi (`isConverted`).
   * C'est le seul contrat sur lequel l'appelant a le droit de s'appuyer : jamais `this.currencyCode`
   * (la devise de la matrice) pour formater un montant issu de `marketReference` — c'est exactement
   * la confusion qui a produit le défaut (des euros affichés sous un symbole de livre).
   */
  get marketReferenceUsableForGauge() {
    return !!(
      this.marketReference &&
      this.marketReference.hasEnoughData &&
      this.marketReference.currencyCode === this.currencyCode
    );
  }

  /** Situation 3 du §1 : comparables restés en EUR faute de taux, alors que l'affaire est dans une autre devise. */
  get marketReferenceCurrencyMismatch() {
    return !!(
      this.marketReference &&
      this.marketReference.hasEnoughData &&
      this.marketReference.currencyCode !== this.currencyCode
    );
  }

  get formattedMarketMedian() {
    return this.showMarketStats
      ? formatMoney(
          this.marketReference.medianTjm,
          this.marketReference.currencyCode
        )
      : "—";
  }

  get formattedMarketP90() {
    return this.showMarketStats
      ? formatMoney(
          this.marketReference.p90Tjm,
          this.marketReference.currencyCode
        )
      : "—";
  }

  /** Situation 3 du §1 : mention explicite quand les repères restent en EUR faute de taux. */
  get showMarketNoRateNote() {
    return this.marketReferenceCurrencyMismatch;
  }

  get marketNoRateNote() {
    if (!this.showMarketNoRateNote) {
      return "";
    }
    return formatLabel(this.labels.marketNoRateNote, this.currencyCode);
  }

  get marketLowConfidenceMessage() {
    if (!this.marketReference) {
      return "";
    }
    const n = this.marketReference.comparableCount;
    if (n <= 0) {
      return this.labels.noComparablePlacement;
    }
    const placementWord =
      n > 1 ? this.labels.placementPlural : this.labels.placementSingular;
    const comparableWord =
      n > 1 ? this.labels.comparablePlural : this.labels.comparableSingular;
    return formatLabel(
      this.labels.lowConfidenceMessage,
      n,
      placementWord,
      comparableWord
    );
  }

  /**
   * Contenu du popover d'explicabilité « Repères marché » (session 71) — moteur pondéré.
   * Détaille les poids réels (lus du serveur) et les deux vrais circleCode actuels.
   */
  get marketCircleExplanation() {
    if (!this.marketReference) {
      return "";
    }

    const weights = this.marketReference;
    const metierLabel = formatLabel(
      this.labels.weightMetier,
      weights.weightMetierPercent || 50
    );
    const secteurLabel = formatLabel(
      this.labels.weightSecteur,
      weights.weightSecteurPercent || 30
    );
    const clientLabel = formatLabel(
      this.labels.weightClientPct,
      weights.weightClientPercent || 20
    );

    const byCode = {
      no_country_specified: this.labels.noCountrySpecified,
      weighted_metier_secteur_client: formatLabel(
        this.labels.weightedExplanation,
        metierLabel,
        secteurLabel,
        clientLabel
      )
    };

    return (
      byCode[this.marketReference.circleCode] ||
      this.marketReference.circleLabel
    );
  }

  get marketPeriodLabel() {
    if (!this.marketReference) {
      return "";
    }
    return `${this.formatFrenchDate(this.marketReference.periodStart)} → ${this.formatFrenchDate(this.marketReference.periodEnd)}`;
  }

  // Session 86 (i18n) : même raison que openAccountRecordAriaLabel ci-dessus.
  get modalFooterNote() {
    return formatLabel(this.labels.modalFooterNote, this.marketPeriodLabel);
  }

  get marketConfidenceExplanation() {
    if (!this.marketReference) {
      return "";
    }
    const n = this.marketReference.comparableCount;
    const levelLabel =
      CONFIDENCE_LABELS[this.marketReference.confidenceLevel] || "";
    const comparableWord =
      n > 1 ? this.labels.comparablePlural : this.labels.comparableSingular;
    const countLabel = `${n} ${comparableWord}`;
    const highMin = this.marketReference.highConfidenceMin;
    const mediumMin = this.marketReference.mediumConfidenceMin;
    let base;
    if (!this.marketReference.hasEnoughData) {
      base = formatLabel(
        this.labels.confidenceExplanationNotEnough,
        countLabel,
        levelLabel.toLowerCase(),
        mediumMin
      );
    } else {
      base = formatLabel(
        this.labels.confidenceExplanationEnough,
        countLabel,
        levelLabel.toLowerCase(),
        highMin,
        mediumMin
      );
    }
    // Session 24b : un comparable converti depuis l'EUR est moins fiable qu'un comparable natif
    // (taux du jour + historique GBP/MAD aujourd'hui inexistant) — la confiance affichée est déjà
    // déclassée côté serveur, mais la raison doit rester visible, pas seulement le résultat.
    return this.marketReference.isConverted
      ? `${base}${this.labels.confidenceDowngradedNote}`
      : base;
  }

  get showMarketConversionNote() {
    return !!(this.marketReference && this.marketReference.isConverted);
  }

  /** Mention explicite de la source et du taux (décision produit du 18/08/2026, cf. docs/24-multidevise.md). */
  get marketConversionNote() {
    if (!this.showMarketConversionNote) {
      return "";
    }
    const sourceLabel = formatMoney(
      this.marketReference.medianTjmEurSource,
      "EUR"
    );
    const rateLabel = Number(
      this.marketReference.conversionRateApplied
    ).toLocaleString("fr-FR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    });
    return formatLabel(this.labels.conversionNote, sourceLabel, rateLabel);
  }

  /** Session 71 : score de similarité moyen du pool retenu, affiché en pourcentage (0-100). */
  get marketSimilarityScoreLabel() {
    if (
      !this.marketReference ||
      this.marketReference.similarityScoreAvg == null
    ) {
      return "";
    }
    const percentage = Math.round(
      this.marketReference.similarityScoreAvg * 100
    );
    return `${percentage}%`;
  }

  /** Session 71 : seuil minimum d'effectif pondéré pour « confiance moyenne » (affiché en étape 4 du pipeline). */
  get marketMinimumConfidence() {
    if (
      !this.marketReference ||
      this.marketReference.mediumConfidenceMin == null
    ) {
      return "3,0";
    }
    return Number(this.marketReference.mediumConfidenceMin).toLocaleString(
      "fr-FR",
      {
        minimumFractionDigits: 1,
        maximumFractionDigits: 1
      }
    );
  }

  /** Session 72 : labels de poids pour affichage dans les barres (étape 3 du pipeline). */
  get metierPercentLabel() {
    const r = this.marketReference;
    if (!r) return "";
    const target = r.resolvedMetierLabel ? `${r.resolvedMetierLabel} : ` : "";
    return `${target}${Math.round(r.avgMetierMatchPercent ?? 0)} %`;
  }

  get secteurPercentLabel() {
    const r = this.marketReference;
    if (!r) return "";
    const target = r.resolvedSecteurLabel ? `${r.resolvedSecteurLabel} : ` : "";
    return `${target}${Math.round(r.avgSecteurMatchPercent ?? 0)} %`;
  }

  get clientPercentLabel() {
    return `${Math.round(this.marketReference?.avgClientMatchPercent ?? 0)} %`;
  }

  /** Session 72 : styles des barres de poids (LWC ne permet pas d'expression style dynamique inline). */
  get metierBarStyle() {
    return `width:${Math.round(this.marketReference?.avgMetierMatchPercent ?? 0)}%`;
  }

  get secteurBarStyle() {
    return `width:${Math.round(this.marketReference?.avgSecteurMatchPercent ?? 0)}%`;
  }

  get clientBarStyle() {
    return `width:${Math.round(this.marketReference?.avgClientMatchPercent ?? 0)}%`;
  }

  /** Session 73 : résultats réels du moteur — effictif pondéré */
  get marketWeightedEffectiveLabel() {
    return this.marketReference?.weightedEffectiveCount != null
      ? Number(this.marketReference.weightedEffectiveCount).toLocaleString(
          "fr-FR",
          {
            minimumFractionDigits: 1,
            maximumFractionDigits: 1
          }
        )
      : "—";
  }

  /** Session 73 : pays retenu pour le calcul des comparables */
  get marketCountryLabel() {
    return this.marketReference?.resolvedCountry || "—";
  }

  /** Session 78 : pondération métier */
  get marketMetierRealizedLabel() {
    return formatLabel(
      this.labels.weighting,
      Math.round(this.marketReference?.weightMetierPercent ?? 50)
    );
  }

  /** Session 78 : pondération secteur */
  get marketSecteurRealizedLabel() {
    return formatLabel(
      this.labels.weighting,
      Math.round(this.marketReference?.weightSecteurPercent ?? 30)
    );
  }

  /** Session 78 : pondération client */
  get marketClientRealizedLabel() {
    return formatLabel(
      this.labels.weighting,
      Math.round(this.marketReference?.weightClientPercent ?? 20)
    );
  }

  /** Session 73 : indicateurs de seuil actif pour les chips de confiance */
  get isHighConfidenceActive() {
    return this.marketReference?.confidenceLevel === "high";
  }

  get isMediumConfidenceActive() {
    return this.marketReference?.confidenceLevel === "medium";
  }

  get isLowConfidenceActive() {
    return this.marketReference?.confidenceLevel === "low";
  }

  get highConfidenceChipClass() {
    return `confidence-chip high ${this.isHighConfidenceActive ? "active" : "inactive"}`;
  }

  get mediumConfidenceChipClass() {
    return `confidence-chip medium ${this.isMediumConfidenceActive ? "active" : "inactive"}`;
  }

  get lowConfidenceChipClass() {
    return `confidence-chip low ${this.isLowConfidenceActive ? "active" : "inactive"}`;
  }

  /** Session 74 : étape 2 - pays retenu dans les comparables */
  get hasResolvedCountry() {
    return !!(this.marketReference && this.marketReference.resolvedCountry);
  }

  /** Session 74 : étape 2 - libellé du type de contrat sélectionné */
  get contractTypeLabel() {
    const opt = CONTRACT_TYPE_OPTIONS.find(
      (o) => o.value === this.contractType
    );
    return opt ? opt.label : this.contractType;
  }

  /** Session 74 : étape 2 - afficher le type de contrat seulement s'il est renseigné */
  get hasContractTypeLabel() {
    return !!this.contractType;
  }

  formatFrenchDate(value) {
    if (!value) {
      return "—";
    }
    return new Date(value).toLocaleDateString("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric"
    });
  }

  /**
   * Libellé "(calculé auto)" + note (Zone 1, session 17, pricing-tool.html:1996-2000). Gardé par
   * `isEditable` (session 18b) : la note contient littéralement « — modifiable », qui n'a pas de
   * sens sur une matrice verrouillée — `handleValidate` change `this.status` sans repasser par
   * `applyInput`, donc sans ce garde-fou une matrice tout juste validée garderait la note visible
   * jusqu'au prochain rechargement.
   */
  /** Jours facturables = jours de mission − congés prévus (plancher 0) ; congés comptés 0 en régie. */
  get billableDays() {
    return calcBillableDays({
      missionDays: this.numberOfDays,
      plannedLeaveDays: this.rplsrEnabled ? 0 : this.plannedLeaveDays
    });
  }

  /** « Jours facturables : N », masqué tant que la durée de mission est inconnue. */
  get billableDaysText() {
    if (this.numberOfDays === null || this.numberOfDays === undefined) {
      return null;
    }
    return formatLabel(this.labels.billableDays, formatDays(this.billableDays));
  }

  /** Congés supérieurs aux jours de mission : message sous le champ (la validation est bloquée côté serveur). */
  get leaveExceedsMission() {
    const leave = Number(this.plannedLeaveDays) || 0;
    return leave > 0 && leave > (Number(this.numberOfDays) || 0);
  }

  get plannedLeaveInputValue() {
    return this.plannedLeaveDays === null || this.plannedLeaveDays === undefined
      ? ""
      : this.plannedLeaveDays;
  }

  get feeMonthlyOtherInputValue() {
    return this.feeMonthlyOther === null || this.feeMonthlyOther === undefined
      ? ""
      : this.feeMonthlyOther;
  }

  get showNumberOfDaysAutoLabel() {
    return this.isEditable && this.numberOfDaysAuto && !this.missionDateError;
  }

  get hasMissionDateError() {
    return !!(this.missionDateError || this.dateInputError);
  }

  get missionDateErrorText() {
    return this.dateInputError || this.missionDateError;
  }

  // Session 88 : badge coloré du statut du besoin
  get selectedPositionPreviewHasStatus() {
    return !!(
      this.selectedPositionPreview && this.selectedPositionPreview.status
    );
  }

  get positionStatusBadgeClass() {
    if (!this.selectedPositionPreview || !this.selectedPositionPreview.status) {
      return "position-preview-badge position-preview-badge-neutral";
    }
    const status = this.selectedPositionPreview.status;
    const successStatuses = ["Open", "Sur Opportunité"];
    const dangerStatuses = ["Signature puis désistement"];
    if (successStatuses.includes(status)) {
      return "position-preview-badge position-preview-badge-success";
    }
    if (dangerStatuses.includes(status)) {
      return "position-preview-badge position-preview-badge-danger";
    }
    return "position-preview-badge position-preview-badge-neutral";
  }

  /**
   * Rendu lecture seule des champs mission Zone 1 (session 17b, contrôle Chrome du 09/08) : sur une
   * matrice verrouillée, les contrôles interactifs (combobox, sélecteur de date) sont remplacés par
   * un simple `lightning-input` désactivé affichant la valeur ou « — » — plus de placeholder invitant
   * à saisir (« Sélectionner une entité », « Prénom NOM »…) ni de sélecteur de date grisé sans valeur
   * lisible sur un enregistrement qu'on ne peut plus modifier.
   */
  get displayEntity() {
    if (!this.entity) {
      return "—";
    }
    const option = this.entityOptions.find((o) => o.value === this.entity);
    return (option && option.label) || this.entityName || "—";
  }

  // Session 54 : la valeur du lookup (consultantLabel) prime sur l'ancien texte libre pour
  // l'affichage lecture seule (matrice verrouillée post-décision) — le texte libre reste un repli,
  // jamais les deux affichés comme des données concurrentes.
  get displayConsultantName() {
    return this.consultantLabel || this.consultantName || "—";
  }

  get showNoConsultantResults() {
    return (
      this.showConsultantDropdown &&
      !this.isSearchingConsultants &&
      this.consultantSearchTerm.length >= 1 &&
      this.consultantSearchResults.length === 0
    );
  }

  /** Bandeau de suggestion (session 54) : uniquement quand aucun consultant n'est déjà sélectionné —
   * ne doit jamais réapparaître après que l'utilisateur l'a explicitement écartée ou utilisée. */
  get showConsultantSuggestion() {
    return !this.consultantId && !!this.suggestedConsultantId;
  }

  /** Ancien texte libre (6 matrices historiques sur 47 au 05/09/2026) affiché en lecture seule à
   * titre d'historique quand aucun lookup n'a encore été sélectionné pour cette matrice — jamais
   * modifiable, cf. AR_Consultant_Name__c.field-meta.xml. */
  get showLegacyConsultantName() {
    return !this.consultantId && !!this.consultantName;
  }

  /**
   * Pays affiché en Zone 1 (session 141) : celui de l'ENTITÉ sélectionnée, lu sur la fiche du
   * référentiel — jamais celui du besoin Connexys (« France » par défaut, trompeur). Entité sans
   * pays : « Non renseigné », sans repli sur le pays du besoin. Aucune entité : pays du besoin,
   * comme avant. Getter dérivé de `entity` : recalculé tout seul au changement d'entité comme à la
   * réhydratation d'une matrice (le pays n'est pas stocké sur la matrice).
   */
  get entityCountry() {
    if (!this.entity) {
      return null;
    }
    const option = this.entityOptions.find((o) => o.value === this.entity);
    const defaults = this.entityPricingDefaults.get(this.entity);
    return (option && option.country) || (defaults && defaults.country) || null;
  }

  get displayCountry() {
    if (!this.entity) {
      return this.positionContext.accountCountry;
    }
    return this.entityCountry || this.labels.entityCountryMissing;
  }

  get showEntityCountryHelp() {
    return !!this.entity && !this.entityCountry && this.isEditable;
  }

  get displayClientSite() {
    return this.clientSite || "—";
  }

  get displayStartDate() {
    return this.formatFrenchDate(this.startDate);
  }

  get displayEndDate() {
    return this.formatFrenchDate(this.endDate);
  }

  /**
   * Bandeau récapitulatif "{profil} — {région} — {secteur}" (Zone 1, session 17, maquette
   * pricing-tool.html:1877-1880) : n'importe lequel des trois peut être absent sur le besoin
   * (cf. PositionContext.perimetre/businessLine, docs/17-contexte-affaire.md) — on affiche les
   * parties disponibles plutôt qu'un tiret orphelin pour la partie manquante.
   */
  get recapBannerParts() {
    return [
      this.positionContext.positionName,
      this.positionContext.perimetre,
      this.positionContext.businessLine
    ].filter((part) => !!part);
  }

  get showRecapBanner() {
    return this.recapBannerParts.length > 0;
  }

  get recapBannerLabel() {
    return this.recapBannerParts.join(" — ");
  }

  /**
   * RÈGLE DE LECTURE SEULE (session 18b, cf. docs/18b-lecture-seule-et-bornes.md) — posée ici une
   * fois pour toutes après deux régressions locales (17b sur les champs mission, 18 sur les champs
   * VIE/Nearshore/INDEP ajoutés sans reprendre le même traitement) :
   *
   * Un champ de saisie a exactement deux représentations, gouvernées par ce seul et même getter
   * `isEditable` :
   *   1. Éditable — le contrôle interactif (input/combobox) PLUS tous ses éléments d'aide à la
   *      saisie (placeholder, encart d'avertissement, mention « modifiable », légende de formule,
   *      message d'écart). Champ isolé sans aide (ex. TJM proposé) : `disabled={isNotEditable}`
   *      suffit, pas de bloc dédié.
   *   2. Verrouillé — uniquement la valeur formatée (ou « — » si vide), sans aucun texte d'aide.
   *
   * Pour un champ à aides multiples (sélecteur pays + CJM + encart + note d'écart, ou mark-up +
   * légende + alerte), les DEUX représentations vivent chacune dans un unique bloc
   * `<template if:true={isEditable}>` / `<template if:false={isEditable}>` dans le HTML — jamais un
   * `if:true` séparé par aide. Un nouvel élément d'aide s'ajoute TOUJOURS à l'intérieur du bloc
   * `if:true={isEditable}` déjà existant du champ concerné : il en hérite par construction, sans
   * qu'il faille penser à le conditionner soi-même.
   *
   * Pour un champ à aide unique (légende seule, note seule), gager directement le getter de l'aide
   * avec `this.isEditable &&` reproduit la même règle avec moins de structure — toujours le même
   * test réutilisé, jamais un booléen inventé pour l'occasion.
   */
  /** Session 282 : seul un `canEdit === false` explicite du serveur verrouille (absent = comportement antérieur). */
  applyAccess(input) {
    this.readOnlyAccess = !!input && input.canEdit === false;
    this.readOnlyOwnerName = (input && input.ownerName) || "";
  }

  get readOnlyBannerMessage() {
    if (!this.readOnlyAccess) {
      return null;
    }
    return formatLabel(
      this.labels.readOnlyBanner,
      this.readOnlyOwnerName || "—"
    );
  }

  get isEditable() {
    // Lecture seule (session 282) : aucune saisie, aucune action d'écriture, calcul figé sur le stocké.
    if (this.readOnlyAccess) {
      return false;
    }
    // Un statut inconnu (jamais censé arriver après la correction Apex de la session 28b, mais
    // défendu ici pour ne plus jamais dépendre de cette seule garantie) n'est jamais traité comme
    // "décidé" : le formulaire reste éditable plutôt que de se verrouiller sur une valeur qui n'a
    // aucun sens métier. Ce même getter conditionne aussi applyFrozenCalculationIfDecided() : un
    // statut inconnu ne peut donc pas non plus déclencher un gel de calcul erroné.
    return this.status === "Brouillon" || !KNOWN_STATUSES.includes(this.status);
  }

  /**
   * Point de passage unique pour toute affectation de `status` reçue du serveur (session 28b §1) :
   * un statut absent/inconnu doit être tracé (anomalie technique à investiguer), jamais silencieux —
   * mais ne doit jamais non plus verrouiller le formulaire, cf. `isEditable` ci-dessus, qui traite
   * déjà tout statut hors `KNOWN_STATUSES` comme éditable.
   */
  setStatusFromServer(value) {
    if (!KNOWN_STATUSES.includes(value)) {
      console.error(
        `arPriceMatrixSimulator : statut de matrice absent ou inconnu reçu du serveur ("${value}") — traité comme éditable plutôt que de verrouiller le formulaire.`
      );
    }
    this.status = value;
  }

  async loadPendingDerogation() {
    if (!this.matrixId) {
      this.pendingDerogation = null;
      return;
    }
    try {
      const result = await getPendingDerogationForCurrentUser({
        matrixId: this.matrixId
      });
      if (result) {
        this.pendingDerogation = result;
        const date = new Date(result.requestedAt);
        this.pendingDerogationDate = date.toLocaleDateString("fr-FR");
      } else {
        this.pendingDerogation = null;
      }
    } catch (error) {
      console.error("Error loading pending derogation:", error);
      this.pendingDerogation = null;
    }
  }

  /**
   * Blocage client (session 24) : une devise sans taux ne doit jamais être traitée comme un taux
   * de 1 (CLAUDE.md — erreur de facteur invisible à l'écran). Le serveur bloque déjà
   * (AR_CurrencyRateService.NoRateAvailableException, remontée par
   * AR_PricingMatrixService.calculateAndPopulate) ; ce bandeau + la désactivation des boutons
   * évitent à l'utilisateur un aller-retour serveur pour découvrir le blocage.
   */
  get noRateBannerMessage() {
    if (!this.noRateAvailable) {
      return null;
    }
    return formatLabel(this.labels.noRateBanner, this.currencyCode);
  }

  /**
   * Référentiel VIE/Nearshore incomplet (session 28, cf. prompts/session-28-ecarts-contractuels.md
   * §2) : même règle que le taux de change absent ci-dessus, généralisée. Mirroir client de
   * AR_PricingMatrixService.loadVieAllowance/loadNearshoreRate — un pays saisi manuellement
   * (cjmVie/cjmNearshore déjà renseigné) n'est jamais bloquant, quel que soit le référentiel ;
   * sans saisie manuelle, le pays du compte (positionContext.accountCountry) doit avoir une ligne de
   * référentiel, exactement comme le repli serveur (AR_Account_Country__c) — sinon le calcul serait
   * accepté ici et rejeté à l'enregistrement.
   */
  get missingVieReferentialMessage() {
    if (!this.isVIE || (this.cjmVie !== null && this.cjmVie !== undefined)) {
      return null;
    }
    const accountCountry = this.positionContext.accountCountry;
    if (!accountCountry) {
      return this.labels.missingVieReferentialNoCountry;
    }
    const hasReferential = this.vieReferentialOptions.some(
      (opt) => opt.country === accountCountry
    );
    if (hasReferential) {
      return null;
    }
    return formatLabel(
      this.labels.missingVieReferentialWithCountry,
      accountCountry
    );
  }

  get missingNearshoreReferentialMessage() {
    if (this.isNEARSHORE && this.nearshoreRateMissing) {
      return this.nearshoreRateMissing;
    }
    if (
      !this.isNEARSHORE ||
      (this.cjmNearshore !== null && this.cjmNearshore !== undefined)
    ) {
      return null;
    }
    const accountCountry = this.positionContext.accountCountry;
    if (!accountCountry) {
      return this.labels.missingNearshoreReferentialNoCountry;
    }
    const hasReferential = this.nearshoreReferentialOptions.some(
      (opt) => opt.country === accountCountry
    );
    if (hasReferential) {
      return null;
    }
    return formatLabel(
      this.labels.missingNearshoreReferentialWithCountry,
      accountCountry
    );
  }

  /**
   * Liste des conditions bloquantes (session 28 §2) : remplace le drapeau unique `noRateAvailable`
   * par une liste extensible — le taux manquant, le référentiel VIE/Nearshore incomplet, et
   * n'importe quelle autre condition future s'y ajoutent de la même façon, sans dupliquer
   * `isActionDisabled`/`canSaveDraft`/`persist`/`scheduleAutosave` à chaque fois (cf. prompt §2 :
   * "ne duplique pas noRateAvailable en noVieAllowanceAvailable puis un troisième drapeau").
   */
  get blockingConditions() {
    const conditions = [];
    if (this.noRateBannerMessage) {
      conditions.push({ key: "noRate", message: this.noRateBannerMessage });
    }
    if (this.missingVieReferentialMessage) {
      conditions.push({
        key: "missingVieReferential",
        message: this.missingVieReferentialMessage
      });
    }
    if (this.missingNearshoreReferentialMessage) {
      conditions.push({
        key: "missingNearshoreReferential",
        message: this.missingNearshoreReferentialMessage
      });
    }
    return conditions;
  }

  get hasBlockingCondition() {
    return this.blockingConditions.length > 0;
  }

  get blockingConditionsMessage() {
    return this.blockingConditions.map((c) => c.message).join(" ");
  }

  get isActionDisabled() {
    return (
      this.isSaving ||
      this.hasBlockingCondition ||
      this.positionAccessDenied ||
      this.readOnlyAccess
    );
  }

  /** Session 167 : la demande de dérogation écrit la matrice — même blocage que Sauvegarder/Valider. */
  get isDerogationActionDisabled() {
    return this.isDerogationButtonDisabled || this.positionAccessDenied;
  }

  /**
   * Session 157 : Valider n'est actif que si le calcul affiché est à jour de la dernière saisie et
   * qu'aucune sauvegarde (manuelle ou autosave) n'est en cours.
   */
  get isValidateDisabled() {
    return (
      this.isActionDisabled ||
      this._calcPending ||
      this._autosaveState === "saving"
    );
  }

  /**
   * Confiance sur le taux appliqué (session 24) : date d'effet affichée au format ISO brut, pas
   * `Date`/`toLocaleDateString` — AR_Currency_Rate__c.AR_Effective_Date__c arrive en "AAAA-MM-JJ"
   * et un parsing local réintroduirait le décalage UTC classique (jour affiché ≠ jour saisi) pour
   * un simple texte d'aide, sans bénéfice.
   */
  get currencyRateHelpText() {
    if (this.currencyCode === "EUR" || this.noRateAvailable) {
      return null;
    }
    const rateLabel = Number(this.rateResolution.rateToEur).toLocaleString(
      "fr-FR",
      { minimumFractionDigits: 2, maximumFractionDigits: 6 }
    );
    const dateLabel = this.rateResolution.effectiveDate || "—";
    return formatLabel(
      this.labels.currencyRateHelp,
      this.currencyCode,
      rateLabel,
      dateLabel
    );
  }

  // Gate de la génération PTF (session 20) : uniquement matrice validée, jamais Brouillon/En
  // dérogation/Refusée — le serveur (AR_PTFDataService.collect) revalide indépendamment ce statut.
  get isValidatedStatus() {
    return (
      !!this.matrixId &&
      (this.status === "Validée" || this.status === "Validée par dérogation")
    );
  }

  // Entité modifiable seule, sur une matrice validée (Validée / Validée par dérogation).
  get isEntityChangeableOnly() {
    return !this.readOnlyAccess && this.isValidatedStatus;
  }

  get isNotEditable() {
    return !this.isEditable;
  }

  get isCDI() {
    return this.contractType === "CDI";
  }

  get isCDD() {
    return this.contractType === "CDD";
  }

  // CDI et CDD partagent le champ Salaire annuel + le même bloc de rendu (session 28) : seul le
  // coefficient appliqué au calcul du CJM diffère (cf. showCjmHelper/cjmHelperText, qui restent
  // génériques et n'ont donc rien à changer d'autre ici).
  get isSalaryBased() {
    return this.isCDI || this.isCDD;
  }

  get isINDEP() {
    return this.contractType === "INDEP";
  }

  get isVIE() {
    return this.contractType === "VIE";
  }

  get isNEARSHORE() {
    return this.contractType === "NEARSHORE";
  }

  get showOmAndPonctuelsFees() {
    return this.isCDI || this.isCDD || this.isVIE;
  }

  /**
   * Helper CJM sous le salaire (session 15, pricing-tool.html:1911) : coefficient et jours ouvrés
   * dérivés des valeurs réelles (settings + calc.cjm), jamais écrits en dur — contrairement à la
   * maquette qui affiche littéralement « × 2,02 / 218 jours ». Le coefficient est reconstruit par
   * `cjm × jours ÷ salaire` plutôt que recopié depuis la formule (1,01 × 2) : si un jour le
   * coefficient dépend du pays/contrat, ce calcul reste correct sans modification.
   */
  // isEditable (session 18b) : une légende de formule est une aide à la saisie, elle n'a rien à
  // faire sur une matrice verrouillée — cf. la règle posée en tête de fichier.
  get showCjmHelper() {
    return this.isEditable && (this.isCDI || this.isCDD) && !!this.annualSalary;
  }

  get cjmHelperText() {
    if (!this.showCjmHelper) {
      return "";
    }
    const days = this.settings.workingDaysPerYear;
    // Sous le salaire de la période 1 : son propre CJM, jamais le pondéré.
    const cjm = this.calc.salaryPeriods?.[0]?.cjm ?? this.calc.cjm;
    const coefficient = days ? (cjm * days) / this.annualSalary : null;
    const coefficientLabel =
      coefficient != null ? coefficient.toFixed(2).replace(".", ",") : "—";
    return formatLabel(
      this.labels.cjmCalculatedHelper,
      formatMoney(cjm, this.currencyCode),
      coefficientLabel,
      days
    );
  }

  /**
   * Encadré de coût journalier (session 15, pricing-tool.html:2038-2043) : rétabli, absent de l'org.
   * Toutes les valeurs viennent de `calc` (déjà recalculé côté client), aucun appel serveur.
   */
  get formattedCjm() {
    return formatMoney(this.calc.cjm, this.currencyCode);
  }

  /**
   * Options des sélecteurs pays VIE/Nearshore (session 18, maquette pricing-tool.html:1913-1970) :
   * `{drapeau} {pays} — {cjm} €/j`, drapeau décoratif (cf. COUNTRY_FLAGS), montant brut sans
   * formatage FR (comme la maquette — ce sont de petits nombres, pas besoin de séparateur de milliers).
   */
  get vieCountryOptions() {
    return this.vieReferentialOptions.map((opt) => ({
      label: `${countryFlag(opt.country)} ${opt.country} — ${opt.cjm} €${this.labels.perDaySuffix}`,
      value: opt.id
    }));
  }

  /** Un pays n'apparaît qu'une fois, quel que soit le nombre de séniorités tarifées. */
  get nearshoreCountryOptions() {
    const countries = [
      ...new Set(this.nearshoreReferentialOptions.map((opt) => opt.country))
    ];
    return countries.map((country) => ({
      label: `${countryFlag(country)} ${country}`,
      value: country
    }));
  }

  get nearshoreCountryValue() {
    return this.nearshoreChosenCountry || this.nearshoreCountryLabel || null;
  }

  get hasVieCountry() {
    return !!this.vieCountryId;
  }

  get hasNearshoreCountry() {
    return !!this.nearshoreCountryId;
  }

  get hasNearshoreChosenCountry() {
    return !!this.nearshoreCountryValue;
  }

  /** Encart d'avertissement tant qu'aucun pays n'est choisi (maquette pricing-tool.html:1935-1937/1964-1966). */
  get showVieCountryWarning() {
    return !this.hasVieCountry;
  }

  get showNearshoreCountryWarning() {
    return !this.hasNearshoreChosenCountry;
  }

  get selectedVieReferential() {
    return this.vieReferentialOptions.find(
      (opt) => opt.id === this.vieCountryId
    );
  }

  get selectedNearshoreReferential() {
    return this.nearshoreReferentialOptions.find(
      (opt) => opt.id === this.nearshoreCountryId
    );
  }

  get vieCountryLabel() {
    return this.selectedVieReferential
      ? this.selectedVieReferential.country
      : "";
  }

  get nearshoreCountryLabel() {
    return this.selectedNearshoreReferential
      ? this.selectedNearshoreReferential.country
      : "";
  }

  /**
   * Rendu lecture seule des champs VIE/Nearshore/INDEP (session 18b) : valeur formatée ou « — »,
   * rien d'autre — `formatMoney` porte déjà ce fallback (cf. règle posée sur `isEditable`), pas
   * besoin d'un utilitaire dédié de plus.
   */
  get displayVieCountry() {
    return this.vieCountryLabel || "—";
  }

  get displayNearshoreCountry() {
    return this.nearshoreCountryLabel || "—";
  }

  get displayCjmVie() {
    return formatMoney(this.cjmVie, this.currencyCode);
  }

  get displayCjmNearshore() {
    return formatMoney(this.cjmNearshore, this.currencyCode);
  }

  get displayCjmBeforeMarkup() {
    return formatMoney(this.cjmBeforeMarkup, this.currencyCode);
  }

  get displayMarkupApplied() {
    return formatMoney(this.markupApplied, this.currencyCode);
  }

  /**
   * Écart au référentiel (session 18, prompt §3 — ajout délibéré, absent de la maquette) : quand
   * l'utilisateur surcharge le CJM après avoir choisi un pays, le lookup est conservé
   * (`handleVieCountryChange`/`handleFieldChange` ne le touchent jamais l'un sans l'autre) mais le
   * montant affiché n'est plus celui du référentiel — signalé ici plutôt que silencieusement perdu.
   */
  get showVieReferentialMismatch() {
    const ref = this.selectedVieReferential;
    return (
      !!ref &&
      this.cjmVie !== null &&
      this.cjmVie !== undefined &&
      Number(this.cjmVie) !== Number(ref.cjm)
    );
  }

  get showNearshoreReferentialMismatch() {
    const ref = this.selectedNearshoreReferential;
    return (
      !!ref &&
      this.cjmNearshore !== null &&
      this.cjmNearshore !== undefined &&
      Number(this.cjmNearshore) !== Number(ref.cjm)
    );
  }

  get vieReferentialMismatchLabel() {
    // Devise du référentiel (session 24), pas celle de la matrice : ce montant de référence est
    // exprimé dans SA devise à lui, potentiellement différente de currencyCode (cf.
    // showVieReferentialCurrencyMismatch ci-dessous, qui signale précisément ce cas).
    return this.showVieReferentialMismatch
      ? formatLabel(
          this.labels.referentialGapLabel,
          formatMoney(
            this.selectedVieReferential.cjm,
            this.selectedVieReferential.currencyCode
          )
        )
      : "";
  }

  get nearshoreReferentialMismatchLabel() {
    return this.showNearshoreReferentialMismatch
      ? formatLabel(
          this.labels.referentialGapLabel,
          formatMoney(
            this.selectedNearshoreReferential.cjm,
            this.selectedNearshoreReferential.currencyCode
          )
        )
      : "";
  }

  /**
   * Alerte proactive (session 24) : le référentiel choisi porte une devise différente de celle de
   * la matrice — AR_PricingMatrixService.loadVieAllowance/loadNearshoreRate bloqueront le calcul à
   * la sauvegarde (le moteur ne convertit jamais, CLAUDE.md). Signalé avant l'aller-retour serveur,
   * même principe que noRateBannerMessage.
   */
  get showVieReferentialCurrencyMismatch() {
    const ref = this.selectedVieReferential;
    return !!ref && (ref.currencyCode || "EUR") !== this.currencyCode;
  }

  get showNearshoreReferentialCurrencyMismatch() {
    const ref = this.selectedNearshoreReferential;
    return !!ref && (ref.currencyCode || "EUR") !== this.currencyCode;
  }

  get vieReferentialCurrencyMismatchLabel() {
    return this.showVieReferentialCurrencyMismatch
      ? formatLabel(
          this.labels.referentialCurrencyMismatch,
          this.selectedVieReferential.currencyCode,
          this.currencyCode
        )
      : "";
  }

  get nearshoreReferentialCurrencyMismatchLabel() {
    return this.showNearshoreReferentialCurrencyMismatch
      ? formatLabel(
          this.labels.referentialCurrencyMismatch,
          this.selectedNearshoreReferential.currencyCode,
          this.currencyCode
        )
      : "";
  }

  /**
   * Libellés des champs chiffrés avec leur unité (« Repas (€/jour) »). Le symbole vient de la devise
   * courante ; seul le texte entre parenthèses est dans le libellé (sans style discret : lightning-input
   * ne rend que du texte brut dans son label).
   */
  get unitLabels() {
    const sym = currencySymbol(this.currencyCode);
    const withSymbol = (template) => formatLabel(template, sym);
    const isSalaryPremium = this.isCDI || this.isCDD;
    return {
      annualSalary: withSymbol(
        isSalaryPremium ? this.labels.annualSalaryCdi : this.labels.annualSalary
      ),
      cjmBeforeMarkup: withSymbol(this.labels.cjmBeforeMarkup),
      markupCalculated: withSymbol(this.labels.markupCalculated),
      markupApplied: withSymbol(this.labels.markupApplied),
      proposedTjm: withSymbol(this.labels.proposedTjmLabel),
      feeIK: withSymbol(this.labels.feeIK),
      feeMeals: withSymbol(this.labels.feeMeals),
      feeLodging: withSymbol(this.labels.feeLodging),
      feeOther: withSymbol(this.labels.feeOtherDaily),
      feeComputer: withSymbol(this.labels.feeComputer),
      feePhone: withSymbol(this.labels.feePhone),
      feeMonthlyOther: withSymbol(this.labels.feeMonthlyOther),
      feeTraining: withSymbol(this.labels.feeTraining),
      feeEPI: withSymbol(this.labels.feeEPI),
      feeOtherPerMission: withSymbol(this.labels.feeOtherPerMission)
    };
  }

  /** Libellés de frais scindés « nom » / « (unité) » : l'unité est grisée (lightning-input n'accepte que du texte brut). */
  get unitLabelParts() {
    const all = this.unitLabels;
    const parts = {};
    Object.keys(all).forEach((k) => {
      parts[k] = splitUnitLabel(all[k]);
    });
    return parts;
  }

  get gratuityDaysParts() {
    return splitUnitLabel(this.labels.gratuityDays);
  }

  /** Libellés de champ par devise courante (session 24) — remplace le "(€/jour)" en dur. */
  get vieCjmEditableLabel() {
    return formatLabel(
      this.labels.vieCjmEditableLabel,
      currencySymbol(this.currencyCode)
    );
  }

  get vieCjmReadOnlyLabel() {
    return formatLabel(
      this.labels.vieCjmReadOnlyLabel,
      currencySymbol(this.currencyCode)
    );
  }

  get nearshoreCjmEditableLabel() {
    return formatLabel(
      this.labels.nearshoreCjmEditableLabel,
      currencySymbol(this.currencyCode)
    );
  }

  get nearshoreCjmReadOnlyLabel() {
    return formatLabel(
      this.labels.nearshoreCjmReadOnlyLabel,
      currencySymbol(this.currencyCode)
    );
  }

  /**
   * Mark-up calculé INDEP (session 18, maquette pricing-tool.html:1975-1978) : `calc.markupCalcule`
   * était déjà produit par le pipeline (AR_PricingCalculator.compute), simplement jamais affiché —
   * l'utilisateur voyait qu'il dépassait (`calc.markupMismatch`) sans savoir de combien.
   * `formatMoneyPrecise` (session 18b) : un `toFixed(2)` local affichait « 60.00 » (format anglais)
   * au milieu d'un écran entièrement francisé — la valeur passe désormais par le même utilitaire
   * centralisé que le reste du composant plutôt qu'un formatage ad hoc.
   */
  get formattedMarkupCalcule() {
    return formatMoneyPrecise(this.calc.markupCalcule, this.currencyCode);
  }

  /** 18 % et le plafond viennent d'AR_Settings__mdt (`this.settings`), jamais écrits en dur ici. */
  get markupFormulaLegend() {
    return formatLabel(
      this.labels.markupFormulaLegend,
      this.settings.markupPercent,
      this.settings.markupMax
    );
  }

  get formattedCjmTotalIndep() {
    return formatMoney(this.calc.cjm, this.currencyCode);
  }

  /**
   * Détail du calcul de gratuité (session 18, maquette pricing-tool.html:2026-2029) : visible dès
   * que des jours de gratuité sont saisis, quel que soit le statut de contrat (CDI/INDEP/VIE/NEARSHORE
   * y ont tous droit, cf. session 15). Gardé par `isEditable` (session 18b) : c'est une aide à la
   * saisie comme les autres, elle n'a rien à faire sur une matrice verrouillée.
   */
  get showGratuityDetail() {
    return this.isEditable && (this.gratuityDays || 0) > 0 && !!this.calc.cjm;
  }

  /** `formatMoneyPrecise` pour le montant/jour (session 18b, même correctif que le mark-up calculé
   * — un `toFixed(2)` local se cachait ici en paire du précédent) ; `formatMoney` pour le total
   * annuel, déjà le bon format (entier, séparateur de milliers). */
  get gratuityDetailLabel() {
    if (!this.showGratuityDetail) {
      return "";
    }
    const days = this.calc.feePonctuelsDivisorDays || 218;
    const total = this.gratuityDays * this.calc.cjm;
    const perDay = total / days;
    const gratuityLabel = String(this.gratuityDays).replace(".", ",");
    return formatLabel(
      this.labels.gratuityDetail,
      gratuityLabel,
      formatMoney(this.calc.cjm, this.currencyCode),
      formatMoney(total, this.currencyCode),
      formatMoneyPrecise(perDay, this.currencyCode)
    );
  }

  // --- Périodes de TJM (docs/254) : frise, lignes, pied « TJM moyen pondéré » ---

  /**
   * TJM de référence de tout ce qui est affiché et comparé (panier, RFA, jauge, repères, P2/P3) : le
   * TJM moyen pondéré dès qu'une période est ajoutée, sinon le TJM saisi — sans période, rien ne change.
   */
  get effectiveTjm() {
    return this.hasTjmPeriods && this.calc?.tjmWeighted != null
      ? this.calc.tjmWeighted
      : this.proposedTjm;
  }

  get showTjmPeriodsLink() {
    return !this.isNotEditable;
  }

  get tjmPeriodsLinkLabel() {
    return this.tjmPeriodsOpen
      ? this.labels.tjmPeriodsCloseLink
      : this.labels.tjmPeriodsOpenLink;
  }

  get tjmPanelClass() {
    return this.isTjmCompact
      ? "tjm-periods-panel tjm-periods-panel_compact"
      : "tjm-periods-panel";
  }

  get tjmBlockClass() {
    const open = this.showTjmPeriodsPanel;
    return [
      "tjm-block",
      open ? "is-open" : "",
      this.isNotEditable ? "is-locked" : "",
      this.tjmPhase ? `is-${this.tjmPhase}` : "",
      this.tjmQuick ? "is-quick" : ""
    ]
      .filter(Boolean)
      .join(" ");
  }

  get tjmToggleExpanded() {
    return String(this.tjmPeriodsOpen);
  }

  // Le lien existe en édition ; verrouillée, le cadre n'apparaît que s'il y a des périodes à lire.
  get showTjmPeriodsBlock() {
    return !this.isNotEditable || this.hasTjmPeriods;
  }

  get tjmTimelineRole() {
    return this.isTjmCompact ? "button" : null;
  }

  get tjmTimelineTabindex() {
    return this.isTjmCompact ? "0" : "-1";
  }

  get tjmTimelineTitle() {
    return this.isTjmCompact ? this.labels.tjmPeriodsEdit : null;
  }

  get tjmTimelineAriaExpanded() {
    return this.isTjmCompact ? "false" : null;
  }

  // Lignes décalées de 35 ms : --i pour le dépliage (première → dernière), --ri pour le repliage.
  tjmFadeStyle(index) {
    const count = this.tjmPeriods.length + 1;
    return `--i: ${index}; --ri: ${count - 1 - index}`;
  }

  get tjmMessageStyle() {
    return this.tjmFadeStyle(0);
  }

  get tjmAddLinkStyle() {
    return this.tjmFadeStyle(this.tjmPeriods.length + 1);
  }

  // Verrouillée : frise en lecture seule, seulement si la matrice a des périodes.
  get showTjmPeriodsPanel() {
    return this.isNotEditable ? this.hasTjmPeriods : this.tjmPeriodsOpen;
  }

  get showTjmPeriodAddLink() {
    return (
      !this.isNotEditable && this.tjmPeriods.length < MAX_ADDED_TJM_PERIODS
    );
  }

  get tjmMissionUnknown() {
    return this.hasTjmPeriods && !!this.calc.tjmPeriodsMissionUnknown;
  }

  get tjmExceedLabel() {
    return this.hasTjmPeriods && this.calc.tjmPeriodsExceedMission
      ? formatLabel(this.labels.tjmPeriodsExceed, formatDays(this.billableDays))
      : null;
  }

  get tjmTimelineTotalDays() {
    return (this.calc.tjmPeriods || []).reduce(
      (t, p) => t + (Number(p.days) || 0),
      0
    );
  }

  // Frise : un segment par période de jours > 0, largeur ∝ jours (dépassement : normalisée sur la somme).
  get hasTjmTimeline() {
    return (
      this.hasTjmPeriods &&
      !this.calc.tjmPeriodsMissionUnknown &&
      this.tjmTimelineTotalDays > 0
    );
  }

  get tjmTimelineSegments() {
    if (!this.hasTjmTimeline) {
      return [];
    }
    const total = this.tjmTimelineTotalDays;
    return this.calc.tjmPeriods
      .filter((p) => Number(p.days) > 0)
      .map((p) => ({
        key: `ts-${p.index}`,
        className: `tjm-segment tjm-color-${p.index}`,
        style: `width: ${(Number(p.days) / total) * 100}%;`,
        tjmLabel: formatMoney(p.tjm, this.currencyCode),
        daysLabel: `${formatDays(p.days)} j`
      }));
  }

  get tjmTimelineStartLabel() {
    return this.labels.tjmTimelineStart;
  }

  get tjmTimelineEndLabel() {
    return formatLabel(
      this.labels.tjmTimelineEnd,
      formatDays(this.tjmTimelineTotalDays)
    );
  }

  get tjmFirstRow() {
    const p1 = this.calc.tjmPeriods?.[0];
    const unknown = this.calc.tjmPeriodsMissionUnknown || p1?.days == null;
    return {
      colorClass: "tjm-dot tjm-color-1",
      label: unknown
        ? this.labels.tjmPeriodFirstRowUnknown
        : formatLabel(this.labels.tjmPeriodFirstRow, formatDays(p1.days)),
      amount: formatMoney(this.proposedTjm, this.currencyCode)
        .slice(0, -(currencySymbol(this.currencyCode).length + 1))
        .trim(),
      symbol: currencySymbol(this.currencyCode),
      style: this.tjmFadeStyle(0)
    };
  }

  get tjmPeriodRows() {
    return this.tjmPeriods.map((p, i) => {
      const rank = i + 2;
      const row = {
        key: `tp-${p.key}`,
        periodKey: p.key,
        colorClass: `tjm-dot tjm-color-${rank}`,
        title: formatLabel(this.labels.tjmPeriodRowTitle, rank),
        removeLabel: formatLabel(this.labels.tjmPeriodRemove, rank),
        tjmAria: formatLabel(this.labels.tjmPeriodTjmAria, rank),
        currencySymbol: currencySymbol(this.currencyCode),
        daysAria: formatLabel(this.labels.tjmPeriodDaysAria, rank),
        tjm: p.tjm,
        days: p.days,
        style: this.tjmFadeStyle(i + 1)
      };
      return row;
    });
  }

  get tjmWeightedFormatted() {
    return formatMoney(this.calc.tjmWeighted, this.currencyCode);
  }

  // Panier : légende « (60 x 650,00 €) + (60 x 700,00 €) » au format des frais lissés ; sans période, rien.
  get tjmBasketCaption() {
    if (!this.hasTjmPeriods || this.calc.tjmPeriodsMissionUnknown) {
      return null;
    }
    return this.calc.tjmPeriods
      .filter((p) => Number(p.days) > 0)
      .map((p) =>
        formatLabel(
          this.labels.feePeriodCaption,
          formatDays(p.days),
          formatMoneyPrecise(p.tjm, this.currencyCode)
        )
      )
      .join(" + ");
  }

  get invoicedTjmLabel() {
    return this.hasTjmPeriods
      ? this.labels.tjmWeightedGaugeTitle
      : this.labels.invoicedTjm;
  }

  get hasFeePeriods() {
    return this.feePeriods.length > 0;
  }

  get hasSalaryPeriods() {
    return this.salaryPeriods.length > 0;
  }

  get showSalaryPeriodAddLink() {
    return (
      !this.isNotEditable && this.salaryPeriods.length < MAX_ADDED_TJM_PERIODS
    );
  }

  get salaryPeriodRows() {
    return this.salaryPeriods.map((p, i) => ({
      key: `sp-${p.key}`,
      periodKey: p.key,
      title: formatLabel(this.labels.feePeriodTitle, i + 2),
      removeLabel: formatLabel(this.labels.feePeriodRemove, i + 2),
      days: p.days,
      salary: p.salary
    }));
  }

  // Ligne « Période 1 · N j (calculé) » sous le salaire annuel, dès qu'une période est ajoutée.
  get salaryPeriodFirstLabel() {
    if (!this.hasSalaryPeriods || !this.calc.salaryPeriods?.length) {
      return null;
    }
    if (this.calc.salaryPeriodsMissionUnknown) {
      return this.labels.feePeriodFirstUnknown;
    }
    return formatLabel(
      this.labels.feePeriodFirstCalc,
      formatDays(this.calc.salaryPeriods[0].days)
    );
  }

  get salaryPeriodExceedLabel() {
    return this.isSalaryBased && this.calc.salaryPeriodsExceedMission
      ? formatLabel(this.labels.tjmPeriodsExceed, formatDays(this.billableDays))
      : null;
  }

  // CJM pondéré : seulement quand le moteur a détaillé plusieurs périodes (CDI/CDD).
  get isCjmWeighted() {
    return (this.calc.salaryPeriods || []).length > 1;
  }

  get cjmSummaryLabel() {
    return this.isCjmWeighted
      ? this.labels.cjmWeightedLabel
      : this.labels.cjmMc2Label;
  }

  // Infobulle du CJM pondéré : une ligne par période (jours, salaire, CJM).
  get cjmWeightedTooltip() {
    if (!this.isCjmWeighted) {
      return null;
    }
    return this.calc.salaryPeriods
      .map((p) =>
        formatLabel(
          this.labels.salaryPeriodTooltipLine,
          p.index,
          p.days == null ? "?" : formatDays(p.days),
          formatMoney(p.salary, this.currencyCode),
          formatMoney(p.cjm, this.currencyCode)
        )
      )
      .join("\n");
  }

  // Récapitulatif : légende « (100 x 417,00 €) + (118 x 463,00 €) », au format des frais lissés.
  get cjmWeightedCaption() {
    if (!this.isCjmWeighted || this.calc.salaryPeriodsMissionUnknown) {
      return null;
    }
    return this.calc.salaryPeriods
      .filter((p) => Number(p.days) > 0)
      .map((p) =>
        formatLabel(
          this.labels.feePeriodCaption,
          formatDays(p.days),
          formatMoneyPrecise(p.cjm, this.currencyCode)
        )
      )
      .join(" + ");
  }

  get showFeePeriodAddLink() {
    return !this.isNotEditable;
  }

  get feePeriodRows() {
    return this.feePeriods.map((p, i) => ({
      key: `fp-${p.key}`,
      periodKey: p.key,
      title: formatLabel(this.labels.feePeriodTitle, i + 2),
      removeLabel: formatLabel(this.labels.feePeriodRemove, i + 2),
      days: p.days,
      feeIk: p.feeIk,
      feeMeals: p.feeMeals,
      feeLodging: p.feeLodging,
      feeOmOther: p.feeOmOther
    }));
  }

  // Ligne « Période 1 · N j (calculé) » sous la rangée Frais OM, dès qu'une période est ajoutée.
  get feePeriodFirstLabel() {
    if (!this.hasFeePeriods) {
      return null;
    }
    if (this.calc.feePeriodsMissionUnknown) {
      return this.labels.feePeriodFirstUnknown;
    }
    return formatLabel(
      this.labels.feePeriodFirstCalc,
      formatDays(this.calc.feeOmPeriods[0].days)
    );
  }

  get feePeriodExceedLabel() {
    return this.calc.feePeriodsExceedMission
      ? formatLabel(this.labels.feePeriodExceed, formatDays(this.billableDays))
      : null;
  }

  // Lignes lissées du panier (une par frais) : Σ(jours × frais) / Σ jours sur les périodes de jours > 0.
  // Durée de mission inconnue : valeurs de la période 1, sans « (lissé) » ni légende.
  get smoothedFeeLines() {
    const code = this.currencyCode;
    const unknown = this.calc.feePeriodsMissionUnknown;
    const p1Days = this.calc.feeOmPeriods?.[0]?.days;
    const periods = [
      {
        days: p1Days,
        feeIk: this.feeIk,
        feeMeals: this.feeMeals,
        feeLodging: this.feeLodging,
        feeOmOther: this.feeOmOther
      },
      ...this.feePeriods.map((p) => ({
        days: p.days,
        feeIk: p.feeIk,
        feeMeals: p.feeMeals,
        feeLodging: p.feeLodging,
        feeOmOther: p.feeOmOther
      }))
    ]
      .map((p) => ({ ...p, days: Number(p.days) || 0 }))
      .filter((p) => p.days > 0);
    const totalDays = periods.reduce((t, p) => t + p.days, 0);
    const categories = [
      { key: "feeIk", label: this.labels.costBreakdownFeeIk },
      { key: "feeMeals", label: this.labels.recapFeeMeals },
      { key: "feeLodging", label: this.labels.recapFeeLodging },
      { key: "feeOmOther", label: this.labels.otherMissionFees }
    ];
    const lines = [];
    categories.forEach((c) => {
      let value;
      let caption = null;
      let label = c.label;
      if (unknown || totalDays === 0) {
        value = Number(this[c.key]) || 0;
      } else {
        const numerator = periods.reduce(
          (t, p) => t + p.days * (Number(p[c.key]) || 0),
          0
        );
        value = numerator / totalDays;
        label = formatLabel(this.labels.feeSmoothedSuffix, c.label);
        caption = periods
          .map((p) =>
            formatLabel(
              this.labels.feePeriodCaption,
              formatDays(p.days),
              formatMoneyPrecise(Number(p[c.key]) || 0, code)
            )
          )
          .join(" + ");
      }
      if (!(value > 0)) {
        return;
      }
      const breakdown = formatMoneyWithDecimalBreakdown(value, code);
      lines.push({
        key: `${c.key}Smoothed`,
        label,
        caption,
        formattedValue: `- ${formatMoney(value, code)}`,
        intPart: breakdown.intPart,
        decPart: breakdown.decPart,
        hasDecimal: breakdown.hasDecimal,
        symbol: breakdown.symbol,
        decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
      });
    });
    return lines;
  }

  get showFeeOmLine() {
    return this.showOmAndPonctuelsFees && this.calc.feeOmPerDay > 0;
  }

  get formattedFeeOmPerDay() {
    return `+${formatMoney(this.calc.feeOmPerDay, this.currencyCode)}${this.labels.perDaySuffix}`;
  }

  get showFeePonctuelsLine() {
    return this.calc.feePonctuelsPerDay > 0;
  }

  get feePonctuelsLineLabel() {
    const divisor = this.calc.feePonctuelsDivisorDays || 218;
    const baseLabel = this.isINDEP
      ? this.labels.feePonctuelsIndep
      : this.labels.feePonctuelsOther;
    return formatLabel(baseLabel, divisor);
  }

  get formattedFeePonctuelsPerDay() {
    return `+${formatMoney(this.calc.feePonctuelsPerDay, this.currencyCode)}${this.labels.perDaySuffix}`;
  }

  get formattedTotalDailyCost() {
    return formatMoney(this.calc.totalDailyCost, this.currencyCode);
  }

  get totalDailyCostBreakdown() {
    return this.addDecimalClass(
      formatMoneyWithDecimalBreakdown(
        this.calc.totalDailyCost,
        this.currencyCode
      )
    );
  }

  /** Ligne du récapitulatif : même forme que les autres lignes, montant par jour en partie droite. */
  detailLine(key, label, caption, perDay) {
    const breakdown = formatMoneyWithDecimalBreakdown(
      perDay,
      this.currencyCode
    );
    return {
      key,
      label,
      caption,
      formattedValue: `- ${formatMoney(perDay, this.currencyCode)}`,
      intPart: breakdown.intPart,
      decPart: breakdown.decPart,
      hasDecimal: breakdown.hasDecimal,
      symbol: breakdown.symbol,
      decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
    };
  }

  /**
   * Session 252 : légende d'un frais saisi par jour. Le frais PC donne son coût sur toute la mission
   * (« 15 €/jour × 120 jours = 1 800 € sur la mission ») avec le même nombre de jours que les frais
   * ponctuels ; sans durée de mission, la légende d'origine. Le montant par jour ne change pas.
   */
  dailyFeeCaption(line, amount) {
    const days = this.calc.feePonctuelsDivisorDays;
    if (
      line.key === "feeComputer" &&
      this.calc.feePonctuelsDivisorSource === "mission" &&
      days > 0
    ) {
      return formatLabel(
        this.labels.recapFeeComputerMission,
        amount,
        formatDays(days),
        formatMoney(line.amount * days, this.currencyCode)
      );
    }
    return formatLabel(this.labels.recapFeeDay, amount);
  }

  /**
   * Une ligne par frais ponctuel : le nom du frais, le montant saisi dans son unité en légende, le
   * montant par jour à droite. Les valeurs viennent de `calc.feeBreakdown`, rien n'est recalculé ici.
   */
  get feeDetailLines() {
    const code = this.currencyCode;
    const names = {
      feeComputer: this.labels.recapFeeComputer,
      feePhone: this.labels.recapFeePhone,
      feeMonthlyOther: this.labels.recapFeeMonthlyOther,
      feeTraining: this.labels.recapFeeTraining,
      feeEpi: this.labels.recapFeeEpi,
      feeOfiiTax: this.labels.recapFeeOfiiTax,
      feeOther: this.labels.recapFeeOther
    };
    return (this.calc.feeBreakdown || []).map((l) => {
      const amount = formatEnteredAmount(l.amount, code);
      let caption;
      if (l.unit === "day") {
        caption = this.dailyFeeCaption(l, amount);
      } else if (l.unit === "month") {
        caption = formatLabel(this.labels.recapFeeMonth, amount);
      } else if (l.unit === "mission") {
        caption =
          l.divisorSource === "mission"
            ? formatLabel(
                this.labels.recapFeeMission,
                amount,
                formatDays(l.divisor)
              )
            : formatLabel(this.labels.recapFeeMissionFallback, amount);
      } else {
        caption = formatLabel(this.labels.recapFeeYear, amount);
        const conversion = this.ofiiConversionCaption;
        if (conversion) {
          caption = `${caption} · ${conversion}`;
        }
      }
      return this.detailLine(l.key, names[l.key], caption, l.perDay);
    });
  }

  // ---------- Taxe OFII : liste déroulante N/A + valeur calculée ----------

  /** Taux des Paramètres généraux, en % du salaire mensuel brut ; null tant qu'il n'est pas renseigné. */
  get ofiiTaxAdminRate() {
    const rate = Number(this.settings && this.settings.ofiiTaxRate);
    return rate > 0 ? rate : null;
  }

  /** Plafond des Paramètres généraux, en euros ; null tant qu'il n'est pas renseigné. */
  get ofiiTaxAdminCapEur() {
    const cap = Number(this.settings && this.settings.ofiiTaxCapEur);
    return cap > 0 ? cap : null;
  }

  /**
   * Plafond dans la devise de la matrice : l'euro tel quel, sinon converti au taux déjà appliqué à la
   * matrice (`rateToEur`, 1 devise = x EUR). Null si le plafond n'est pas administré ou si la devise n'a
   * pas de taux (la matrice est alors bloquée par ailleurs).
   */
  get ofiiTaxCapInMatrixCurrency() {
    const eur = this.ofiiTaxAdminCapEur;
    if (eur === null) {
      return null;
    }
    if (this.currencyCode === "EUR") {
      return eur;
    }
    if (this.noRateAvailable) {
      return null;
    }
    return (
      Math.round((eur / Number(this.rateResolution.rateToEur)) * 100) / 100
    );
  }

  /** Valeur calculée : min(taux × salaire annuel ÷ 12, plafond), dans la devise de la matrice, ou null. */
  get ofiiTaxCurrentAmount() {
    return computeOfiiTax(
      this.annualSalary,
      this.ofiiTaxAdminRate,
      this.ofiiTaxCapInMatrixCurrency
    );
  }

  isOfiiCurrentAmount(value) {
    const current = this.ofiiTaxCurrentAmount;
    return current !== null && Math.abs(Number(value) - current) < 0.005;
  }

  /** Vrai si la taxe posée sur la matrice est la valeur calculée du moment (non nulle). */
  ofiiTaxIsFollowingCalculation() {
    return (
      (Number(this.feeOfiiTax) || 0) > 0 &&
      this.isOfiiCurrentAmount(this.feeOfiiTax)
    );
  }

  /**
   * Remet la taxe à la nouvelle valeur calculée quand elle suivait la précédente. Si le calcul devient
   * impossible (salaire vidé), la taxe repasse à N/A et on retient qu'elle suivait le calcul, pour la
   * reprendre dès que le salaire revient. Retourne vrai si `feeOfiiTax` a été réécrit.
   */
  followOfiiCalculation(wasFollowing) {
    if (!wasFollowing && !this._ofiiFollowsWhenCalculable) {
      return false;
    }
    const current = this.ofiiTaxCurrentAmount;
    this._ofiiFollowsWhenCalculable = current === null;
    this.feeOfiiTax = current;
    return true;
  }

  formatOfiiOption(value) {
    return formatMoneyPrecise(value, this.currencyCode);
  }

  /**
   * N/A, la valeur calculée, et — sans jamais la réécrire — la valeur déjà enregistrée sur la matrice
   * quand elle ne correspond pas au calcul actuel (ancien montant fixe, ou montant saisi avant la liste).
   */
  get ofiiTaxOptions() {
    const options = [{ label: "N/A", value: "0" }];
    const current = this.ofiiTaxCurrentAmount;
    if (current !== null) {
      options.push({
        label: this.formatOfiiOption(current),
        value: String(current)
      });
    }
    const stored = Number(this.feeOfiiTax) || 0;
    if (stored > 0 && !this.isOfiiCurrentAmount(stored)) {
      options.push({
        label: this.formatOfiiOption(stored),
        value: String(stored)
      });
    }
    return options;
  }

  get ofiiTaxValue() {
    const stored = Number(this.feeOfiiTax) || 0;
    if (stored <= 0) {
      return "0";
    }
    return this.isOfiiCurrentAmount(stored)
      ? String(this.ofiiTaxCurrentAmount)
      : String(stored);
  }

  /** Taux ou plafond non renseigné dans l'administration. */
  get showOfiiTaxNotSet() {
    return this.ofiiTaxAdminRate === null || this.ofiiTaxAdminCapEur === null;
  }

  /** Paramètres présents, mais pas de salaire annuel à renseigner (le champ n'existe que pour CDI/CDD). */
  get showOfiiTaxNoSalary() {
    return (
      !this.showOfiiTaxNotSet &&
      this.isSalaryBased &&
      !(Number(this.annualSalary) > 0)
    );
  }

  /** Aide du champ : méthode de calcul avec les valeurs administrées, puis rappel de la taxe annuelle. */
  get ofiiTaxHelpText() {
    const cap = this.ofiiTaxCapInMatrixCurrency;
    if (this.ofiiTaxAdminRate === null || cap === null) {
      return this.labels.ofiiTaxHelp;
    }
    const rate = Number(this.ofiiTaxAdminRate).toLocaleString("fr-FR", {
      maximumFractionDigits: 2
    });
    return `${formatLabel(
      this.labels.ofiiTaxMethod,
      rate,
      this.formatOfiiOption(cap)
    )}. ${this.labels.ofiiTaxHelp}`;
  }

  /**
   * Conversion écrite dans le récapitulatif : plafond administré en euros et taux appliqué à la matrice,
   * uniquement quand la taxe retenue est le plafond converti.
   */
  get ofiiConversionCaption() {
    const stored = Number(this.feeOfiiTax) || 0;
    const cap = this.ofiiTaxCapInMatrixCurrency;
    if (
      this.currencyCode === "EUR" ||
      this.noRateAvailable ||
      stored <= 0 ||
      cap === null ||
      Math.abs(stored - cap) >= 0.005
    ) {
      return null;
    }
    const rate = Number(this.rateResolution.rateToEur).toLocaleString("fr-FR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 6
    });
    return formatLabel(
      this.labels.recapOfiiConversion,
      formatMoneyPrecise(this.ofiiTaxAdminCapEur, "EUR"),
      `1 ${this.currencyCode} = ${rate} EUR`
    );
  }

  handleOfiiTaxChange(event) {
    this.markCalcPending();
    this._ofiiFollowsWhenCalculable = false;
    const raw = event.detail.value;
    this.feeOfiiTax =
      raw === "" || raw === null || raw === undefined ? null : Number(raw);
    this.recompute();
    this.setDirty(true);
  }

  get costBreakdownLines() {
    const lines = [];
    const feePonctuelsDivisor = this.calc.feePonctuelsDivisorDays || 218;

    const cjmBreakdown = formatMoneyWithDecimalBreakdown(
      this.calc.cjm || 0,
      this.currencyCode
    );
    lines.push({
      key: "cjm",
      label: this.isCjmWeighted
        ? this.labels.costBreakdownCjmWeighted
        : this.labels.costBreakdownCjm,
      caption: this.cjmWeightedCaption,
      title: this.cjmWeightedTooltip,
      formattedValue: `- ${formatMoney(this.calc.cjm || 0, this.currencyCode)}`,
      intPart: cjmBreakdown.intPart,
      decPart: cjmBreakdown.decPart,
      hasDecimal: cjmBreakdown.hasDecimal,
      symbol: cjmBreakdown.symbol,
      decClass: cjmBreakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
    });

    if (this.showOmAndPonctuelsFees) {
      // Avec périodes, les quatre frais journaliers sont remplacés par leur moyenne lissée (docs/239 §4).
      if (this.hasFeePeriods) {
        lines.push(...this.smoothedFeeLines);
      }

      if (!this.hasFeePeriods && (this.feeIk || 0) > 0) {
        const breakdown = formatMoneyWithDecimalBreakdown(
          this.feeIk,
          this.currencyCode
        );
        lines.push({
          key: "feeIk",
          label: this.labels.costBreakdownFeeIk,
          caption: null,
          formattedValue: `- ${formatMoney(this.feeIk, this.currencyCode)}`,
          intPart: breakdown.intPart,
          decPart: breakdown.decPart,
          hasDecimal: breakdown.hasDecimal,
          symbol: breakdown.symbol,
          decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
        });
      }

      if (!this.hasFeePeriods && (this.feeMeals || 0) > 0) {
        const breakdown = formatMoneyWithDecimalBreakdown(
          this.feeMeals,
          this.currencyCode
        );
        lines.push({
          key: "feeMeals",
          label: this.labels.recapFeeMeals,
          caption: null,
          formattedValue: `- ${formatMoney(this.feeMeals, this.currencyCode)}`,
          intPart: breakdown.intPart,
          decPart: breakdown.decPart,
          hasDecimal: breakdown.hasDecimal,
          symbol: breakdown.symbol,
          decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
        });
      }

      if (!this.hasFeePeriods && (this.feeLodging || 0) > 0) {
        const breakdown = formatMoneyWithDecimalBreakdown(
          this.feeLodging,
          this.currencyCode
        );
        lines.push({
          key: "feeLodging",
          label: this.labels.recapFeeLodging,
          caption: null,
          formattedValue: `- ${formatMoney(this.feeLodging, this.currencyCode)}`,
          intPart: breakdown.intPart,
          decPart: breakdown.decPart,
          hasDecimal: breakdown.hasDecimal,
          symbol: breakdown.symbol,
          decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
        });
      }

      if (!this.hasFeePeriods && (this.feeOmOther || 0) > 0) {
        const breakdown = formatMoneyWithDecimalBreakdown(
          this.feeOmOther,
          this.currencyCode
        );
        lines.push({
          key: "feeOmOther",
          label: this.labels.otherMissionFees,
          caption: null,
          formattedValue: `- ${formatMoney(this.feeOmOther, this.currencyCode)}`,
          intPart: breakdown.intPart,
          decPart: breakdown.decPart,
          hasDecimal: breakdown.hasDecimal,
          symbol: breakdown.symbol,
          decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
        });
      }

      lines.push(...this.feeDetailLines);

      if ((this.gratuityDays || 0) > 0) {
        const gratuityValue =
          (this.gratuityDays * (this.calc.cjm || 0)) / feePonctuelsDivisor;
        const breakdown = formatMoneyWithDecimalBreakdown(
          gratuityValue,
          this.currencyCode
        );
        lines.push({
          key: "gratuityDays",
          label: formatLabel(
            this.labels.gratuityDaysLabel,
            Math.round(this.gratuityDays)
          ),
          caption: null,
          formattedValue: `- ${formatMoney(gratuityValue, this.currencyCode)}`,
          intPart: breakdown.intPart,
          decPart: breakdown.decPart,
          hasDecimal: breakdown.hasDecimal,
          symbol: breakdown.symbol,
          decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
        });
      }
    }

    return lines;
  }

  /**
   * Libellé de la section frais ponctuels : « Frais ponctuels/Gratuité » (CDI/VIE) ou
   * « Gratuité client annuelle » (INDEP).
   */
  get fraisPonctuelsToggleLabel() {
    return this.isINDEP
      ? formatLabel(
          this.labels.gratuiteClientAnnuelle,
          this.calc.feePonctuelsDivisorDays || 218
        )
      : this.labels.fraisPonctuelsAnnuels;
  }

  get showOneTimeFeesYearFallback() {
    return this.calc.feePonctuelsDivisorSource === "year_fallback";
  }

  // Sans TJM saisi, calcMC2 retombe sur 0 % — classé "below_floor" par défaut par le moteur.
  // Un badge rouge sur un champ vide serait trompeur : état neutre tant qu'aucun TJM n'existe.
  get hasProposedTjm() {
    return !!this.proposedTjm;
  }

  get isBelowFloor() {
    return this.hasProposedTjm && this.calc.corridorSegment === "below_floor";
  }

  /**
   * Coût nul (session 16, cf. docs/16-zones-et-jauge.md) : rétablir l'encadré de coût en session 15
   * a rendu visible un cas qui passait inaperçu — un statut VIE/Nearshore sans CJM résolu (ni
   * référentiel ni surcharge) donne `calc.cjm = null` (le moteur JS n'a pas accès aux référentiels
   * pays, contrairement à l'Apex côté sauvegarde), donc `calc.totalDailyCost = 0`. Sans garde-fou,
   * un TJM saisi dans ce contexte donne MC2 = 100 % et un bandeau « Excellence » — un artefact
   * (division par un coût nul), pas une vraie performance. `hasCalculableDecision` neutralise
   * l'affichage du segment/MC2 tant que le coût n'est pas établi, sans toucher au calcul lui-même.
   */
  get isCostCalculable() {
    return this.calc.totalDailyCost > 0;
  }

  /**
   * Session 26 §3 : le message d'encadré coût journalier disait toujours « renseignez le CJM »,
   * alors que le CJM n'est un champ de saisie qu'en INDEP — en CDI (le type de contrat le plus
   * courant) le champ à remplir s'appelle Salaire annuel, en VIE Indemnité VIE, en NEARSHORE CJM
   * Nearshore. Le message envoyait l'utilisateur chercher un champ absent de l'écran.
   */
  get costNotCalculableFieldLabel() {
    switch (this.contractType) {
      case "INDEP":
        return this.labels.costNotCalculableIndep;
      case "VIE":
        return this.labels.costNotCalculableVie;
      case "NEARSHORE":
        return this.labels.costNotCalculableNearshore;
      case "CDI":
      case "CDD":
      default:
        return this.labels.costNotCalculableDefault;
    }
  }

  get costNotCalculableMessage() {
    return formatLabel(
      this.labels.costNotCalculableMessage,
      this.costNotCalculableFieldLabel
    );
  }

  get hasCalculableDecision() {
    return this.hasProposedTjm && this.isCostCalculable;
  }

  /**
   * Trois états mutuellement exclusifs du bouton d'action principal (session 15, pricing-tool.html:2108-2115) :
   * pas de TJM → désactivé ; TJM et segment ≠ below_floor → validation ; TJM et below_floor → dérogation.
   * Avant ce correctif, `isBelowFloor` renvoyait `false` sans TJM et le bouton vert « Valider »
   * s'affichait sur une matrice vide (l'Apex rejetait, mais l'utilisateur recevait une erreur au
   * lieu d'être guidé).
   */
  get showNoTjmButton() {
    return !this.hasProposedTjm;
  }

  /**
   * Une dérogation est requise : sous le plancher pour une matrice ordinaire ; pour un avenant en Brouillon,
   * MC2 % strictement inférieure (au centième de point) à celle de la matrice amendée, quel que soit le
   * plancher (même règle que AR_AvenantService.requiresHumanValidation, que le serveur réapplique).
   */
  get isDerogationRequired() {
    if (!this.hasProposedTjm) {
      return false;
    }
    if (this._avenantMc2Before !== null) {
      return (
        Math.round(this.calc.mc2PercentHuman * 100) <
          Math.round(this._avenantMc2Before * 100) &&
        !this.isDispensedFromDerogation
      );
    }
    return this.isBelowFloor && !this.isDispensedFromDerogation;
  }

  /**
   * Session 237 — dispense de dérogation : MC2/jour convertie en EUR (taux de la matrice) égale ou
   * supérieure au montant administré. Miroir de AR_PricingMatrixService.isDispensedFromDerogation ;
   * montant vide = règle désactivée, sans valeur de repli.
   */
  get isDispensedFromDerogation() {
    const waiver = this.settings.derogationWaiverAmount;
    if (waiver === null || waiver === undefined || this.noRateAvailable) {
      return false;
    }
    const mc2Eur =
      Math.round(
        this.calc.mc2PerDay * Number(this.rateResolution.rateToEur) * 100
      ) / 100;
    return mc2Eur >= waiver;
  }

  get showValidateButton() {
    return this.hasProposedTjm && !this.isDerogationRequired;
  }

  get showDerogationButton() {
    return this.hasProposedTjm && this.isDerogationRequired;
  }

  get segmentLabel() {
    return this.hasCalculableDecision && this.calc.corridorSegment
      ? SEGMENT_META[this.calc.corridorSegment].label
      : "";
  }

  get segmentClass() {
    return this.hasCalculableDecision && this.calc.corridorSegment
      ? SEGMENT_META[this.calc.corridorSegment].cssClass
      : "segment-pill";
  }

  /**
   * Hiérarchie zone 3 (session 16, pricing-tool.html:2079-2083) : une valeur dominante (MC2/jour)
   * plutôt que des tuiles de poids égal — remplace l'ancien `mc2ValueClass` (2 tuiles côte à côte).
   * Seuil de couleur = plancher du corridor appliqué (session 155 ; fixe à 20 % avant — le plancher
   * est aussi le seuil de dérogation, la couleur doit donc suivre le corridor, Paramètres généraux
   * compris).
   */
  get mc2DominantValueClass() {
    if (!this.hasCalculableDecision) {
      return "mc2-dominant-value";
    }
    return `mc2-dominant-value ${this.calc.mc2PercentHuman >= this.floorPercentValue ? "value-green" : "value-red"}`;
  }

  get mc2ContextLine() {
    if (!this.hasProposedTjm) {
      return "";
    }
    if (!this.isCostCalculable) {
      return this.labels.mc2CostNotCalculable;
    }
    const floorPercent = this.floorPercentValue;
    const thresholdNote = formatLabel(
      this.calc.mc2PercentHuman >= floorPercent
        ? this.labels.mc2AboveThreshold
        : this.labels.mc2BelowThreshold,
      Math.round(floorPercent)
    );
    return formatLabel(
      this.labels.mc2ContextLine,
      formatPercent(this.calc.mc2PercentHuman),
      thresholdNote
    );
  }

  /**
   * « Remise vs cible » (session 15, pricing-tool.html:2100-2101) : corrige un bug d'affichage à
   * deux visages — le libellé disait « remise » même quand le TJM dépassait la cible (un
   * dépassement, pas une remise), et affichait une valeur aberrante (« −556 € (−100 %) ») sans TJM
   * saisi. `discount = cible − TJM` (positif = en dessous de la cible, une vraie remise) ; rien
   * n'est affiché sans TJM ni sans cible calculée.
   */
  get showDiscountVsTarget() {
    return (
      this.hasProposedTjm && this.isCostCalculable && this.calc.tjmTarget > 0
    );
  }

  get discountVsTargetEuro() {
    return (this.calc.tjmTarget || 0) - (this.effectiveTjm || 0);
  }

  get discountVsTargetLabel() {
    if (!this.showDiscountVsTarget) {
      return "";
    }
    const diff = this.discountVsTargetEuro;
    if (diff > 0) {
      return formatLabel(
        this.labels.discountVsTargetOver,
        formatMoney(diff, this.currencyCode),
        formatMoney(this.calc.tjmTarget, this.currencyCode)
      );
    }
    return formatLabel(
      this.labels.discountVsTargetUnder,
      formatMoney(-diff, this.currencyCode)
    );
  }

  /**
   * Décomposition MC2 (session 15, pricing-tool.html:2085-2096) : rétablie, absente de l'org — le
   * seul résultat était affiché sans jamais montrer le chemin (TJM → RFA → coût → MC2). Visible dès
   * qu'un TJM est saisi. Le seuil de couleur vert/rouge (20 %) est celui de la maquette pour ce bloc
   * précis (« ≥ seuil rupture (20%) ») — pas les paliers du corridor Grand Compte, qui n'interviennent
   * pas ici dans la maquette non plus.
   */
  get showMc2Breakdown() {
    return this.hasCalculableDecision;
  }

  get formattedProposedTjmBreakdown() {
    return formatMoney(this.effectiveTjm, this.currencyCode);
  }

  addDecimalClass(breakdown) {
    return {
      ...breakdown,
      decClass: breakdown.hasDecimal ? "amt-dec" : "amt-dec amt-dec-hidden"
    };
  }

  get proposedTjmBreakdown() {
    return this.addDecimalClass(
      formatMoneyWithDecimalBreakdown(this.effectiveTjm, this.currencyCode)
    );
  }

  get showRfaLineInBreakdown() {
    return (this.rfaPercent || 0) > 0;
  }

  get formattedRfaAmount() {
    return formatMoney(
      ((this.effectiveTjm || 0) * (this.rfaPercent || 0)) / 100,
      this.currencyCode
    );
  }

  get rfaAmountBreakdown() {
    return this.addDecimalClass(
      formatMoneyWithDecimalBreakdown(
        ((this.effectiveTjm || 0) * (this.rfaPercent || 0)) / 100,
        this.currencyCode
      )
    );
  }

  get formattedNetRevenueAfterRfa() {
    return formatMoney(
      ((this.effectiveTjm || 0) * (100 - (this.rfaPercent || 0))) / 100,
      this.currencyCode
    );
  }

  get netRevenueAfterRfaBreakdown() {
    return this.addDecimalClass(
      formatMoneyWithDecimalBreakdown(
        ((this.effectiveTjm || 0) * (100 - (this.rfaPercent || 0))) / 100,
        this.currencyCode
      )
    );
  }

  /**
   * Prix de négociation 2 et 3 (indicatifs) : MC2 recalculée par les fonctions du moteur
   * (`calcMc2ForTjm`, factorisé avec ce que `compute` fait pour le TJM proposé) avec le coût
   * total et les seuils du calcul en cours, jamais une formule recopiée. Sans coût calculable ou sans
   * prix saisi (> 0), aucune entrée : le panier et la jauge restent ceux du prix 1.
   */
  // Même coût que la MC2 du prix 1 (`costForMargin` du moteur) : coût piloté si la régie sans régule est
  // active (calcul piloté disponible), coût standard sinon.
  get negoCostForMargin() {
    const piloted = this.calc.totalDailyCostPiloted;
    return piloted !== null && piloted !== undefined
      ? piloted
      : this.calc.totalDailyCost;
  }

  get negoEntries() {
    if (!this.isCostCalculable) {
      return [];
    }
    return [
      {
        rank: 2,
        value: this.negoPrice2,
        header: this.labels.negoColPrice2,
        marker: this.labels.negoGaugeMarker2
      },
      {
        rank: 3,
        value: this.negoPrice3,
        header: this.labels.negoColPrice3,
        marker: this.labels.negoGaugeMarker3
      }
    ]
      .filter((entry) => Number(entry.value) > 0)
      .map((entry) => {
        const { mc2PerDay, mc2PercentHuman, corridorSegment } = calcMc2ForTjm(
          entry.value,
          this.negoCostForMargin,
          this.rfaPercent,
          this.appliedCorridorPercents
        );
        return {
          ...entry,
          mc2PerDay,
          mc2PercentHuman,
          segment: corridorSegment,
          isBelowFloor: corridorSegment === "below_floor"
        };
      });
  }

  // --- Champs « Prix de négociation 2 / 3 » (zone 3) ---

  /** Prix de référence de chaque champ : TJM proposé pour le prix 2, prix 2 (à défaut le TJM) pour le prix 3. */
  negoNotLower(price, previous) {
    return (
      Number(price) > 0 &&
      Number(previous) > 0 &&
      Number(price) >= Number(previous)
    );
  }

  get negoPrice2NotLower() {
    return this.negoNotLower(this.negoPrice2, this.effectiveTjm);
  }

  get negoPrice3NotLower() {
    return this.negoNotLower(
      this.negoPrice3,
      Number(this.negoPrice2) > 0 ? this.negoPrice2 : this.effectiveTjm
    );
  }

  get negoPrice2BelowFloor() {
    return this.negoEntries.some((e) => e.rank === 2 && e.isBelowFloor);
  }

  get negoPrice3BelowFloor() {
    return this.negoEntries.some((e) => e.rank === 3 && e.isBelowFloor);
  }

  /** Message unique sous le champ intermédiaire : ordre d'abord, puis seuil. */
  get negoPrice2Message() {
    if (this.negoPrice2NotLower) {
      return { text: this.labels.negoPriceNotLower, isFloor: false };
    }
    if (this.negoPrice2BelowFloor) {
      return { text: this.labels.negoPriceBelowFloor, isFloor: true };
    }
    return null;
  }

  /** Message unique sous le champ plancher : même priorité, référence = intermédiaire s'il est renseigné. */
  get negoPrice3Message() {
    if (this.negoPrice3NotLower) {
      return {
        text:
          Number(this.negoPrice2) > 0
            ? this.labels.negoPriceNotLowerInter
            : this.labels.negoPriceNotLower,
        isFloor: false
      };
    }
    if (this.negoPrice3BelowFloor) {
      return { text: this.labels.negoPriceBelowFloor, isFloor: true };
    }
    return null;
  }

  get negoPrice2MessageClass() {
    return this.negoPrice2Message?.isFloor
      ? "nego-message nego-message-floor"
      : "nego-message";
  }

  get negoPrice3MessageClass() {
    return this.negoPrice3Message?.isFloor
      ? "nego-message nego-message-floor"
      : "nego-message";
  }

  get negoCurrencySymbol() {
    return currencySymbol(this.currencyCode);
  }

  // --- Panier : colonnes des prix 2 et 3 ---

  get hasNegoColumns() {
    return this.showMc2Breakdown && this.negoEntries.length > 0;
  }

  get mc2BreakdownBoxClass() {
    return this.hasNegoColumns
      ? `mc2-breakdown-box slds-m-top_medium mc2-breakdown-box-multi mc2-breakdown-box-multi-${this.negoEntries.length}${this.negoOpen ? " is-nego-open" : ""}`
      : "mc2-breakdown-box slds-m-top_medium";
  }

  /**
   * Cellule P2/P3 d'une ligne qui dépend du TJM : affichée seulement si, arrondie comme affichée, elle diffère
   * de la valeur du prix 1 ; sinon vide (la cellule garde sa largeur). Règle générique, pas une liste de lignes.
   */
  negoCell(valueAtNego, valueAtPrice1) {
    const shown = formatMoney(valueAtNego, this.currencyCode);
    if (shown === formatMoney(valueAtPrice1, this.currencyCode)) {
      return { show: false };
    }
    return {
      show: true,
      ...this.addDecimalClass(
        formatMoneyWithDecimalBreakdown(valueAtNego, this.currencyCode)
      )
    };
  }

  get negoColumns() {
    const rfa = this.rfaPercent || 0;
    const tjm1 = this.effectiveTjm || 0;
    return this.negoEntries.map((entry) => ({
      key: `p${entry.rank}`,
      tjmId: `nego-tjm-p${entry.rank}`,
      header: entry.header,
      tjm: this.negoCell(entry.value, tjm1),
      rfa: this.showRfaLineInBreakdown
        ? this.negoCell((entry.value * rfa) / 100, (tjm1 * rfa) / 100)
        : { show: false },
      net: this.negoCell(
        (entry.value * (100 - rfa)) / 100,
        (tjm1 * (100 - rfa)) / 100
      ),
      mc2: this.addDecimalClass(
        formatMoneyWithDecimalBreakdown(entry.mc2PerDay, this.currencyCode)
      ),
      mc2Percent: formatPercent(entry.mc2PercentHuman),
      percentClass: entry.isBelowFloor
        ? "mc2-breakdown-extra-percent nego-percent-below-floor"
        : "mc2-breakdown-extra-percent"
    }));
  }

  /** Rangée d'en-tête du panier : rendue colonnes P2/P3 ouvertes, repliée à hauteur nulle sinon. */
  get negoHeadClass() {
    return this.negoOpen ? "nego-head is-open" : "nego-head";
  }

  get negoHeadAriaHidden() {
    return this.negoOpen ? "false" : "true";
  }

  // --- Jauge : repères secondaires P2 / P3 ---

  /**
   * Position par `calcGaugePosition` sur la même échelle que le curseur du TJM proposé ; montant et
   * MC2 % dans le `title`. Les pastilles P2 / P3 sont dans `gaugeView`.
   */
  get gaugeNegoMarkers() {
    const thresholds = this.gaugeThresholdsContext;
    return this.negoEntries.map((entry) => {
      const position = calcGaugePosition(entry.value, thresholds);
      const outOfScale = isGaugePositionOutOfScale(entry.value, thresholds);
      const hover = formatLabel(
        this.labels.negoGaugeHover,
        entry.header,
        formatMoney(entry.value, this.currencyCode),
        formatPercent(entry.mc2PercentHuman)
      );
      return {
        key: `p${entry.rank}`,
        title: outOfScale
          ? `${hover} ${this.labels.gaugeOutOfScaleSuffix}`
          : hover,
        tickClass: `gauge-nego-tick${negoSegmentSuffix(entry.segment)}`,
        tickStyle: `left: ${position}%;`,
        position
      };
    });
  }

  get hasGaugeNegoMarkers() {
    return this.negoEntries.length > 0;
  }

  get mc2BreakdownValueClass() {
    return this.calc.mc2PercentHuman >= this.floorPercentValue
      ? "value-green"
      : "value-red";
  }

  /**
   * Bandeaux d'alerte contextuels (session 15, pricing-tool.html:2104-2107) : rétablis, absents de
   * l'org (seul un badge de segment sec existait). Les pourcentages/seuils cités viennent de
   * `corridorPercents` (surcharge Grand Compte) quand elle s'applique, pas de 20/25/30 en dur.
   */
  get showBelowFloorBanner() {
    return (
      this.hasCalculableDecision &&
      this.calc.corridorSegment === "below_floor" &&
      !this.isDispensedFromDerogation
    );
  }

  get belowFloorBannerMessage() {
    return formatLabel(
      this.labels.belowFloorMessage,
      formatMoney(this.calc.tjmFloor, this.currencyCode),
      this.floorPercentValue
    );
  }

  get showLowMarginBanner() {
    return (
      this.hasCalculableDecision && this.calc.corridorSegment === "low_margin"
    );
  }

  get lowMarginBannerMessage() {
    return formatLabel(
      this.labels.lowMarginMessage,
      formatMoney(this.calc.tjmIdeal, this.currencyCode),
      this.idealPercentValue
    );
  }

  get showRecommendedBanner() {
    return (
      this.hasCalculableDecision && this.calc.corridorSegment === "recommended"
    );
  }

  get recommendedBannerMessage() {
    return formatLabel(
      this.labels.recommendedMessage,
      this.targetPercentValue,
      this.idealPercentValue
    );
  }

  get showSuperstarBanner() {
    return (
      this.hasCalculableDecision && this.calc.corridorSegment === "superstar"
    );
  }

  get superstarBannerMessage() {
    return formatLabel(this.labels.superstarMessage, this.idealPercentValue);
  }

  /**
   * Cards de seuils (session 18) : sans CJM résolu, `calc.tjmFloor/Target/Ideal` valent 0 — sur la
   * matrice VOLVO validée (VIE, aucun CJM saisi), les 3 cards affichaient « 0 € » comme s'il
   * s'agissait d'une vraie valeur calculée, pendant que la jauge juste en dessous était déjà
   * correctement masquée (session 17b) pour la même raison. Même garde-fou ici, réutilisé plutôt que
   * dupliqué une troisième fois — cf. `isCostCalculable`.
   */
  get formattedTjmFloor() {
    return this.isCostCalculable
      ? formatMoney(this.calc.tjmFloor, this.currencyCode)
      : "—";
  }

  get formattedTjmTarget() {
    return this.isCostCalculable
      ? formatMoney(this.calc.tjmTarget, this.currencyCode)
      : "—";
  }

  get formattedTjmIdeal() {
    return this.isCostCalculable
      ? formatMoney(this.calc.tjmIdeal, this.currencyCode)
      : "—";
  }

  get formattedTjmTop10() {
    return formatMoney(this.calc.tjmTop10, this.currencyCode);
  }

  /**
   * Libellé de la borne droite de la jauge (session 15, cf. docs/15-decision-exactitude.md) :
   * « Top 10 % » désignait deux nombres différents sur le même écran (le p90 réel du bloc Repères
   * marché, et `max(p90, idéal×1,10)` ici) — même formule que la maquette (`calcThresholds`,
   * arPricingEngine.js l.111-113), pas touchée, seul le libellé change pour lever l'ambiguïté.
   * Le libellé « Top 10 % » reste réservé au bloc Repères marché.
   */
  get gaugeCeilingHelpText() {
    const idealPlus10 = formatMoney(
      Math.ceil((this.calc.tjmIdeal || 0) * 1.1),
      this.currencyCode
    );
    if (!this.marketReference || !this.marketReference.hasEnoughData) {
      return formatLabel(this.labels.gaugeCeilingNoMarketRef, idealPlus10);
    }
    // Session 26 : `top10Comparables` n'alimente `compute()` que si `marketReferenceUsableForGauge`
    // (même devise) — le texte doit rester exact avec ce que le calcul retient réellement, jamais
    // annoncer un « plus élevé entre » deux montants dont un seul a été comparé.
    const marketP90 = formatMoney(
      this.marketReference.p90Tjm,
      this.marketReference.currencyCode
    );
    if (!this.marketReferenceUsableForGauge) {
      return formatLabel(
        this.labels.gaugeCeilingCurrencyMismatch,
        idealPlus10,
        marketP90
      );
    }
    return formatLabel(
      this.labels.gaugeCeilingBothAvailable,
      marketP90,
      idealPlus10
    );
  }

  /**
   * Pourcentages du corridor appliqué (session 14, tâche 1) : surcharge Grand Compte
   * (`corridorPercents`, alimenté par `AR_PricingMatrixService.getAccountCorridorPercents`) si elle
   * existe, sinon les défauts du moteur (`arPricingEngine` — mêmes constantes que `AR_PricingCalculator`).
   */
  get floorPercentValue() {
    return this.appliedCorridorPercents.floorPercent;
  }

  get targetPercentValue() {
    return this.appliedCorridorPercents.targetPercent;
  }

  get idealPercentValue() {
    return this.appliedCorridorPercents.idealPercent;
  }

  /**
   * Session 155 — corridor effectivement appliqué : grand compte (`corridorPercents`) s'il existe,
   * sinon les seuils de Paramètres généraux servis par `getPricingSettings` (`this.settings`), sinon
   * seulement les constantes du moteur (serveur muet). `corridorPercents` reste à null sans grand
   * compte : `hasGrandCompteCorridor` et le bandeau « Grand compte » s'appuient dessus.
   */
  get appliedCorridorPercents() {
    if (this.corridorPercents) {
      return this.corridorPercents;
    }
    const pick = (fromSettings, fallback) => {
      const usable =
        typeof fromSettings === "number" && Number.isFinite(fromSettings);
      return usable ? fromSettings : fallback;
    };
    return {
      floorPercent: pick(
        this.settings?.floorPercentDefault,
        FLOOR_PERCENT_DEFAULT
      ),
      targetPercent: pick(
        this.settings?.targetPercentDefault,
        TARGET_PERCENT_DEFAULT
      ),
      idealPercent: pick(
        this.settings?.idealPercentDefault,
        IDEAL_PERCENT_DEFAULT
      )
    };
  }

  get floorPercentLabel() {
    return formatLabel(this.labels.floorPercentLabel, this.floorPercentValue);
  }

  get targetPercentLabel() {
    return formatLabel(this.labels.targetPercentLabel, this.targetPercentValue);
  }

  // Libellé "Annoncé" conforme à la maquette (pricing-tool.html:2056) pour cette card — le moteur
  // garde en interne "idéal" (tjmIdeal/idealPercent), et la jauge/le panneau de dérogation gardent
  // l'affichage "Idéal" (fidèles eux aussi à la maquette, qui n'emploie "Annoncé" qu'ici) : les deux
  // usages coexistent dans la maquette elle-même, ce n'est pas une incohérence introduite ici — cf.
  // docs/14-seuils-explicabilite.md.
  get idealPercentLabel() {
    return formatLabel(this.labels.idealPercentLabel, this.idealPercentValue);
  }

  // Session 252 : un corridor figé « DEFAULT » porte les pourcentages appliqués, sans bandeau.
  get hasGrandCompteCorridor() {
    return (
      !!this.corridorPercents && this.corridorPercents.source !== "DEFAULT"
    );
  }

  /** Libellé d'origine du bandeau : « Seuils Grand Compte : » ou « Seuils de l'entité <nom> : ». */
  get thresholdsOriginLabel() {
    if (this.corridorPercents?.source === "ENTITY") {
      return formatLabel(
        this.labels.entityThresholdsLabel,
        this.corridorPercents.entityName
      );
    }
    return this.labels.grandCompteThresholdsLabel;
  }

  get grandCompteBannerLabel() {
    if (!this.corridorPercents) {
      return "";
    }
    return formatLabel(
      this.labels.grandCompteBanner,
      this.floorPercentValue,
      this.targetPercentValue,
      this.idealPercentValue
    );
  }

  /**
   * Contenu du popover d'explicabilité du bloc seuils (session 14, tâche 2b) — formule reprise telle
   * quelle de arPricingEngine.js/AR_PricingCalculator.cls (les deux moteurs sont identiques, cf.
   * docs/14-seuils-explicabilite.md), avec les valeurs de la simulation en cours. Aucun appel serveur :
   * tout vient de `calc`, déjà recalculé côté client à chaque saisie.
   */
  get thresholdsFormulaCjmLine() {
    const cjmValue = formatMoney(this.calc.cjm, this.currencyCode);
    if (this.isCDI) {
      return formatLabel(
        this.labels.thresholdCjmLineCDI,
        this.settings.workingDaysPerYear,
        cjmValue
      );
    }
    if (this.isINDEP) {
      return formatLabel(this.labels.thresholdCjmLineIndep, cjmValue);
    }
    if (this.isVIE) {
      return formatLabel(this.labels.thresholdCjmLineVie, cjmValue);
    }
    return formatLabel(this.labels.thresholdCjmLineNearshore, cjmValue);
  }

  get thresholdsFormulaCostLine() {
    const totalValue = formatMoney(this.calc.totalDailyCost, this.currencyCode);
    if (this.isCDI || this.isVIE) {
      return formatLabel(
        this.labels.thresholdCostLineStandard,
        formatMoney(this.calc.feeOmPerDay, this.currencyCode),
        formatMoney(this.calc.feePonctuelsPerDay, this.currencyCode),
        totalValue
      );
    }
    return formatLabel(
      this.labels.thresholdCostLineOther,
      this.settings.workingDaysPerYear,
      totalValue
    );
  }

  // Même origine que le bandeau (`thresholdsOriginLabel`) : entité, grand compte ou paramètres généraux.
  get thresholdsFormulaCorridorLine() {
    let source = this.labels.thresholdCorridorStandard;
    if (this.corridorPercents?.source === "ENTITY") {
      source = formatLabel(
        this.labels.thresholdCorridorEntity,
        this.corridorPercents.entityName,
        this.floorPercentValue,
        this.targetPercentValue,
        this.idealPercentValue
      );
    } else if (this.hasGrandCompteCorridor) {
      source = formatLabel(
        this.labels.thresholdCorridorGrandCompte,
        this.floorPercentValue,
        this.targetPercentValue,
        this.idealPercentValue
      );
    }
    return formatLabel(this.labels.thresholdCorridorLine, source);
  }

  get thresholdsFormulaRfaLine() {
    const rfa = this.rfaPercent || 0;
    const gratuity = this.gratuityDays || 0;
    const parts = [];
    if (rfa > 0) {
      parts.push(formatLabel(this.labels.rfaImpact, formatPercent(rfa)));
    }
    if (gratuity > 0) {
      const gratuityTemplate =
        gratuity > 1
          ? this.labels.gratuityImpactPlural
          : this.labels.gratuityImpactSingular;
      parts.push(
        formatLabel(
          gratuityTemplate,
          gratuity,
          this.calc.feePonctuelsDivisorDays
        )
      );
    }
    return parts.length ? `${parts.join(" ; ")}.` : this.labels.noRfaNoGratuity;
  }

  get thresholdsFormulaNote() {
    return this.labels.thresholdsFormulaNote;
  }

  /**
   * Tuile MC2/jour dominante (session 18) : sans CJM résolu, `calc.mc2PerDay` vaut TJM − 0, un
   * chiffre faux affiché en gros et en vert (matrice VOLVO validée : « 763 € » de marge sur un TJM
   * de 763 €). Le message explicatif (`mc2ContextLine`) arrivait déjà en dessous, mais en petit —
   * le plus gros caractère de la zone 3 restait le chiffre erroné. Réutilise `isCostCalculable`
   * (déjà partagé par la jauge et les cards de seuils), pas un test dédié de plus. L'autre usage de
   * ce getter (décomposition MC2) est déjà masqué par `showMc2Breakdown` dans ce même cas — ce
   * garde-fou ne change rien pour lui, juste sûr par construction.
   */
  get formattedMc2PerDay() {
    return this.isCostCalculable
      ? formatMoney(this.calc.mc2PerDay, this.currencyCode)
      : "—";
  }

  get mc2PerDayBreakdown() {
    return this.isCostCalculable
      ? this.addDecimalClass(
          formatMoneyWithDecimalBreakdown(
            this.calc.mc2PerDay,
            this.currencyCode
          )
        )
      : {
          intPart: "—",
          decPart: "",
          hasDecimal: false,
          symbol: "",
          decClass: "amt-dec amt-dec-hidden"
        };
  }

  get formattedMc2Percent() {
    return formatPercent(this.calc.mc2PercentHuman);
  }

  get gaugeThresholdsContext() {
    return {
      floorValue: this.calc.tjmFloor,
      targetValue: this.calc.tjmTarget,
      idealValue: this.calc.tjmIdeal,
      top10Value: this.calc.tjmTop10,
      // Session 126 : la jauge démarre au coût de revient (marge 0 %).
      // Calcul serveur (matrice validée) : pas de tjmZeroMargin → dérivé de totalDailyCost.
      zeroMarginValue:
        this.calc.tjmZeroMargin != null
          ? this.calc.tjmZeroMargin
          : this.calc.totalDailyCost
            ? Math.ceil(
                this.calc.totalDailyCost /
                  Math.max(0.01, 1 - (Number(this.rfaPercent) || 0) / 100)
              )
            : null
    };
  }

  get gaugeCursorStyle() {
    return `left: ${this.gaugePosition}%; transform: translate(-50%, -50%);`;
  }

  /**
   * Session 18d : un TJM hors de l'échelle [min, max] est borné à 0/100 par `calcGaugePosition`
   * comme n'importe quelle position — sans ce signal, le curseur se pose au bord et devient
   * indiscernable d'un TJM légitimement au bord de l'échelle (même défaut de principe que les
   * affichages faux corrigés en sessions 15/16). Gardé par `hasProposedTjm` : sans TJM saisi,
   * `proposedTjm` vaut `undefined` (→ 0 côté moteur), qui serait presque toujours "hors échelle"
   * par rapport à un plancher typique — un faux positif permanent sur l'état par défaut de l'écran.
   */
  get isGaugeOutOfScale() {
    return (
      this.hasProposedTjm &&
      isGaugePositionOutOfScale(this.effectiveTjm, this.gaugeThresholdsContext)
    );
  }

  get gaugeCursorClass() {
    return this.isGaugeOutOfScale
      ? "gauge-dot gauge-dot-out-of-scale"
      : "gauge-dot";
  }

  /**
   * Dégradé de la piste calculé sur la même échelle que les graduations (session 17b) : la barre
   * était restée un dégradé à pas fixes (25/50/75%) pendant que les graduations, repositionnées en
   * session 16 via `calcGaugePosition`, tombaient ailleurs — au TJM de référence 560€ le curseur
   * atterrissait dans la bande orange pendant que le badge annonçait « Recommandé », l'écran se
   * contredisait (confirmé à l'écran le 09/08, cf. docs/15-diff-maquette-org.md). Réutilise
   * `calcGaugePosition`, comme le curseur et les graduations — pas de quatrième fonction de
   * positionnement. `Math.max` impose des frontières non décroissantes (seuils très resserrés) :
   * un dégradé CSS à positions décroissantes se comporterait déjà ainsi nativement, mais autant être
   * explicite plutôt que de compter sur ce détail de la spec.
   */
  get gaugeTrackStyle() {
    const floor = calcGaugePosition(
      this.calc.tjmFloor || 0,
      this.gaugeThresholdsContext
    );
    const target = calcGaugePosition(
      this.calc.tjmTarget || 0,
      this.gaugeThresholdsContext
    );
    const ideal = calcGaugePosition(
      this.calc.tjmIdeal || 0,
      this.gaugeThresholdsContext
    );

    const floorPct = Math.max(0, floor);
    const targetPct = Math.max(floorPct, target);
    const idealPct = Math.max(targetPct, ideal);

    return (
      `background: linear-gradient(to right, ` +
      `#dc2626 0%, #dc2626 ${floorPct}%, ` +
      `#f59e0b ${floorPct}%, #f59e0b ${targetPct}%, ` +
      `#4ade80 ${targetPct}%, #4ade80 ${idealPct}%, ` +
      `#16a34a ${idealPct}%, #16a34a 100%);`
    );
  }

  get gaugeTitleTjmLabel() {
    return this.hasProposedTjm
      ? `${this.formattedProposedTjmBreakdown}${this.labels.gaugeTitleTjmSuffix}`
      : "";
  }

  // --- Jauge : mise en page en pixels réels ---

  gaugeTrackWidth = 0;
  _gaugeObserver;
  _gaugeObservedTrack;
  _gaugeFontFamily = "sans-serif";

  /** Branche (une seule fois par élément) le `ResizeObserver` sur la piste ; sans API (Jest), largeur de repli. */
  observeGaugeTrack() {
    const track = this.template.querySelector(".gauge-track");
    if (track !== this._gaugeObservedTrack) {
      this.disconnectGaugeObserver();
      this._gaugeObservedTrack = track;
      if (track && typeof ResizeObserver === "function") {
        this._gaugeFontFamily =
          getComputedStyle(track).fontFamily || "sans-serif";
        this._gaugeObserver = new ResizeObserver((entries) => {
          this.setGaugeTrackWidth(
            entries[entries.length - 1]?.contentRect?.width
          );
        });
        this._gaugeObserver.observe(track);
      }
    }
    // Mesure directe à chaque rendu et à chaque redimensionnement de fenêtre : filet si l'observateur ne notifie pas.
    const measured = track ? track.getBoundingClientRect().width : 0;
    if (measured > 0) {
      this.setGaugeTrackWidth(measured);
    }
  }

  disconnectGaugeObserver() {
    if (this._gaugeObserver) {
      this._gaugeObserver.disconnect();
    }
    this._gaugeObserver = undefined;
    this._gaugeObservedTrack = undefined;
  }

  setGaugeTrackWidth(width) {
    const next = Math.floor(Number(width) || 0);
    if (next !== this.gaugeTrackWidth) {
      this.gaugeTrackWidth = next;
    }
  }

  /** Côté d'une valeur hors échelle : « left » sous le coût de revient, « right » au-dessus du plafond, sinon vide. */
  gaugeOutSide(value) {
    const thresholds = this.gaugeThresholdsContext;
    if (!isGaugePositionOutOfScale(value, thresholds)) {
      return "";
    }
    return calcGaugePosition(value, thresholds) <= 0 ? "left" : "right";
  }

  /** Pastille « MC2 27,5 % · Annoncé » de l'en-tête : zone et % du prix 1, absente sans TJM. */
  get gaugeHeaderPill() {
    const segment = this.calc.corridorSegment;
    if (!this.hasCalculableDecision || !segment) {
      return null;
    }
    const zoneLabels = {
      below_floor: this.labels.gaugeZoneBelowFloor,
      low_margin: this.labels.gaugeZoneLowMargin,
      recommended: this.labels.gaugeZoneRecommended,
      superstar: this.labels.gaugeZoneSuperstar
    };
    return {
      text: `${formatLabel(this.labels.gaugeMc2, formatPercent(this.calc.mc2PercentHuman))} \u00B7 ${zoneLabels[segment]}`,
      cssClass: GAUGE_ZONE_PILL_CLASS[segment]
    };
  }

  /**
   * Mise en page complète de la jauge : étage des prix (pastilles + tiges) au-dessus de la piste, étage
   * des seuils (traits + étiquettes) dessous. Toute position vient de `calcGaugePosition`, convertie en
   * pixels sur la largeur mesurée de la piste.
   */
  get gaugeView() {
    const measured = this.gaugeTrackWidth > 0;
    const width = measured
      ? this.gaugeTrackWidth
      : GAUGE_FALLBACK_TRACK_WIDTH_PX;
    const font = this._gaugeFontFamily;
    const measure = (text, weight, size) =>
      measureGaugeText(text, weight, size, font, measured);
    const round = (value) => Math.round(value * 100) / 100;
    const toPx = (position) => (position / 100) * width;
    const thresholds = this.gaugeThresholdsContext;
    const money = (value) => formatMoney(value, this.currencyCode);

    // Étage des prix
    const pills = [];
    const pushPill = (pill) => {
      const tagWeight = pill.tagWeight || 700;
      pills.push({
        ...pill,
        width:
          measure(pill.tag, tagWeight, 12) +
          (pill.value ? measure(` ${pill.value}`, 700, 12) : 0) +
          GAUGE_PILL_PADDING_PX
      });
    };
    const priceValueText = (value) => {
      const side = this.gaugeOutSide(value);
      return `${side === "left" ? "\u2039 " : ""}${money(value)}${side === "right" ? " \u203A" : ""}`;
    };
    const priceTitle = (tag, value, mc2Percent) => {
      const hover = formatLabel(
        this.labels.negoGaugeHover,
        tag,
        money(value),
        formatPercent(mc2Percent)
      );
      return this.gaugeOutSide(value)
        ? `${hover} ${this.labels.gaugeOutOfScaleSuffix}`
        : hover;
    };
    if (this.hasProposedTjm) {
      const actualTag = formatLabel(this.labels.gaugeActualLabel, "").trim();
      pushPill({
        key: "actual",
        tag: actualTag,
        tagWeight: 500,
        tagClass: "gauge-pill-tag gauge-pill-tag-actual",
        value: priceValueText(this.effectiveTjm),
        title: priceTitle(
          this.hasTjmPeriods ? this.labels.tjmWeightedGaugeTitle : actualTag,
          this.effectiveTjm,
          this.calc.mc2PercentHuman
        ),
        pillClass: "gauge-pill gauge-pill-actual",
        stemClass: "gauge-stem gauge-stem-actual",
        x: toPx(this.gaugePosition)
      });
    }
    this.negoEntries.forEach((entry) => {
      const suffix = negoSegmentSuffix(entry.segment);
      pushPill({
        key: `p${entry.rank}`,
        tag: entry.marker,
        tagClass: "gauge-pill-tag",
        value: priceValueText(entry.value),
        title: priceTitle(entry.header, entry.value, entry.mc2PercentHuman),
        pillClass: `gauge-pill gauge-pill-nego${suffix}`,
        stemClass: `gauge-stem gauge-stem-nego${suffix}`,
        x: toPx(calcGaugePosition(entry.value, thresholds))
      });
    });
    if (this.showRplsrGhost) {
      pushPill({
        key: "rplsr",
        tag: this.labels.rplsrClassic,
        tagClass: "gauge-pill-tag",
        value: "",
        title: this.rplsrGhostTitle,
        pillClass: "gauge-pill gauge-pill-ghost",
        stemClass: "gauge-stem gauge-stem-ghost",
        x: toPx(this.rplsrGhostPosition)
      });
    }
    const priceStage = stageGaugeLabels(pills, width, GAUGE_LABEL_GAP_PX);
    const laneHeight =
      priceStage.levelCount * GAUGE_PILL_LEVEL_STEP_PX +
      GAUGE_PILL_LANE_PADDING_PX;
    const prices = priceStage.placed.map((pill) => {
      const top =
        laneHeight -
        (GAUGE_PILL_HEIGHT_PX + GAUGE_PILL_LANE_PADDING_PX) -
        pill.level * GAUGE_PILL_LEVEL_STEP_PX;
      const stemTop = top + GAUGE_PILL_HEIGHT_PX;
      const stemLeft = Math.min(width - 2, Math.max(0, pill.x - 1));
      return {
        key: pill.key,
        tag: pill.tag,
        value: pill.value,
        title: pill.title,
        pillClass: pill.pillClass,
        tagClass: pill.tagClass,
        stemClass: pill.stemClass,
        x: round(pill.x),
        level: pill.level,
        boxLeft: round(pill.boxLeft),
        boxRight: round(pill.boxRight),
        stemLeft: round(stemLeft),
        pillStyle: `left: ${round(pill.boxLeft)}px; top: ${top}px; width: ${round(pill.width)}px;`,
        stemStyle: `left: ${round(stemLeft)}px; top: ${stemTop}px; height: ${laneHeight + GAUGE_TRACK_HEIGHT_PX / 2 - stemTop}px;`
      };
    });

    // Étage des seuils
    // « MC2 20 % » : les seuils sont des pourcentages ronds, la décimale nulle est omise.
    const mc2Label = (percent) =>
      formatLabel(
        this.labels.gaugeMc2,
        formatPercent(percent).replace(/,0(?=\s|$)/, "")
      );
    const ruler = [];
    const zeroMargin = Number(thresholds.zeroMarginValue);
    if (zeroMargin > 0 && zeroMargin < Number(thresholds.floorValue)) {
      ruler.push({
        key: "cost",
        name: this.labels.gaugeCostLabel,
        colorClass: "gauge-grad-cost",
        value: zeroMargin,
        percent: 0
      });
    }
    ruler.push(
      {
        key: "floor",
        name: this.labels.gradFloor,
        colorClass: "gauge-grad-floor",
        value: this.calc.tjmFloor,
        percent: this.floorPercentValue
      },
      {
        key: "target",
        name: this.labels.gradTarget,
        colorClass: "gauge-grad-target",
        value: this.calc.tjmTarget,
        percent: this.targetPercentValue
      },
      {
        key: "ideal",
        name: this.labels.gradIdeal,
        colorClass: "gauge-grad-ideal",
        value: this.calc.tjmIdeal,
        percent: this.idealPercentValue
      },
      {
        key: "ceiling",
        name: this.labels.gradCeiling,
        colorClass: "gauge-grad-top10",
        value: this.calc.tjmTop10,
        percent: calcMc2ForTjm(
          this.calc.tjmTop10,
          this.negoCostForMargin,
          this.rfaPercent,
          this.appliedCorridorPercents
        ).mc2PercentHuman,
        hasHelpText: true
      }
    );
    const rulerItems = ruler.map((item) => {
      const nameWidth =
        measure(item.name, 600, 11) +
        (item.hasHelpText ? GAUGE_RULER_HELP_ICON_PX : 0);
      const valueWidth =
        measure(money(item.value), 700, 13) +
        measure(` \u00B7 ${mc2Label(item.percent)}`, 400, 12);
      return {
        ...item,
        valueText: money(item.value),
        mc2Text: ` \u00B7 ${mc2Label(item.percent)}`,
        x: toPx(calcGaugePosition(item.value, thresholds)),
        width: Math.max(nameWidth, valueWidth) + GAUGE_RULER_LABEL_PADDING_PX
      };
    });
    const rulerStage = stageGaugeLabels(rulerItems, width, GAUGE_LABEL_GAP_PX);
    const rulerTop = laneHeight + GAUGE_TRACK_HEIGHT_PX + 4;
    const thresholdItems = rulerStage.placed.map((item) => {
      const align =
        item.x - item.width / 2 < 0
          ? "left"
          : item.x + item.width / 2 > width
            ? "right"
            : "center";
      const tickLeft = Math.min(width - 1, Math.max(0, item.x - 0.5));
      return {
        key: item.key,
        name: item.name,
        nameClass: `gauge-ruler-name ${item.colorClass}`,
        valueText: item.valueText,
        mc2Text: item.mc2Text,
        hasHelpText: !!item.hasHelpText,
        x: round(item.x),
        level: item.level,
        boxLeft: round(item.boxLeft),
        boxRight: round(item.boxRight),
        tickLeft: round(tickLeft),
        tickStyle: `left: ${round(tickLeft)}px; top: ${rulerTop}px; height: ${GAUGE_RULER_TICK_PX + item.level * GAUGE_RULER_LEVEL_STEP_PX}px;`,
        labelClass: `gauge-ruler-label gauge-ruler-label-${align}`,
        labelStyle: `left: ${round(item.boxLeft)}px; top: ${rulerTop + 10 + item.level * GAUGE_RULER_LEVEL_STEP_PX}px; width: ${round(item.width)}px;`
      };
    });
    const separators = ["tjmFloor", "tjmTarget", "tjmIdeal"].map((field) => ({
      key: field,
      style: `left: ${calcGaugePosition(this.calc[field] || 0, thresholds)}%;`
    }));

    return {
      width,
      stageStyle: `height: ${rulerTop + 10 + rulerStage.levelCount * GAUGE_RULER_LEVEL_STEP_PX}px;`,
      trackStyle: `${this.gaugeTrackStyle} top: ${laneHeight}px;`,
      prices,
      thresholds: thresholdItems,
      separators
    };
  }

  /**
   * Légende de la jauge (session 16, MarketGauge l.984-989) : pourcentages issus de
   * `corridorPercents` (surcharge Grand Compte) quand elle s'applique, jamais 20/25/30 en dur.
   */
  get gaugeLegendItems() {
    return [
      {
        key: "floor",
        swatchStyle: "background: #dc2626;",
        label: formatLabel(this.labels.gaugeLegendFloor, this.floorPercentValue)
      },
      {
        key: "target",
        swatchStyle: "background: #f59e0b;",
        label: formatLabel(
          this.labels.gaugeLegendTarget,
          this.floorPercentValue,
          this.targetPercentValue
        )
      },
      {
        key: "ideal",
        swatchStyle: "background: #4ade80;",
        label: formatLabel(
          this.labels.gaugeLegendIdeal,
          this.targetPercentValue,
          this.idealPercentValue
        )
      },
      {
        key: "superstar",
        swatchStyle: "background: #16a34a;",
        label: formatLabel(
          this.labels.gaugeLegendSuperstar,
          this.idealPercentValue
        )
      }
    ];
  }

  get markupMismatchMessage() {
    return this.calc.markupMismatch
      ? formatLabel(
          this.labels.markupMismatch,
          formatMoney(this.calc.markupCalcule, this.currencyCode)
        )
      : "";
  }

  // Matrice validée : seule l'entité reste modifiable (isEntityChangeableOnly), le bandeau le dit au
  // lieu de répéter que la matrice n'est plus modifiable. Autres statuts décidés : statut traduit.
  get statusBannerMessage() {
    if (this.isEditable) {
      return "";
    }
    if (this.isEntityChangeableOnly) {
      return this.labels.statusBannerValidated;
    }
    return formatLabel(this.labels.statusBannerLocked, this.statusLabel);
  }

  // Badge « Gagnée · P2 » de l'en-tête (session 284) : la version confirmée gagnante du besoin.
  wonBadgeText = "";

  async loadWonBadge() {
    this.wonBadgeText = "";
    if (
      !this.matrixId ||
      !this.positionId ||
      !["Validée", "Validée par dérogation"].includes(this.status)
    ) {
      return;
    }
    try {
      const deal = await loadWonDeal({ positionId: this.positionId });
      const version =
        deal && deal.versions
          ? deal.versions.find((v) => v.matrixId === this.matrixId && v.won)
          : null;
      if (version) {
        const levels = {
          P1: LBL_AR_Won_Dlg_Price1,
          P2: LBL_AR_Won_Dlg_Price2,
          P3: LBL_AR_Won_Dlg_Price3,
          "Hors grille": LBL_AR_Won_Dlg_OffGrid
        };
        this.wonBadgeText = formatLabel(
          LBL_AR_Won_Badge,
          levels[version.signedPriceLevel] || version.signedPriceLevel || ""
        );
      }
    } catch (error) {
      // Journaliser : le badge est une information secondaire, son absence ne bloque rien.
      console.error("arPriceMatrixSimulator.loadWonBadge", error);
    }
  }

  get statusLabel() {
    const labels = {
      Validée: this.labels.statusValidated,
      "Validée par dérogation": this.labels.statusValidatedByDerogation,
      "En dérogation": this.labels.statusInDerogation,
      Refusée: this.labels.statusRejected
    };
    return labels[this.status] || this.status;
  }

  /**
   * Restyle du bandeau de statut (session 16) : c'était une bande `slds-theme_alert-texture` grise
   * brute, en décalage avec la charte — même défaut que la bande Salesforce neutralisée en session
   * 12b. Une teinte par statut, cohérente avec les couleurs déjà utilisées dans « Mes matrices »
   * (arMatrixList.css : status-validated/pending/validated-derog/rejected).
   */
  get statusBannerClass() {
    return `status-banner ${STATUS_BANNER_META[this.status] || "status-banner-rejected"}`;
  }

  /**
   * Rappel chiffré dans la modale de dérogation (session 16, pricing-tool.html:2168-2190) : absent
   * de l'org, la maquette rappelle le TJM proposé et le plancher pour que le motif se construise
   * en connaissance de cause.
   */
  get derogationRecallMessage() {
    return formatLabel(
      this.labels.derogationRecall,
      formatMoney(this.effectiveTjm, this.currencyCode),
      formatMoney(this.calc.tjmFloor, this.currencyCode)
    );
  }

  // Motif(s), commentaire et valideur sont obligatoires côté Apex (AR_PricingMatrixService.requestDerogation) :
  // désactiver l'envoi tant que l'un des trois manque évite l'aller-retour serveur pour rien.
  get isDerogationSendDisabled() {
    return (
      this.isSaving ||
      (this.derogationReasonIds || []).length === 0 ||
      !this.derogationValidatorId ||
      !this.hasDerogationComment
    );
  }

  // Duplication / chaîne de négociation (session 22). Visible sur toute matrice déjà enregistrée
  // (décidée ou Brouillon) — jamais sur la vue de saisie d'une matrice pas encore créée.
  //
  // Choix EXPLICITEMENT ASSUMÉ, tranché en session 28b §3 (le bouton apparaissant sur un Brouillon
  // avait été signalé comme suspect, soupçonné d'être un effet de bord du statut "undefined" — ce
  // n'en est pas un : `canDuplicate` n'a jamais dépendu de `this.status`, avant comme après le
  // correctif de session 28b §1). Un Brouillon dupliqué produit une copie libre, sans filiation ni
  // motif (`isChainDuplication` ci-dessous en décide, séparément de la visibilité du bouton) —
  // cohérent avec l'action de ligne « Dupliquer » ajoutée sur `arMatrixList` en session 28, qui
  // adopte la même règle (visible sur toute matrice, y compris Brouillon) : les deux points d'entrée
  // ne doivent pas diverger silencieusement.
  get hasMatrixId() {
    return !!this.matrixId;
  }

  get canDuplicate() {
    return !!this.matrixId && !this.readOnlyAccess;
  }

  get isChainDuplication() {
    return CHAIN_SOURCE_STATUSES.includes(this.status);
  }

  get duplicateSourcePositionLabel() {
    const name = this.positionContext && this.positionContext.positionName;
    if (!name) {
      return "";
    }
    const account =
      this.positionContext.accountName || this.labels.noAccountFallback;
    return formatLabel(this.labels.duplicateSourcePositionLabel, name, account);
  }

  handleOpenDuplicateModal() {
    this.showDuplicateModal = true;
  }

  handleCloseDuplicateModal() {
    this.showDuplicateModal = false;
  }

  handleMatrixDuplicated(event) {
    this.showDuplicateModal = false;
    this.showToast(
      this.labels.successTitle,
      this.labels.matrixDuplicated,
      "success"
    );
    // Le simulateur ne se recharge pas lui-même sur un nouvel enregistrement : on délègue la
    // navigation au parent (arPricingApp), même contrat d'événement que arMatrixList/onopenmatrix.
    this.dispatchEvent(
      new CustomEvent("openmatrix", {
        detail: { matrixId: event.detail.matrixId },
        bubbles: true,
        composed: true
      })
    );
  }

  handleOpenAvenantModal() {
    this.showAvenantModal = true;
  }

  handleCloseAvenantModal() {
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
    // Remonter le simulateur sur la matrice avenant (piège session 117) : le shell navigue, comme pour
    // la duplication. `focusSection: "derogation"` ouvre la demande de dérogation à l'arrivée.
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

  // Session 156 : getter pour l'accès en lecture seule au template (binding vers le brouillon).
  get derogationReason() {
    return this._derogationReasonDraft;
  }
}