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
calibrated_ratings AS (
  SELECT
    er.id_reference,
    rlt.id_rating_level,
    rlt.rating_description,
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
    AND rlt.language = 'US'
),
base_evaluations AS (
  SELECT
    e.id_assignment,
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
complete_cycle AS (
  SELECT
    base.id_assignment,
    employees.id_period_of_service,
    base.id_evaluation,
    employees.id_person,
    employees.assignment_number,
    MAX(IF(base.section_name = 'Impact', rw.id_rating_level, NULL)) AS id_impact_rating_level_from_self,
    MAX(IF(base.section_name = 'Impact', rm.id_rating_level, NULL)) AS id_impact_rating_level_from_manager,
    MAX(IF(base.section_name = 'Impact', rc.id_rating_level, NULL)) AS id_impact_rating_level_from_calibration,
    MAX(IF(base.section_name = 'Leadership', rw.id_rating_level, NULL)) AS id_leadership_rating_level_from_self,
    MAX(IF(base.section_name = 'Leadership', rm.id_rating_level, NULL)) AS id_leadership_rating_level_from_manager,
    MAX(IF(base.section_name = 'Leadership', rc.id_rating_level, NULL)) AS id_leadership_rating_level_from_calibration,
    MAX(IF(base.section_name = 'Behavior', rw.id_rating_level, NULL)) AS id_behavior_rating_level_from_self,
    MAX(IF(base.section_name = 'Behavior', rm.id_rating_level, NULL)) AS id_behavior_rating_level_from_manager,
    MAX(IF(base.section_name = 'Behavior', rc.id_rating_level, NULL)) AS id_behavior_rating_level_from_calibration,
    MAX(rpt.review_period_name) AS cycle_name,
    MAX(IF(base.section_name = 'Impact', COALESCE(rw.rating_description, '-1'), NULL)) AS description_impact_from_self,
    MAX(IF(base.section_name = 'Impact', COALESCE(rm.rating_description, '-1'), NULL)) AS description_impact_from_manager,
    MAX(IF(base.section_name = 'Impact', COALESCE(rc.rating_description, '-1'), NULL)) AS description_impact_from_calibration,
    MAX(IF(base.section_name = 'Leadership', COALESCE(rw.rating_description, '-1'), NULL)) AS description_leadership_from_self,
    MAX(IF(base.section_name = 'Leadership', COALESCE(rm.rating_description, '-1'), NULL)) AS description_leadership_from_manager,
    MAX(IF(base.section_name = 'Leadership', COALESCE(rc.rating_description, '-1'), NULL)) AS description_leadership_from_calibration,
    MAX(IF(base.section_name = 'Behavior', COALESCE(rw.rating_description, '-1'), NULL)) AS description_behavior_from_self,
    MAX(IF(base.section_name = 'Behavior', COALESCE(rm.rating_description, '-1'), NULL)) AS description_behavior_from_manager,
    MAX(IF(base.section_name = 'Behavior', COALESCE(rc.rating_description, '-1'), NULL)) AS description_behavior_from_calibration,
    MAX(IF(base.section_name = 'Impact', rw.numeric_rating, NULL)) AS numeric_impact_from_self,
    MAX(IF(base.section_name = 'Impact', rm.numeric_rating, NULL)) AS numeric_impact_from_manager,
    MAX(IF(base.section_name = 'Impact', rc.numeric_rating, NULL)) AS numeric_impact_from_calibration,
    MAX(IF(base.section_name = 'Leadership', rw.numeric_rating, NULL)) AS numeric_leadership_from_self,
    MAX(IF(base.section_name = 'Leadership', rm.numeric_rating, NULL)) AS numeric_leadership_from_manager,
    MAX(IF(base.section_name = 'Leadership', rc.numeric_rating, NULL)) AS numeric_leadership_from_calibration,
    MAX(IF(base.section_name = 'Behavior', rw.numeric_rating, NULL)) AS numeric_behavior_from_self,
    MAX(IF(base.section_name = 'Behavior', rm.numeric_rating, NULL)) AS numeric_behavior_from_manager,
    MAX(IF(base.section_name = 'Behavior', rc.numeric_rating, NULL)) AS numeric_behavior_from_calibration,
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
  LEFT JOIN
    ratings_worker_manager AS rw
      ON base.id_eval_item = rw.id_reference
      AND rw.role_type = 'WORKER'
  LEFT JOIN
    ratings_worker_manager AS rm
      ON base.id_eval_item = rm.id_reference
      AND rm.role_type = 'MANAGER'
  LEFT JOIN
    calibrated_ratings AS rc
      ON base.id_eval_item = rc.id_reference
  LEFT JOIN
    datalake_pin_talent_clean.review_period_base AS rpb
      ON base.dt_performance_document_started BETWEEN rpb.dt_started AND rpb.dt_ended
  LEFT JOIN
    datalake_pin_talent_clean.review_period_translation AS rpt
      ON rpb.id_review_period = rpt.id_review_period
      AND rpt.language = 'US'
  GROUP BY
    base.id_assignment,
    employees.id_period_of_service,
    base.id_evaluation,
    employees.id_person,
    employees.assignment_number,
    base.dt_evaluation_occurred,
    base.dt_performance_document_started,
    base.dt_performance_document_ended,
    base.ts_created,
    base.ts_updated
)

SELECT
  MD5(CONCAT(
    COALESCE(description_behavior_from_manager, '-1'),
    COALESCE(description_impact_from_manager, '-1'),
    COALESCE(description_leadership_from_manager, '-1')
  )) AS id_performance_rating_from_manager,
  MD5(CONCAT(
    COALESCE(description_behavior_from_calibration, '-1'),
    COALESCE(description_impact_from_calibration, '-1'),
    COALESCE(description_leadership_from_calibration, '-1')
  )) AS id_performance_rating_from_calibration,
  MD5(CONCAT(
    COALESCE(description_behavior_from_self, '-1'),
    COALESCE(description_impact_from_self, '-1'),
    COALESCE(description_leadership_from_self, '-1')
  )) AS id_performance_rating_from_self,
  id_assignment,
  id_period_of_service,
  id_evaluation,
  id_person,
  assignment_number,
  id_impact_rating_level_from_self,
  id_impact_rating_level_from_manager,
  id_impact_rating_level_from_calibration,
  id_leadership_rating_level_from_self,
  id_leadership_rating_level_from_manager,
  id_leadership_rating_level_from_calibration,
  id_behavior_rating_level_from_self,
  id_behavior_rating_level_from_manager,
  id_behavior_rating_level_from_calibration,
  cycle_name,
  description_impact_from_self,
  description_impact_from_manager,
  description_impact_from_calibration,
  description_leadership_from_self,
  description_leadership_from_manager,
  description_leadership_from_calibration,
  description_behavior_from_self,
  description_behavior_from_manager,
  description_behavior_from_calibration,
  numeric_impact_from_self,
  numeric_impact_from_manager,
  numeric_impact_from_calibration,
  numeric_leadership_from_self,
  numeric_leadership_from_manager,
  numeric_leadership_from_calibration,
  numeric_behavior_from_self,
  numeric_behavior_from_manager,
  numeric_behavior_from_calibration,
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
  complete_cycle
