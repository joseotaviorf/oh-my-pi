drop table if exists datalake_clean.ods_dim_proposal;
create external table if not exists datalake_clean.ods_dim_proposal (
  sk_proposal string,
  id_proposal string,
  dt_proposal string,
  guarantee string,
  renting_proposal_value string,
  status string,
  dt_proposal_approved string,
  tenant_document_sent string,
  dt_tenant_document_sent string,
  owner_document_sent string,
  dt_owner_document_sent string,
  tenant_contract_accepted string,
  owner_contract_accepted string,
  status_doc_tenant string,
  status_doc_owner string,
  tenant_doc_sent_count string,
  dt_created string,
  dt_updated string,
  dt_timestamp string,
  dt_tenant_first_document_sent string,
  dt_tenant_auto_first_doc_sent string,
  dt_credit_analysis_first_init string,
  dt_credit_analysis_last_init string,
  dt_credit_analysis_init string,
  dt_credit_analysis_first_end string,
  dt_credit_analysis_last_end string,
  dt_credit_analysis_end string,
  dt_credit_last_approved string,
  dt_tenant_first_doc_complete string,
  dt_tenant_last_doc_complete string,
  dt_tenant_doc_complete string,
  dt_first_credit_evaluation_init string,
  dt_last_credit_evaluation_init string,
  dt_first_credit_evaluation_positive string,
  dt_last_credit_evaluation_positive string,
  dt_first_credit_evaluation_negative string,
  dt_last_credit_evaluation_negative string,
  dt_guarantee string,
  dt_first_doc_analysis_approved string,
  dt_last_doc_analysis_approved string,
  dt_first_doc_analysis_rejected string,
  dt_last_doc_analysis_rejected string,
  dt_guarantee_paid string,
  status_sortinghat string,
  result_credit_evaluation string,
  credit_evaluation_count string,
  flg_doc_reused string,
  ts_processed string,
  rejection_reason string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/proposal'
tblproperties (
  'skip.header.line.count' = '1'
)
;