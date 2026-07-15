SELECT
    id,
    negotiation_id AS id_negotiation,
    finance_entity_id AS id_finance_entity,
    uuid AS uuid_installment,
    installment_number,
    status,
    grace_period_days,
    total_amount,
    principal_amount,
    fine_amount,
    interest_amount,
    discount_amounts,
    residual_amounts,
    additional_charges_amounts,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.installment
