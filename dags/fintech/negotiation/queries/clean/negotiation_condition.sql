SELECT
    id,
    negotiation_id AS id_negotiation,
    source_key,
    source_type,
    installment_interval,
    number_of_installments,
    down_payment_percentage,
    down_payment,
    total_amount,
    principal_amount,
    discount_amount,
    discount_on_interest_percentage,
    discount_on_fine_percentage,
    discount_on_principal_amount_percentage,
    discount_on_additional_charges_percentage,
    fine_amount,
    interest_amount,
    residual_amount,
    additional_charges_amount,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_condition
