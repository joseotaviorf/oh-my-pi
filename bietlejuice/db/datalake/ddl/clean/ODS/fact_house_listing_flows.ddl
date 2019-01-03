drop table if exists datalake_clean.ods_fact_house_listing_flows;

create external table datalake_clean.ods_fact_house_listing_flows (
	sk_house_listing_flow string,
	sk_lead string,
	sk_lead_conversion string,
	sk_first_photo_job string,
	sk_house_listing string,
	sk_user_house_registrant string,
	sk_user_sales_rep string,
	sk_user_lead_affiliate string,
	sk_user_task_assignee string,
	sk_region string,
	sk_lead_date string,
	sk_prospect_date string,
	sk_task_created_date string,
	sk_task_closed_date string,
	sk_first_inside_sales_contact_date string,
	sk_conversion_date string,
	sk_qualified_date string,
	sk_opportunity_date string,
	sk_first_listing_date string,
	sk_discard_date string,
	funnel_step string,
	funnel_drop_reason string,
	hours_lead_to_prospect string,
	hours_prospect_to_qualified string,
	hours_lead_to_first_inside_sales_contact string,
	hours_prospect_to_first_inside_sales_contact string,
	hours_qualified_to_opportunity string,
	hours_opportunity_to_listing string,
	hours_lead_to_listing string,
	days_lead_to_prospect string,
	days_prospect_to_qualified string,
	days_lead_to_first_inside_sales_contact string,
	days_prospect_to_first_inside_sales_contact string,
	days_qualified_to_opportunity string,
	days_opportunity_to_listing string,
	days_lead_to_listing string,
	days_lead_to_processing string,
	is_exclusive string,
	first_isales_intervention string,
	lead_type string,
	lead_origin string,
	lead_utm_source string,
	lead_utm_medium string,
	is_branded string,
	is_b2b string,
	is_doorman string,
	is_isales_direct_register string,
	is_cx_direct_register string,
	has_isales_intervention string,
	is_callcenter string,
	mkt_branded string,
	mkt_category string,
	mkt_flow string,
	mkt_completion string,
	mkt_channel string,
	mkt_platform string,
	mkt_medium string,
	mkt_source string,
	ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/house_listing_flows'
tblproperties (
  'skip.header.line.count' = '1'
)
;