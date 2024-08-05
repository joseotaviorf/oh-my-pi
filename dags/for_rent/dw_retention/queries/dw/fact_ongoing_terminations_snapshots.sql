SELECT
    id_contract AS sk_contract,
    id_termination AS sk_termination,
    CAST(DATE_FORMAT(ts_snapshot, 'yyyyMMdd') AS BIGINT) AS sk_snapshot_date,
    is_overdue_stock,
    is_anomaly,
    ts_snapshot,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_ongoing_terminations_snapshot.ongoing_terminations_stock_snapshot
WHERE
    CAST(ts_snapshot AS DATE) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')