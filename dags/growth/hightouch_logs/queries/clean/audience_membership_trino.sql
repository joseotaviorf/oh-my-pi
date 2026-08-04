WITH ranked AS (
    SELECT
        CAST(ht_audience_id AS STRING) AS id_audience,
        CAST(ht_row_id AS STRING) AS id_row,
        CAST(ht_event_type AS STRING) AS ht_event_type,
        CAST(ht_split_group AS STRING) AS ht_split_group,
        CAST(ht_timestamp AS TIMESTAMP) AS ts_ht,
        YEAR(CAST(ht_timestamp AS DATE)) AS year,
        MONTH(CAST(ht_timestamp AS DATE)) AS month,
        DAY(CAST(ht_timestamp AS DATE)) AS day,
        ROW_NUMBER() OVER (
            PARTITION BY ht_audience_id, ht_row_id
            ORDER BY ht_timestamp DESC
        ) AS rn
    FROM
        datalake_hightouch_logs_raw.audience_membership_trino
    WHERE
        CAST(ht_timestamp AS DATE) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    id_audience,
    id_row,
    ht_event_type,
    ht_split_group,
    ts_ht,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
