({
	handleShowToast : function(cmp, event, helper) {
		
        var toastParams = event.getParams();

        var duration = toastParams.duration;
        if(!duration)
        	duration = cmp.get('v.defaultDuration');
        
        
        if(toastParams.serverError){
            helper.showServerError(cmp, toastParams.serverError, toastParams.title, duration, toastParams.forceCustomToast);
        }
        else{
            helper.showToast(cmp, toastParams.type, toastParams.message, toastParams.title, duration, toastParams.forceCustomToast);
        }
        
	}
})