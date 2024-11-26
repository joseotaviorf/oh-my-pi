SELECT
    rating_model_id AS id_rating_model,
    business_group_id AS id_business_group,
    module_id AS id_module,
    created_by,
    last_updated_by,
    object_version_number,
    rating_level_count AS rating_levels_count,
    distribution_threshold AS distribution_threshold_value,
    rating_model_code AS rating_model_type,
    date_from AS dt_started,
    date_to AS dt_ended,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_rating_models_b
