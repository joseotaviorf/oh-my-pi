SELECT
  business_group_id AS id_business_group,
  person_id AS id_person,
  disability_id AS id_disability,
  disability_code,
  category,
  created_by,
  last_updated_by,
  quota_fte,
  status,
  TRIM(description) AS disability_description,
  TRIM(work_restriction) AS work_restriction,
  TRIM(accommodation_request) AS accommodation_request,
  TRIM(attribute2) AS clinical_classification_code,
  TRIM(attribute1) AS documented_subclassification,
  legislation_code,
  CAST(object_version_number AS INT) AS object_version_number,
  COALESCE(
    NULLIF(TO_DATE(effective_end_date), DATE('4712-12-31')),
    DATE('9999-12-31')
  ) AS dt_effective_ended,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_disabilities_f
