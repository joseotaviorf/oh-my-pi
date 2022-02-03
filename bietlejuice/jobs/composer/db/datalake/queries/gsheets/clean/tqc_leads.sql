SELECT
    agent_email,
    agent_cpf,
    lead_phone,
    lead_email,
    program_phase,
    BOOLEAN(NULLIF(is_valid_lead, '')) AS is_valid_lead,
    CAST(appointment_date AS TIMESTAMP) AS ts_appointment,
    CAST(new_lead_date AS TIMESTAMP) AS ts_new_lead
FROM
    datalake_gsheets_raw.tqc_leads