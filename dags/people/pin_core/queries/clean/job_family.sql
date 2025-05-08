SELECT
  business_group_id AS id_business_group,
  action_occurrence_id AS id_action_occurrence,
  job_family_id AS id_job_family,
  job_family_code,
  created_by,
  last_updated_by AS updated_by,
  active_status,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_job_family_f
