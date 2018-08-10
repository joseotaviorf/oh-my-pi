drop table if exists datalake_clean.ods_dim_booking;
create external table if not exists datalake_clean.ods_dim_booking (
  sk_booking string,
  id_booking string,
  valid_bookings_not_rescheduled string,
  dt_scheduling string,
  type string,
  confirmed string,
  closed string,
  visit_follow_up string,
  dt_visit_follow_up string,
  rescheduled_from_id string,
  id_visitor string,
  id_visit string,
  id_property string,
  id_agent string,
  id_attendant string,
  id_rental_flow string,
  status string,
  slot_dia string,
  reason string,
  reason_category string,
  responsible string,
  app_type string,
  media_source string,
  adjust_network string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  dt_cancel string,
  dt_created string,
  dt_updated string,
  dt_timestamp string,
  last_update_source string,
  first_update_source string,
  visitor_arrived string,
  visitor_missing_reason string,
  agent_arrived string,
  agent_missing_reason string,
  owner_arrived string,
  owner_missing_reason string,
  successful_entrance string,
  troublesome_entrance string,
  checkin_status string,
  flg_branded string,
  flg_via_reschedule string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_device string,
  mkt_channel_type string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/booking'
tblproperties (
  'skip.header.line.count' = '1'
)
;