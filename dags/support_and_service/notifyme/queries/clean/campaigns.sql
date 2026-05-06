SELECT
    name,
    external_reference,
    experimental_external_reference,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM datalake_notifyme_raw.campaigns
