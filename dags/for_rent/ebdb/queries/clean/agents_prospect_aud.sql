SELECT
    id,
    externalId AS id_external,
    agent_id AS id_agent,
    name,
    phone,
    rev,
    revtype AS rev_type,
    externalId_MOD AS mod_id_external,
    agent_id_MOD AS mod_id_agent,
    name_MOD AS mod_name,
    phone_MOD AS mod_phone,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.agentsprospect_aud