SELECT
    CAST(agent_id AS BIGINT) AS id_agent,
    agent_name,
    agent_phone,
    agent_email,
    group_name,
    lead_phone,
    lead_email,
    CAST(is_valid_lead AS BOOLEAN) AS is_valid_lead,
    TO_TIMESTAMP(appointment_date, 'M/d/y H:m:s') AS ts_appointment
FROM 
    datalake_gsheets_raw.tqc_leads_bh