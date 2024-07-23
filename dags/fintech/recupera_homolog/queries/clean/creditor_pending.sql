SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_installment,
    CAST(id_sequence_number AS INT) AS id_sequence_number,
    CAST(sequential_avoid_duplication AS INT) AS sequential_avoid_duplication,
    id_operator,
    CAST(payment_option AS INT) AS payment_option,
    dat_emiss_notif,
    receipt_code,
    CASE
        WHEN is_calculation_finished = "S" THEN True
        ELSE False
    END AS is_calculation_finished,
    CASE
        WHEN is_installment = "S" THEN True
        ELSE False
    END AS is_installment,
    installment_code,
    cod_borde,
    auth_code,
    calculation_index_code,
    installment_number,
    installments_amount,
    CAST(index_quotation_amount AS INT) AS index_quotation_amount,
    CAST(expense_amount AS FLOAT) AS expense_amount,
    CAST(main_amount_paid AS FLOAT) AS main_amount_paid,
    CAST(main_amount AS FLOAT) AS main_amount,
    CAST(corrected_amount AS FLOAT) AS corrected_amount,
    CAST(charges_amount AS FLOAT) AS charges_amount,
    CAST(minimun_amount AS FLOAT) AS minimun_amount,
    CAST(amount_to_pay AS FLOAT) AS amount_to_pay,
    CAST(amount_fine AS FLOAT) AS amount_fine,
    CAST(interest_fee_amount AS FLOAT) AS interest_fee_amount,
    CAST(adm_fee_amount AS FLOAT) AS adm_fee_amount,
    CAST(revenue_amount AS FLOAT) AS revenue_amount,
    CAST(transfer_amount AS FLOAT) AS transfer_amount,
    CAST(discount_amount AS FLOAT) AS discount_amount,
    CAST(interest_fee_discount_amount AS FLOAT) AS interest_fee_discount_amount,
    DATE(dt_paid) AS dt_paid,
    DATE(dt_table_insertion) AS dt_table_insertion,
    DATE(dt_installment_due_date) AS dt_installment_due_date,
    DATE(dt_correction) AS dt_correction,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.creditor_pending
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
