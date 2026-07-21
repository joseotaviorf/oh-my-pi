SELECT
  business_group_id AS id_business_group,
  rating_model_id AS id_rating_model,
  created_by,
  last_updated_by AS updated_by,
  last_update_login,
  language,
  source_lang AS source_language,
  rating_name AS rating_model_name,
  rating_description AS rating_model_description,
  seed_data_source,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_rating_models_tl;
