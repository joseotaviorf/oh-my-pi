SELECT
    id AS id_repair_request_mediation,
    inspection_id AS id_inspection,
    uuid,
    applied_discount_amount,
    applied_discount_currency,
    tenant_payment_amount,
    tenant_payment_currency,
    mediation_discount_limit_amount,
    mediation_discount_limit_currency,
    negotiation_summary,
    tenant_counter_offer_amount,
    tenant_counter_offer_currency,
    tenant_agreed AS is_tenant_agreed,
    completed AS is_completed,
    completed_at AS ts_completed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_request_mediation
