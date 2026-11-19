({
    doInitHelper: function (cmp) {
        let callBack = function (response) {
            if (cmp.isValid() && response.getState() === 'SUCCESS') {
                var config = response.getReturnValue();
                cmp.set('v._availableMobilities', config.availableMobilities);
                cmp.set('v._selectedMobilities', config.selectedMobilities);
            } else {
                console.error(response.getError());
            }
            cmp.set('v._loading', false);
        };
        var action = this.constructAction(
            cmp,
            'c.getMobilitiesConfig',
            {
                'recordId': cmp.get('v.recordId'),
                'fieldValueToBeStored': cmp.get('v.fieldValueToBeStored')
            },
            callBack
        );

        $A.enqueueAction(action);
    },

    saveSelectedMobilitiesHelper: function (cmp) {

        cmp.set('v._loading', true);

        var callBack = function (response) {
            if (cmp.isValid() && response.getState() === 'SUCCESS') {
                cmp.set('v._isUpdated', false);
                $A.get('e.force:showToast').setParams({
                    type: 'success',
                    message: 'Mobilités enregistrées'
                }).fire();
                window.location.reload();
            } else {
                $A.get('e.c:EVT_ShowToast').setParams({ serverError: response.getError() }).fire();
            }

            cmp.set('v._loading', false);
        };

        var action = this.constructAction(
            cmp,
            'c.saveMobilities',
            {
                'recordId': cmp.get('v.recordId'),
                'mobilities': cmp.get('v._selectedMobilities'),
                'fieldValueToBeStored': cmp.get('v.fieldValueToBeStored')
            },
            callBack
        );

        $A.enqueueAction(action);
    },

    constructAction: function (cmp, methodName, paramsBody, callBack) {
        var action = cmp.get(methodName);
        action.setParams(paramsBody);
        action.setCallback(this, callBack);
        return action;
    }
})