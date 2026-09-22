-- Synthetic meetings sit after the 2026-09-03 PIN Q3 committees so this H2 cycle
-- wins is_last_cycle. Evaluated (2026-09) is later than carried (2026-02).
-- Negative ids stay outside the PIN meeting id range.
WITH
carried_committee AS (
  SELECT
    CAST(-20260904 AS BIGINT) AS id_meeting,
    '2026-02' AS review_month,
    'Talent Review H2 2026 - Carried from February 2026' AS committee_title,
    'talent_review' AS meeting_type,
    CAST(NULL AS STRING) AS meeting_status_code,
    CAST('2026-09-04 12:00:00' AS TIMESTAMP) AS ts_meeting
),
evaluated_committee AS (
  SELECT
    CAST(-20260918 AS BIGINT) AS id_meeting,
    '2026-09' AS review_month,
    'Talent Review H2 2026 - Evaluated September 2026' AS committee_title,
    'talent_review' AS meeting_type,
    CAST(NULL AS STRING) AS meeting_status_code,
    CAST('2026-09-18 12:00:00' AS TIMESTAMP) AS ts_meeting
)
SELECT
  id_meeting,
  review_month,
  committee_title,
  meeting_type,
  meeting_status_code,
  ts_meeting,
  NOW() AS ts_load
FROM
  carried_committee
UNION ALL
SELECT
  id_meeting,
  review_month,
  committee_title,
  meeting_type,
  meeting_status_code,
  ts_meeting,
  NOW() AS ts_load
FROM
  evaluated_committee
