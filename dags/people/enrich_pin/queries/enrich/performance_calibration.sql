WITH
ratings AS (
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
    e.id_evaluation,
    rlt.id_rating_level,
    ptst.section_name,
    rlt.rating_description,
    CASE
      WHEN ptst.section_name = 'Liderança de Pessoas' 
      THEN 'Leadership'
      WHEN ptst.section_name = 'Aderência aos comportamentos esperados' 
      THEN 'Behavior'
      WHEN ptst.section_name = 'Impacto' 
      THEN 'Impact'
      ELSE NULL
    END AS calibrated_section_name,
    rlb.numeric_rating
  FROM
    datalake_pin_performance_clean.evaluation AS e
  INNER JOIN
    datalake_pin_talent_clean.profile_base AS pb
      ON e.id_person = pb.id_person
  INNER JOIN
    datalake_pin_talent_clean.review_period_base AS rpb
      ON e.id_review_period = rpb.id_review_period
  INNER JOIN
    datalake_pin_talent_clean.profile_item AS pi
      ON pb.id_profile = pi.id_profile
  INNER JOIN
    datalake_pin_talent_clean.profile_type_sections_translation AS ptst
      ON pi.id_section = ptst.id_section
  INNER JOIN
    datalake_pin_talent_clean.rating_level_base AS rlb
      ON pi.id_rating_level = rlb.id_rating_level
  INNER JOIN
    datalake_pin_talent_clean.rating_level_translation AS rlt
      ON rlb.id_rating_level = rlt.id_rating_level
  WHERE 
    YEAR(pi.ts_started) = YEAR(rpb.dt_ended)
    AND pi.alternative_source_key_1 IS NOT NULL
    AND ptst.language = 'US'
    AND ptst.source_language = 'US'
    AND ptst.section_name IN (
      'People Leadership', 
      'Adherence to expected behaviours', 
      'Impact'
    )
    AND rlt.language = 'US'
    AND rlt.source_language = 'US'
  QUALIFY 
    ROW_NUMBER() OVER (
      PARTITION BY pi.id_profile, pi.id_section, rpb.dt_ended
      ORDER BY pi.ts_started DESC
    ) = 1 
)

SELECT
  e.id_assignment,
  employees.id_period_of_service,
  es.id_evaluation,
  es.id_eval_section,
  rw.id_rating_level AS id_rating_level_from_self,
  rm.id_rating_level AS id_rating_level_from_manager,
  rc.id_rating_level AS id_rating_level_from_calibration,
  employees.assignment_number,
  CASE 
      WHEN hsdvl.name ILIKE '%Leadership%' THEN 'Leadership'
      WHEN hsdvl.name ILIKE '%Impact%' THEN 'Impact'
      WHEN hsdvl.name ILIKE '%Behavi%' THEN 'Behavior'
  END AS section_name,
  rw.rating_description AS rating_description_from_self,
  rm.rating_description AS rating_description_from_manager,
  rc.rating_description AS rating_description_from_calibration,
  rw.numeric_rating AS numeric_rating_from_self,
  rm.numeric_rating AS numeric_rating_from_manager,
  rc.numeric_rating AS numeric_rating_from_calibration,
  e.dt_evaluation_occurred,
  e.dt_performance_document_started,
  e.dt_performance_document_ended,
  NOW() AS ts_load,
  YEAR(e.dt_performance_document_started) AS year,
  MONTH(e.dt_performance_document_started) AS month,
  YEAR(e.dt_performance_document_started) AS day
FROM
  datalake_pin_performance_clean.evaluation AS e
INNER JOIN 
  datalake_hr_system.employee_ids AS employees 
    ON employees.id_assignment = e.id_assignment
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
LEFT JOIN
  ratings AS rw
    ON ei.id_eval_item = rw.id_reference
    AND rw.role_type = 'WORKER'
LEFT JOIN
  ratings AS rm
    ON ei.id_eval_item = rm.id_reference
    AND rm.role_type = 'MANAGER'
LEFT JOIN
  calibrated_ratings AS rc
    ON es.id_evaluation = rc.id_evaluation
    AND CASE 
      WHEN hsdvl.name ILIKE '%Leadership%' THEN 'Leadership'
      WHEN hsdvl.name ILIKE '%Impact%' THEN 'Impact'
      WHEN hsdvl.name ILIKE '%Behavi%' THEN 'Behavior'
    END = rc.section_name
WHERE 
  hsdvl.language = 'US'
