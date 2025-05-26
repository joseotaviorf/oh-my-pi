SELECT
  hm.id_meeting AS sk_meeting,
  hm.meeting_title AS committee_title,
  CASE
    WHEN hm.meeting_title LIKE 'TR.Q1%'
      OR hm.meeting_title LIKE 'TR Q1%' THEN 'Q1'
    WHEN hm.meeting_title LIKE 'TR.Q2%'
      OR hm.meeting_title LIKE 'TR Q2%' THEN 'Q2'
    WHEN hm.meeting_title LIKE 'TR.Q3%'
      OR hm.meeting_title LIKE 'TR Q3%' THEN 'Q3'
    WHEN hm.meeting_title LIKE 'TR.Q4%'
      OR hm.meeting_title LIKE 'TR Q4%' THEN 'Q4'
    WHEN hm.meeting_title LIKE 'TR.H1%'
      OR hm.meeting_title LIKE 'TR H1%' THEN 'H1'
    WHEN hm.meeting_title LIKE 'TR.H2%'
      OR hm.meeting_title LIKE 'TR H2%' THEN 'H2'
    ELSE hm.meeting_title
  END AS reference_period,
  NOW() AS ts_load
FROM
  datalake_pin_hr_review_clean.meeting AS hm
INNER JOIN 
  datalake_pin_hr_review_clean.dashboard_template_translation AS hdtt 
    ON hm.id_dashboard_template = hdtt.id_dashboard_template
WHERE
  hdtt.language = 'US'
  AND hdtt.name = 'Talent Review'