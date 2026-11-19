({
    doInit : function(cmp, event, helper) {
        
        var startExpended = cmp.get('v.startExpended').toLowerCase();

        if(startExpended == 'true')
           cmp.set('v._collapse', false);
        else if(startExpended == 'false')
            cmp.set('v._collapse', true);
        else{
            var level = cmp.get('v.level');
            
            cmp.set('v._collapse', level > 0 || !cmp.get('v.node.hasCheckedChildren'));
        }
    },
    
    
    /**
     * Coche le parent si tous ses enfants son cochés
     * Décoche le parent si tous ses enfants ne sont pas cochés
     */
    handleChildCheckboxChanged : function(cmp, event, helper) {
        helper.checkParentDependingOfChildren(cmp, event.getSource().get('v.node'));
    },
    
    
    toggleChildrenVisibility : function(cmp, event, helper) {
        cmp.set('v._collapse', !cmp.get('v._collapse'));
    },
    
    
    checkNode : function(cmp, event, helper) {

		var node = cmp.get('v.node');
        
        if(cmp.get('v.toggleNodesRecursively') === true){
            

            helper.checkAllChildrenHierachy(cmp, node, node.checked);
            
        }

        cmp.getEvent('childCheckboxChanged').fire();

        cmp.getEvent('refreshSelectedValues').fire();
        
    }
    
})