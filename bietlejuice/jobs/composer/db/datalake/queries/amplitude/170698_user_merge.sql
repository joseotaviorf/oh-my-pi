SELECT
    amplitude_id AS id_amplitude,
    merged_amplitude_id AS id_amplitude_merged,
    scope AS id_app,
    timestamp(merge_time/1000) AS ts_merge,
    timestamp(merge_server_time/1000) AS ts_server_merge,
    YEAR(timestamp(merge_time/1000)) AS year,
    MONTH(timestamp(merge_time/1000)) AS month,
    DAY(timestamp(merge_time/1000)) AS day
FROM
    datalake_amplitude_raw.170698_user_merge
WHERE
    amplitude_id IS NOT NULL
    AND merge_time IS NOT NULL
    AND YEAR(timestamp(merge_time/1000)) = {year}
    AND MONTH(timestamp(merge_time/1000)) = {month}
    AND DAY(timestamp(merge_time/1000)) = {day}