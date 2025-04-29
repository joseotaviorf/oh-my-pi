SELECT
    role_id AS id_role,
    business_group_id AS id_business_group,
    language,
    source_lang AS source_language,
    name,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_role_defns_tl
