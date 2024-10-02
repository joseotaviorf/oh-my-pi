SELECT
    id,
    agent_id AS id_agent,
    total_houses,
    capacity,
    average_ticket,
    average_lat,
    average_lng,
    CAST(has_opted_out AS BOOLEAN) AS has_opted_out,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.AgentWithKeysAllocationParameters
