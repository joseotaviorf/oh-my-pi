SELECT
    id,
    key,
    installment_interval,
    max_number_of_installments,
    min_down_payment_percentage,
    max_discount_on_interest_percentage,
    max_discount_on_fine_percentage,
    max_discount_on_principal_amount_percentage,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_policy
