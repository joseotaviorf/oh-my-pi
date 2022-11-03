SELECT
    agent_email,
    agent_cpf,
    agent_creci,
    lead_name,
    lead_phone,
    lead_email,
    agent_visits,
    lead_interest_area,
    program_phase,
    BOOLEAN(NULLIF(is_valid_lead, '')) AS is_valid_lead,
    CAST(appointment_date AS TIMESTAMP) AS ts_appointment,
    CAST(new_lead_date AS TIMESTAMP) AS ts_new_lead
FROM
    datalake_gsheets_raw.tqc_leads