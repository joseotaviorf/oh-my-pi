drop table if exists datalake_clean.asterisk_ivr_entries;
create external table if not exists datalake_clean.asterisk_ivr_entries (
  ivr_id integer,
  selection string,
  destination string,
  ivr_ret integer
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/ivr_entries/'
;