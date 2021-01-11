SELECT
    id,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    version,
    attempt,
    rent_flow_id as id_rent_flow,
    status,
    tenant_id as id_tenant,
    value,
    house_id as id_house,
    mundipagg_token,
    is_ongoing,
    cancellation_reason,
    cast(installments as integer) as installments,
    last_charge_status,
    tenant_refund_percentage
FROM
    datalake_kill_queue_raw.reservation
