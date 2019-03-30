drop table if exists datalake_clean.asterisk_calls_details;
create external table if not exists datalake_clean.asterisk_calls_details (    
    id_c.id_call string,
    s.call_source_number string,
    d.call_destination_number string,
    u.id_ura string,
    u.ts_start_ura string,
    u.ts_end_ura string,
    u.is_URA_HELP_solved string,
    q.id_queue string,
    q.id_caller string,
    q.ts_start_queue string,
    q.ts_end_queue string,
    a.id_attendance string,
    a.ts_start_attendance string,
    q.ts_end_attendance string,
    sec_time_duration_ura string,
    sec_time_duration_queue string,
    sec_time_duration_attendance string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/logs_full/'
;