SELECT
  business_group_id AS id_business_group,
  contact_person_id AS id_contact_person,
  contact_relationship_id AS id_contact_relationship,
  person_id AS id_person,
  contact_type,
  legislation_code,
  created_by,
  last_updated_by AS updated_by,
  dependent_flag = 'Y' AS is_dependent,
  emergency_contact_flag = 'Y' AS is_emergency_contact,
  personal_flag = 'Y' AS is_personal,
  primary_contact_flag = 'Y' AS is_primary_contact,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_contact_relships_f
