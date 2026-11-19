/**
 * Wraps exceptions from Apex into readable AuraHandledException messages for LWC.
 *
 * Session 104: DML exceptions (field integrity, access, etc.) were displayed as
 * "Erreur inconnue" instead of actionable error messages. This utility extracts
 * the real error cause and formats it for the UI.
 */
public class AR_AuraErrors {

  /**
   * Wrap any exception into an AuraHandledException with a readable message.
   * @param e Exception to wrap
   * @param action User-facing action description (e.g. "l'enregistrement", "la validation")
   * @return AuraHandledException with setMessage() applied
   */
  public static AuraHandledException wrap(Exception e, String action) {
    String message = buildErrorMessage(e, action);

    System.debug(LoggingLevel.ERROR, 'AR_AuraErrors.wrap called for action: ' + action);
    System.debug(LoggingLevel.ERROR, 'Exception type: ' + e.getTypeName());
    System.debug(LoggingLevel.ERROR, 'Exception message: ' + e.getMessage());
    System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

    AuraHandledException ahe = new AuraHandledException(message);
    ahe.setMessage(message);

    return ahe;
  }

  private static String buildErrorMessage(Exception e, String action) {
    // If already an AuraHandledException, pass through
    if (e instanceof AuraHandledException) {
      return e.getMessage();
    }

    // DmlException: extract field-level details
    if (e instanceof DmlException) {
      DmlException de = (DmlException) e;

      if (de.getNumDml() > 0) {
        String statusCode = de.getDmlStatusCode(0);
        String baseMessage = de.getDmlMessage(0);

        // Field access/integrity errors
        if (statusCode == 'FIELD_INTEGRITY_EXCEPTION') {
          List<String> fieldNames = de.getDmlFieldNames(0);
          String fieldLabel = (fieldNames.size() > 0) ? fieldLabel(fieldNames[0]) : Label.AR_Msg_AFieldFallback;
          return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, fieldLabel + ' — ' + baseMessage }) + ' [' + statusCode + ']';
        }

        if (statusCode == 'REQUIRED_FIELD_MISSING') {
          List<String> fieldNames = de.getDmlFieldNames(0);
          String fieldLabel = (fieldNames.size() > 0) ? fieldLabel(fieldNames[0]) : Label.AR_Msg_RequiredFieldFallback;
          return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, AR_I18n.format(Label.AR_Msg_FieldRequired, new List<Object>{ fieldLabel }) }) + ' [' + statusCode + ']';
        }

        if (statusCode == 'INVALID_FIELD_VALUE') {
          List<String> fieldNames = de.getDmlFieldNames(0);
          String fieldLabel = (fieldNames.size() > 0) ? fieldLabel(fieldNames[0]) : Label.AR_Msg_AFieldFallback;
          return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, AR_I18n.format(Label.AR_Msg_InvalidValueFor, new List<Object>{ fieldLabel }) }) + ' [' + statusCode + ']';
        }

        // Generic DML message with status code
        return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, baseMessage }) + ' [' + statusCode + ']';
      }

      // Fallback if no DML details
      return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, Label.AR_Msg_SaveError }) + ' [' + de.getMessage() + ']';
    }

    // Generic exception: type + message
    if (String.isNotBlank(e.getMessage())) {
      return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, e.getMessage() }) + ' [' + e.getTypeName() + ']';
    }

    // Last resort: type only
    return AR_I18n.format(Label.AR_Msg_ActionFailed, new List<Object>{ action, AR_I18n.format(Label.AR_Msg_TypeError, new List<Object>{ e.getTypeName() }) });
  }

  // Simple field name to label mapper (extend as needed)
  private static String fieldLabel(String fieldName) {
    final Map<String, String> FIELD_LABELS = new Map<String, String>{
      'AR_Manager_Contact__c' => 'Manager (Contact)',
      'AR_Manager__c' => 'Manager',
      'AR_Position__c' => 'Besoin',
      'AR_Proposed_TJM__c' => 'TJM idéal',
      'AR_TJM_Periods__c' => 'Périodes de TJM',
      'AR_TJM_Weighted__c' => 'TJM moyen pondéré',
      'AR_Salary_Periods__c' => 'Périodes de salaire',
      'AR_RPLSR_Enabled__c' => 'Régie par lot sans régule',
      'AR_RPLSR_Days_Per_Month__c' => 'Jours facturés par mois (régie par lot)',
      'AR_RPLSR_Plan__c' => 'Plan prévisionnel (régie par lot)',
      'AR_RFA_Percent__c' => 'RFA %',
      'AR_Selected_Validator__c' => 'Valideur sélectionné'
    };

    return FIELD_LABELS.get(fieldName) != null ? FIELD_LABELS.get(fieldName) : fieldName;
  }
}