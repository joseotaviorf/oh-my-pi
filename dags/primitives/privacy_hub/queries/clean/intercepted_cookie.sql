SELECT
    CAST(id AS BIGINT) AS id,
    CAST(website_id AS BIGINT) AS id_website,
    name,
    script_url,
    domain,
    ttl,
    CAST(version AS INT) AS version,
    CAST(is_catalogued AS BOOLEAN) AS is_catalogued,
    CAST(updated_at AS TIMESTAMP) AS ts_updated_at,
    CAST(created_at AS TIMESTAMP) AS ts_created_at,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM datalake_privacy_hub_raw.intercepted_cookie
