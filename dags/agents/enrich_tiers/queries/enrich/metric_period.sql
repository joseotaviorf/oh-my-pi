WITH month_period AS (
    SELECT DISTINCT
        month_start,
        month_end,
        year,
        month
    FROM
        datalake_quintoandar.aux_date
    WHERE
        date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
metrics AS (
    SELECT 
        EXPLODE(
            ARRAY(
                "CCV",
                "CCV_TQC",
                "CCV_CIQ",
                "BP",
                "GMV",
                "OS_BY",
                "OS2CCV_BY",
                "BP2CCV",
                "CS",
                "TP",
                "FL_FR",
                "FL_FS",
                "TP2CS"
            )
        ) AS metric
)
SELECT
    XXHASH64(
        metrics.metric,
        month_period.month_start
    ) AS id,
    metrics.metric,
    "VALID" AS status,
    month_period.month_start AS dt_init,
    month_period.month_end AS dt_end,
    -- add 3 hours to the start and end dates to align with the UTC timezone
    month_period.month_start + INTERVAL 3 HOUR AS ts_interval_started,
    IF(
        metrics.metric IN ("FL_FR", "FL_FS"),
        TIMESTAMP(month_period.month_end || ' 23:59:59') + INTERVAL 3 HOUR + INTERVAL 2 DAY,
        TIMESTAMP(month_period.month_end || ' 23:59:59') + INTERVAL 3 HOUR
    ) AS ts_interval_ended,
    TIMESTAMP(month_period.month_start) AS ts_created,
    NOW() AS ts_updated,
    month_period.year,
    month_period.month
FROM
    month_period
CROSS JOIN
    metrics