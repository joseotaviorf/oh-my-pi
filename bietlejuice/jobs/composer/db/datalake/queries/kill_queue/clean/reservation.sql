SELECT
    id,
    house_id AS id_house,
    rent_flow_id AS id_rent_flow,
    tenant_id AS id_tenant,
    cancellation_reason,
    last_charge_status,
    mundipagg_token,
    status,
    CAST(version AS SMALLINT) AS version,
    CAST(attempt AS SMALLINT) AS attempt,
    CAST(installments AS INTEGER) AS installments,
    CAST(tenant_refund_percentage AS FLOAT) AS tenant_refund_percentage,
    CAST(value AS FLOAT) AS value,
    CAST(is_ongoing AS BOOLEAN) is_ongoing,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_kill_queue_raw.reservation