SELECT
  GoalId AS id_goal,
  PersonId AS id_person,
  PersonNumber AS person_number,
  AssignmentId AS id_assignment,
  GoalName AS goal_name,
  description,
  associatedGoalPlans AS associated_goal_plans,
  status,
  StatusMeaning AS status_meaning,
  FLOAT(PercentComplete) AS percent_complete,
  to_date(StartDate) AS dt_start,
  to_date(TargetCompletionDate) AS dt_target_completion,
  ts_load
FROM datalake_hr_system_raw.performance_goals
