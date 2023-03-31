SELECT
    `id` AS id_revenue_share,
    offer_agent_id AS id_offer_agent,
    offer_partner_id AS id_offer_partner,
    output AS json_output,
    errors AS json_errors,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.revenue_share_by_participant
