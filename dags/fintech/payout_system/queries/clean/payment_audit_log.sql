SELECT
    id,
    payment_request_id AS id_payment_request,
    entity_id AS id_entity,
    correlation_id AS id_correlation,
    audit_type,
    entity_type,
    field_name,
    old_value,
    new_value,
    change_reason,
    trace_id,
    principal,
    principal_type,
    TIMESTAMP(payment_request_created_at) AS ts_payment_request_created,
    TIMESTAMP(changed_at) AS ts_changed,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_payout_system_raw.payment_audit_log
