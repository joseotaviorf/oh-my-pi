SELECT
  business_group_id AS id_business_group,
  rating_level_id AS id_rating_level,
  language,
  source_lang AS source_language,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  rating_description,
  rating_short_descr AS rating_short_description,
  review_rating_descr AS review_rating_description,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_rating_levels_tl;
