SELECT
    rating_level_id AS id_rating_level,
    business_group_id AS id_business_group,
    rating_model_id AS id_rating_model,
    module_id AS id_module,
    rating_level_code AS rating_level_type,
    career_str_dev AS career_strength_and_development,
    created_by,
    last_updated_by AS updated_by,
    star_rating AS star_rating_value,
    min_rating_distribution AS min_rating_distribution_value,
    max_rating_distribution AS max_rating_distribution_value,
    review_points,
    numeric_rating AS numeric_rating_value,
    from_points AS points_from,
    to_points AS points_to,
    object_version_number AS version_number,
    date_from AS dt_started,
    date_to AS dt_ended,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_rating_levels_b
