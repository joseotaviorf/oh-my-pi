SELECT
    id,
    rev,
    revtype,
    key,
    installment_interval,
    max_number_of_installments,
    min_down_payment_percentage,
    max_discount_on_interest_percentage,
    max_discount_on_fine_percentage,
    max_discount_on_principal_amount_percentage,
    key_mod AS mod_key,
    installment_interval_mod AS mod_installment_interval,
    max_number_of_installments_mod AS mod_max_number_of_installments,
    min_down_payment_percentage_mod AS mod_min_down_payment_percentage,
    max_discount_on_interest_percentage_mod AS mod_max_discount_on_interest_percentage,
    max_discount_on_fine_percentage_mod AS mod_max_discount_on_fine_percentage,
    max_discount_on_principal_amount_percentage_mod AS mod_max_discount_on_principal_amount_percentage,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_policy_aud
