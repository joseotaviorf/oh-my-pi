SELECT
    EXECUTION_ID AS id_execution,
    STATUS AS status,
    ERROR_MESSAGE AS error_message,
    CASE
        WHEN START_DATETIME IS NOT NULL AND END_DATETIME IS NOT NULL
        THEN ROUND((UNIX_TIMESTAMP(END_DATETIME) - UNIX_TIMESTAMP(START_DATETIME)) / 60.0, 2)
        ELSE NULL
    END AS duration_minutes,
    START_DATETIME AS ts_start,
    END_DATETIME AS ts_end,
    NOW() AS ts_load
FROM datalake_cyber_raw.execution_log
