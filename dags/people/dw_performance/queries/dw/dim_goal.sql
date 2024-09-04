WITH
associatedGoalPlans_step1 AS (
  SELECT
    id_goal,
    EXPLODE(associated_goal_plans) AS associated_goal_plans
  FROM datalake_hr_system_clean.performance_goals
),
associatedGoalPlans_cte as (
  SELECT
    a.id_goal,
    a.associated_goal_plans.TargetGoalPlanId,
    a.associated_goal_plans.GoalPlanGoalId,
    a.associated_goal_plans.ReviewPeriodId,
    a.associated_goal_plans.TargetReviewPeriod,
    a.associated_goal_plans.TargetAssignmentId,
    a.associated_goal_plans.PriorityMeaning,
    a.associated_goal_plans.Weight,
    a.associated_goal_plans.ReviewPeriod,
    a.associated_goal_plans.Priority,
    a.associated_goal_plans.GoalPlanName,
    a.associated_goal_plans.ReviewPeriodName,
    a.associated_goal_plans.GoalPlanId
  FROM
    associatedGoalPlans_step1 AS a
)
SELECT
  pg.id_goal AS sk_goal,
  pg.id_assignment AS sk_assignment,
  replace(pg.dt_start, '-', '') AS sk_started_date,
  replace(pg.dt_target_completion, '-', '') AS sk_target_completion_date,
  pg.goal_name AS goal_name,
  ag.priority,
  ag.weight

FROM datalake_hr_system_clean.performance_goals AS pg
LEFT JOIN associatedGoalPlans_cte AS ag ON pg.id_goal = ag.id_goal
