SELECT
    id,
    worker_portfolio_id AS id_portfolio,
    portfolio_file_id AS id_portfolio_file,
    event_type,
    author,
    description,
    portfolio_unit_id,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.worker_portfolio_event
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
