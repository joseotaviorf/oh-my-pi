SELECT
    id,
    agent_uuid AS uuid_agent,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.ClientPortfolioMigration
