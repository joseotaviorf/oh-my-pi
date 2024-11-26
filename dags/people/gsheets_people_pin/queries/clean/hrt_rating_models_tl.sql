SELECT
    rating_model_id AS id_rating_model,
    business_group_id AS id_business_group,
    language AS language_code,
    source_lang AS source_language,
    rating_name,
    rating_description,
    created_by,
    last_updated_by,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_rating_models_tl
