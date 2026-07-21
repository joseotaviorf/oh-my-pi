SELECT
  business_group_id AS id_business_group,
  review_period_id AS id_review_period,
  created_by,
  last_updated_by AS updated_by,
  status_code,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(start_date) AS dt_started,
  COALESCE(NULLIF(TO_DATE(end_date), DATE('4712-12-31')), DATE('9999-12-31')) AS dt_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_talent_raw.hrt_review_periods_b
