SELECT
    CAST(agent_id AS BIGINT) AS id_agent,
    agent_name,
    agent_phone,
    agent_email,
    agent_cpf,
    group_name,
    lead_phone,
    lead_email,
    CAST(is_valid_lead AS BOOLEAN) AS is_valid_lead,
    CAST(appointment_date AS TIMESTAMP) AS ts_appointment
FROM
    datalake_gsheets_raw.tqc_leads_bh
WHERE
    group_name <> ""
