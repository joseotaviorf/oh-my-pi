SELECT
  organization_id AS id_organization,
  business_group_id AS id_business_group,
  organization_code,
  created_by,
  last_updated_by AS updated_by,
  name,
  internal_external_flag AS organization_scope,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  TO_TIMESTAMP(effective_start_date) AS ts_effective_started,
  TO_TIMESTAMP(effective_end_date) AS ts_effective_ended,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.hr_lookups