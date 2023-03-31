SELECT
    `id` AS id_advance,
    offer_id AS id_offer,
    agent_id AS id_agent,
    bonus_fee AS gross_advance,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.advance
