drop table if exists datalake_clean.asterisk_queues_config;
create external table if not exists datalake_clean.asterisk_queues_config (
  extension string,
  description string,
  grppre string,
  alert_info string,
  ringing integer,
  max_wait string,
  password string,
  ivr_id string,
  destination string,
  cw_ignore integer,
  queue_wait integer,
  use_queue_context integer,
  toggle_hint integer,
  q_no_answer integer,
  call_confirm integer,
  call_confirm_id integer,
  q_regex string,
  agent_announce_id integer,
  join_announce_id integer,
  monitor_type string,
  monitor_heard integer,
  monitor_spoken integer,
  callback_id string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/queues_config/'
;