SELECT
  representative_assignment_id AS id_representative_assignment,
  representative_id AS id_representative,
  representative_person_id AS id_representative_person,
  responsibility_id AS id_responsibility,
  worker_assignment_id AS id_worker_assignment,
  worker_person_id AS id_worker_person,
  responsibility_type,
  created_by,
  last_updated_by AS updated_by,
  approvals_flag = 'Y' AS has_approval_responsibility,
  checklists_flag = 'Y' AS has_checklist_responsibility,
  work_contacts_flag = 'Y' AS has_inclusion_in_work_contacts,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  object_version_number,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_asg_representatives
