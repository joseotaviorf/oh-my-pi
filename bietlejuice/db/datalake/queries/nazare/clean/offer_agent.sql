SELECT
    `id` AS id_offer_agent,
    agent_id AS id_agent,
    offer_id AS id_offer,
    `role` AS agent_role,
    dissociated_at AS ts_dissociated,
    created_at AS ts_created
FROM
    datalake_nazare_raw.offer_agent
