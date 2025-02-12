SELECT
    id,
    app_id,
    source,
    display_name,
    description,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated,
    timestamp(deleted_at) AS ts_deleted
FROM
    datalake_authx_scim_raw.`entitlements`
