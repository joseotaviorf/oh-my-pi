SELECT
    sk_agent AS id_agent,
    id_business_unit,
    agent_group,
    hub_name,
    CAST(round AS INTEGER) AS round
FROM
    datalake_gsheets_raw.agent_tiers
