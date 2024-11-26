SELECT
    tmpl_role_id AS id_template_role,
    business_group_id AS id_business_group,
    template_defn_id AS id_template_definition,
    role_id AS id_role,
    module_id AS id_module,
    role_type_code AS role_type,
    created_by,
    last_updated_by AS updated_by,
    minimum_num_pcpns AS min_participants,
    maximum_num_pcpns AS max_participants,
    object_version_number AS version_number,
    matrix_participant_flag AS is_matrix_participant,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_tmpl_roles
