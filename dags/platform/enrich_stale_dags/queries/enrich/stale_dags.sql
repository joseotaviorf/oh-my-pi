WITH current_dags AS (
    SELECT
        id_dag,
        owners,
        schedule_interval,
        fileloc
    FROM datalake_astro_clean.dag
    WHERE MAKE_DATE(year, month, day) = CURRENT_DATE()
      AND is_active = TRUE
      AND is_paused = FALSE
),
last_success AS (
    SELECT
        id_dag,
        MAX(ts_started) AS ts_last_success
    FROM datalake_astro_clean.dag_run
    WHERE state = 'success'
    GROUP BY 1
),
last_serialized AS (
    SELECT
        id_dag,
        MAX(ts_last_updated) AS ts_last_serialized
    FROM datalake_astro_clean.serialized_dag
    GROUP BY 1
)
SELECT
    d.id_dag,
    d.owners,
    d.schedule_interval,
    d.fileloc,
    ls.ts_last_success,
    lz.ts_last_serialized,
    CAST(MONTHS_BETWEEN(CURRENT_TIMESTAMP(), ls.ts_last_success) AS INT) AS months_since_last_success,
    CAST(MONTHS_BETWEEN(CURRENT_TIMESTAMP(), lz.ts_last_serialized) AS INT) AS months_since_last_change,
    CASE
        WHEN ls.ts_last_success IS NULL THEN TRUE
        WHEN ls.ts_last_success < ADD_MONTHS(CURRENT_DATE(), -1) THEN TRUE
        ELSE FALSE
    END AS is_stale_no_recent_success,
    CASE
        WHEN lz.ts_last_serialized < ADD_MONTHS(CURRENT_DATE(), -1) THEN TRUE
        ELSE FALSE
    END AS is_stale_old_serialization
FROM current_dags d
LEFT JOIN last_success ls ON d.id_dag = ls.id_dag
LEFT JOIN last_serialized lz ON d.id_dag = lz.id_dag
WHERE
    ls.ts_last_success IS NULL
    OR ls.ts_last_success < ADD_MONTHS(CURRENT_DATE(), -1)
    OR lz.ts_last_serialized < ADD_MONTHS(CURRENT_DATE(), -1)
