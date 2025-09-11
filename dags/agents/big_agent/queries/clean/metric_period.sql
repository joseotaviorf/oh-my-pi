SELECT
    id, 
    invalidated_by AS id_invalidated_by, 
    metric, 
    status, 
    DATE(init_date) AS dt_init,
    DATE(end_date) AS dt_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.metric_period