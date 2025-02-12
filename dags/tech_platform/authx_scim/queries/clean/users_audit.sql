SELECT
    id,
    user_id,
    method,
    data,
    timestamp(created_at) AS ts_created
FROM
    datalake_authx_scim_raw.`users_audit`
