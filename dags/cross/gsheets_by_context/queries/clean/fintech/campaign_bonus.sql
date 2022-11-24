SELECT
    id_offer,
    id_agent,
    hub,
    campaign,
    agent_full_name,
    partner_type,
    CAST(campaign_bonus AS FLOAT) AS campaign_bonus,
    CAST(dt_started AS DATE) AS dt_started,
    CAST(dt_ended AS DATE) AS dt_ended
FROM
    datalake_gsheets_raw.campaign_bonus
