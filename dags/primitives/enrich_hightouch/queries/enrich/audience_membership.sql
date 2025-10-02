SELECT
    id_audience,
    id_row,
    ht_event_type,
    ht_split_group,
    ts_ht
FROM
    datalake_hightouch_logs_clean.audience_membership_databricks

UNION ALL

SELECT
    id_audience,
    id_row,
    ht_event_type,
    ht_split_group,
    ts_ht

FROM
    datalake_hightouch_logs_clean.audience_membership_trino
