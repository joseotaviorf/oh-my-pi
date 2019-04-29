drop table if exists datalake_clean.asterisk_calls_details;
create external table if not exists datalake_clean.asterisk_calls_details (    
    id_call string,
    call_source_number string,
    call_destination_number string,
    id_ura string,
    ts_ura_started string,
    ts_ura_ended string,
    audio_message string,
    typed_answer string,
    is_ura_help_solved string,
    id_queue string,
    id_caller string,
    ts_queue_started string,
    ts_queue_ended string,
    id_attendance string,
    ts_attendance_started string,
    ts_attendance_ended string,
    seconds_duration_ura string,
    seconds_duration_queue string,
    seconds_duration_attendance string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/asterisk/calls_details/'
;