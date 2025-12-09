SELECT
    BIGINT(`id`) AS id_campaign,
    BIGINT(offer_id) AS id_offer,
    BIGINT(agent_id) AS id_agent,
    BIGINT(partner_id) AS id_partner,
    description,
    agent_role,
    partner_role,
    updated_by,
    CAST(bonus_fee AS DECIMAL(38,20)) AS bonus_fee,
    cumulative AS is_cumulative,
    DATE(start_date) AS dt_campaign_start,
    DATE(end_date) AS dt_campaign_end,
    TIMESTAMP(deleted_at) AS ts_deleted,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.campaign
