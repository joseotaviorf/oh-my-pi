drop table if exists datalake_clean.ods_dim_proposal;
create external table if not exists datalake_clean.ods_dim_proposal (
  sk_proposal bigint,
  id_proposal bigint,
  guarantee varchar(50),
  status varchar(50),
  status_doc_tenant varchar(50),
  status_doc_owner varchar(50),
  rejection_reason varchar(255),
  result_credit_evaluation varchar(50),
  status_sortinghat varchar(50),
  renting_proposal_value double,
  tenant_document_sent_count int,
  credit_evaluation_count int,
  tenant_document_sent int,
  tenant_contract_accepted int,
  owner_contract_accepted int,
  owner_document_sent int,
  flg_doc_reused int,
  dt_proposal timestamp,
  dt_proposal_approved timestamp,
  ts_processed timestamp,
  dt_created timestamp,
  dt_updated timestamp,
  dt_tenant_document_sent timestamp,
  dt_owner_document_sent timestamp,
  dt_tenant_first_document_sent timestamp,
  dt_tenant_auto_first_doc_sent timestamp,
  dt_credit_analysis_first_init timestamp,
  dt_credit_analysis_init timestamp,
  dt_credit_analysis_first_end timestamp,
  dt_credit_analysis_end timestamp,
  dt_credit_last_approved timestamp,
  dt_tenant_first_doc_complete timestamp,
  dt_tenant_last_doc_complete timestamp,
  dt_first_credit_evaluation_init timestamp,
  dt_last_credit_evaluation_init timestamp,
  dt_first_credit_evaluation_negative timestamp,
  dt_last_credit_evaluation_negative timestamp,
  dt_guarantee timestamp,
  dt_first_doc_analysis_approved timestamp,
  dt_last_doc_analysis_approved timestamp,
  dt_first_doc_analysis_rejected timestamp,
  dt_last_doc_analysis_rejected timestamp,
  dt_guarantee_paid timestamp,
  dt_first_credit_evaluation_positive timestamp,
  dt_last_credit_evaluation_positive timestamp,
  dt_credit_analysis_last_init timestamp,
  dt_credit_analysis_last_end timestamp,
  dt_tenant_doc_complete timestamp,
  dt_timestamp timestamp,
  ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_proposal'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
;