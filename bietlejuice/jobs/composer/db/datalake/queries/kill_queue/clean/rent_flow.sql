SELECT
    id,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    version,
    firestore_id as id_firestore,
    house_id as id_house,
    tenant_id as id_tenant,
    status
FROM
    datalake_kill_queue_raw.rent_flow