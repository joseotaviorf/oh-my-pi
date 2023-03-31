SELECT
    `id` AS id_campaign,
    offer_id AS id_offer,
    agent_id AS id_agent,
    description,
    agent_role,
    bonus_fee,
    cumulative AS is_cumulative,
    DATE (start_date) AS dt_campaign_start,
    DATE (end_date) AS dt_campaign_end,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.campaign
