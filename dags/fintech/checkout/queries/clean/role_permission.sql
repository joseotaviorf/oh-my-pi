SELECT
    role_id AS id_role,
    permission_id AS id_permission,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_raw.role_permission
