SELECT
    id,
    externalId AS id_external,
    agent_id AS id_agent,
    name,
    phone,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.agentsprospect