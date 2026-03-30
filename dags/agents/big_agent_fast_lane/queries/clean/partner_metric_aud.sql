SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    metric_period_id AS id_metric_period,
    metric_period_history_id AS id_metric_period_history,
    partner_external_id AS id_partner_external,
    partner_external_type,
    total,
    metric_period_id_mod AS mod_id_metric_period,
    metric_period_history_id_mod AS mod_id_metric_period_history,
    partner_external_id_mod AS mod_id_partner_external,
    partner_external_type_mod AS mod_partner_external_type,
    total_mod AS mod_total,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.partner_metric_aud