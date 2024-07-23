SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_installment,
    bank_branch_code,
    bank_account_number,
    CAST(payment_option AS INT) AS payment_option,
    CASE
        WHEN type_pendency_debt = "PA" THEN "parcelamento"
        WHEN type_pendency_debt = "DE" THEN "deposito identificado"
        WHEN type_pendency_debt = "OP" THEN "opção de pagamento"
        ELSE type_pendency_debt
    END AS type_pendency_debt,
    installment_code,
    installments_amount,
    installment_number,
    CAST(main_amount AS FLOAT) AS main_amount,
    CAST(corrected_amount AS FLOAT) AS corrected_amount,
    CAST(minimun_amount AS FLOAT) AS minimun_amount,
    CAST(amount_paid AS FLOAT) AS amount_paid,
    DATE(dt_debt_due_date) AS dt_debt_due,
    DATE(dt_last_debt_correction) AS dt_last_debt_correction,
    DATE(dt_contract_start) AS dt_contract_start,
    DATE(dt_paid) AS dt_paid,
    TIMESTAMP(ts_last_debt_update) AS ts_last_debt_update,
    ts_load
FROM
    datalake_recupera_homolog_raw.complementary_records
