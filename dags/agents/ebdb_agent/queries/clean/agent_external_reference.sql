SELECT
    id,
    agent_id AS id_agent,
    type,
    value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.agentexternalreference
