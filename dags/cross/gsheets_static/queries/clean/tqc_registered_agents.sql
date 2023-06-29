SELECT
    agent_email,
    agent_cpf,
    program_phase,
    CAST(subscription_date AS TIMESTAMP) AS ts_subscription
FROM
    datalake_gsheets_raw.tqc_registered_agents
