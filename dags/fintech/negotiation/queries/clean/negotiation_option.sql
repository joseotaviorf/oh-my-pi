SELECT
    id,
    key,
    installment_interval,
    number_of_installments,
    down_payment_percentage,
    discount_on_interest_percentage,
    discount_on_fine_percentage,
    discount_on_additional_charges_percentage,
    discount_on_principal_amount_percentage,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_option
