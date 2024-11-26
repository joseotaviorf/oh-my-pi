SELECT
    rating_level_id AS id_rating_level,
    business_group_id AS id_business_group,
    language AS language_code,
    source_lang AS source_language,
    rating_description AS description_rating,
    rating_short_descr AS short_description_rating,
    review_rating_descr AS description_review_rating,
    created_by,
    last_updated_by AS updated_by,
    object_version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_rating_levels_tl
