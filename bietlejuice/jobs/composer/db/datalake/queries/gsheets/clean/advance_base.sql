SELECT
    id_offer,
    id_agent,
    agent_full_name,
    partner_type,
    CAST(gross_advance AS FLOAT) AS gross_advance
FROM
    datalake_gsheets_raw.advance_base
