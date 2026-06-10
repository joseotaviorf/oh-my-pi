SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    partner_metric_id AS id_partner_metric,
    replaced_partner_metric_id AS id_replaced_partner_metric,
    author,
    partner_metric_id_mod AS mod_id_partner_metric,
    replaced_partner_metric_id_mod AS mod_id_replaced_partner_metric,
    author_mod AS mod_author,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.partner_metric_manual_ingestion_info_aud
