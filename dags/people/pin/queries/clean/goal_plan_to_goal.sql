SELECT
  business_group_id AS id_business_group,
  assignment_id AS id_assignment,
  goal_id AS id_goal,
  goal_plan_goal_id AS id_goal_plan_to_goal,
  goal_plan_id AS id_goal_plan,
  review_period_id AS id_review_period,
  priority_code,
  CAST(weighting AS DECIMAL) AS goal_weight,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_goal_raw.hrg_goal_plan_goals
