SELECT
    id,
    payments_period_id AS id_payments_period,
    company_uuid AS uuid_company,
    payment_provider_id AS id_payment_provider,
    version,
    status,
    total_amount,
    currency,
    payment_provider,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.bills
