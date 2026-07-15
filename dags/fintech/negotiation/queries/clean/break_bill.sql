SELECT
    id,
    negotiation_id AS id_negotiation,
    finance_entity_id AS id_finance_entity,
    channel,
    domain,
    total_amount,
    principal_amount,
    fine_amount,
    interest_amount,
    reversed_discount_amounts,
    residual_amounts,
    additional_charges_amounts,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.break_bill
