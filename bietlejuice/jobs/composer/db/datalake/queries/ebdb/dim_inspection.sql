SELECT
    id_inspection AS sk_inspection,
    id_inspection,
    type,
    status,
    ts_created,
    ts_expired,
    is_tenant_approved,
    is_owner_approved,
    has_inspector_comment,
    has_tenant_comment,
    has_owner_comment,
    now() AS ts_load
FROM
    datalake_ebdb_clean.inspection
