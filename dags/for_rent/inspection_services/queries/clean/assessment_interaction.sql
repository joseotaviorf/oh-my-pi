SELECT
    id AS id_assessment_interaction,
    assessment_id AS id_assessment,
    user_id AS id_user,
    interaction_type,
    user_type,
    flow_type,
    error_detail,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.assessment_interaction
