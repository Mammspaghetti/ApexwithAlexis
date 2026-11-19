import LBL_AR_Common_TechnicalErrorNoDetail from "@salesforce/label/c.AR_Common_TechnicalErrorNoDetail";

const I18N = {
  AR_Common_TechnicalErrorNoDetail: LBL_AR_Common_TechnicalErrorNoDetail
};
/**
 * Error reduction utility: converts various error formats into readable messages.
 *
 * Session 104: Replace all "Erreur inconnue" fallbacks with proper error messages.
 * Handles Apex exceptions, field errors, validation errors, and generic server errors.
 */

export function reduceErrors(errors) {
  if (!errors) {
    return I18N.AR_Common_TechnicalErrorNoDetail;
  }

  if (Array.isArray(errors)) {
    const results = errors
      .map((e) => reduceError(e))
      .filter((err) => err && err.length > 0)
      .join("\n");
    if (!results || results.length === 0) {
      return I18N.AR_Common_TechnicalErrorNoDetail;
    }
    return results;
  }

  const result = reduceError(errors);
  if (!result || result.length === 0) {
    return I18N.AR_Common_TechnicalErrorNoDetail;
  }
  return result;
}

function reduceError(error) {
  if (!error) {
    return "";
  }

  // Handle error.body as array (form from 23/09: [{fieldErrors, pageErrors}])
  if (Array.isArray(error.body)) {
    const arrayResults = error.body
      .map((bodyElement) => processErrorBody(bodyElement))
      .filter((err) => err && err.length > 0);
    if (arrayResults.length > 0) {
      return arrayResults.join("\n");
    }
    return "";
  }

  // If we have error.body, process it
  if (error.body) {
    const bodyMessage = processErrorBody(error.body);
    if (bodyMessage && bodyMessage.length > 0) {
      return bodyMessage;
    }
  }

  // Direct error message
  if (error.message && error.message.length > 0) {
    return error.message;
  }

  return "";
}

function processErrorBody(body) {
  if (!body) {
    return "";
  }

  // AuraHandledException from server (our error wrapper)
  if (body.exceptionType === "AuraHandledException" && body.message) {
    return body.message;
  }

  // Generic server error message
  if (body.message) {
    return body.message;
  }

  // Page-level errors (form validation, etc.)
  if (body.pageErrors && Array.isArray(body.pageErrors)) {
    const pageErrors = body.pageErrors
      .map((e) => e.message)
      .filter((m) => m && m.length > 0);
    if (pageErrors.length > 0) {
      return pageErrors.join("\n");
    }
  }

  // Field-level errors (most common for DML)
  if (body.fieldErrors && typeof body.fieldErrors === "object") {
    const fieldErrors = [];
    Object.keys(body.fieldErrors).forEach((fieldName) => {
      const errors = body.fieldErrors[fieldName];
      if (Array.isArray(errors)) {
        errors.forEach((e) => {
          if (e.message) {
            fieldErrors.push(e.message);
          }
        });
      }
    });
    if (fieldErrors.length > 0) {
      return fieldErrors.join("\n");
    }
  }

  // Other output.errors format
  if (body.output?.errors && Array.isArray(body.output.errors)) {
    const outputErrors = body.output.errors
      .map((e) => e.message)
      .filter((m) => m && m.length > 0);
    if (outputErrors.length > 0) {
      return outputErrors.join("\n");
    }
  }

  return "";
}