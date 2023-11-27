SELECT
    id,
    agent_id AS id_agent,
    lead_id AS id_lead,
    rev,
    revtype AS rev_type,
    name,
    status,
    phone,
    code,
    origin,
    name_mod AS mod_name,
    status_mod AS mod_status,
    code_mod AS mod_code,
    phone_mod AS mod_phone,
    origin_mod AS mod_origin,
    agent_id_mod AS mod_id_agent,
    lead_id_mod AS mod_id_lead,
    createdAt AS ts_created
FROM
    datalake_ebdb_raw.agentleadreferral_aud
