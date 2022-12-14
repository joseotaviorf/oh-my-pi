SELECT
    dashboard_name,
    url,
    current_domain,
    updated_domain,
    editor,
    status,
    CAST(updated_at as TIMESTAMP) as updated_at
FROM
    datalake_gsheets_raw.domain_management_looker_dashboards
