SELECT
    eval_rating_id AS id_eval_rating,
    business_group_id AS id_business_group,
    evaluation_id AS id_evaluation,
    reference_id AS id_reference,
    performance_rating_id AS id_performance_rating,
    eval_participant_id AS id_eval_participant,
    reference_type,
    role_type_code AS role_type,
    created_by,
    last_updated_by AS updated_by,
    CAST(calculated_rating AS INT) AS calculated_rating,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_eval_ratings
