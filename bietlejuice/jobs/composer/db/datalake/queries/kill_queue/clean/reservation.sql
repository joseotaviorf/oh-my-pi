SELECT
    id,
    house_id AS id_house,
    rent_flow_id AS id_rent_flow,
    tenant_id AS id_tenant,
    cancellation_reason,
    last_charge_status,
    mundipagg_token,
    status,
    version,
    attempt,
    CAST(installments AS INTEGER) AS installments,
    tenant_refund_percentage,
    value,
    CAST(is_ongoing AS BOOLEAN) is_ongoing,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year, 
    month, 
    day
FROM
    datalake_kill_queue_raw.reservation
WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}
