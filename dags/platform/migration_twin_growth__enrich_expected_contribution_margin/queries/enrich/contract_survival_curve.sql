WITH durations_table AS (
  SELECT
      id,
      date_trunc('QUARTER', dt_started) AS quarter,
      date_diff(coalesce(dt_termination, current_date), dt_started) AS duration,
      CASE WHEN dt_termination IS NOT NULL THEN 1 ELSE 0 END AS is_event
  FROM
      datalake_ebdb_contract.contract
  WHERE
      NOT is_canceled
      AND dt_started IS NOT NULL
      AND dt_started < current_date
      AND (NOT is_ended OR dt_termination IS NOT NULL)
      AND dt_started >= '2016-01-01'
      AND date_diff(coalesce(dt_termination, current_date), dt_started) > 0
),

num_samples AS (
    SELECT
        quarter,
        count(1) AS num_samples
    FROM
        durations_table
    GROUP BY
        quarter
),

counts_table AS (
    SELECT
        quarter,
        duration,
        count(DISTINCT id) AS num_obs,
        sum(is_event) AS num_events
    FROM
        durations_table
    GROUP BY
        quarter,
        duration
),

at_risk_table AS (
    SELECT
        quarter,
        duration,
        num_obs,
        num_events,
        num_samples - coalesce(
            sum(num_obs) OVER (
                PARTITION BY quarter
                ORDER BY duration
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ),
            0
        ) AS at_risk_count
    FROM
        counts_table
    JOIN
        num_samples USING (quarter)
)

SELECT
    date(quarter) AS quarter,
    duration AS days_since_start,
    exp(
        sum(log(1 - num_events / at_risk_count)) OVER (
            PARTITION BY quarter
            ORDER BY duration
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
    ) AS survival_probability
FROM
    at_risk_table
ORDER BY
    quarter,
    days_since_start
