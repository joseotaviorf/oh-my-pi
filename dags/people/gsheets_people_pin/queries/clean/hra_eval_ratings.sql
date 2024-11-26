SELECT
    eval_rating_id AS id_eval_rating,
    business_group_id AS id_business_group,
    evaluation_id AS id_evaluation,
    reference_id AS id_reference,
    performance_rating_id AS id_performance_rating,
    proficiency_rating_id AS id_proficiency_rating,
    eval_participant_id AS id_eval_participant,
    reference_type,
    comments AS comment_summary,
    role_type_code AS role_type,
    created_by,
    last_updated_by AS updated_by,
    comment_text AS text_comments,
    justification_text AS text_justification,
    justification AS action_justification,
    review_points,
    calculated_rating,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_eval_ratings
