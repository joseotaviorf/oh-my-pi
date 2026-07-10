SELECT
    id,
    incentive_engine_id AS id_incentive_engine,
    author,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.incentive_engine_disablement
