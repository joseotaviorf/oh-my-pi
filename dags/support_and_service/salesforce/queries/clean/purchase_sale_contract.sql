SELECT    
  Id,
  OwnerId AS id_owner,
  CreatedById AS id_created_by,
  LastModifiedById AS id_last_modified_by,
  ExternalId__c AS id_external,
  OfferId__c AS id_offer,
  Name AS name,
  DiligenceClassification__c AS diligence_classification,
  DiligenceStatus__c AS diligence_status,
  PaymentMethod__c AS payment_method,
  Stage__c AS stage,
  Buyer__c AS buyer,
  ClauseIdentifiers__c AS clause_identifiers,
  SalesFlowUrl__c AS sales_flow_url,
  Seller__c AS seller,
  ZendeskUrl__c AS zendesk_url,
  AgentEmail__c AS agent_email,
  CRNStatus__c AS crn_status,
  CCVStatus__c AS ccv_status,
  HouseChattelMortgage__c AS house_chattel_mortgage,
  HouseState__c AS house_state,
  ITBIStatus__c AS itbi_status,
  SimplifiedStage__c AS simplified_stage,
  SubscriptionModelBuyer__c AS subscription_model_buyer,
  SubscriptionModelSeller__c AS subscription_model_seller,
  CRI_Protocol__c AS cri_protocol,
  CRNName__c AS crn_name,
  AlienationStatus__c AS alienation_status,
  BypassRescissionValidation__c AS bypass_rescission_validation,  
  CRI_HaveDemandNote__c AS cri_have_demand_note,
  CRNPartner__c AS crn_partner,
  CRN_Complexity__c AS crn_complexity,
  Escrivao__c AS escrivao,
  HaveUnpaidAlienation__c AS have_unpaid_alienation,
  HouseOccupant__c AS house_occupant,
  PreemptiveRight__c AS preemptive_right,
  ProofPaymentReceived__c AS proof_payment_received,
  RequestType__c AS request_type,
  RequestedBy__c AS requested_by,
  RescissionStatus__c AS rescission_status,
  FS_AVE_ProtocolCCV__c AS fs_ave_protocol_ccv,
  FS_CRINameCCV__c AS fs_cri_name_ccv,
  FS_CRIStatus__c AS fs_cri_status,
  FS_EndorsementStatusCCV__c AS fs_endorsement_status_ccv,
  FS_IDCartorioCCV__c AS fs_cartorio_ccv_id,
  FS_ReasonNonConversionCCV__c AS fs_reason_non_conversion_ccv, 
  Address__c AS address,
  AddendumStatus__c AS addendum_status,
  FS_ResponsibleAssistantCCV__c AS fs_responsible_assistant_ccv,
  LTBookkeepingDoneForm__c AS lt_bookkeeping_done_form,
  FS_ReasonsLTOverrunRegisterCCV__c AS fs_reasons_lt_overrun_register_ccv,
  FS_ReasonsLTOverrunCCV__c AS fs_reasons_lt_overrun_ccv,
  DealMakerName__c AS deal_maker_name,
  HubName__c AS hub_name,
  LongTermPayment__c AS long_term_payment,
  Faixa_de_Dias_desde_CCV__c AS range_of_days_since_ccv,
  ThreadId__c AS thread_id,
  HaveDemandNoteReason__c AS have_demand_note_reason,
  CASE
    WHEN IsDeleted = 'true' THEN TRUE
    WHEN IsDeleted = 'false' THEN FALSE
  END AS is_deleted,
  CASE
    WHEN IsDownPaymentPaid__c = 'Sim' THEN TRUE
    WHEN IsDownPaymentPaid__c = 'Não' THEN
      FALSE
  END AS is_down_payment_paid,
  CASE
    WHEN BYPaysEntireDeposit__c = 'true' THEN TRUE
    WHEN BYPaysEntireDeposit__c = 'false' THEN FALSE
  END AS is_buyer_pays_entire_deposit,
  CASE
    WHEN IsDiligenceAccepted__c = 'true' THEN TRUE
    WHEN IsDiligenceAccepted__c = 'false' THEN FALSE
  END AS is_diligence_accepted,
  CASE
    WHEN HasDownPaymentExtension__c = 'Sim' THEN TRUE
    WHEN HasDownPaymentExtension__c = 'Não' THEN FALSE
  END AS has_down_payment_extension,
  CASE
    WHEN PaidViaTed__c = 'Sim' THEN TRUE
    WHEN PaidViaTed__c = 'Não' THEN FALSE
  END AS is_paid_via_ted,
  CASE
    WHEN SignalBrokerage__c = 'Sim' THEN TRUE
    WHEN SignalBrokerage__c = 'Não' THEN FALSE
  END AS is_seller_pays_part_deposit,
  CASE
    WHEN KeysReceived__c = 'True' THEN TRUE
    WHEN KeysReceived__c = 'False' THEN FALSE
  END AS is_key_received,
  CASE
    WHEN ContinueWithPartnerRegistry__c = 'Sim' THEN TRUE
    WHEN ContinueWithPartnerRegistry__c = 'Não' THEN FALSE
  END AS is_continue_with_partner_registry,
  CASE
    WHEN HouseRegistryMustBeUpdated__c = 'true' THEN TRUE
    WHEN HouseRegistryMustBeUpdated__c = 'false' THEN FALSE
  END AS is_house_registry_must_be_updated,
  CASE
    WHEN IsSuspended__c = 'true' THEN TRUE
    WHEN IsSuspended__c = 'false' THEN FALSE
  END AS is_suspended,
  CASE
    WHEN IsAssigned__c = 'true' THEN TRUE
    WHEN IsAssigned__c = 'false' THEN FALSE
  END AS is_assigned,
  CASE
    WHEN FS_BalancePaymentMade__c = 'Sim' THEN TRUE
    WHEN FS_BalancePaymentMade__c = 'Não' THEN FALSE
  END AS is_balance_payment_made,
  CASE
    WHEN ShareCommunityPortal__c = 'true' THEN TRUE
    WHEN ShareCommunityPortal__c = 'false' THEN FALSE
  END AS is_share_community_portal,
  CASE
    WHEN ListViewUser__c = 'true' THEN TRUE
    WHEN ListViewUser__c = 'false' THEN FALSE
  END AS is_list_view_user,
  CASE
    WHEN HouseRegistryMustBeUpdatedForm__c = 'Sim' THEN TRUE
    WHEN HouseRegistryMustBeUpdatedForm__c = 'Não' THEN FALSE
  END AS is_house_registry_must_be_updated_form,
  CASE
    WHEN ConcomitantRegistration__c = 'Sim' THEN TRUE
    WHEN ConcomitantRegistration__c = 'Não' THEN FALSE
  END AS is_concomitant_registration,
  CASE
    WHEN LeaseComplaintSent__c = 'Sim' THEN TRUE
    WHEN LeaseComplaintSent__c = 'Não' THEN FALSE
  END AS is_lease_complaint_sent,
  CAST(DownPaymentDeadline__c AS DATE) AS dt_down_payment_deadline,
  CAST(FS_BY_KeyDeliveryDate__c AS DATE) AS dt_key_delivery_buyer,
  CAST(FS_SL_KeyDeliveryDate__c AS DATE) AS dt_key_delivery_seller,
  CAST(KeyDeliveryDate__c AS DATE) AS dt_key_delivery,
  CAST(dt_updated AS DATE) AS dt_updated,
  CAST(SubscriptionSchedulingDate__c AS DATE) AS dt_subscription_scheduling,
  CAST(BookkeepingDoneDateCCV__c AS DATE) AS dt_bookkeeping_done_ccv,
  CAST(CRIDoneDateCCV__c AS DATE) AS dt_cri_done_ccv,
  CAST(FS_Endorsement_RequestDateCCV__c AS DATE) AS dt_fs_endorsement_request_ccv,
  CAST(FS_CRI_RequestDateCCV__c AS DATE) AS dt_fs_cri_request_ccv,
  CAST(CCVCompletionDate__c AS DATE) AS dt_completion_ccv,  
  CAST(CreatedDate AS TIMESTAMP) AS ts_created,
  CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
  CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
  CAST(LastActivityDate AS TIMESTAMP) AS ts_last_activity,
  CAST(LastViewedDate AS TIMESTAMP) AS ts_last_viewed,
  CAST(LastReferencedDate AS TIMESTAMP) AS ts_last_referenced,
  CAST(CCVSignedAt__c AS TIMESTAMP) AS ts_ccv_signed,
  CAST(CCVTerminationCreatedAt__c AS TIMESTAMP) AS ts_ccv_termination,
  CAST(DDAcceptedDate__c AS TIMESTAMP) AS ts_dd_accepted,
  year,
  month,
  day 
FROM 
  datalake_salesforce_raw.purchase_sale_contract
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
