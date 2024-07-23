SELECT
    id_installment,
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    CAST(main_amount AS FLOAT) AS main_amount,
    CAST(amount_to_pay AS FLOAT) AS amount_to_pay,
    CAST(amount_fine AS FLOAT) AS amount_fine,
    CAST(interest_fee_amount AS FLOAT) AS interest_fee_amount,
    CAST(adm_fee_amount AS FLOAT) AS adm_fee_amount,
    CAST(transfer_amount AS FLOAT) AS transfer_amount,
    CAST(revenue_amount AS FLOAT) AS revenue_amount,
    CAST(discount_amount AS FLOAT) AS discount_amount,
    CAST(expense_amount AS FLOAT) AS expense_amount,
    CAST(default_interest_amount AS FLOAT) AS default_interest_amount,
    CAST(installment_fee_amount AS FLOAT) AS installment_fee_amount,
    DATE(dt_expiration_installment_agreement) AS dt_expiration_installment_agreement,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.installment_detail
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
