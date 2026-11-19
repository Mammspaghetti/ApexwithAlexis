import { LightningElement } from "lwc";
import { reduceErrors } from "c/arErrorUtils";
import { confirmAdminDelete } from "c/arConfirmDelete";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getGeneralSettings from "@salesforce/apex/AR_AdminSettingsService.getGeneralSettings";
import saveGeneralSettingsApex from "@salesforce/apex/AR_AdminSettingsService.saveGeneralSettings";
import getWorkingDaysExceptions from "@salesforce/apex/AR_AdminSettingsService.getWorkingDaysExceptions";
import saveWorkingDaysException from "@salesforce/apex/AR_AdminSettingsService.saveWorkingDaysException";
import deleteWorkingDaysException from "@salesforce/apex/AR_AdminSettingsService.deleteWorkingDaysException";
import getEntityOptions from "@salesforce/apex/AR_PricingMatrixService.getEntityOptions";
import { formatLabel, pluralLabel } from "c/arI18n";
import LBL_AR_AGS_AddException from "@salesforce/label/c.AR_AGS_AddException";
import LBL_AR_AGS_DaysPerYear from "@salesforce/label/c.AR_AGS_DaysPerYear";
import LBL_AR_AGS_DraftPurgeSection from "@salesforce/label/c.AR_AGS_DraftPurgeSection";
import LBL_AR_AGS_EngineDefaultsNotice from "@salesforce/label/c.AR_AGS_EngineDefaultsNotice";
import LBL_AR_AGS_EscalationHours from "@salesforce/label/c.AR_AGS_EscalationHours";
import LBL_AR_AGS_ExceptionCountMany from "@salesforce/label/c.AR_AGS_ExceptionCountMany";
import LBL_AR_AGS_ExceptionCountOne from "@salesforce/label/c.AR_AGS_ExceptionCountOne";
import LBL_AR_AGS_ExceptionHeading from "@salesforce/label/c.AR_AGS_ExceptionHeading";
import LBL_AR_AGS_ExceptionRemoved from "@salesforce/label/c.AR_AGS_ExceptionRemoved";
import LBL_AR_AGS_ExceptionSaved from "@salesforce/label/c.AR_AGS_ExceptionSaved";
import LBL_AR_AGS_FloorPercentDefault from "@salesforce/label/c.AR_AGS_FloorPercentDefault";
import LBL_AR_AGS_FreqDaily from "@salesforce/label/c.AR_AGS_FreqDaily";
import LBL_AR_AGS_FreqDisabled from "@salesforce/label/c.AR_AGS_FreqDisabled";
import LBL_AR_AGS_FreqImmediate from "@salesforce/label/c.AR_AGS_FreqImmediate";
import LBL_AR_AGS_FreqWeekly from "@salesforce/label/c.AR_AGS_FreqWeekly";
import LBL_AR_AGS_Frequency from "@salesforce/label/c.AR_AGS_Frequency";
import LBL_AR_AGS_HierarchyNotificationFrequency from "@salesforce/label/c.AR_AGS_HierarchyNotificationFrequency";
import LBL_AR_AGS_HierarchyNotificationSection from "@salesforce/label/c.AR_AGS_HierarchyNotificationSection";
import LBL_AR_AGS_IdealPercentDefault from "@salesforce/label/c.AR_AGS_IdealPercentDefault";
import LBL_AR_AGS_InAppNotificationsEnabled from "@salesforce/label/c.AR_AGS_InAppNotificationsEnabled";
import LBL_AR_AGS_LifetimeDays from "@salesforce/label/c.AR_AGS_LifetimeDays";
import LBL_AR_AGS_MarkupMax from "@salesforce/label/c.AR_AGS_MarkupMax";
import LBL_AR_AGS_MarkupPercent from "@salesforce/label/c.AR_AGS_MarkupPercent";
import LBL_AR_AGS_MaxPerRun from "@salesforce/label/c.AR_AGS_MaxPerRun";
import LBL_AR_AGS_MaxRecipientsPerEscalation from "@salesforce/label/c.AR_AGS_MaxRecipientsPerEscalation";
import LBL_AR_AGS_NoException from "@salesforce/label/c.AR_AGS_NoException";
import LBL_AR_AGS_NoExceptionYet from "@salesforce/label/c.AR_AGS_NoExceptionYet";
import LBL_AR_AGS_NotificationsSection from "@salesforce/label/c.AR_AGS_NotificationsSection";
import LBL_AR_AGS_OfiiTaxRate from "@salesforce/label/c.AR_AGS_OfiiTaxRate";
import LBL_AR_AGS_OfiiTaxRateHelp from "@salesforce/label/c.AR_AGS_OfiiTaxRateHelp";
import LBL_AR_AGS_OfiiTaxCap from "@salesforce/label/c.AR_AGS_OfiiTaxCap";
import LBL_AR_AGS_DashboardMc2Bands from "@salesforce/label/c.AR_AGS_DashboardMc2Bands";
import LBL_AR_AGS_DashboardMc2BandsHelp from "@salesforce/label/c.AR_AGS_DashboardMc2BandsHelp";
import LBL_AR_AGS_DashboardMc2BandsEmpty from "@salesforce/label/c.AR_AGS_DashboardMc2BandsEmpty";
import LBL_AR_AGS_DashboardMc2BandsInvalid from "@salesforce/label/c.AR_AGS_DashboardMc2BandsInvalid";
import LBL_AR_AGS_DerogationWaiver from "@salesforce/label/c.AR_AGS_DerogationWaiver";
import LBL_AR_AGS_DerogationWaiverHelp from "@salesforce/label/c.AR_AGS_DerogationWaiverHelp";
import LBL_AR_AGS_OfiiTaxCapHelp from "@salesforce/label/c.AR_AGS_OfiiTaxCapHelp";
import LBL_AR_AGS_PurgeDays from "@salesforce/label/c.AR_AGS_PurgeDays";
import LBL_AR_AGS_PurgeEnabled from "@salesforce/label/c.AR_AGS_PurgeEnabled";
import LBL_AR_AGS_PurgeMaxPerRun from "@salesforce/label/c.AR_AGS_PurgeMaxPerRun";
import LBL_AR_AGS_ReminderEnabled from "@salesforce/label/c.AR_AGS_ReminderEnabled";
import LBL_AR_AGS_ReminderEscalationSection from "@salesforce/label/c.AR_AGS_ReminderEscalationSection";
import LBL_AR_AGS_ReminderHours from "@salesforce/label/c.AR_AGS_ReminderHours";
import LBL_AR_AGS_ReminderMaxPerRun from "@salesforce/label/c.AR_AGS_ReminderMaxPerRun";
import LBL_AR_AGS_SettingsSaved from "@salesforce/label/c.AR_AGS_SettingsSaved";
import LBL_AR_AGS_TargetPercentDefault from "@salesforce/label/c.AR_AGS_TargetPercentDefault";
import LBL_AR_AGS_ThresholdsAndMarkup from "@salesforce/label/c.AR_AGS_ThresholdsAndMarkup";
import LBL_AR_AGS_ValidatedInPopupSection from "@salesforce/label/c.AR_AGS_ValidatedInPopupSection";
import LBL_AR_AGS_ValidatedLifetime from "@salesforce/label/c.AR_AGS_ValidatedLifetime";
import LBL_AR_AGS_WarningDaysBefore from "@salesforce/label/c.AR_AGS_WarningDaysBefore";
import LBL_AR_AGS_WorkingDaysExceptions from "@salesforce/label/c.AR_AGS_WorkingDaysExceptions";
import LBL_AR_AGS_WorkingDaysExceptionsHelp from "@salesforce/label/c.AR_AGS_WorkingDaysExceptionsHelp";
import LBL_AR_Common_Edit from "@salesforce/label/c.AR_Common_Edit";
import LBL_AR_Common_Entity from "@salesforce/label/c.AR_Common_Entity";
import LBL_AR_Common_ErrorTitle from "@salesforce/label/c.AR_Common_ErrorTitle";
import LBL_AR_Common_LastModified from "@salesforce/label/c.AR_Common_LastModified";
import LBL_AR_Common_LastModifiedByOn from "@salesforce/label/c.AR_Common_LastModifiedByOn";
import LBL_AR_Common_Loading from "@salesforce/label/c.AR_Common_Loading";
import LBL_AR_Common_Remove from "@salesforce/label/c.AR_Common_Remove";
import LBL_AR_Common_Save from "@salesforce/label/c.AR_Common_Save";
import LBL_AR_Common_SuccessTitle from "@salesforce/label/c.AR_Common_SuccessTitle";
import LBL_AR_Common_WorkingDaysPerYear from "@salesforce/label/c.AR_Common_WorkingDaysPerYear";
import LBL_AR_PMS_RecapFeeOfiiTax from "@salesforce/label/c.AR_PMS_RecapFeeOfiiTax";

