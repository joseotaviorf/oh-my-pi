SELECT
  absence_type_id AS id_absence_type,
  enterprise_id AS id_enterprise,
  name,
  created_by,
  last_updated_by AS updated_by,
  language,
  source_lang AS source_language,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  TO_DATE(effective_start_date) AS dt_effective_started,
  TO_DATE(effective_end_date) AS dt_effective_ended,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_absence_raw.anc_absence_types_f_tl