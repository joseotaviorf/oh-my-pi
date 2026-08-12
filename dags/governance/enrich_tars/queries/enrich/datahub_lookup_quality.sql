-- Table-discovery success/failure from Vector datahub_access_instructions events.
-- One row per lookup call Tars made to resolve a table name into DataHub domain/access
-- guidance. is_found = FALSE means the requested table could not be located in the catalog.
SELECT
    COALESCE(id_turn, CONCAT('lookup-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING))) AS id_lookup,
    id_session,
    session_source,
    domain_name,
    table_name,
    is_found,
    status,
    error_class,
    duration_ms,
    ts_event AS ts_lookup,
    dt_event AS dt_lookup,
    year,
    month,
    day
FROM
    datalake_tars_clean.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND event_type = 'datahub_access_instructions'
