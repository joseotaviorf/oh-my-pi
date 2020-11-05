SELECT
    uuid AS id_source_unique, 
    caller_phone_number,
    destination_phone_number,
    direction,
    provider,
    metadata,
    recording_url,
    start_time AS ts_started,
    end_time AS ts_ended
FROM
    datalake_bigfone_raw.call