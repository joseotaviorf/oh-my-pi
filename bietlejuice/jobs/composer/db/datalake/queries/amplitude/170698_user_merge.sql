SELECT
    amplitude_id AS id_amplitude,
    merged_amplitude_id AS id_amplitude_merged,
    scope AS id_app,
    timestamp(merge_time) AS ts_merge,
    timestamp(merge_server_time) AS ts_server_merge 
FROM
    datalake_amplitude_raw.170698_user_merge