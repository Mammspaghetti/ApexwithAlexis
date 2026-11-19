import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";

/**
 * Cible de la quick action AR_Create_Price_Matrix sur cxsrec__cxsPosition__c : redirige vers
 * l'app Pricing Tool (onglet AR_Pricing_App), vue Simulateur pré-remplie avec le besoin d'origine
 * (c__positionId).
 *
 * Session 184a2 : action HEADLESS (`actionType` = Action, `invoke()`), remplace arMatrixLauncher
 * (ScreenAction). En ScreenAction, la navigation lancée dans connectedCallback entrait en course
 * avec la fermeture de la modale de l'action (CloseActionScreenEvent) : navigation annulée ou état
 * `c__positionId` perdu (constaté en navigateur : tableau de bord au 1er clic, rien au 2e). Une
 * action headless n'a pas de modale à fermer. Le type d'une action LWC ne peut pas être changé sur
 * un bundle déployé (« Cannot change the type of the existing Lightning Web Component action »)
 * d'où un nouveau composant ; arMatrixLauncher n'est plus référencé par aucune action.
 *
 * Session 184a4 : le 1er clic sur la fiche ne faisait rien (le 2e marchait). Navigation rendue
 * déterministe : URL générée par GenerateUrl puis `window.location.assign` (rechargement complet
 * de Lightning, accepté), et jamais de navigation sans recordId (pas d'atterrissage silencieux
 * ailleurs). Session 184g : console.info de diagnostic retiré avant la prod.
 */
export default class ArMatrixOpener extends NavigationMixin(LightningElement) {
  @api recordId;

  @api async invoke() {
    let positionId = this.recordId;
    if (!positionId) {
      // recordId peut ne pas être posé au 1er appel : attendre un tick puis relire.
      await Promise.resolve();
      positionId = this.recordId;
    }
    if (!positionId) {
      console.error(
        "[arMatrixOpener] recordId absent : navigation annulée (aucune matrice ouverte)"
      );
      return;
    }
    try {
      const url = await this[NavigationMixin.GenerateUrl]({
        type: "standard__navItemPage",
        attributes: {
          apiName: "AR_Pricing_App"
        },
        state: {
          c__positionId: positionId
        }
      });
      window.location.assign(url);
    } catch (error) {
      console.error("[arMatrixOpener] génération de l'URL impossible", error);
    }
  }
}