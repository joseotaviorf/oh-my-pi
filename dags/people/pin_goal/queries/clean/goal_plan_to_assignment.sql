SELECT
  business_group_id AS id_business_group,
  assignment_id AS id_assignment,
  goal_plan_id AS id_goal_plan,
  review_period_id AS id_review_period,
  person_id AS id_person,
  status,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  TO_DATE(goal_plan_start_date) AS dt_goal_plan_started,
  TO_DATE(goal_plan_end_date) AS dt_goal_plan_ended,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_pin_goal_raw.hrg_goal_pln_assignments
