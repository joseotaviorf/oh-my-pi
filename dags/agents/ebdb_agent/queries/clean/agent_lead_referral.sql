SELECT
    id,
    agent_id AS id_agent,
    lead_id AS id_lead,
    name,
    status,
    phone,
    code,
    origin,
    createdAt AS ts_created,
    updatedAt AS ts_updated
FROM
    datalake_ebdb_raw.agentleadreferral
