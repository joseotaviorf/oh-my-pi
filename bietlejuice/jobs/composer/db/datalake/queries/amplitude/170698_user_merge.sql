SELECT
    amplitude_id AS id_amplitude,
    merged_amplitude_id AS id_amplitude_merged,
    scope AS id_app,
    timestamp(merge_time) AS ts_merge,
    timestamp(merge_server_time) AS ts_server_merge,
    YEAR(timestamp(merge_time)) AS year,
    MONTH(timestamp(merge_time)) AS month,
    DAY(timestamp(merge_time)) AS day
FROM
    datalake_amplitude_raw.170698_user_merge
WHERE
    YEAR(TIMESTAMP(merge_time)) = {year}
    AND MONTH(TIMESTAMP(merge_time)) = {month}
    AND DAY(TIMESTAMP(merge_time)) = {day}