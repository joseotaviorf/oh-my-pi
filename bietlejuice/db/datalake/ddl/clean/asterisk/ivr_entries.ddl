drop table if exists datalake_clean.asterisk_ivr_entries;
create external table if not exists datalake_clean.asterisk_ivr_entries (
  ivr_id string,
  selection string,
  destination string,
  ivr_ret string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/ivr_entries/'
;