SELECT
    id,
    rev,
    revtype,
    revend,
    metric_period_id AS id_metric_period,
    created_by AS id_created_by,
    metric_link_file,
    query_link_file,
    status,
    metric_period_id_mod AS mod_id_metric_period,
    metric_link_file_mod AS mod_metric_link_file,
    query_link_file_mod AS mod_query_link_file,
    created_by_mod AS mod_id_created_by,
    status_mod AS mod_status,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.metric_period_history_aud