drop table if exists datalake_clean.transactional_messages;
create external table datalake_clean.transactional_messages (
  can_be_resent string,
  subject string,
  email_from string,
  email_to string,
  message_id string,
  sent_at string,
  smart_email_id string,
  status string,
  total_clicks string,
  total_opens string,
  property_email_id string,
  rn_property_email_id string,
  url string,
  property_link_id string,
  first_opened_date string,
  `date` string,
  city string,
  country_code string,
  country_name string,
  region string,
  long string,
  lat string,
  opened string,
  clicked string
)
partitioned by (
  project string
)
stored as parquet
location
  's3://5a-datalake/clean/campaign_monitor/transactional_messages/'
;


msck repair table datalake_clean.transactional_messages;