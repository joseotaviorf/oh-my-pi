SELECT
    CAST(id AS BIGINT) AS id,
    name_pattern,
    friendly_name,
    domain,
    description,
    lifespan_type,
    party_type,
    retention,
    CAST(version AS INT) AS version,
    CAST(is_regex AS BOOLEAN) AS is_regex,
    CAST(created_at AS TIMESTAMP) AS ts_created_at,
    CAST(updated_at AS TIMESTAMP) AS ts_updated_at,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM datalake_privacy_hub_raw.cookie_definition
