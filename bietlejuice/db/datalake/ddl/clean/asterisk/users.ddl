drop table if exists datalake_clean.asterisk_users;
create external table if not exists datalake_clean.asterisk_users (
  extension string,
  password string,
  name string,
  voicemail string,
  ring_timer integer,
  no_answer string,
  recording string,
  outbound_cid string,
  sip_name string,
  no_answer_cid string,
  busy_cid string,
  channel_unavailable_cid string,
  no_answer_destination string,
  busy_destination string,
  channel_unavailable_destination string,
  moh_class string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/users/'
;