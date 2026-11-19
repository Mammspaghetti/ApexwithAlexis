({
    
	showServerError : function(cmp, serverErrors, title, duration, forceCustomToast){

        var errors = [];
        for(var i = 0; i < serverErrors.length; i++){
            
            if(serverErrors[i].message){
                errors.push(serverErrors[i].message);
            }
            
            if(serverErrors[i].duplicateResults){
                for(var j = 0; j < serverErrors[i].duplicateResults.length; j++){
                    errors.push(serverErrors[i].duplicateResults[j].message);
                }
            }
            
            if(serverErrors[i].fieldErrors){
                for(var fieldName in serverErrors[i].fieldErrors){
                    for(var j = 0; j < serverErrors[i].fieldErrors[fieldName].length; j++)   
                        errors.push(fieldName + ' : ' + serverErrors[i].fieldErrors[fieldName][j].message);
                }
            }
            
            if(serverErrors[i].pageErrors){
                for(var j = 0; j < serverErrors[i].pageErrors.length; j++){
                    errors.push(serverErrors[i].pageErrors[j].message);
                }
            }
            
        }
        
        
        if(errors.length > 3 )
            this.showToast(cmp, 'error', errors.join(', '), title, duration, forceCustomToast);
        else{
            for(var i = 0; i < errors.length; i++)
                this.showToast(cmp, 'error', errors[i], title, duration, forceCustomToast);
        }
        
        return errors;
    },
    
    
    showToast : function(cmp, type, message, title, duration, forceCustomToast){
        
        var showToastEvent = $A.get('e.force:showToast');
        var toastParams = {
            title : title,
            type : type,
            message : message,
            duration : duration
        };
        
        var isOneDotApp = (location.href.indexOf('.com/one/one.app') != -1 || location.href.indexOf('.com/lightning') != -1);
        
        //Si on est dans one.app, on utilise l'event natif
        if(!forceCustomToast && showToastEvent && isOneDotApp){
            showToastEvent.setParams(toastParams).fire();
        }
        //Sinon on gere l'affichage des toasts manuellement
        else{
            toastParams.id = (Date.now() + Math.random());
            
            var toasts = cmp.get('v._toasts');
            toasts.push(toastParams);
            cmp.set('v._toasts', toasts);

            //Retire le toast au bout de "duration" millisecondes
            window.setTimeout($A.getCallback(function(){
                var toasts = cmp.get('v._toasts');
                var newToasts = [];
                for(var i = 0, l = toasts.length; i < l; i++){
                    if(toasts[i].id != toastParams.id)
                        newToasts.push(toasts[i]);
                }
                cmp.set('v._toasts', newToasts);
            }), duration);

        }
            
    }
})