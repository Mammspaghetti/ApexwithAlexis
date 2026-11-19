({

	doInit : function(cmp, event, helper) {
        
        var selectedNodes = cmp.get('v.selectedNodes');
        var selectedValues = cmp.get('v.selectedValues');

        var nodes = JSON.parse(JSON.stringify(cmp.get('v.nodes')));

        if(nodes.length == 0)
            return;

        if(selectedNodes.length && nodes.length > 0){
            selectedValues = helper.getSelectedValues(selectedNodes);
        }


        
        
        helper.setSelectedValues(cmp, nodes, selectedValues);
        
        
    },
    
    handleChangeSelectedValues : function(cmp, event, helper) {

        var selectedValues = cmp.get('v.selectedValues');

        if(JSON.stringify(cmp.get('v._prevSelectedValues')) != JSON.stringify(selectedValues)){
            helper.setSelectedValues(cmp, cmp.get('v._initedNodes'), selectedValues); 
        }
    },
    
    handleChangeSelectedNodes : function(cmp, event, helper) {
        
        var selectedNodes = cmp.get('v.selectedNodes');
        
        if(JSON.stringify(cmp.get('v._prevSelectedNodes')) != JSON.stringify(selectedNodes)){
            helper.setSelectedValues(cmp, helper.getSelectedValues(selectedNodes));
        }
    },
    
	
    
    refreshSelectedValues : function(cmp, event, helper) {

        var selectedNodes = helper.getSelectedNodes(cmp, cmp.get('v._initedNodes'));
        helper.setSelectedValuesNodes(cmp, selectedNodes);
        
    }
})