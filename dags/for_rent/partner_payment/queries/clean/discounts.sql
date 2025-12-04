SELECT
    id,
    agent_id AS id_agent,
    agent_payment_id AS id_agent_payment,
    version,
    discount_type,
    agent_contract_type,
    base_amount,
    discount_amount,
    agent_type,
    business_source,
    schedule_date AS dt_schedule,
    cancelation_date AS dt_cancellation,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.discounts