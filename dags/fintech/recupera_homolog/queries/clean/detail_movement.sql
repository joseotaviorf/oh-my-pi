SELECT
    id_site,
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_installment,
    CAST(id_sequence_number AS INT) AS id_sequence_number,
    id_operator,
    receipt_code,
    CASE
        WHEN installment_status = "L" THEN "Liquidação"
        WHEN installment_status = "A" THEN "Amortização"
        ELSE installment_status
    END AS installment_status,
    auth_code,
    customer_name,
    customer_document,
    CASE
        WHEN receipt_type = "C" THEN "Cheque-Dia"
        WHEN receipt_type = "P" THEN "Cheque-Pré"
        WHEN receipt_type = "D" THEN "Dinheiro"
        WHEN receipt_type = "B" THEN "Depósito em dinheiro"
        WHEN receipt_type = "G" THEN "Depósito em Cheque"
        WHEN receipt_type = "S" THEN "Ficha de Compensação"
        WHEN receipt_type = "J" THEN "Cartão de Crédito"
        WHEN receipt_type = "X" THEN "Pix pago"
        ELSE receipt_type
    END AS receipt_type,
    CASE
        WHEN is_promise_generated = "S" THEN True
        ELSE False
    END AS is_promise_generated,
    refund_reason_description,
    CASE
        WHEN payment_type = "4" THEN "Liquidação"
        WHEN payment_type = "3" THEN "Parcela Intermediária"
        WHEN payment_type = "9" THEN "Entrada"
        ELSE payment_type
    END AS payment_type,
    refund_reason_code,
    calculation_index_code,
    expense_accountability,
    CASE
        WHEN accountability_status = "N" THEN "Liberado"
        WHEN accountability_status = "S" THEN "Suspenso"
        WHEN accountability_status = "R" THEN "Redepósito"
        WHEN accountability_status = "E" THEN "Estornado"
        WHEN accountability_status = "P" THEN "Prestado Contas"
        ELSE accountability_status
    END AS accountability_status,
    operator_name,
    installment_number,
    CAST(installments_amount AS INT) AS installments_amount,
    CAST(index_quotation_amount AS INT) AS index_quotation_amount,
    CAST(main_amount AS FLOAT) AS main_amount,
    CAST(amount_paid AS FLOAT) AS amount_paid,
    CAST(amount_fine AS FLOAT) AS amount_fine,
    CAST(interest_fee_amount AS FLOAT) AS interest_fee_amount,
    CAST(adm_fee_amount AS FLOAT) AS adm_fee_amount,
    CAST(revenue_amount AS FLOAT) AS revenue_amount,
    CAST(transfer_amount AS FLOAT) AS transfer_amount,
    CAST(discount_amount AS FLOAT) AS discount_amount,
    CAST(expense_amount AS FLOAT) AS expense_amount,
    DATE(dt_written_down) AS dt_written_down,
    DATE(dt_installment_due_date) AS dt_installment_due_date,
    DATE(dt_paid) AS dt_paid,
    DATE(dt_expected_transfer) AS dt_expected_transfer,
    DATE(dt_expense_accountability) AS dt_expense_accountability,
    DATE(dt_redeposit) AS dt_redeposit,
    DATE(dt_transfer) AS dt_transfer,
    ts_load
FROM
    datalake_recupera_homolog_raw.detail_movement
