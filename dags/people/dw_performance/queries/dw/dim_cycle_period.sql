WITH
released_cycles AS (
  -- Curated release allow-list, updated via PR. Cycles not listed here are not released.
  SELECT
    cycle_name
  FROM (
    VALUES
      ('Performa 2023'),
      ('Performa 2024'),
      ('Performa 2025'),
      ('Talent Review 2024 Q1'),
      ('Talent Review 2024 Q2'),
      ('Talent Review 2024 Q3'),
      ('Talent Review 2025 H1'),
      ('Talent Review 2025 H2'),
      ('Talent Review 2026 Q1'),
      ('Talent Review 2026 H2')
  ) AS released (cycle_name)
),
distinct_cycles AS (
  SELECT
    meeting_type,
    meeting_year,
    reference_period,
    MAX(DATE(ts_meeting)) AS dt_last_meeting
  FROM
    dw_performance.dim_committee_meeting
  WHERE
    meeting_year IS NOT NULL
  GROUP BY
    meeting_type,
    meeting_year,
    reference_period
),
cycles_with_start AS (
  SELECT
    meeting_type,
    meeting_year,
    reference_period,
    MD5(CONCAT(
      meeting_type,
      CAST(meeting_year AS STRING),
      COALESCE(reference_period, '-1')
    )) AS sk_cycle_period,
    CASE
      WHEN meeting_type = 'performance_calibration'
        THEN CONCAT('Performa ', CAST(meeting_year - 1 AS STRING))
      WHEN meeting_type = 'talent_review'
        THEN CONCAT('Talent Review ', CAST(meeting_year AS STRING), ' ', reference_period)
    END AS cycle_name,
    -- Talent Review: first day of the month of the cycle's closure (latest committee meeting).
    -- Performance Calibration: January 1st of meeting_year (calendar rule).
    CASE
      WHEN meeting_type = 'talent_review'
        THEN TRUNC(dt_last_meeting, 'MM')
      WHEN meeting_type = 'performance_calibration'
        THEN MAKE_DATE(meeting_year, 1, 1)
    END AS dt_start
  FROM
    distinct_cycles
),
cycles_with_release AS (
  SELECT
    cs.sk_cycle_period,
    cs.cycle_name,
    cs.meeting_type,
    cs.meeting_year,
    cs.reference_period,
    cs.dt_start,
    rc.cycle_name IS NOT NULL AS is_released
  FROM
    cycles_with_start AS cs
  LEFT JOIN
    released_cycles AS rc
      ON rc.cycle_name = cs.cycle_name
),
released_starts AS (
  -- Different reference_period values can share a start month (e.g. Q1 and H1).
  SELECT DISTINCT
    meeting_type,
    dt_start
  FROM
    cycles_with_release
  WHERE
    is_released
),
released_starts_with_next AS (
  SELECT
    meeting_type,
    dt_start,
    LEAD(dt_start) OVER (
      PARTITION BY meeting_type
      ORDER BY dt_start
    ) AS dt_next_start
  FROM
    released_starts
),
review_periods AS (
  SELECT
    cwr.sk_cycle_period,
    cwr.cycle_name,
    cwr.meeting_type,
    cwr.meeting_year,
    cwr.reference_period,
    cwr.is_released,
    CASE WHEN cwr.is_released THEN cwr.dt_start END AS dt_valid_from,
    CASE
      WHEN NOT cwr.is_released THEN NULL
      WHEN rswn.dt_next_start IS NULL THEN DATE'9999-12-31'
      ELSE DATE_ADD(rswn.dt_next_start, -1)
    END AS dt_valid_to
  FROM
    cycles_with_release AS cwr
  LEFT JOIN
    released_starts_with_next AS rswn
      ON rswn.meeting_type = cwr.meeting_type
      AND rswn.dt_start = cwr.dt_start
),
latest_released_cycle AS (
  SELECT
    meeting_type,
    MAX(dt_valid_from) AS dt_latest_released_valid_from
  FROM
    review_periods
  WHERE
    is_released
  GROUP BY
    meeting_type
)
SELECT
  rp.sk_cycle_period,
  rp.cycle_name,
  rp.meeting_type,
  rp.meeting_year,
  rp.reference_period,
  (
    rp.is_released
    AND rp.dt_valid_from = lrc.dt_latest_released_valid_from
  ) AS is_current,
  rp.is_released,
  rp.dt_valid_from,
  rp.dt_valid_to,
  NOW() AS ts_load
FROM
  review_periods AS rp
LEFT JOIN
  latest_released_cycle AS lrc
    ON lrc.meeting_type = rp.meeting_type
