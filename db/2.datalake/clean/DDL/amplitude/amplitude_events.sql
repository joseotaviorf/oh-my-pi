-- Table without user and event properties

drop table datalake_clean.amplitude_events;
create external table datalake_clean.amplitude_events (
  id bigint, 
  uuid string, 
  app int, 
  amplitude_id bigint, 
  device_id string, 
  user_id string, 
  event_time timestamp, 
  client_event_time timestamp, 
  client_upload_time timestamp, 
  server_upload_time timestamp, 
  event_id int, 
  session_id bigint, 
  event_type string, 
  amplitude_event_type string, 
  first_event boolean, 
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
  revenue double, 
  product_id string, 
  quantity int, 
  price double, 
  location_lat double, 
  location_lng double, 
  ip_address string, 
  region string, 
  city string, 
  dma string, 
  paying boolean, 
  platform string, 
  start_version string, 
  user_creation_time timestamp, 
  library string
)
partitioned by (
  et string, 
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/amplitude/events'
;

-- warning: do not load all partitions (msck repair table)