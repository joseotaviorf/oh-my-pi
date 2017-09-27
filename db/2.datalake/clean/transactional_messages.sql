create external table datalake_clean.transactional_messages (
  can_be_resent boolean,
  subject string,
  email_from string,
  email_to string,
  messageid string,
  sent_at string,
  smart_email_id string,
  status string,
  total_clicks int,
  total_opens int,
  property_email_id int,
  url string,
  property_link_id int,
  first_opened_date string,
  `date` string,
  city string,
  country_code string,
  country_name string,
  region string,
  long double,
  lat double,
  opened boolean,
  clicked boolean
)
partitioned by (
  project string
)
stored as parquet
location
  's3://5a-datalake/clean/campaign_monitor/transactional_messages/'
;


msck repair table datalake_clean.transactional_messages;