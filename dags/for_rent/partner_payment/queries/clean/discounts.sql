SELECT
    id,
    agent_payment_id AS id_agent_payment,
    operation_agent_id AS id_operation_agent,
    agent_id AS id_agent,
    version,
    discount_type,
    agent_contract_type,
    base_amount,
    discount_amount,
    agent_type,
    business_source,
    schedule_date AS dt_schedule,
    cancelation_date AS dt_cancelation,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.discounts