const I18N = {
  AR_AGS_AddException: LBL_AR_AGS_AddException,
  AR_AGS_DaysPerYear: LBL_AR_AGS_DaysPerYear,
  AR_AGS_DraftPurgeSection: LBL_AR_AGS_DraftPurgeSection,
  AR_AGS_EngineDefaultsNotice: LBL_AR_AGS_EngineDefaultsNotice,
  AR_AGS_EscalationHours: LBL_AR_AGS_EscalationHours,
  AR_AGS_ExceptionCountMany: LBL_AR_AGS_ExceptionCountMany,
  AR_AGS_ExceptionCountOne: LBL_AR_AGS_ExceptionCountOne,
  AR_AGS_ExceptionHeading: LBL_AR_AGS_ExceptionHeading,
  AR_AGS_ExceptionRemoved: LBL_AR_AGS_ExceptionRemoved,
  AR_AGS_ExceptionSaved: LBL_AR_AGS_ExceptionSaved,
  AR_AGS_FloorPercentDefault: LBL_AR_AGS_FloorPercentDefault,
  AR_AGS_FreqDaily: LBL_AR_AGS_FreqDaily,
  AR_AGS_FreqDisabled: LBL_AR_AGS_FreqDisabled,
  AR_AGS_FreqImmediate: LBL_AR_AGS_FreqImmediate,
  AR_AGS_FreqWeekly: LBL_AR_AGS_FreqWeekly,
  AR_AGS_Frequency: LBL_AR_AGS_Frequency,
  AR_AGS_HierarchyNotificationFrequency:
    LBL_AR_AGS_HierarchyNotificationFrequency,
  AR_AGS_HierarchyNotificationSection: LBL_AR_AGS_HierarchyNotificationSection,
  AR_AGS_IdealPercentDefault: LBL_AR_AGS_IdealPercentDefault,
  AR_AGS_InAppNotificationsEnabled: LBL_AR_AGS_InAppNotificationsEnabled,
  AR_AGS_LifetimeDays: LBL_AR_AGS_LifetimeDays,
  AR_AGS_MarkupMax: LBL_AR_AGS_MarkupMax,
  AR_AGS_MarkupPercent: LBL_AR_AGS_MarkupPercent,
  AR_AGS_MaxPerRun: LBL_AR_AGS_MaxPerRun,
  AR_AGS_MaxRecipientsPerEscalation: LBL_AR_AGS_MaxRecipientsPerEscalation,
  AR_AGS_NoException: LBL_AR_AGS_NoException,
  AR_AGS_NoExceptionYet: LBL_AR_AGS_NoExceptionYet,
  AR_AGS_NotificationsSection: LBL_AR_AGS_NotificationsSection,
  AR_AGS_OfiiTaxRate: LBL_AR_AGS_OfiiTaxRate,
  AR_AGS_OfiiTaxRateHelp: LBL_AR_AGS_OfiiTaxRateHelp,
  AR_AGS_OfiiTaxCap: LBL_AR_AGS_OfiiTaxCap,
  AR_AGS_DashboardMc2Bands: LBL_AR_AGS_DashboardMc2Bands,
  AR_AGS_DashboardMc2BandsHelp: LBL_AR_AGS_DashboardMc2BandsHelp,
  AR_AGS_DashboardMc2BandsEmpty: LBL_AR_AGS_DashboardMc2BandsEmpty,
  AR_AGS_DashboardMc2BandsInvalid: LBL_AR_AGS_DashboardMc2BandsInvalid,
  AR_AGS_DerogationWaiver: LBL_AR_AGS_DerogationWaiver,
  AR_AGS_DerogationWaiverHelp: LBL_AR_AGS_DerogationWaiverHelp,
  AR_AGS_OfiiTaxCapHelp: LBL_AR_AGS_OfiiTaxCapHelp,
  AR_AGS_PurgeDays: LBL_AR_AGS_PurgeDays,
  AR_AGS_PurgeEnabled: LBL_AR_AGS_PurgeEnabled,
  AR_AGS_PurgeMaxPerRun: LBL_AR_AGS_PurgeMaxPerRun,
  AR_AGS_ReminderEnabled: LBL_AR_AGS_ReminderEnabled,
  AR_AGS_ReminderEscalationSection: LBL_AR_AGS_ReminderEscalationSection,
  AR_AGS_ReminderHours: LBL_AR_AGS_ReminderHours,
  AR_AGS_ReminderMaxPerRun: LBL_AR_AGS_ReminderMaxPerRun,
  AR_AGS_SettingsSaved: LBL_AR_AGS_SettingsSaved,
  AR_AGS_TargetPercentDefault: LBL_AR_AGS_TargetPercentDefault,
  AR_AGS_ThresholdsAndMarkup: LBL_AR_AGS_ThresholdsAndMarkup,
  AR_AGS_ValidatedInPopupSection: LBL_AR_AGS_ValidatedInPopupSection,
  AR_AGS_ValidatedLifetime: LBL_AR_AGS_ValidatedLifetime,
  AR_AGS_WarningDaysBefore: LBL_AR_AGS_WarningDaysBefore,
  AR_AGS_WorkingDaysExceptions: LBL_AR_AGS_WorkingDaysExceptions,
  AR_AGS_WorkingDaysExceptionsHelp: LBL_AR_AGS_WorkingDaysExceptionsHelp,
  AR_Common_Edit: LBL_AR_Common_Edit,
  AR_Common_Entity: LBL_AR_Common_Entity,
  AR_Common_ErrorTitle: LBL_AR_Common_ErrorTitle,
  AR_Common_LastModified: LBL_AR_Common_LastModified,
  AR_Common_LastModifiedByOn: LBL_AR_Common_LastModifiedByOn,
  AR_Common_Loading: LBL_AR_Common_Loading,
  AR_Common_Remove: LBL_AR_Common_Remove,
  AR_Common_Save: LBL_AR_Common_Save,
  AR_Common_SuccessTitle: LBL_AR_Common_SuccessTitle,
  AR_Common_WorkingDaysPerYear: LBL_AR_Common_WorkingDaysPerYear,
  AR_PMS_RecapFeeOfiiTax: LBL_AR_PMS_RecapFeeOfiiTax
};
// Correctif session 23b (contrôle navigateur du 18/08, cf. §3 du prompt de session) : la date
// arrivait en ISO brut à l'écran (2026-08-17T23:22:15.000Z) faute de tout formatage, même défaut
// de locale que la PTF corrigée en session 20c.
function formatFrenchDateTime(value) {
  if (!value) {
    return "—";
  }
  return new Date(value).toLocaleString("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

/**
 * Onglet « Paramètres généraux » (session 23) : formulaire du singleton AR_General_Setting__c
 * (remplace AR_Settings__mdt) + sous-liste des exceptions jours travaillés. Écriture DML
 * synchrone classique — décision de migration __mdt → objet custom, cf. docs/23-administration.md.
 */
export default class ArAdminGeneralSettings extends LightningElement {
  i18n = I18N;

  isLoading = true;
  isSaving = false;
  errorMessage;
  settings = {};
  exceptions = [];
  entityOptions = [];

  showExceptionForm = false;
  isEditingException = false;
  exceptionEntity;
  exceptionWorkingDays;

  connectedCallback() {
    this.loadAll();
  }

  async loadAll() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      const [settings, exceptions, entityOptions] = await Promise.all([
        getGeneralSettings(),
        getWorkingDaysExceptions(),
        getEntityOptions()
      ]);
      this.settings = settings || {};
      this.exceptions = exceptions.map((e) => ({
        ...e,
        formattedLastModifiedDate: formatFrenchDateTime(e.lastModifiedDate)
      }));
      this.entityOptions = entityOptions.map((o) => ({
        label: o.label,
        value: o.value
      }));
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get hasSettings() {
    return !this.isLoading && !this.errorMessage;
  }

  /**
   * Valeur affichée pour un paramètre (session 35) : celle enregistrée si elle existe, sinon la
   * constante que le moteur applique réellement (AR_GeneralSettingDefaults, servie par le serveur —
   * jamais une liste en dur ici, elle divergerait). Sans ça, la production affichait des champs
   * vides pendant que le moteur appliquait le corridor 20/25/30 : « on ne peut pas modifier ce
   * qu'on ne voit pas ».
   */
  effectiveValue(property) {
    const stored = this.settings[property];
    if (stored !== undefined && stored !== null && stored !== "") {
      return stored;
    }
    const defaults = this.settings.engineDefaults;
    return defaults ? defaults[property] : undefined;
  }

  isFromEngineDefault(property) {
    const stored = this.settings[property];
    return stored === undefined || stored === null || stored === "";
  }

  get floorPercentDefault() {
    return this.effectiveValue("floorPercentDefault");
  }
  get targetPercentDefault() {
    return this.effectiveValue("targetPercentDefault");
  }
  get idealPercentDefault() {
    return this.effectiveValue("idealPercentDefault");
  }
  get workingDaysPerYear() {
    return this.effectiveValue("workingDaysPerYear");
  }
  get markupPercent() {
    return this.effectiveValue("markupPercent");
  }
  get markupMax() {
    return this.effectiveValue("markupMax");
  }
  get draftPurgeEnabled() {
    return !!this.effectiveValue("draftPurgeEnabled");
  }
  get draftPurgeDays() {
    return this.effectiveValue("draftPurgeDays");
  }
  get draftPurgeWarningDays() {
    return this.effectiveValue("draftPurgeWarningDays");
  }
  get draftPurgeMaxPerRun() {
    return this.effectiveValue("draftPurgeMaxPerRun");
  }
  get validatedMatrixLifetimeDays() {
    return this.effectiveValue("validatedMatrixLifetimeDays");
  }
  // Pas de défaut moteur : vide = la matrice ne propose que N/A (valeur enregistrée, jamais effectiveValue).
  get ofiiTaxRate() {
    return this.settings.ofiiTaxRate;
  }

  get ofiiTaxCap() {
    return this.settings.ofiiTaxCap;
  }

  // Session 237 : vide = règle désactivée ; jamais de valeur de repli (pas de effectiveValue).
  get dashboardMc2Bands() {
    return this.settings.dashboardMc2Bands;
  }
  get derogationWaiverAmount() {
    return this.settings.derogationWaiverAmount;
  }
  get derogationReminderEnabled() {
    return !!this.effectiveValue("derogationReminderEnabled");
  }
  get derogationReminderHours() {
    return this.effectiveValue("derogationReminderHours");
  }
  get derogationEscalationHours() {
    return this.effectiveValue("derogationEscalationHours");
  }
  get derogationReminderMaxPerRun() {
    return this.effectiveValue("derogationReminderMaxPerRun");
  }
  get derogationEscalationMaxRecipients() {
    return this.effectiveValue("derogationEscalationMaxRecipients");
  }
  get hierarchyNotificationFrequency() {
    return this.effectiveValue("hierarchyNotificationFrequency");
  }
  get inAppNotificationEnabled() {
    return !!this.effectiveValue("inAppNotificationEnabled");
  }

  /**
   * Liste des paramètres actuellement servis par la constante du moteur plutôt que par une valeur
   * enregistrée — affichée nommément sous le formulaire. Une mention générique (« certaines valeurs
   * sont des défauts ») ne dirait pas LESQUELLES : c'est le point du bloc.
   */
  get engineDefaultLabels() {
    const labels = {
      floorPercentDefault: I18N.AR_AGS_FloorPercentDefault,
      targetPercentDefault: I18N.AR_AGS_TargetPercentDefault,
      idealPercentDefault: I18N.AR_AGS_IdealPercentDefault,
      workingDaysPerYear: I18N.AR_Common_WorkingDaysPerYear,
      markupPercent: I18N.AR_AGS_MarkupPercent,
      markupMax: I18N.AR_AGS_MarkupMax,
      draftPurgeDays: I18N.AR_AGS_PurgeDays,
      draftPurgeWarningDays: I18N.AR_AGS_WarningDaysBefore,
      draftPurgeMaxPerRun: I18N.AR_AGS_PurgeMaxPerRun,
      validatedMatrixLifetimeDays: I18N.AR_AGS_ValidatedLifetime,
      derogationReminderHours: I18N.AR_AGS_ReminderHours,
      derogationEscalationHours: I18N.AR_AGS_EscalationHours,
      derogationReminderMaxPerRun: I18N.AR_AGS_ReminderMaxPerRun,
      derogationEscalationMaxRecipients: I18N.AR_AGS_MaxRecipientsPerEscalation,
      hierarchyNotificationFrequency: I18N.AR_AGS_HierarchyNotificationFrequency
    };
    return Object.keys(labels)
      .filter((k) => this.isFromEngineDefault(k))
      .map((k) => `${labels[k]} (${this.effectiveValue(k)})`);
  }

  get hasEngineDefaults() {
    return this.engineDefaultLabels.length > 0;
  }

  get engineDefaultsNotice() {
    return formatLabel(
      I18N.AR_AGS_EngineDefaultsNotice,
      this.engineDefaultLabels.join(" · ")
    );
  }

  get lastModifiedLabel() {
    return formatLabel(
      I18N.AR_Common_LastModifiedByOn,
      this.settings.lastModifiedByName,
      this.formattedSettingsLastModifiedDate
    );
  }

  get formattedSettingsLastModifiedDate() {
    return formatFrenchDateTime(this.settings.lastModifiedDate);
  }

  get exceptionCountLabel() {
    const n = this.exceptions.length;
    return n === 0
      ? I18N.AR_AGS_NoException
      : pluralLabel(
          n,
          I18N.AR_AGS_ExceptionCountOne,
          I18N.AR_AGS_ExceptionCountMany
        );
  }

  get isExceptionsEmpty() {
    return !this.isLoading && this.exceptions.length === 0;
  }

  handleFloorChange(event) {
    this.settings = {
      ...this.settings,
      floorPercentDefault: event.target.value
    };
  }
  handleTargetChange(event) {
    this.settings = {
      ...this.settings,
      targetPercentDefault: event.target.value
    };
  }
  handleIdealChange(event) {
    this.settings = {
      ...this.settings,
      idealPercentDefault: event.target.value
    };
  }
  handleWorkingDaysChange(event) {
    this.settings = {
      ...this.settings,
      workingDaysPerYear: event.target.value
    };
  }
  handleMarkupPercentChange(event) {
    this.settings = { ...this.settings, markupPercent: event.target.value };
  }
  handleMarkupMaxChange(event) {
    this.settings = { ...this.settings, markupMax: event.target.value };
  }
  // handleCdiCoefficientChange/handleCddCoefficientChange retirés (session 28, incident
  // post-livraison) : écran correspondant retiré, cf. arAdminGeneralSettings.html.
  handleDraftPurgeEnabledChange(event) {
    this.settings = {
      ...this.settings,
      draftPurgeEnabled: event.target.checked
    };
  }
  handleDraftPurgeDaysChange(event) {
    this.settings = { ...this.settings, draftPurgeDays: event.target.value };
  }
  handleDraftPurgeWarningDaysChange(event) {
    this.settings = {
      ...this.settings,
      draftPurgeWarningDays: event.target.value
    };
  }
  handleDraftPurgeMaxPerRunChange(event) {
    this.settings = {
      ...this.settings,
      draftPurgeMaxPerRun: event.target.value
    };
  }

  handleValidatedMatrixLifetimeDaysChange(event) {
    this.settings = {
      ...this.settings,
      validatedMatrixLifetimeDays: event.target.value
    };
  }

  handleOfiiTaxRateChange(event) {
    const raw = event.target.value;
    this.settings = {
      ...this.settings,
      ofiiTaxRate: raw === "" || raw === null ? null : Number(raw)
    };
  }

  handleDashboardMc2BandsChange(event) {
    this.settings = {
      ...this.settings,
      dashboardMc2Bands: event.target.value
    };
    this.reportBandsValidity(event.target);
  }

  // Même règle que AR_AdminSettingsService.normalizeDashboardBands (le serveur fait foi) :
  // vide = défaut ; sinon 1 à 6 nombres de 0 à 100, strictement croissants, virgule ou point.
  get dashboardMc2BandsValid() {
    const raw = this.settings.dashboardMc2Bands;
    if (raw === null || raw === undefined || String(raw).trim() === "") {
      return true;
    }
    const tokens = String(raw).split(";");
    if (tokens.length > 6) {
      return false;
    }
    let previous = null;
    for (const token of tokens) {
      const text = token.trim().replace(",", ".");
      if (!/^\d+(\.\d+)?$/.test(text)) {
        return false;
      }
      const bound = Number(text);
      if (bound > 100 || (previous !== null && bound <= previous)) {
        return false;
      }
      previous = bound;
    }
    return true;
  }

  reportBandsValidity(input) {
    const field =
      input || this.template.querySelector(".dashboard-bands-input");
    if (field) {
      field.setCustomValidity(
        this.dashboardMc2BandsValid ? "" : I18N.AR_AGS_DashboardMc2BandsInvalid
      );
      field.reportValidity();
    }
  }

  handleDerogationWaiverAmountChange(event) {
    const raw = event.target.value;
    this.settings = {
      ...this.settings,
      derogationWaiverAmount: raw === "" || raw === null ? null : Number(raw)
    };
  }

  handleOfiiTaxCapChange(event) {
    const raw = event.target.value;
    this.settings = {
      ...this.settings,
      ofiiTaxCap: raw === "" || raw === null ? null : Number(raw)
    };
  }

  // Relances/escalades de dérogation + notification hiérarchie (session 29).
  handleDerogationReminderEnabledChange(event) {
    this.settings = {
      ...this.settings,
      derogationReminderEnabled: event.target.checked
    };
  }
  handleDerogationReminderHoursChange(event) {
    this.settings = {
      ...this.settings,
      derogationReminderHours: event.target.value
    };
  }
  handleDerogationEscalationHoursChange(event) {
    this.settings = {
      ...this.settings,
      derogationEscalationHours: event.target.value
    };
  }
  handleDerogationReminderMaxPerRunChange(event) {
    this.settings = {
      ...this.settings,
      derogationReminderMaxPerRun: event.target.value
    };
  }
  // Plafond de destinataires par escalade (session 29c) — borne le cercle élargi à l'entité.
  handleDerogationEscalationMaxRecipientsChange(event) {
    this.settings = {
      ...this.settings,
      derogationEscalationMaxRecipients: event.target.value
    };
  }
  handleHierarchyNotificationFrequencyChange(event) {
    this.settings = {
      ...this.settings,
      hierarchyNotificationFrequency: event.detail.value
    };
  }

  // Notifications in-app (session 34) : n'affecte jamais l'envoi des e-mails, canal indépendant.
  handleInAppNotificationEnabledChange(event) {
    this.settings = {
      ...this.settings,
      inAppNotificationEnabled: event.target.checked
    };
  }

  get hierarchyNotificationFrequencyOptions() {
    return [
      { label: I18N.AR_AGS_FreqDisabled, value: "Désactivé" },
      { label: I18N.AR_AGS_FreqImmediate, value: "Immédiat" },
      { label: I18N.AR_AGS_FreqDaily, value: "Quotidien" },
      { label: I18N.AR_AGS_FreqWeekly, value: "Hebdomadaire" }
    ];
  }

  get filterEntityOptionsForException() {
    if (this.isEditingException) {
      // En édition, afficher toutes les entités (y compris la sélection actuelle)
      return this.entityOptions;
    }
    // À l'ajout, ne proposer que les entités sans exception existante
    const exceptionEntityIds = this.exceptions.map((e) => e.id);
    return this.entityOptions.filter(
      (o) => !exceptionEntityIds.includes(o.value)
    );
  }

  async handleSaveSettings() {
    if (!this.dashboardMc2BandsValid) {
      this.reportBandsValidity();
      this.showToast(
        I18N.AR_Common_ErrorTitle,
        I18N.AR_AGS_DashboardMc2BandsInvalid,
        "error"
      );
      return;
    }
    this.isSaving = true;
    try {
      // On envoie les valeurs EFFECTIVES (défaut moteur compris), pas l'état brut : ce que
      // l'administrateur voit à l'écran est exactement ce qui part en base. Le serveur applique la
      // même garde de nullité (AR_AdminSettingsService.saveGeneralSettings) — c'est lui qui fait
      // foi, ceci évite seulement un aller-retour où l'écran afficherait 20 et enregistrerait vide.
      const payload = { ...this.settings };
      Object.keys(this.settings.engineDefaults || {}).forEach((key) => {
        payload[key] = this.effectiveValue(key);
      });
      const saved = await saveGeneralSettingsApex({
        dtoJson: JSON.stringify(payload)
      });
      this.settings = saved;
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_AGS_SettingsSaved,
        "success"
      );
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

  handleAddException() {
    this.isEditingException = false;
    this.exceptionEntity = undefined;
    this.exceptionWorkingDays = undefined;
    this.showExceptionForm = true;
  }

  handleEditException(event) {
    const entityId = event.currentTarget.dataset.entityId;
    const workingDays = event.currentTarget.dataset.workingDays;
    this.isEditingException = true;
    this.exceptionEntity = entityId;
    this.exceptionWorkingDays = workingDays;
    this.showExceptionForm = true;
  }

  handleExceptionEntityChange(event) {
    this.exceptionEntity = event.target.value;
  }
  handleExceptionWorkingDaysChange(event) {
    this.exceptionWorkingDays = event.target.value;
  }

  handleCancelException() {
    this.showExceptionForm = false;
    this.isEditingException = false;
  }

  async handleSaveException() {
    this.isSaving = true;
    try {
      await saveWorkingDaysException({
        entityId: this.exceptionEntity,
        workingDays: this.exceptionWorkingDays
      });
      this.showExceptionForm = false;
      this.isEditingException = false;
      this.exceptions = (await getWorkingDaysExceptions()).map((e) => ({
        ...e,
        formattedLastModifiedDate: formatFrenchDateTime(e.lastModifiedDate)
      }));
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_AGS_ExceptionSaved,
        "success"
      );
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

  async handleDeleteException(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.exceptions.find((r) => r.id === id);
    // Rien n'est appelé côté serveur sans confirmation.
    if (!row || !(await confirmAdminDelete(row.entityName))) {
      return;
    }
    try {
      await deleteWorkingDaysException({ entityId: id });
      this.exceptions = (await getWorkingDaysExceptions()).map((e) => ({
        ...e,
        formattedLastModifiedDate: formatFrenchDateTime(e.lastModifiedDate)
      }));
      this.showToast(
        I18N.AR_Common_SuccessTitle,
        I18N.AR_AGS_ExceptionRemoved,
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