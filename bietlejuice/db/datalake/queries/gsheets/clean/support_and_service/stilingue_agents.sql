SELECT
    CAST(id_external_agent AS BIGINT) AS id_external_agent,
    external_agent_name,
    agent_email,
    channel,
    CAST(is_moderator AS BOOLEAN) AS is_moderator
FROM
    datalake_gsheets_raw.stilingue_agents