drop table if exists datalake_raw.asterisk_queues_config;
create external table if not exists datalake_raw.asterisk_queues_config (
  extension string,
  descr string,
  grppre string,
  alertinfo string,
  ringing string,
  maxwait string,
  password string,
  ivr_id string,
  dest string,
  cwignore string,
  queuewait string,
  use_queue_context string,
  togglehint string,
  qnoanswer string,
  callconfirm string,
  callconfirm_id string,
  qregex string,
  agentannounce_id string,
  joinannounce_id string,
  monitor_type string,
  monitor_heard string,
  monitor_spoken string,
  callback_id string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/queues_config/'
;