SELECT
    id,
    operation_event_id AS id_operation_event,
    operation_payment_id AS id_operation_payment,
    agent_payment_id AS id_agent_payment,
    version,
    error_date,
    status,
    message_error,
    error_category,
    source_reference,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.error_records