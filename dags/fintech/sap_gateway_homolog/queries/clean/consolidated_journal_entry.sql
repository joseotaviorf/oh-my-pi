SELECT
    id,
    originated_by,
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
