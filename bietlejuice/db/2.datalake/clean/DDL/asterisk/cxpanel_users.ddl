drop table if exists datalake_clean.asterisk_cxpanel_users;
create external table if not exists datalake_clean.asterisk_cxpanel_users (
  cxpanel_user_id integer,
  user_id integer,
  display_name string,
  peer string,
  add_extension integer,
  `full` integer,
  add_user integer,
  hashed_password string,
  initial_password string,
  auto_answer integer,
  parent_user_id float,
  password_dirty integer
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/cxpanel_users/'
;