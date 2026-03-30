SELECT
    id,
    metric_period_id AS id_metric_period,
    created_by AS id_created_by,
    metric_link_file,
    query_link_file,
    status,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.metric_period_history