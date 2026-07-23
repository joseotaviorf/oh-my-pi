WITH
all_evaluations AS (
  SELECT
    'calibration_evaluation' AS source_type,
    CAST(id_calibration_evaluation AS STRING) AS id_source_record,
    person_number,
    id_meeting,
    calibrated_behavior_description,
    calibrated_behavior_numeric,
    pre_calibration_behavior_description,
    pre_calibration_behavior_numeric,
    calibrated_impact_description,
    calibrated_impact_numeric,
    pre_calibration_impact_description,
    pre_calibration_impact_numeric,
    calibrated_leadership_description,
    calibrated_leadership_numeric,
    pre_calibration_leadership_description,
    pre_calibration_leadership_numeric,
    ts_meeting AS dt_evaluation
  FROM
    datalake_performance.performa_calibration_evaluation
  UNION ALL
  SELECT
    'extra_info' AS source_type,
    CAST(id_person_extra_info AS STRING) AS id_source_record,
    person_number,
    id_meeting,
    behavior_description AS calibrated_behavior_description,
    behavior_numeric AS calibrated_behavior_numeric,
    NULL AS pre_calibration_behavior_description,
    NULL AS pre_calibration_behavior_numeric,
    impact_description AS calibrated_impact_description,
    impact_numeric AS calibrated_impact_numeric,
    NULL AS pre_calibration_impact_description,
    NULL AS pre_calibration_impact_numeric,
    leadership_description AS calibrated_leadership_description,
    leadership_numeric AS calibrated_leadership_numeric,
    NULL AS pre_calibration_leadership_description,
    NULL AS pre_calibration_leadership_numeric,
    dt_evaluation
  FROM
    datalake_performance.performa_calibration_extra_info
),
calibrations_with_version AS (
  SELECT
    source_type,
    id_source_record,
    person_number,
    id_meeting,
    calibrated_behavior_description,
    calibrated_behavior_numeric,
    pre_calibration_behavior_description,
    pre_calibration_behavior_numeric,
    calibrated_impact_description,
    calibrated_impact_numeric,
    pre_calibration_impact_description,
    pre_calibration_impact_numeric,
    calibrated_leadership_description,
    calibrated_leadership_numeric,
    pre_calibration_leadership_description,
    pre_calibration_leadership_numeric,
    dt_evaluation,
    ROW_NUMBER() OVER (
      PARTITION BY
        person_number,
        id_meeting
      ORDER BY
        CASE source_type
          WHEN 'calibration_evaluation' THEN 1
          WHEN 'extra_info' THEN 2
        END,
        dt_evaluation DESC
    ) AS calibration_version
  FROM
    all_evaluations
  WHERE
    person_number IS NOT NULL
    AND id_meeting IS NOT NULL
)
SELECT
  MD5(CONCAT(
    CAST(person_number AS STRING),
    CAST(id_meeting AS STRING),
    CAST(calibration_version AS STRING)
  )) AS sk_performance_calibration_version,
  MD5(CONCAT(
    CAST(person_number AS STRING),
    CAST(id_meeting AS STRING)
  )) AS sk_performance_calibration,
  id_source_record,
  person_number,
  calibration_version,
  source_type,
  calibrated_behavior_description,
  calibrated_impact_description,
  calibrated_leadership_description,
  pre_calibration_behavior_description,
  pre_calibration_impact_description,
  pre_calibration_leadership_description,
  calibrated_behavior_numeric,
  calibrated_impact_numeric,
  calibrated_leadership_numeric,
  pre_calibration_behavior_numeric,
  pre_calibration_impact_numeric,
  pre_calibration_leadership_numeric,
  (calibration_version = 1) AS is_current,
  dt_evaluation,
  NOW() AS ts_load
FROM
  calibrations_with_version
