SELECT
    id_agent AS sk_agent,
    id_agent_twilio AS sk_agent_twilio,
    name AS full_name,
    email,
    phone,
    organization AS agent_organization,
    organization AS agent_company,
    DATE(ts_created) AS dt_agent_start,
    NOW() AS ts_load
FROM
    datalake_zendesk_users.agents
