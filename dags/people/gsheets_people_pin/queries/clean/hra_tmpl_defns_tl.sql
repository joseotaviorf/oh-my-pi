SELECT
    template_defn_id AS id_template_definition,
    business_group_id AS id_business_group,
    language AS language_code,
    source_lang AS source_language,
    name AS template_name,
    comments AS template_comments,
    created_by,
    last_updated_by AS updated_by,
    object_version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_tmpl_defns_tl
