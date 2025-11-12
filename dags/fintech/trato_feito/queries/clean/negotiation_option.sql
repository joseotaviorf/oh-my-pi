SELECT
    CAST(id AS BIGINT) AS id_negotiation_option,
    version,
    internal_key,
    payment_method,
    down_payment_percentage,
    business_days_until_down_payment,
    installments_quantity,
    credit_card_fee_percentage,
    discount_on_fee_percent,
    discount_on_additional_charges_percentage,
    discount_on_principal_amount_percentage,
    discount_on_fine_percent,
    external_key,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.negotiation_option
