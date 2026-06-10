SELECT
    id,
    partner_metric_id AS id_partner_metric,
    replaced_partner_metric_id AS id_replaced_partner_metric,
    author,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.partner_metric_manual_ingestion_info
