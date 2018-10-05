drop table if exists datalake_clean.asterisk_cxpanel_users;
create external table if not exists datalake_clean.asterisk_cxpanel_users (
  cxpanel_user_id string,
  user_id string,
  display_name string,
  peer string,
  add_extension string,
  `full` string,
  add_user string,
  hashed_password string,
  initial_password string,
  auto_answer string,
  parent_user_id string,
  password_dirty string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/cxpanel_users/'
;