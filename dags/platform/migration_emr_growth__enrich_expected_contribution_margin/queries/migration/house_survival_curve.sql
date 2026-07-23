WITH house_table AS (
  SELECT
    id_house,
    dt_first_publication
  FROM (
    SELECT
      h.id AS id_house,
      COALESCE(
        IF(lbc.business_context = 'RENT', lbc.ts_first_publication, NULL),
        h.dt_first_publication
      ) AS dt_first_publication,
      ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY IF(lbc.business_context = 'RENT', 1, 2)) AS _w,
      h.id,
      lbc.business_context
    FROM datalake_ebdb_clean.house AS h
    LEFT JOIN datalake_ebdb_clean.listing_business_context AS lbc
      ON lbc.id_house = h.id
  ) AS _t
  WHERE
    _w = 1
), durations_table AS (
  SELECT
    id_house,
    quarter,
    SUM(duration) AS duration,
    CASE WHEN SUM(open_contract) = 0 THEN 1 ELSE 0 END AS is_event
  FROM (
    SELECT
      id_house,
      DATE_TRUNC('QUARTER', dt_first_publication) AS quarter,
      DATEDIFF(TO_DATE(COALESCE(dt_termination, CURRENT_DATE)), TO_DATE(dt_started)) AS duration,
      CASE WHEN dt_termination IS NULL THEN 1 ELSE 0 END AS open_contract
    FROM datalake_ebdb_contract.contract
    JOIN house_table
      USING (id_house)
    WHERE
      NOT is_canceled
      AND NOT dt_started IS NULL
      AND dt_started < CURRENT_DATE
      AND (
        NOT is_ended OR NOT dt_termination IS NULL
      )
      AND dt_first_publication >= '2016-01-01'
  )
  WHERE
    duration > 0
  GROUP BY
    id_house,
    quarter
  HAVING
    SUM(open_contract) <= 1
), num_samples AS (
  SELECT
    quarter,
    COUNT(1) AS num_samples
  FROM durations_table
  GROUP BY
    quarter
), counts_table AS (
  SELECT
    duration,
    quarter,
    COUNT(DISTINCT id_house) AS num_obs,
    SUM(is_event) AS num_events
  FROM durations_table
  GROUP BY
    duration,
    quarter
), at_risk_table AS (
  SELECT
    duration,
    quarter,
    num_obs,
    num_events,
    num_samples - COALESCE(
      SUM(num_obs) OVER (PARTITION BY quarter ORDER BY duration ROWS BETWEEN UNBOUNDED PRECEDING AND 1 preceding),
      0
    ) AS at_risk_count
  FROM counts_table
  JOIN num_samples
    USING (quarter)
)
SELECT
  CAST(quarter AS DATE) AS quarter,
  duration AS days_since_start,
  EXP(
    SUM(LN(1 - num_events / at_risk_count)) OVER (PARTITION BY quarter ORDER BY duration ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  ) AS survival_probability
FROM at_risk_table
ORDER BY
  quarter,
  days_since_start
