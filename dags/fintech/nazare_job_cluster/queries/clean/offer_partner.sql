SELECT
    `id` AS id_offer_partner,
    partner_id AS id_partner,
    offer_id AS id_offer,
    `role` AS agent_role,
    dissociated_at AS ts_dissociated,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.offer_partner
