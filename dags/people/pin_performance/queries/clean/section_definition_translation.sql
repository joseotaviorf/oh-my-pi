SELECT
    section_def_id AS id_section_definition,
    business_group_id AS id_business_group,
    language,
    source_lang AS source_language,
    name,
    description,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_section_defns_tl