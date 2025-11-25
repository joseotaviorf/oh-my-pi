SELECT
    CAST(ht_audience_id AS STRING) AS id_audience,
    CAST(ht_row_id AS STRING) AS id_row,
    CAST(ht_event_type AS STRING) AS ht_event_type,
    CAST(ht_split_group AS STRING) AS ht_split_group,
    CAST(ht_timestamp AS TIMESTAMP) AS ts_ht,
    YEAR(CAST(ht_timestamp AS DATE)) AS year,
    MONTH(CAST(ht_timestamp AS DATE)) AS month,
    DAY(CAST(ht_timestamp AS DATE)) AS day
FROM
    datalake_hightouch_logs_raw.audience_membership_databricks
WHERE
    CAST(ht_timestamp AS DATE) BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY ht_audience_id, ht_row_id
        ORDER BY ht_timestamp DESC
    ) = 1
