drop table if exists datalake_clean.ods_sale_fact_listing_sale_flows;
create external table datalake_clean.ods_sale_fact_listing_sale_flows (
  ods_id string,
  sk_house_listing string,
  sk_house_first_listing_date string,
  sk_house_listing_date string,
  sk_house_listing_de_publication_date string,
  sk_region string,
  sk_sale_flow string,
  sk_booking string,
  sk_booking_created_date string,
  sk_visit_date string,
  sk_owner string,
  sk_user_agent string,
  sk_client string,
  sk_visit string,
  sk_agent_review_rating_date string,
  flg_visit_completed string,
  flg_visit_performed string,
  flg_visit_created_from_app string,
  visit_created_type string,
  flg_visit_last_updated_from_app string,
  days_booking_created_to_visit string,
  days_user_created_to_visit string,
  days_house_listing_to_visit string,
  funnel_step string,
  funnel_step_drop_reason string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/sale_listing_sale_flows'
tblproperties (
  'skip.header.line.count' = '1'
);
