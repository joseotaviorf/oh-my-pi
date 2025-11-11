SELECT
    id,
    agent_id AS id_agent,
    agent_payment_id AS id_agent_payment,
    version,
    amount,
    weakly_hours_response,
    specific_hours_response,
    holidays_response,
    agent_type,
    business_source,
    start_date AS dt_start,
    end_date AS dt_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.agenda_availability