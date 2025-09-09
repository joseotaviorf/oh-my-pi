SELECT
    -- ids
    id,
    -- text fields
    name,
    description,
    type,
    "from" AS from_address,
    body,
    html_body,
    -- boolean
    CAST(default AS BOOLEAN) AS is_default,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.email_templates
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1