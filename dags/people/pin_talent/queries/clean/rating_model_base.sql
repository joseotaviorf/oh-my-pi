SELECT
  business_group_id AS id_business_group,
  rating_model_id AS id_rating_model,
  module_id AS id_module,
  rating_model_code,
  created_by,
  last_updated_by AS updated_by,
  seed_data_source,
  CAST(rating_level_count AS INT) AS rating_level_count,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(date_from) AS dt_started,
  TO_DATE(date_to) AS dt_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_rating_models_b
