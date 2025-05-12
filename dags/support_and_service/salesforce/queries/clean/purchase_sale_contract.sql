SELECT 
  Id,
  OwnerId AS id_owner,
  CreatedById AS id_created_by,
  LastModifiedById AS id_last_modified_by,
  ExternalId__c AS id_external,
  OfferId__c AS id_offer,
  Name,
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
  CAST(DownPaymentDeadline__c AS DATE) AS dt_down_payment_deadline,
  CAST(FS_BY_KeyDeliveryDate__c AS DATE) AS dt_key_delivery_buyer,
  CAST(FS_SL_KeyDeliveryDate__c AS DATE) AS dt_key_delivery_seller,
  CAST(KeyDeliveryDate__c AS DATE) AS dt_key_delivery,
  CAST(dt_updated AS DATE) AS dt_updated,
  CAST(CreatedDate AS TIMESTAMP) AS ts_created,
  CAST(LastModifiedDate AS TIMESTAMP) AS ts_last_modified,
  CAST(SystemModstamp AS TIMESTAMP) AS ts_system_mod,
  CAST(LastActivityDate AS TIMESTAMP) AS ts_last_activity,
  CAST(LastViewedDate AS TIMESTAMP) AS ts_last_viewed,
  CAST(LastReferencedDate AS TIMESTAMP) AS ts_last_referenced,
  CAST(CCVSignedAt__c AS TIMESTAMP) AS ts_ccv_signed,
  year,
  month,
  day
FROM 
  datalake_salesforce_raw.purchase_sale_contract
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')