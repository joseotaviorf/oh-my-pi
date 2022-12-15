SELECT
    table,
    dag,
    dag_owners,
    current_domain,
    updated_domain,
    editor,
    status,
    CAST(updated_at as TIMESTAMP) as updated_at,
    ts_load
FROM
    datalake_gsheets_raw.domain_management_datasets
