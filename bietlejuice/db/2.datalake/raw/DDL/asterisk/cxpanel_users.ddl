drop table if exists datalake_raw.asterisk_cxpanel_users;
create external table if not exists datalake_raw.asterisk_cxpanel_users (
  cxpanel_user_id string,
  user_id string,
  display_name string,
  peer string,
  add_extension string,
  full string,
  add_user string,
  hashed_password string,
  initial_password string,
  auto_answer string,
  parent_user_id string,
  password_dirty string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/cxpanel_users/'
;