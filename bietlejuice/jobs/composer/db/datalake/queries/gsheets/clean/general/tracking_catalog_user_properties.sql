SELECT
    project_name,
    id_app,
    user_property,
    TO_DATE(first_seen, 'yyyy-MM-dd') AS first_seen,
    TO_DATE(last_seen, 'yyyy-MM-dd') AS last_seen,
    description,
    type,
    status,
    owner
FROM
    datalake_gsheets_raw.user_properties