SELECT
  national_identifier_id AS id_national_identifier,
  person_id AS id_person,
  business_group_id AS id_business_group,
  legislation_code,
  national_identifier_type,
  national_identifier_number,
  place_of_issue,
  attribute1 AS issuing_state,
  attribute2 AS issuing_authority,
  attribute_category,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(issue_date) AS dt_issue,
  TO_DATE(expiration_date) AS dt_expiration,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_core_raw.per_national_identifiers
