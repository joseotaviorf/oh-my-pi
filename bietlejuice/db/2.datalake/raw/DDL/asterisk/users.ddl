drop table if exists datalake_raw.asterisk_users;
create external table if not exists datalake_raw.asterisk_users (
  extension string,
  password string,
  name string,
  voicemail string,
  ringtimer string,
  noanswer string,
  recording string,
  outboundcid string,
  sipname string,
  noanswer_cid string,
  busy_cid string,
  chanunavail_cid string,
  noanswer_dest string,
  busy_dest string,
  chanunavail_dest string,
  mohclass string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/users/'
;