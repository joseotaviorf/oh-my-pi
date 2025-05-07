SELECT
  business_group_id AS id_business_group,
  rating_level_id AS id_rating_level,
  rating_model_id AS id_rating_model,
  created_by,
  last_updated_by AS updated_by,
  rating_level_code,
  CAST(numeric_rating AS FLOAT) AS numeric_rating,
  CAST(star_rating AS FLOAT) AS star_rating,
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
  datalake_pin_talent_raw.hrt_rating_levels_b
