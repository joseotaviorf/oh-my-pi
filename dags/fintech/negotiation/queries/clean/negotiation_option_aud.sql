SELECT
    id,
    rev,
    revtype,
    key,
    installment_interval,
    number_of_installments,
    down_payment_percentage,
    discount_on_interest_percentage,
    discount_on_fine_percentage,
    discount_on_additional_charges_percentage,
    discount_on_principal_amount_percentage,
    key_mod AS mod_key,
    installment_interval_mod AS mod_installment_interval,
    number_of_installments_mod AS mod_number_of_installments,
    down_payment_percentage_mod AS mod_down_payment_percentage,
    discount_on_interest_percentage_mod AS mod_discount_on_interest_percentage,
    discount_on_fine_percentage_mod AS mod_discount_on_fine_percentage,
    discount_on_additional_charges_percentage_mod AS mod_discount_on_additional_charges_percentage,
    discount_on_principal_amount_percentage_mod AS mod_discount_on_principal_amount_percentage,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_option_aud
