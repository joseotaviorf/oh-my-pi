SELECT
    BIGINT(`id`) AS id_offer_agent,
    BIGINT(agent_id) AS id_agent,
    BIGINT(offer_id) AS id_offer,
    `role` AS agent_role,
    TIMESTAMP(dissociated_at) AS ts_dissociated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.offer_agent
