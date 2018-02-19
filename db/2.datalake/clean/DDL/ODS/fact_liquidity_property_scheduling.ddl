drop table if exists datalake_clean.ods_fact_liquidity_property_scheduling;
create external table if not exists datalake_clean.ods_fact_liquidity_property_scheduling (
  ods_id string,
  sk_property string,
  sk_region string,
  listing_number string,
  sk_booking string,
  sk_owner string,
  sk_user_affiliate string,
  sk_user_agent string,
  sk_user_visitor string,
  sk_user_visit_agent string,
  sk_visit string,
  sk_negotiation string,
  sk_offer string,
  sk_proposal string,
  sk_contract string,
  id_rental_flow string,
  sk_first_listing_date string,
  sk_listing_date string,
  sk_booking_created_date string,
  sk_visit_date string,
  sk_visitor_user_signup_date string,
  sk_offer_created_date string,
  sk_contract_signed_date string,
  sk_user_agent_date string,
  dt_contract_anullment string,
  visit_created_from_app string,
  visit_created_type string,
  visit_last_updated_from_app string,
  visit_last_updated_type string,
  initial_source string,
  initial_medium string,
  initial_campaign string,
  initial_referring_domain string,
  source string,
  medium string,
  campaign string,
  referring_domain string,
  vl_cost_marketing_campaigns string,
  vl_cost_marketing_ads string,
  vl_cost_marketing_sms string,
  vl_cost_agents_comission string,
  vl_cost_agents_slot string,
  vl_cost_visit_support string,
  vl_cost_closing_support string,
  vl_cost_classifieds string,
  dt_timestamp string,
  booking_to_visit string,
  offer_to_internal_analyis string,
  offer_to_credit_analysis string,
  credit_analysis_to_contract string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
stored as textfile
location 's3://5a-datalake/clean/ods/property_scheduling'
tblproperties (
  'skip.header.line.count' = '1'
)
;