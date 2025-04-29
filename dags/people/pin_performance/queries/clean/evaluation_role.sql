SELECT
    eval_role_id AS id_evaluation_role,
    business_group_id AS id_business_group,
    evaluation_id AS id_evaluation,
    tmpl_role_id AS id_template_role,
    role_type_code AS role_type,
    created_by,
    last_updated_by AS updated_by,
    CAST(minimum_num_pcpns AS INT) AS min_participants,
    CAST(maximum_num_pcpns AS INT) AS max_participants,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_eval_roles
