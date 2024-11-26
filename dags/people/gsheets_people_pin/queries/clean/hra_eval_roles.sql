SELECT
    eval_role_id AS id_eval_role,
    business_group_id AS id_business_group,
    evaluation_id AS id_evaluation,
    tmpl_role_id AS id_template_role,
    role_type_code AS role_type,
    created_by,
    last_updated_by AS updated_by,
    minimum_num_pcpns AS min_participants,
    maximum_num_pcpns AS max_participants,
    matrix_participant_flag AS is_matrix_participant,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_eval_roles
