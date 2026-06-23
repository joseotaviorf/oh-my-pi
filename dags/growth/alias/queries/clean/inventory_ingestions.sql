SELECT
    uuid AS uuid_inventory_ingestion,
    company_uuid AS uuid_company,
    status,
    created AS quantity_created,
    updated AS quantity_updated,
    failed AS quantity_failed,
    skipped AS quantity_skipped,
    unpublished AS quantity_unpublished,
    failure_reason,
    CAST(started_at AS TIMESTAMP) AS ts_started,
    CAST(completed_at AS TIMESTAMP) AS ts_completed,
    YEAR(CAST(started_at AS TIMESTAMP)) AS year,
    MONTH(CAST(started_at AS TIMESTAMP)) AS month,
    DAY(CAST(started_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.inventory_ingestions