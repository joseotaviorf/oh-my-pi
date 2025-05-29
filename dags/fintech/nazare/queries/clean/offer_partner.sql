SELECT
    BIGINT(`id`) AS id_offer_partner,
    BIGINT(partner_id) AS id_partner,
    BIGINT(offer_id) AS id_offer,
    `role` AS agent_role,
    TIMESTAMP(dissociated_at) AS ts_dissociated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.offer_partner
