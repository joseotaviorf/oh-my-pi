SELECT
    id,
    metric_period_id AS id_metric_period,
    metric_period_history_id AS id_metric_period_history,
    partner_external_id AS id_partner_external,
    partner_external_type,
    total,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_metric