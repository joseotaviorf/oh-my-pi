SELECT
    id,
    sync_sap_job_id AS id_sync_sap_job,
    source_client,
    status,
    city_state,
    city,
    event_date      AS dt_event,
    due_date        AS dt_due,
    created_at      AS ts_created,
    updated_at      AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.consolidated_journal_entry
