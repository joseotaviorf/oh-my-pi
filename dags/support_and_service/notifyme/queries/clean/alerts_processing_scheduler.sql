SELECT
    CAST(id AS BIGINT) AS id,
    campaign_name,
    CAST(last_processing_date AS TIMESTAMP) AS ts_last_processing,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM datalake_notifyme_raw.alerts_processing_scheduler
