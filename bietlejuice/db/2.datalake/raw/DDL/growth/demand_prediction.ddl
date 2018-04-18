drop table if exists datalake_raw.growth_demand_prediction;
create external table datalake_raw.growth_demand_prediction (
  city string,
  region string,
  `date` string,
  booking_created string,
  effective_visit string,
  offer_first_sent string,
  offer_approved string,
  tenant_first_document_sent string,
  proposal_approved string,
  booking_created_yearly_count string,
  effective_visit_yearly_count string,
  offer_first_sent_yearly_count string,
  offer_approved_yearly_count string,
  tenant_first_document_sent_yearly_count string,
  proposal_approved_yearly_count string,
  booking_created_monthly_count string,
  effective_visit_monthly_count string,
  offer_first_sent_monthly_count string,
  offer_approved_monthly_count string,
  tenant_first_document_sent_monthly_count string,
  proposal_approved_monthly_count string,
  booking_created_weekly_count string,
  effective_visit_weekly_count string,
  offer_first_sent_weekly_count string,
  offer_approved_weekly_count string,
  tenant_first_document_sent_weekly_count string,
  proposal_approved_weekly_count string,
  dt_timestamp string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/growth/demand_prediction/'
tblproperties (
  'skip.header.line.count' = '1'
)
;