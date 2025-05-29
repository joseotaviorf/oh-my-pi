SELECT
    BIGINT(`id`) AS id_revenue_share,
    BIGINT(offer_agent_id) AS id_offer_agent,
    BIGINT(offer_partner_id) AS id_offer_partner,
    output AS json_output,
    errors AS json_errors,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.revenue_share_by_participant
