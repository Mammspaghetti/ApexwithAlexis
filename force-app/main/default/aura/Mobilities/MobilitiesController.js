({
    doInit: function (cmp, event, helper) {
        helper.doInitHelper(cmp);
    },


    handleMobilitiesUpdated: function (cmp, event, helper) {
        cmp.set('v._isUpdated', true);
    },


    saveSelectedMobilities: function (cmp, event, helper) {
        helper.saveSelectedMobilitiesHelper(cmp);
    }
})