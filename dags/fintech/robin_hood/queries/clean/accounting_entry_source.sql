SELECT
    id,
    code,
    abbr,
    description,
    NULLIF(name, '') AS source_name,
    created_at AS ts_created,
    active AS is_active
FROM
    datalake_robin_hood_raw.accounting_entry_source
