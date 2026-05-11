SELECT
  hm.id_meeting AS sk_meeting,
  hm.meeting_title AS committee_title,
  CASE
    WHEN hdtt.name = 'Talent Review' THEN 'talent_review'
    WHEN hdtt.name LIKE 'Calibration%' THEN 'performance_calibration'
  END AS meeting_type,
  CASE
    WHEN hm.meeting_title LIKE '%Q1%' THEN 'Q1'
    WHEN hm.meeting_title LIKE '%Q2%' THEN 'Q2'
    WHEN hm.meeting_title LIKE '%Q3%' THEN 'Q3'
    WHEN hm.meeting_title LIKE '%Q4%' THEN 'Q4'
    WHEN hm.meeting_title LIKE '%H1%' THEN 'H1'
    WHEN hm.meeting_title LIKE '%H2%' THEN 'H2'
    ELSE NULL
  END AS reference_period,
  hm.meeting_status_code,
  YEAR(hm.ts_meeting) AS meeting_year,
  hm.ts_meeting AS ts_meeting,
  NOW() AS ts_load
FROM
  datalake_pin_hr_review_clean.meeting AS hm
INNER JOIN
  datalake_pin_hr_review_clean.dashboard_template_translation AS hdtt
    ON hm.id_dashboard_template = hdtt.id_dashboard_template
WHERE
  hdtt.language = 'US'
  AND (
    hdtt.name LIKE 'Calibration%'
    OR hdtt.name = 'Talent Review'
  )
