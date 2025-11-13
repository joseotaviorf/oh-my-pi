SELECT
  org_unit_classification_id AS id_organization_unit_classification,
  business_group_id AS id_business_group,
  action_occurrence_id AS id_action_occurrence,
  organization_id AS id_organization,
  set_id AS id_set,
  module_id AS id_module,
  classification_code,
  status,
  category_code,
  legislation_code,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  CURRENT_TIMESTAMP() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.hr_org_unit_classifications_f
