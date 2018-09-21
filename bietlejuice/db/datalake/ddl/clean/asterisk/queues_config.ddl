drop table if exists datalake_clean.asterisk_queues_config;
create external table if not exists datalake_clean.asterisk_queues_config (
  extension string,
  description string,
  grppre string,
  alert_info string,
  ringing string,
  max_wait string,
  password string,
  ivr_id string,
  destination string,
  cw_ignore string,
  queue_wait string,
  use_queue_context string,
  toggle_hint string,
  q_no_answer string,
  call_confirm string,
  call_confirm_id string,
  q_regex string,
  agent_announce_id string,
  join_announce_id string,
  monitor_type string,
  monitor_heard string,
  monitor_spoken string,
  callback_id string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/queues_config/'
;