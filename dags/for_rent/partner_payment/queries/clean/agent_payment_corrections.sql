SELECT
    id,
    operation_payment_id AS id_operation_payment,
    agent_payment_id AS id_agent_payment,
    agent_id AS id_agent,
    version,
    request_type,
    request_category,
    amount,
    approving_user,
    source_reference,
    agent_type,
    business_source,
    request_date AS dt_request,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.agent_payment_corrections