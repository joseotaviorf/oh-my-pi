-- Table without user and event properties

drop table datalake_clean.amplitude_events;
create external table datalake_clean.amplitude_events (
  id string, 
  uuid string, 
  app string, 
  amplitude_id string, 
  device_id string, 
  user_id string, 
  event_time string, 
  client_event_time string, 
  client_upload_time string, 
  server_upload_time string, 
  event_id string, 
  session_id string, 
  event_type string, 
  amplitude_event_type string, 
  first_event string, 
  version_name string, 
  os_name string, 
  os_version string, 
  device_brand string, 
  device_manufacturer string, 
  device_model string, 
  device_family string, 
  device_type string, 
  device_carrier string, 
  country string, 
  `language` string,
  revenue string, 
  product_id string, 
  quantity string, 
  price string, 
  location_lat string, 
  location_lng string, 
  ip_address string, 
  region string, 
  city string, 
  dma string, 
  paying string, 
  platform string, 
  start_version string, 
  user_creation_time string, 
  library string, 
)
partitioned by (
  et string, 
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/amplitude/events'
;

-- warning: do not load all partitions (msck repair table)