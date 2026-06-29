WITH
evaluations_with_version AS (
  SELECT
    assignment_number,
    manager_assignment_number,
    cycle_name,
    dt_evaluation_occurred,
    evaluation_type,
    description_behavior,
    description_impact,
    description_leadership,
    open_evaluation,
    numeric_behavior,
    numeric_impact,
    numeric_leadership,
    ROW_NUMBER() OVER (
      PARTITION BY cycle_name, assignment_number, evaluation_type
      ORDER BY dt_evaluation_occurred
    ) AS evaluation_version,
    dt_evaluation_occurred AS dt_valid_from,
    COALESCE(
      LEAD(dt_evaluation_occurred) OVER (
        PARTITION BY cycle_name, assignment_number, evaluation_type
        ORDER BY dt_evaluation_occurred
      ) - INTERVAL '1 DAY',
      DATE('9999-12-31')
    ) AS dt_valid_to
  FROM
    datalake_pin.performance_evaluation
  WHERE
    cycle_name IS NOT NULL
)
SELECT
  MD5(CONCAT(
    CAST(assignment_number AS STRING),
    evaluation_type,
    CAST(dt_valid_from AS STRING),
    COALESCE(cycle_name, '-1')
  )) AS sk_performance_evaluation_version,
  MD5(CONCAT(
    CAST(assignment_number AS STRING),
    evaluation_type,
    COALESCE(cycle_name, '-1')
  )) AS sk_performance_evaluation,
  assignment_number,
  manager_assignment_number,
  cycle_name,
  evaluation_type,
  evaluation_version,
  description_behavior,
  description_impact,
  description_leadership,
  open_evaluation,
  numeric_behavior,
  numeric_impact,
  numeric_leadership,
  (
    dt_valid_from <= DATE('{load_start_date}')
    AND dt_valid_to >= DATE('{load_start_date}')
  ) AS is_current,
  dt_valid_from,
  dt_valid_to,
  NOW() AS ts_load
FROM
  evaluations_with_version
