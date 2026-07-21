SELECT
  goal_plan_id AS id_goal_plan,
  business_group_id AS id_business_group,
  language,
  source_lang AS source_language,
  goal_plan_name,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_goal_raw.hrg_goal_plans_tl