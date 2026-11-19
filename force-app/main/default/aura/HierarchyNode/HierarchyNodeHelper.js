({
    
    checkAllChildrenHierachy : function(cmp, node, checked){

        var children = cmp.get('v.node.children');
        
        this.checkChildren(node.children, checked);
        
        node.hasCheckedChildren = checked;
        cmp.set('v.node', node);
    },
    
    
	checkChildren : function(children, checked) {
		var childrenLength = children.length;

        for(var i = 0; i < childrenLength; i++){
            children[i].checked = checked; 
            children[i].hasCheckedChildren = checked;
            this.checkChildren(children[i].children, checked);
        }

	},
    
    
    /**
     * Coche le parent si tous ses enfants son cochés
     * Décoche le parent si tous ses enfants ne sont pas cochés
     */
    checkParentDependingOfChildren : function(cmp, updatedNode){
        
        var node = cmp.get('v.node');
        
        //Pour ne pas catcher l'event sur son propre composant
        if(updatedNode.value != node.value){

            var nbCheckedChildren = 0;
            var hasCheckedChildren = false;
            //Boucle sur tous les enfants de ce noeud, s'ils sont tous cochés, on ira cocher ce noeud
            if(node.children && node.children.length > 0){
                for(var i = 0, l = node.children.length; i < l; i++){
                    if(node.children[i].checked){
                        nbCheckedChildren ++;
                        hasCheckedChildren = true;
                    }
                    else if(node.children[i].hasCheckedChildren)
                        hasCheckedChildren = true;
                }
            }
            
            node.hasCheckedChildren = hasCheckedChildren;

            if(cmp.get('v.toggleNodesRecursively')){
                node.checked = (nbCheckedChildren == node.children.length);
            }
            
            cmp.set('v.node', node);
            
        }
    }
})