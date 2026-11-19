({
    
    
    setSelectedValues : function(cmp, nodes, selectedValues){

        var fakeMasterNode = {children : nodes};

        this.initCheckedHierarhy(fakeMasterNode, selectedValues, cmp.get('v.toggleNodesRecursively'))

        cmp.set('v._initedNodes', fakeMasterNode.children);
        
        var selectedNodes = this.getSelectedNodes(cmp, fakeMasterNode.children);
        this.setSelectedValuesNodes(cmp, selectedNodes);
        
    },
    
    
	/**
     * Récursivement:
     * Coche un parent si tous ses enfants sont cochés
     * Coche tous les enfants dont le parent est coché
     */
    initCheckedHierarhy : function(node, selectedValues, toggleNodesRecursively){

        var childrenLength = node.children.length;
        
        var allChildrenChecked = (childrenLength > 0);
        var nbCheckedChildren = 0;
        var nbCheckedChildrenRecursive = 0;
        var bypassCheckChildrenHierarchy;
        for(var i = 0; i < childrenLength; i++){

            bypassCheckChildrenHierarchy = false;

            if(selectedValues.indexOf(node.children[i].value) != -1){

                node.children[i].checked = true; 
                nbCheckedChildren ++;
                nbCheckedChildrenRecursive ++;
                
                if(toggleNodesRecursively){
                    bypassCheckChildrenHierarchy = true;
                    nbCheckedChildrenRecursive += this.checkChildren(node.children[i].children);
                }
                node.children[i].hasCheckedChildren = true;
            }
            else{
                node.children[i].checked = false;
            }

            if(!bypassCheckChildrenHierarchy){
                var nbCheckedChildrenTemp = this.initCheckedHierarhy(node.children[i], selectedValues, toggleNodesRecursively);
                nbCheckedChildrenRecursive += nbCheckedChildrenTemp[1];

                node.children[i].hasCheckedChildren = (nbCheckedChildrenTemp[1] > 0);
                //On coche le noeud courant si tous ses enfants son cochés
                if(toggleNodesRecursively)
                	node.children[i].checked = (node.children[i].length == nbCheckedChildrenTemp[0])
                   
                    
            }

        }
		
        return [nbCheckedChildren, nbCheckedChildrenRecursive];
        
    },
    
    checkChildren : function(children) {
		var childrenLength = children.length;
		var nbChecked = childrenLength;
        
        for(var i = 0; i < childrenLength; i++){
            children[i].checked = true;
            children[i].hasCheckedChildren = true;
            nbChecked += this.checkChildren(children[i].children);
        }
		
        return nbChecked;
	},
    
    
    getSelectedNodes : function(cmp, nodes){
        var selectedNodes = this.getSelectedNodesRecursive(nodes, cmp.get('v.selectOnlyLastLevel'), cmp.get('v.selectOnlyHigherLevel'));

		
        return selectedNodes;
    },
    
    getSelectedNodesRecursive : function(nodes, onlyLastLevel, onlyHigherLevel){
    	
        var nodesLength = nodes.length;
        var selectedNodes = [];
        for(var i = 0; i < nodesLength; i++){
            var checked = false;
            if(nodes[i].checked && (!onlyLastLevel || nodes[i].children.length == 0)){
                selectedNodes.push(nodes[i]);
                checked = true;
            }
            
            if(nodes[i].children.length > 0){
                var checkedChildren = this.getSelectedNodesRecursive(nodes[i].children, onlyLastLevel, onlyHigherLevel);
                
                if(!onlyHigherLevel || (!checked && onlyHigherLevel) ){    
                    selectedNodes = selectedNodes.concat(checkedChildren); 
                }
            }
        }
        
        return selectedNodes;
    },

	getSelectedValues : function(selectedNodes){
        var selectedNodesLength = selectedNodes.length;
        var selectedValues = [];
        for(var i = 0; i < selectedNodesLength; i++){
            selectedValues.push(selectedNodes[i].value);
        }

        return selectedValues;
    },
    
    
    setSelectedValuesNodes : function(cmp, selectedNodes){
        cmp.set('v._prevSelectedNodes', selectedNodes);
        cmp.set('v.selectedNodes', selectedNodes);

        var selectedValues = this.getSelectedValues(selectedNodes);

        cmp.set('v._prevSelectedValues', selectedValues);
        cmp.set('v.selectedValues', selectedValues);
        
    }
})