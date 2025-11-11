SELECT
    id,
    user_id AS id_user,
    company_uuid AS uuid_company,
    agent_id AS id_agent,
    version,
    source_error_reference,
    status,
    total_basic_payments,
    total_campaign_payments,
    total_discounts,
    total_agenda_availability,
    total_corrections,
    payment_date AS dt_payment,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.agent_payments