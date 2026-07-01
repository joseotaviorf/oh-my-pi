SELECT
    ii.uuid_inventory_ingestion AS sk_inventory_ingestion,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    ii.status,
    ii.status = 'COMPLETED' AS is_successful,
    ii.quantity_created,
    ii.quantity_updated,
    ii.quantity_failed,
    ii.quantity_skipped,
    ii.quantity_unpublished,
    ii.failure_reason,
    CASE
        WHEN ii.ts_started IS NOT NULL AND ii.ts_completed IS NOT NULL
            THEN (UNIX_TIMESTAMP(ii.ts_completed) - UNIX_TIMESTAMP(ii.ts_started)) / 60.0
    END AS duration_minutes,
    ii.ts_started,
    ii.ts_completed,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(ii.ts_started) AS year,
    MONTH(ii.ts_started) AS month,
    DAY(ii.ts_started) AS day
FROM
    datalake_alias_clean.inventory_ingestions AS ii
LEFT JOIN
    core_brokers.brokers AS cb
        ON ii.uuid_company = cb.uuid_company
WHERE
    (
        ii.ts_started >= TIMESTAMP('{load_start_date}')
        AND ii.ts_started < TIMESTAMP('{load_end_date}')
    )
    OR (
        ii.ts_completed >= TIMESTAMP('{load_start_date}')
        AND ii.ts_completed < TIMESTAMP('{load_end_date}')
    )