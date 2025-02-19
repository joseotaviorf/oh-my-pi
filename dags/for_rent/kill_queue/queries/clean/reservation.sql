SELECT
    CAST(id AS BIGINT) AS id,
    CAST(house_id AS BIGINT) AS id_house,
    CAST(rent_flow_id AS BIGINT) AS id_rent_flow,
    CAST(tenant_id AS BIGINT) AS id_tenant,
    CAST(cancellation_reason AS STRING) AS cancellation_reason,
    CAST(last_charge_status AS STRING) AS last_charge_status,
    CAST(mundipagg_token AS STRING) AS mundipagg_token,
    CAST(status AS STRING) AS status,
    CAST(version AS SMALLINT) AS version,
    CAST(attempt AS SMALLINT) AS attempt,
    CAST(installments AS INTEGER) AS installments,
    CAST(tenant_refund_percentage AS FLOAT) AS tenant_refund_percentage,
    CAST(value AS FLOAT) AS value,
    CAST(is_ongoing AS BOOLEAN) is_ongoing,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_kill_queue_raw.reservation