WITH house_table AS (
    SELECT
        id AS id_house,
        dt_first_publication
    FROM
        datalake_ebdb_clean.house
),

durations_table AS (
    SELECT
        id_house,
        quarter,
        sum(duration) AS duration,
        CASE WHEN sum(open_contract) = 0 THEN 1 ELSE 0 END AS is_event
    FROM (
        SELECT
            id_house,
            date_trunc('QUARTER', dt_first_publication) AS quarter,
            date_diff(coalesce(dt_termination, current_date), dt_started) AS duration,
            CASE WHEN dt_termination IS NULL THEN 1 ELSE 0 END AS open_contract
        FROM
            datalake_ebdb_contract.contract
        JOIN
            house_table USING (id_house)
        WHERE
            NOT is_canceled
            AND dt_started IS NOT NULL
            AND dt_started < current_date
            AND (NOT is_ended OR dt_termination IS NOT NULL)
            AND dt_first_publication >= '2016-01-01'
    )
    WHERE
        duration > 0
    GROUP BY
        id_house,
        quarter
    HAVING
        sum(open_contract) <= 1
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
        duration,
        quarter,
        count(DISTINCT id_house) AS num_obs,
        sum(is_event) AS num_events
    FROM
        durations_table
    GROUP BY
        duration,
        quarter
),

at_risk_table AS (
    SELECT
        duration,
        quarter,
        num_obs,
        num_events,
        num_samples - coalesce(
            sum(num_obs) OVER (
                PARTITION BY quarter
                ORDER BY duration
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 preceding
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
