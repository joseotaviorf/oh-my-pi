WITH
distinct_calibrations AS (
  SELECT DISTINCT
    person_number,
    id_meeting
  FROM
    datalake_performance.performa_calibration_evaluation
  WHERE
    person_number IS NOT NULL
    AND id_meeting IS NOT NULL
  UNION DISTINCT
  SELECT DISTINCT
    person_number,
    id_meeting
  FROM
    datalake_performance.performa_calibration_extra_info
  WHERE
    person_number IS NOT NULL
    AND id_meeting IS NOT NULL
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
),
calibration_rows AS (
  SELECT
    dpc.sk_performance_calibration_version AS sk_performance_calibration_version,
    dpc.sk_performance_calibration AS sk_performance_calibration,
    MD5(CONCAT(
      cs.behavior_calibration_variation,
      cs.impact_calibration_variation,
      cs.leadership_calibration_variation
    )) AS sk_performance_variation,
    dcm.sk_meeting AS sk_committee_meeting,
    dc.person_number,
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
      WHEN cs.performa_score_numeric BETWEEN 70 AND 89 THEN 'Partially misses expectations'
      WHEN cs.performa_score_numeric BETWEEN 90 AND 109 THEN 'Meets expectations'
      WHEN cs.performa_score_numeric BETWEEN 110 AND 137 THEN 'Above expectations'
      WHEN cs.performa_score_numeric BETWEEN 138 AND 150 THEN 'Outstanding'
    END AS performa_score,
    CASE
      WHEN cs.performa_score_numeric < 70 THEN 0.00
      WHEN cs.performa_score_numeric BETWEEN 70 AND 89 THEN 0.70
      WHEN cs.performa_score_numeric BETWEEN 90 AND 109 THEN 1.00
      WHEN cs.performa_score_numeric BETWEEN 110 AND 137 THEN 1.20
      WHEN cs.performa_score_numeric BETWEEN 138 AND 150 THEN 1.50
      ELSE NULL
    END AS performa_ipa,
    dc.id_meeting,
    CASE
      WHEN cs.performa_score_numeric IS NOT NULL THEN 1
      ELSE 0
    END AS _has_performa_score,
    dcm.ts_meeting AS _committee_ts_meeting,
    dcm.meeting_year AS _committee_meeting_year
  FROM
    distinct_calibrations AS dc
  LEFT JOIN
    dw_performance.dim_performance_calibration AS dpc
      ON dc.person_number = dpc.person_number
      AND dpc.sk_performance_calibration = MD5(CONCAT(
        CAST(dc.person_number AS STRING),
        CAST(dc.id_meeting AS STRING)
      ))
      AND dpc.is_current = TRUE
  LEFT JOIN
    dw_performance.dim_committee_meeting AS dcm
      ON dc.id_meeting = dcm.sk_meeting
  LEFT JOIN
    calibrations_score AS cs
      ON cs.sk_performance_calibration_version = dpc.sk_performance_calibration_version
),
ranked AS (
  SELECT
    cr.sk_performance_calibration_version,
    cr.sk_performance_calibration,
    cr.sk_performance_variation,
    cr.sk_committee_meeting,
    cr.person_number,
    cr.calibrated_behavior_description,
    cr.calibrated_impact_description,
    cr.calibrated_leadership_description,
    cr.pre_calibration_behavior_description,
    cr.pre_calibration_impact_description,
    cr.pre_calibration_leadership_description,
    cr.calibrated_behavior_numeric,
    cr.calibrated_impact_numeric,
    cr.calibrated_leadership_numeric,
    cr.pre_calibration_behavior_numeric,
    cr.pre_calibration_impact_numeric,
    cr.pre_calibration_leadership_numeric,
    cr.performa_score_numeric,
    cr.performa_score,
    cr.performa_ipa,
    ROW_NUMBER() OVER (
      PARTITION BY
        cr.person_number,
        COALESCE(
          CAST(cr._committee_meeting_year AS STRING),
          CAST(cr.id_meeting AS STRING)
        )
      ORDER BY
        cr._has_performa_score DESC,
        cr._committee_ts_meeting DESC NULLS LAST,
        CAST(cr.id_meeting AS STRING) DESC
    ) AS _rn
  FROM
    calibration_rows AS cr
)
SELECT
  sk_performance_calibration_version,
  sk_performance_calibration,
  sk_performance_variation,
  sk_committee_meeting,
  person_number,
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
  performa_score_numeric,
  performa_score,
  performa_ipa,
  NOW() AS ts_load
FROM
  ranked
WHERE
  _rn = 1
