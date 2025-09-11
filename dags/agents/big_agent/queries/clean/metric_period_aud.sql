SELECT
    id, 
    rev,
    revtype AS rev_type,
    invalidated_by AS id_invalidated_by, 
    revend AS rev_end,
    metric, 
    status, 
    metric_mod AS mod_metric,
    invalidated_by_mod AS mod_id_invalidated_by,
    status_mod AS mod_status,
    init_date_mod AS mod_dt_init,
    end_date_mod AS mod_dt_end,
    DATE(init_date) AS dt_init,
    DATE(end_date) AS dt_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.metric_period_aud