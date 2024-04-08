SELECT
    id,
    portfolio_id AS id_portfolio,
    portfolio_file_id AS id_portfolio_file,
    event_type,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.worker_portfolio_event
WHERE
    created_at >= '2024-03-01'
