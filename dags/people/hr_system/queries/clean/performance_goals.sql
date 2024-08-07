WITH goal_plans_cte AS (
  SELECT
    GoalId,
    explode(associatedGoalPlans) AS associatedGoalPlans
  FROM
    datalake_hr_system_raw.performance_goals
)

SELECT
  pg.GoalId AS id_goal,
  pg.PersonId AS id_person,
  gp.associatedGoalPlans.GoalPlanGoalId AS id_Goal_Plan_Goal,
  gp.associatedGoalPlans.ReviewPeriodId AS id_Review_Period,
  gp.associatedGoalPlans.GoalPlanId AS id_Goal_Plan,
  pg.AssignmentId AS id_assignment,
  pg.PersonNumber AS person_number,
  pg.GoalName AS goal_name,
  pg.description,
  pg.associatedGoalPlans AS associated_goal_plans,
  gp.associatedGoalPlans.PriorityMeaning AS Priority_Meaning,
  gp.associatedGoalPlans.ReviewPeriod AS Review_Period,
  gp.associatedGoalPlans.Priority AS Priority,
  gp.associatedGoalPlans.GoalPlanName AS Goal_Plan_Name,
  gp.associatedGoalPlans.ReviewPeriodName AS Review_Period_Name,
  pg.status,
  pg.StatusMeaning AS status_meaning,
  gp.associatedGoalPlans.Weight AS Weight,
  FLOAT(pg.PercentComplete) AS percent_complete,
  to_date(pg.StartDate) AS dt_start,
  to_date(pg.TargetCompletionDate) AS dt_target_completion,
  pg.ts_load
FROM
  datalake_hr_system_raw.performance_goals AS pg
LEFT JOIN
  goal_plans_cte gp
    ON pg.GoalId = pg.GoalId
