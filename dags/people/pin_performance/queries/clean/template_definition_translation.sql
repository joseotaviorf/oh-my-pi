SELECT
    template_defn_id AS id_template_definition,
    business_group_id AS id_business_group,
    language,
    source_lang AS source_language,
    name AS translated_template_name,
    created_by,
    last_updated_by AS updated_by,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_tmpl_defns_tl
