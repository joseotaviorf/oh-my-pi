WITH
distinct_cycles AS (
  SELECT DISTINCT
    meeting_type,
    meeting_year,
    reference_period
  FROM
    dw_performance.dim_committee_meeting
  WHERE
    meeting_year IS NOT NULL
),
cycles_with_start AS (
  SELECT
    meeting_type,
    meeting_year,
    reference_period,
    MAKE_DATE(
      meeting_year,
      CASE
        WHEN reference_period IS NULL THEN 1
        WHEN reference_period = 'Q1' THEN 1
        WHEN reference_period = 'Q2' THEN 4
        WHEN reference_period = 'Q3' THEN 7
        WHEN reference_period = 'Q4' THEN 10
        WHEN reference_period = 'H1' THEN 1
        WHEN reference_period = 'H2' THEN 7
      END,
      1
    ) AS dt_valid_from
  FROM
    distinct_cycles
),
distinct_starts AS (
  -- Different reference_period values can share a start month (e.g. Q1 and H1).
  SELECT DISTINCT
    meeting_type,
    dt_valid_from
  FROM
    cycles_with_start
),
distinct_starts_with_next AS (
  SELECT
    meeting_type,
    dt_valid_from,
    LEAD(dt_valid_from) OVER (
      PARTITION BY meeting_type
      ORDER BY dt_valid_from
    ) AS dt_next_valid_from
  FROM
    distinct_starts
),
cycles_with_window AS (
  SELECT
    cs.meeting_type,
    cs.meeting_year,
    cs.reference_period,
    cs.dt_valid_from,
    dswn.dt_next_valid_from
  FROM
    cycles_with_start AS cs
  LEFT JOIN
    distinct_starts_with_next AS dswn
      ON dswn.meeting_type = cs.meeting_type
      AND dswn.dt_valid_from = cs.dt_valid_from
),
review_periods AS (
  SELECT
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
    meeting_type,
    meeting_year,
    reference_period,
    dt_valid_from,
    CASE
      WHEN dt_next_valid_from IS NULL THEN DATE'9999-12-31'
      ELSE DATE_ADD(dt_next_valid_from, -1)
    END AS dt_valid_to
  FROM
    cycles_with_window
),
released_cycles AS (
  -- Curated release allow-list, updated via PR. Cycles not listed here are not released.
  SELECT
    cycle_name
  FROM (
    VALUES
      ('Performa 2023'),
      ('Performa 2024'),
      ('Talent Review 2024 Q1'),
      ('Talent Review 2024 Q2'),
      ('Talent Review 2024 Q3'),
      ('Talent Review 2025 H1'),
      ('Talent Review 2025 H2')
  ) AS released (cycle_name)
),
review_periods_with_release AS (
  SELECT
    rp.sk_cycle_period,
    rp.cycle_name,
    rp.meeting_type,
    rp.meeting_year,
    rp.reference_period,
    rp.dt_valid_from,
    rp.dt_valid_to,
    rc.cycle_name IS NOT NULL AS is_released
  FROM
    review_periods AS rp
  LEFT JOIN
    released_cycles AS rc
      ON rc.cycle_name = rp.cycle_name
),
latest_released_cycle AS (
  SELECT
    meeting_type,
    MAX(dt_valid_from) AS dt_latest_released_valid_from
  FROM
    review_periods_with_release
  WHERE
    is_released
  GROUP BY
    meeting_type
)
SELECT
  rpr.sk_cycle_period,
  rpr.cycle_name,
  rpr.meeting_type,
  rpr.meeting_year,
  rpr.reference_period,
  (
    rpr.is_released
    AND rpr.dt_valid_from = lrc.dt_latest_released_valid_from
  ) AS is_current,
  rpr.is_released,
  rpr.dt_valid_from,
  rpr.dt_valid_to,
  NOW() AS ts_load
FROM
  review_periods_with_release AS rpr
LEFT JOIN
  latest_released_cycle AS lrc
    ON lrc.meeting_type = rpr.meeting_type
