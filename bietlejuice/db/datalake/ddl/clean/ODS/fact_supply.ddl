drop table if exists datalake_clean.fact_supply;

create external table datalake_clean.fact_supply (
	id string,
	lead_id string,
	conversao_id string,
	photo_job_id string,
	imovel_id string,
	rep_id string,
	affiliate_id string,
	owner_id string,
	region_id string,
	photographer_id string,
	dt_lead string,
	dt_prospect string,
	dt_first_inside_sales_contact string,
	dt_conversion string,
	dt_qualified string,
	dt_opportunity string,
	dt_first_listing string,
	dt_discarded string,
	flow string,
	acquisition_method string,
	acquisition_channel string,
	acquisition_source string,
	funnel_step string,
	lead_to_prospect_diff_minutes string,
	prospect_to_qualified_diff_minutes string,
	lead_to_first_inside_sales_contact_diff_minutes string,
	prospect_to_first_inside_sales_contact_diff_minutes string,
	qualified_to_opportunity_diff_minutes string,
	opportunity_to_listing_diff_minutes string,
	lead_to_listing_diff_minutes string,
	lead_to_prospect_diff_hours string,
	prospect_to_qualified_diff_hours string,
	lead_to_first_inside_sales_contact_diff_hours string,
	prospect_to_first_inside_sales_contact_diff_hours string,
	qualified_to_opportunity_diff_hours string,
	opportunity_to_listing_diff_hours string,
	lead_to_listing_diff_hours string,
	lead_to_prospect_diff_days string,
	prospect_to_qualified_diff_days string,
	lead_to_first_inside_sales_contact_diff_days string,
	prospect_to_first_inside_sales_contact_diff_days string,
	qualified_to_opportunity_diff_days string,
	opportunity_to_listing_diff_days string,
	lead_to_listing_diff_days string,
	exclusivity string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/supply'
tblproperties (
  'skip.header.line.count' = '1'
)
;