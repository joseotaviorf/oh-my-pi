SELECT
    id,
    payment_config_id AS id_payment_config,
    convenience_fee_percentage,
    fixed_cost_of_transaction AS transaction_fixed_cost,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_checkout_homolog_raw.credit_card_fee
