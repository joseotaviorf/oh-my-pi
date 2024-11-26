SELECT
    assignment_supervisor_id AS id_assignment_supervisor,
    assignment_id AS id_assignment,
    business_group_id AS id_business_group,
    person_id AS id_person,
    manager_assignment_id AS id_manager_assignment,
    manager_id AS id_manager,
    action_occurrence_id AS id_action_occurrence,
    manager_type AS type_manager,
    created_by,
    last_updated_by,
    object_version_number AS version_number,
    primary_flag AS is_primary,
    working_percentage AS percentage_working,
    effective_start_date AS dt_effective_start,
    effective_end_date AS dt_effective_end,
    creation_date AS dt_created,
    last_update_date AS dt_last_updated,
    freeze_start_date AS dt_freeze_started,
    freeze_until_date AS dt_freeze_ended,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.per_assignment_supervisors_f
