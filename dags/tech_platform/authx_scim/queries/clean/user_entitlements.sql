SELECT
    entitlement_identity_source AS entitlement_source,
    entitlement_identity_id AS entitlement_id,
    user_identity_source AS user_source,
    user_identity_id AS user_id,
    timestamp(updated_at) AS ts_updated,
    timestamp(deleted_at) AS ts_deleted
FROM
    datalake_authx_scim_raw.`user_entitlements`
