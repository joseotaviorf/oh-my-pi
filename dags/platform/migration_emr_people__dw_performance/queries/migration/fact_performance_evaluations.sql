WITH
distinct_cycles AS (
  SELECT DISTINCT
    cycle_name,
    assignment_number
  FROM
    datalake_performance.performance_evaluation
  WHERE
    cycle_name IS NOT NULL
)
SELECT
  dpe_manager.sk_performance_evaluation_version AS sk_performance_evaluation_manager_version,
  dpe_self.sk_performance_evaluation_version AS sk_performance_evaluation_self_version,
  dpe_manager.sk_performance_evaluation AS sk_performance_evaluation_manager,
  dpe_self.sk_performance_evaluation AS sk_performance_evaluation_self,
  dc.assignment_number,
  dc.cycle_name,
  dpe_self.description_behavior AS behavior_self,
  dpe_self.description_impact AS impact_self,
  dpe_self.description_leadership AS leadership_self,
  dpe_manager.description_behavior AS behavior_manager,
  dpe_manager.description_impact AS impact_manager,
  dpe_manager.description_leadership AS leadership_manager,
  dpe_self.numeric_behavior AS numeric_behavior_self,
  dpe_self.numeric_impact AS numeric_impact_self,
  dpe_self.numeric_leadership AS numeric_leadership_self,
  dpe_manager.numeric_behavior AS numeric_behavior_manager,
  dpe_manager.numeric_impact AS numeric_impact_manager,
  dpe_manager.numeric_leadership AS numeric_leadership_manager,
  NOW() AS ts_load
FROM
  distinct_cycles AS dc
LEFT JOIN
  dw_performance.dim_performance_evaluation AS dpe_manager
    ON dc.cycle_name = dpe_manager.cycle_name
    AND dc.assignment_number = dpe_manager.assignment_number
    AND dpe_manager.evaluation_type = 'MANAGER'
    AND dpe_manager.is_current = TRUE
LEFT JOIN
  dw_performance.dim_performance_evaluation AS dpe_self
    ON dc.cycle_name = dpe_self.cycle_name
    AND dc.assignment_number = dpe_self.assignment_number
    AND dpe_self.evaluation_type = 'SELF'
    AND dpe_self.is_current = TRUE
