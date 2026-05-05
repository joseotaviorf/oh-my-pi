SELECT
    id,
    operation_id AS id_operation,
    agent_type_id AS id_agent_type,
    operation_uuid AS uuid_operation,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.operation_event