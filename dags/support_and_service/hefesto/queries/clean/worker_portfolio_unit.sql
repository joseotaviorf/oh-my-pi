SELECT
    id as id_unit, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated, 
    status, 
    worker_portfolio_id, 
    origin_identifier, 
    user_persona, 
    metadata
FROM
    datalake_hefesto_raw.worker_portfolio_unit
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
