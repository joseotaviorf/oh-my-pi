SELECT
  action_occurrence_id AS id_action_occurrence,
  assignment_id AS id_assignment,
  assignment_supervisor_id AS id_assignment_supervisor,
  business_group_id AS id_business_group,
  person_id AS id_person,
  manager_assignment_id AS id_manager_assignment,
  manager_id AS id_manager,
  created_by,
  last_updated_by AS updated_by,
  manager_type,
  primary_flag = 'Y' AS is_primary,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(freeze_start_date) AS dt_freeze_started,
  TO_DATE(freeze_until_date) AS dt_freeze_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_assignment_supervisors_f
