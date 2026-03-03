WITH rating_value AS (
  SELECT
    r.id_rating_level,
    r.rating_description,
    b.numeric_rating,
    r.ts_updated
  FROM
    datalake_pin_talent_clean.rating_level_translation r
  LEFT JOIN
    datalake_pin_talent_clean.rating_level_base b
      ON (b.id_rating_level = r.id_rating_level)
  WHERE
    r.language = 'US'
    AND b.dt_started < CURRENT_DATE()
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY
        b.id_rating_level
      ORDER BY
        b.dt_started DESC
    ) = 1
),
meeting_year AS (
  SELECT
    m.id_meeting,
    COALESCE(EXTRACT(YEAR FROM m.ts_meeting), EXTRACT(YEAR FROM m.ts_created)) AS value
  FROM
    datalake_pin_hr_review_clean.meeting m
)
SELECT
  d.id_dashboard AS id_calibration_evaluation,
  im.person_number,
  m.id_meeting,
  meeting_year.value AS meeting_year,
  m.meeting_title,
  m.meeting_status_code,
  cb.rating_description AS calibrated_behavior_description,
  cb.numeric_rating AS calibrated_behavior_numeric,
  pcb.rating_description AS pre_calibration_behavior_description,
  pcb.numeric_rating AS pre_calibration_behavior_numeric,
  ci.rating_description AS calibrated_impact_description,
  ci.numeric_rating AS calibrated_impact_numeric,
  pci.rating_description AS pre_calibration_impact_description,
  pci.numeric_rating AS pre_calibration_impact_numeric,
  CASE
    WHEN meeting_year.value < 2026 THEN cl.rating_description
    ELSE NULL
  END AS calibrated_leadership_description,
  CASE
    WHEN meeting_year.value < 2026 THEN cl.numeric_rating
    ELSE NULL
  END AS calibrated_leadership_numeric,
  CASE
    WHEN meeting_year.value < 2026 THEN pcl.rating_description
    ELSE NULL
  END AS pre_calibration_leadership_description,
  CASE
    WHEN meeting_year.value < 2026 THEN pcl.numeric_rating
    ELSE NULL
  END AS pre_calibration_leadership_numeric,
  m.ts_meeting
FROM
  datalake_pin_hr_review_clean.dashboard d
LEFT JOIN
  datalake_pin_hr_review_clean.meeting m ON (m.id_meeting = d.id_meeting)
LEFT JOIN
  meeting_year
    ON meeting_year.id_meeting = m.id_meeting
LEFT JOIN
  datalake_people_core.identifier_mapping im
    ON (im.id_assignment = d.id_assignment)
LEFT JOIN
  datalake_pin_hr_review_clean.dashboard_template_translation dtl
    ON (dtl.id_dashboard_template = m.id_dashboard_template
      AND dtl.language = 'US')
LEFT JOIN
  rating_value cb
    ON (cb.id_rating_level = d.id_metric_calibrated_value_4)
LEFT JOIN
  rating_value pcb
    ON (pcb.id_rating_level = d.id_metric_value_4)
LEFT JOIN
  rating_value ci
    ON (ci.id_rating_level = d.id_metric_calibrated_value_5)
LEFT JOIN
  rating_value pci
    ON (pci.id_rating_level = d.id_metric_value_5)
LEFT JOIN
  rating_value cl
    ON (cl.id_rating_level = d.id_metric_calibrated_value_3)
LEFT JOIN
  rating_value pcl
    ON (pcl.id_rating_level = d.id_metric_value_3)
WHERE
  dtl.id_dashboard_template IN (300000008237707, 300000145965905)
  AND cb.rating_description IS NOT NULL
