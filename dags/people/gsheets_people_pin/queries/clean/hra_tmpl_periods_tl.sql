SELECT
    tmpl_period_id AS id_template_period,
    business_group_id AS id_business_group,
    language AS language_code,
    source_lang AS source_language,
    customary_name AS name_customary,
    short_name AS name_short,
    created_by,
    last_updated_by AS updated_by,
    object_version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_tmpl_periods_tl
