WITH
ratings_worker_manager AS (
  SELECT
    er.id_reference,
    rlt.id_rating_level,
    rlt.rating_description,
    er.role_type,
    rlb.numeric_rating
  FROM
    datalake_pin_performance_clean.evaluation_rating AS er
  INNER JOIN
    datalake_pin_talent_clean.rating_level_translation AS rlt
      ON er.id_performance_rating = rlt.id_rating_level
  INNER JOIN
    datalake_pin_talent_clean.rating_level_base AS rlb
      ON rlt.id_rating_level = rlb.id_rating_level
  WHERE
    er.reference_type = 'ITEM'
    AND er.role_type IN ('WORKER', 'MANAGER')
    AND rlt.language = 'US'
),
base_evaluations AS (
  SELECT
    e.id_assignment,
    e.id_manager_assignment,
    e.id_evaluation,
    e.dt_performance_document_started,
    e.dt_performance_document_ended,
    e.dt_evaluation_occurred,
    e.ts_created,
    e.ts_updated,
    es.id_eval_section,
    ei.id_eval_item,
    CASE
        WHEN hsdvl.name ILIKE '%Leadership%' THEN 'Leadership'
        WHEN hsdvl.name ILIKE '%Impact%' THEN 'Impact'
        WHEN hsdvl.name ILIKE '%Behavi%' THEN 'Behavior'
    END AS section_name
  FROM
    datalake_pin_performance_clean.evaluation AS e
  INNER JOIN
    datalake_pin_performance_clean.evaluation_section AS es
      ON e.id_evaluation = es.id_evaluation
  INNER JOIN
    datalake_pin_performance_clean.template_section AS hts
      ON es.id_template_section = hts.id_section
  INNER JOIN
    datalake_pin_performance_clean.section_definition_translation AS hsdvl
      ON hts.id_section_definition = hsdvl.id_section_definition
  INNER JOIN
    datalake_pin_performance_clean.evaluation_item AS ei
      ON es.id_eval_section = ei.id_eval_section
  WHERE
    hsdvl.language = 'US'
),
evaluation_types AS (
  SELECT 'SELF' AS evaluation_type, 'WORKER' AS role_type
  UNION ALL
  SELECT 'MANAGER' AS evaluation_type, 'MANAGER' AS role_type
),
evaluations AS (
  SELECT
    base.id_assignment,
    employees.id_period_of_service,
    base.id_evaluation,
    employees.id_person,
    employees.assignment_number,
    managers.assignment_number AS manager_assignment_number,
    et.evaluation_type,
    MAX(IF(base.section_name = 'Impact', rwm.id_rating_level, NULL)) AS id_impact_rating_level,
    MAX(IF(base.section_name = 'Leadership', rwm.id_rating_level, NULL)) AS id_leadership_rating_level,
    MAX(IF(base.section_name = 'Behavior', rwm.id_rating_level, NULL)) AS id_behavior_rating_level,
    MAX(rpt.review_period_name) AS cycle_name,
    MAX(IF(base.section_name = 'Impact', COALESCE(rwm.rating_description, '-1'), NULL)) AS description_impact,
    MAX(IF(base.section_name = 'Leadership', COALESCE(rwm.rating_description, '-1'), NULL)) AS description_leadership,
    MAX(IF(base.section_name = 'Behavior', COALESCE(rwm.rating_description, '-1'), NULL)) AS description_behavior,
    MAX(IF(base.section_name = 'Impact', rwm.numeric_rating, NULL)) AS numeric_impact,
    MAX(IF(base.section_name = 'Leadership', rwm.numeric_rating, NULL)) AS numeric_leadership,
    MAX(IF(base.section_name = 'Behavior', rwm.numeric_rating, NULL)) AS numeric_behavior,
    base.dt_evaluation_occurred,
    base.dt_performance_document_started,
    base.dt_performance_document_ended,
    base.ts_created,
    base.ts_updated,
    YEAR(base.dt_performance_document_started) AS year,
    MONTH(base.dt_performance_document_started) AS month,
    DAY(base.dt_performance_document_started) AS day
  FROM
    base_evaluations AS base
  INNER JOIN
    datalake_employee_registration.identifier_mapping AS employees
      ON employees.id_assignment = base.id_assignment
  INNER JOIN
    datalake_employee_registration.identifier_mapping AS managers
      ON managers.id_assignment = base.id_manager_assignment
  CROSS JOIN
    evaluation_types AS et
  LEFT JOIN
    ratings_worker_manager AS rwm
      ON base.id_eval_item = rwm.id_reference
      AND rwm.role_type = et.role_type
  LEFT JOIN
    datalake_pin_talent_clean.review_period_base AS rpb
      ON base.dt_performance_document_started BETWEEN rpb.dt_started AND rpb.dt_ended
  LEFT JOIN
    datalake_pin_talent_clean.review_period_translation AS rpt
      ON rpb.id_review_period = rpt.id_review_period
      AND rpt.language = 'US'
  WHERE
    rwm.id_reference IS NOT NULL
  GROUP BY
    base.id_assignment,
    employees.id_period_of_service,
    base.id_evaluation,
    employees.id_person,
    employees.assignment_number,
    managers.assignment_number,
    et.evaluation_type,
    base.dt_evaluation_occurred,
    base.dt_performance_document_started,
    base.dt_performance_document_ended,
    base.ts_created,
    base.ts_updated
)
SELECT
  MD5(CONCAT(
    COALESCE(description_behavior, '-1'),
    COALESCE(description_impact, '-1'),
    COALESCE(description_leadership, '-1')
  )) AS id_performance_rating,
  id_assignment,
  id_period_of_service,
  id_evaluation,
  id_person,
  assignment_number,
  manager_assignment_number,
  id_impact_rating_level,
  id_leadership_rating_level,
  id_behavior_rating_level,
  cycle_name,
  evaluation_type,
  description_impact,
  description_leadership,
  description_behavior,
  numeric_impact,
  numeric_leadership,
  numeric_behavior,
  dt_evaluation_occurred,
  dt_performance_document_started,
  dt_performance_document_ended,
  ts_created,
  ts_updated,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  evaluations
