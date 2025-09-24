WITH bimester AS (
    SELECT DISTINCT
        bimester_start,
        bimester_end,
        year,
        bimester
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
        bimester.bimester_start
    ) AS id,
    metrics.metric,
    "VALID" AS status,
    bimester.bimester_start AS dt_init,
    bimester.bimester_end AS dt_end,
    TIMESTAMP(bimester.bimester_start) AS ts_created,
    NOW() AS ts_updated,
    bimester.year,
    bimester.bimester
FROM
    bimester
CROSS JOIN
    metrics