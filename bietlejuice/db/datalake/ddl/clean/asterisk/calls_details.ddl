drop table if exists datalake_clean.asterisk_calls_details;
create external table if not exists datalake_clean.asterisk_calls_details (    
    id_call string,
    call_source_number string,
    call_destination_number string,
    id_ura string,
    ts_start_ura string,
    ts_end_ura string,
    is_ura_help_solved string,
    id_queue string,
    id_caller string,
    ts_start_queue string,
    ts_end_queue string,
    id_attendance string,
    ts_start_attendance string,
    ts_end_attendance string,
    sec_time_duration_ura string,
    sec_time_duration_queue string,
    sec_time_duration_attendance string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/calls_details/'
;