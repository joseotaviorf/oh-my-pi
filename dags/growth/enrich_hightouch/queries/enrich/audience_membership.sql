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
    datalake_hightouch_logs_clean.audience_membership_databricks
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

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
    datalake_hightouch_logs_clean.audience_membership_trino
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
