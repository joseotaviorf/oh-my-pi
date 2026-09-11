SELECT
    developer_external_id AS id_external_developer,
    company_uuid AS uuid_company,
    provider,
    status,
    last_failure_reason,
    last_attempt_at AS ts_last_attempt,
    last_successful_sync_at AS ts_last_successful_sync,
    year,
    month,
    day
FROM
    datalake_developers_supply_processor_raw.developer_sync_state
