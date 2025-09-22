SELECT
    -- ids
    id,
    -- text fields
    name,
    first_name,
    last_name,
    primary_email_address,
    -- boolean
    CAST(disabled AS BOOLEAN) AS is_disabled,
    CAST(site_admin AS BOOLEAN) AS is_site_admin,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- arrays
    emails,
    linked_candidate_ids,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.users