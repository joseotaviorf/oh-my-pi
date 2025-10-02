SELECT
    CAST(ht_audience_id AS STRING) AS id_audience,
    CAST(ht_row_id AS STRING) AS id_row,
    CAST(ht_event_type AS STRING) AS ht_event_type,
    CAST(ht_split_group AS STRING) AS ht_split_group,
    CAST(ht_timestamp AS TIMESTAMP) AS ts_ht

FROM
    datalake_hightouch_logs_raw.audience_membership_trino
