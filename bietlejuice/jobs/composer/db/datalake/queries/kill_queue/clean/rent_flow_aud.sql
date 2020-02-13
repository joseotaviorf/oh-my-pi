SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    firestore_id as id_firestore,
    house_id as id_house,
    status,
    status_mod as is_status_mod,
    tenant_id as id_tenant
FROM
    datalake_kill_queue_raw.rent_flow_aud