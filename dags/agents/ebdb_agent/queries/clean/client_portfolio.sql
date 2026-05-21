SELECT
    id,
    agent_uuid AS uuid_agent,
    client_person_uuid AS uuid_client_person,
    capability_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_activity_at AS ts_last_activity,
    client_since AS ts_client_since,
    expiration_at AS ts_expiration
FROM
    datalake_ebdb_raw.ClientPortfolio
