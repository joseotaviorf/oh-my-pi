SELECT
    id,
    agent_id AS id_agent,
    capability_id AS id_capability,
    author_type,
    author_identifier,
    author_role,
    channel,
    reason,
    on_behalf_of_role,
    event_type,
    occurred_at AS ts_occurred,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_ebdb_raw.AgentEventLog