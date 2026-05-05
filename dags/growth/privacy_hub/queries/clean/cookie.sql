SELECT
    CAST(id AS BIGINT) AS id,
    CAST(cookie_definition_id AS BIGINT) AS id_cookie_definition,
    CAST(website_id AS BIGINT) AS id_website,
    owner_email,
    CAST(version AS INT) AS version,
    category,
    CAST(is_overwritten AS BOOLEAN) AS is_overwritten,
    CAST(last_seen AS TIMESTAMP) AS ts_last_seen_at,
    CAST(updated_at AS TIMESTAMP) AS ts_updated_at,
    CAST(created_at AS TIMESTAMP) AS ts_created_at,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM datalake_privacy_hub_raw.cookie
