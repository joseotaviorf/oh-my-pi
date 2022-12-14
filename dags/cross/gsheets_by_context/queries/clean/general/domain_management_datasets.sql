SELECT
    table,
    dag,
    dag_owners,
    current_domain,
    updated_domain,
    editor,
    status,
    CAST(updated_at as TIMESTAMP) as updated_at
FROM
    datalake_gsheets_raw.domain_management_datasets
