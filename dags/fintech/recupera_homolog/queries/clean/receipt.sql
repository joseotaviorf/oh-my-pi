SELECT
    id_receipt,
    id_customer,
    id_operator,
    id_collection_operator,
    id_site,
    CASE
        WHEN type_receipt = "D" THEN "Recebimento em dia (pago)  - dinheiro, cheque"
        WHEN type_receipt = "F" THEN "Recebimento Futuro (em aberto) - boleto, cheque-pre"
        WHEN type_receipt = "P" THEN "Recebimento Futuro Depositado (pago) – cheque pre confirmado"
        WHEN type_receipt = "I" THEN "Recebimento Incompleto"
        WHEN type_receipt = "E" THEN "Estornado"
        WHEN type_receipt = "B" THEN "Depósito Bancário em Dinheiro – Deposito identificado"
        WHEN type_receipt = "G" THEN "Depósito Bancário em Cheque – Deposito identificado"
        WHEN type_receipt = "S" THEN "Ficha de Compensação – Boleto confirmado (pago)"
        WHEN type_receipt = "C" THEN "Carta-Boleto emitida (em aberto)"
        WHEN type_receipt = "U" THEN "Depósito Identificado (em aberto)"
        WHEN type_receipt = "J" THEN "Cartão credito (recebido)"
        WHEN type_receipt = "X" THEN "Pix pago"
        WHEN type_receipt = "K" THEN "Pix emitido"
        ELSE type_receipt
    END AS type_receipt,
    CASE
        WHEN type_receipt_original = "D" THEN "Recebimento em dia (pago)  - dinheiro, cheque"
        WHEN type_receipt_original = "F" THEN "Recebimento Futuro (em aberto) - boleto, cheque-pre"
        WHEN type_receipt_original = "P" THEN "Recebimento Futuro Depositado (pago) – cheque pre confirmado"
        WHEN type_receipt_original = "I" THEN "Recebimento Incompleto"
        WHEN type_receipt_original = "E" THEN "Estornado"
        WHEN type_receipt_original = "B" THEN "Depósito Bancário em Dinheiro – Deposito identificado"
        WHEN type_receipt_original = "G" THEN "Depósito Bancário em Cheque – Deposito identificado"
        WHEN type_receipt_original = "S" THEN "Ficha de Compensação – Boleto confirmado (pago)"
        WHEN type_receipt_original = "C" THEN "Carta-Boleto emitida (em aberto)"
        WHEN type_receipt_original = "U" THEN "Depósito Identificado (em aberto)"
        WHEN type_receipt_original = "J" THEN "Cartão credito (recebido)"
        WHEN type_receipt_original = "X" THEN "Pix pago"
        WHEN type_receipt_original = "K" THEN "Pix emitido"
        ELSE type_receipt_original
    END AS type_receipt_original,
    auth_code,
    bank_code,
    bank_agency_number,
    bank_account_number,
    check_number,
    compensation,
    customer_name,
    customer_document,
    CASE
        WHEN written_down_indicator = "N" THEN "Não baixado"
        WHEN written_down_indicator = "C" THEN "Já foi enviado para a tabela de cheque mas não foi baixado"
        WHEN written_down_indicator = "S" THEN "Registro baixado"
        ELSE written_down_indicator
    END AS written_down_indicator,
    CASE
        WHEN is_receipt_finalized = "S" THEN True
        ELSE False
    END AS is_receipt_finalized,
    cmc7_number,
    refund_reason_description,
    refund_reason_code,
    calculation_index_code,
    receipt_observation,
    CASE
        WHEN debt_type_indicator = "O" THEN "Recibo efetuado para originais"
        WHEN debt_type_indicator = "P" THEN "Recibo para parcelas de acordo"
        ELSE debt_type_indicator
    END AS debt_type_indicator,
    CAST(index_quotation_amount AS INT) AS index_quotation_amount,
    CAST(amount_paid_original AS FLOAT) AS amount_paid_original,
    CAST(amount_paid AS FLOAT) AS amount_paid,
    CAST(amount_fine AS FLOAT) AS amount_fine,
    CAST(interest_fee_amount AS FLOAT) AS interest_fee_amount,
    CAST(adm_fee_amount AS FLOAT) AS adm_fee_amount,
    CAST(revenue_amount AS FLOAT) AS revenue_amount,
    CAST(transfer_amount AS FLOAT) AS transfer_amount,
    CAST(discount_amount AS FLOAT) AS discount_amount,
    CAST(expense_amount AS FLOAT) AS expense_amount,
    DATE(dt_paid_original) AS dt_paid_original,
    DATE(dt_paid) AS dt_paid,
    DATE(dt_expected_transfer) AS dt_expected_transfer,
    DATE(dt_redeposit) AS dt_redeposit,
    TIMESTAMP(ts_inclusion) AS ts_inclusion,
    ts_load
FROM
    datalake_recupera_homolog_raw.receipt
