SELECT
    review_period_id AS id_review_period,
    business_group_id AS id_business_group,
    language AS language_code,
    source_lang AS source_language,
    created_by,
    last_updated_by AS updated_by,
    review_period_name AS name_review_period,
    description AS description_review_period,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_review_periods_tl
