WITH
distinct_calibrations AS (
  SELECT DISTINCT
    person_number,
    meeting_year
  FROM
    datalake_pin.performa_calibration_evaluation
  WHERE
    person_number IS NOT NULL
    AND meeting_year IS NOT NULL
  UNION DISTINCT
  SELECT DISTINCT
    person_number,
    meeting_year
  FROM
    datalake_pin.performa_calibration_extra_info
  WHERE
    person_number IS NOT NULL
    AND meeting_year IS NOT NULL
),
calibrations_score AS (
  SELECT
    dpc.sk_performance_calibration_version,
    CASE
      WHEN dpc.calibrated_leadership_numeric IS NOT NULL
        THEN (0.6 * dpc.calibrated_impact_numeric) + (0.2 * dpc.calibrated_behavior_numeric) + (0.2 * dpc.calibrated_leadership_numeric)
      ELSE (0.6 * dpc.calibrated_impact_numeric) + (0.4 * dpc.calibrated_behavior_numeric)
    END AS performa_score_numeric,
    CASE 
      WHEN dpc.pre_calibration_behavior_numeric IS NULL THEN '-1'
      WHEN dpc.pre_calibration_behavior_numeric = dpc.calibrated_behavior_numeric THEN 'Maintained'
      WHEN dpc.pre_calibration_behavior_numeric < dpc.calibrated_behavior_numeric THEN 'Increased'
      ELSE 'Decreased'
    END AS behavior_calibration_variation,
    CASE 
      WHEN dpc.pre_calibration_impact_numeric IS NULL THEN '-1'
      WHEN dpc.pre_calibration_impact_numeric = dpc.calibrated_impact_numeric THEN 'Maintained'
      WHEN dpc.pre_calibration_impact_numeric < dpc.calibrated_impact_numeric THEN 'Increased'
      ELSE 'Decreased'
    END AS impact_calibration_variation,
    CASE 
      WHEN dpc.pre_calibration_leadership_numeric IS NULL THEN '-1'
      WHEN dpc.pre_calibration_leadership_numeric = dpc.calibrated_leadership_numeric THEN 'Maintained'
      WHEN dpc.pre_calibration_leadership_numeric < dpc.calibrated_leadership_numeric THEN 'Increased'
      ELSE 'Decreased'
    END AS leadership_calibration_variation
  FROM
    dw_performance.dim_performance_calibration AS dpc
)
SELECT
  dpc.sk_performance_calibration_version AS sk_performance_calibration_version,
  dpc.sk_performance_calibration AS sk_performance_calibration,
  MD5(CONCAT(
    cs.behavior_calibration_variation,
    cs.impact_calibration_variation,
    cs.leadership_calibration_variation
  )) AS sk_performance_variation,
  dpc.id_meeting,
  dc.person_number,
  dpc.meeting_status_code,
  dc.meeting_year,
  dpc.meeting_title,
  dpc.calibrated_behavior_description,
  dpc.calibrated_impact_description,
  dpc.calibrated_leadership_description,
  dpc.pre_calibration_behavior_description,
  dpc.pre_calibration_impact_description,
  dpc.pre_calibration_leadership_description,
  dpc.calibrated_behavior_numeric,
  dpc.calibrated_impact_numeric,
  dpc.calibrated_leadership_numeric,
  dpc.pre_calibration_behavior_numeric,
  dpc.pre_calibration_impact_numeric,
  dpc.pre_calibration_leadership_numeric,
  cs.performa_score_numeric,
  CASE
    WHEN cs.performa_score_numeric < 70 THEN 'Insufficient'
    WHEN cs.performa_score_numeric BETWEEN 70 AND 89 THEN 'Partially misses expecatations'
    WHEN cs.performa_score_numeric BETWEEN 90 AND 109 THEN 'Meets expectations'
    WHEN cs.performa_score_numeric BETWEEN 110 AND 137 THEN 'Above expectations'
    WHEN cs.performa_score_numeric BETWEEN 138 AND 150 THEN 'Outstanding'
  END AS performa_score,
  NOW() AS ts_load
FROM
  distinct_calibrations AS dc
LEFT JOIN
  dw_performance.dim_performance_calibration AS dpc
    ON dc.person_number = dpc.person_number
    AND dc.meeting_year = dpc.meeting_year
    AND dpc.is_current = TRUE
LEFT JOIN
  calibrations_score AS cs
    ON (cs.sk_performance_calibration_version = dpc.sk_performance_calibration_version)
