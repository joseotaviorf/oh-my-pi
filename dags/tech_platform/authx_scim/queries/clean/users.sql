SELECT
    id,
    source,
    user_name AS email,
    active,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated,
    timestamp(deleted_at) AS ts_deleted
FROM
    datalake_authx_scim_raw.`users`
