global class Opp2create_reprice_finalize_Sync_batch implements Database.Batchable<sObject> {
  
    /*
      Created By: Praveen Makam
      Date: 05/10/2017
      Project: Batch class to reprice, finalize & sync quotelineitems to Opportunity.
    */
    
	String query;
	Map<String,String> QuoteIdtoCartIdmap = new Map<String,String>();
	public static string strEmailDist = '';
	Map<String,String> pendingStageQuoteCartMap = new Map<String,String>();
	Map<String,String> finalizeCartResultMap = new Map<String,String>();
	Map<String,string> quoteIdOppIdMap = new Map<String,String>();
	Set<String> quoteIdSet = new Set<String>();
	String QuoteName;
	Public static Boolean isRepriceNeeded;
	Public static Map<String,String> CartsToFinalizeMap = new Map<String,String>();
  	//Public static Map<String,String> inputquotecartMap = new Map<String,String>();

	global Opp2create_reprice_finalize_Sync_batch(){}

  	global Opp2create_reprice_finalize_Sync_batch(Set<String>quoteIdreceivedSet) {
   		System.debug('****InsideCreate Reprice finalize and sync batch! No. of quotes:: ' + quoteIdreceivedSet.size());
    	for(String QuoteId : quoteIdreceivedSet){
      		quoteIdSet.add(QuoteId);
    	}
  	}//End start method
  
	global Database.QueryLocator start(Database.BatchableContext BC) {
	    BatchLogUtility.batchLoginsert('n', 'Processing', UserInfo.getUserId());
	    Set<String> inputQuoteId = new Set<String>();
	    System.debug('****quoteIdSet: ' + quoteIdSet);

	    query = 'SELECT Id, Name, Apttus_Proposal__Opportunity__c ' 
	                  + 'FROM Apttus_Proposal__Proposal__c ' 
	                  + 'WHERE Name in :quoteIdSet';

	    System.debug('****query' + query);
	    return Database.getQueryLocator(query);
	}//End start method

   	global void execute(Database.BatchableContext BC, List<sObject> scope) {   
   		System.debug('****No.of Quotes received to finalize: ' + scope.size() + ':; QuoteID: ' + scope);		
   		
   		for(Apttus_Proposal__Proposal__c  proprecord: (List<Apttus_Proposal__Proposal__c >)scope){
   			QuoteName = proprecord.Name;
   		}//end for
   		System.debug('****QuoteName: ' + QuoteName);
		try{
			Integer quoteSize = scope!= NULL ? scope.size() : 0;
			if(quoteSize > 0){
				for(Apttus_Config2__ProductConfiguration__c cartRecord : [select Id,Apttus_QPConfig__Proposald__r.Name,Apttus_Config2__Status__c,Apttus_QPConfig__Proposald__r.Apttus_Proposal__Opportunity__c,
																		  Apttus_Config2__IsPricePending__c,Apttus_QPConfig__Proposald__r.Apttus_Proposal__Opportunity__r.Id from Apttus_Config2__ProductConfiguration__c 
																		  where Apttus_QPConfig__Proposald__r.Name = :QuoteName ORDER BY CreatedDate Desc ]){
					if(cartRecord.Apttus_Config2__Status__c == 'New' && !cartRecord.Apttus_Config2__IsPricePending__c){
						CartsToFinalizeMap.put(cartRecord.Apttus_QPConfig__Proposald__r.Name, cartRecord.Id);
						isRepriceNeeded = FALSE;
						//pendingStageQuoteCartMap.put(cartRecord.Apttus_QPConfig__Proposald__r.Name,cartRecord.id);
					}else{// continous reprice cart block for bulk lineitems 						
							Integer repriceRunCount = 0;
							do{
								repriceRunCount++;
								Boolean isRepriceComplete	= Opportunity2Create_Utility.repriceCartRecord(cartRecord.Id);
								Boolean isRepriceNeeded 	= Opportunity2Create_Utility.getCartRecordRepriceStatus(cartRecord.Id);
								if(isRepriceNeeded){
									isRepriceNeeded = TRUE;
								}//end if
							}while(isRepriceNeeded);
							System.debug('****No.of times cart record repriced: ' + repriceRunCount);
							if(!isRepriceNeeded){ //if cart is repriced successfully
								CartsToFinalizeMap.put(cartRecord.Apttus_QPConfig__Proposald__r.Name, cartRecord.Id);
							}//end if	
					}//end cart status check
					quoteIdOppIdMap.put(cartRecord.Apttus_QPConfig__Proposald__r.name,cartRecord.Apttus_QPConfig__Proposald__r.Apttus_Proposal__Opportunity__r.Id);
					QuoteIdtoCartIdmap.put(cartRecord.Apttus_QPConfig__Proposald__r.Name, cartRecord.Id);
				}//end for
			}//end if(quoteSize > 0){

			Map<String,Boolean> finalizeResult = new Map<String,Boolean>();
	      	if(!CartsToFinalizeMap.isEmpty()){
	        	for(String quoteId : CartsToFinalizeMap.keySet()){
	          		finalizeResult = Opportunity2Create_Utility.finalizeCartRecord(quoteId, CartsToFinalizeMap.get(quoteId));  //change return type or input parameter
	        	}//end for
	        	System.debug('*****finalizeResult: '+ finalizeResult);
	      	}// End if(!pendingStageQuoteCartMap.isEmpty()){

		    //get cartstatus
		    List<Apttus_Config2__ProductConfiguration__c> cartrecordforQuote = [select Id,Apttus_QPConfig__Proposald__r.Name,Apttus_Config2__Status__c from Apttus_Config2__ProductConfiguration__c 
                                        WHERE Id = :QuoteIdtoCartIdmap.get(QuoteName)];
      		boolean quoteFinalized;       		
      		if(cartrecordforQuote != NULL){
        		quoteFinalized= cartrecordforQuote[0].Apttus_Config2__Status__c == 'Finalized'? TRUE: FALSE;
      		}//end if

      		System.debug('****quoteFinalized: ' + quoteFinalized);

			if(quoteFinalized && finalizeResult.get(QuoteName)){
				finalizeCartResultMap.put(cartrecordforQuote[0].Apttus_QPConfig__Proposald__r.Name, String.valueOf(cartrecordforQuote[0].Id));
			}
			//synOpportunityLineItems
			if(!finalizeCartResultMap.isEmpty()){
				for(String quoteId : finalizeCartResultMap.keySet()){					
					Opportunity2Create_Utility.SynchQuoteToOpportunity(quoteId,quoteIdOppIdMap.get(quoteId));
				}
			}//End if(!finalizeCartResultMap.isEmpty()){
		} catch (Exception e) {
	      	System.debug('****Exception = ' + e);
		  	String exceptionError = 'Message: '+ e.getMessage()+ 'Line No: '+ e.getLineNumber() +'Error Type: '+e.getTypeName();
	      	BatchLogUtility.batchLogupdate_New('Opp2create_reprice_finalize_Sync_batch','Failed in Execute',0,'','',0,exceptionError, strEmailDist, false);	      
	    }// end exception handling
	}//end execute method
	
	global void finish(Database.BatchableContext BC) {
		BatchLogUtility.batchLogupdate_New('Opp2create_reprice_finalize_Sync_batch','Inside reprice finish and ran successfully!',0,'','',0, null, strEmailDist, false);
	}//end finish method
	
}//end batch class