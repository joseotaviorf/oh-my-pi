SELECT
    id as id_unit, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated, 
    status, 
    worker_portfolio_id, 
    origin_identifier, 
    user_persona, 
    metadata,
    year,
    month,
    day
FROM
    datalake_hefesto_test_raw.worker_portfolio_unit
