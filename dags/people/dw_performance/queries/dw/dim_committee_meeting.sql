WITH
committee_meeting AS (
  SELECT
    meeting.id_meeting AS sk_meeting,
    meeting.meeting_title AS committee_title,
    CASE
      WHEN template.name = 'Talent Review' THEN 'talent_review'
      WHEN template.name LIKE 'Calibration%' THEN 'performance_calibration'
    END AS meeting_type,
    meeting.meeting_status_code,
    meeting.ts_meeting
  FROM
    datalake_pin_hr_review_clean.meeting AS meeting
  INNER JOIN
    datalake_pin_hr_review_clean.dashboard_template_translation AS template
      ON meeting.id_dashboard_template = template.id_dashboard_template
  WHERE
    template.language = 'US'
    AND (
      template.name LIKE 'Calibration%'
      OR template.name = 'Talent Review'
    )
  UNION ALL
  SELECT
    committee.id_meeting AS sk_meeting,
    committee.committee_title,
    committee.meeting_type,
    committee.meeting_status_code,
    committee.ts_meeting
  FROM
    datalake_people.talent_review_committee_2026_h2 AS committee
)
SELECT
  committee_meeting.sk_meeting,
  committee_meeting.committee_title,
  committee_meeting.meeting_type,
  CASE
    WHEN committee_meeting.committee_title LIKE '%Q1%' THEN 'Q1'
    WHEN committee_meeting.committee_title LIKE '%Q2%' THEN 'Q2'
    WHEN committee_meeting.committee_title LIKE '%Q3%' THEN 'Q3'
    WHEN committee_meeting.committee_title LIKE '%Q4%' THEN 'Q4'
    WHEN committee_meeting.committee_title LIKE '%H1%' THEN 'H1'
    WHEN committee_meeting.committee_title LIKE '%H2%' THEN 'H2'
    ELSE NULL
  END AS reference_period,
  committee_meeting.meeting_status_code,
  YEAR(committee_meeting.ts_meeting) AS meeting_year,
  committee_meeting.ts_meeting,
  NOW() AS ts_load
FROM
  committee_meeting
