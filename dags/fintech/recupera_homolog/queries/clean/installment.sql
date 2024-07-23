SELECT
    id_installment,
    id_creditor,
    id_customer,
    CAST(id_sequence_number AS INT) AS id_sequence_number,
    id_site,
    id_operator,
    receipt_code,
    CASE
        WHEN is_installment_active = "S" THEN True
        ELSE False
    END AS is_installment_active,
    CASE
        WHEN installment_situation = "A" THEN "Parcela em aberta"
        WHEN installment_situation = "P" THEN "Parcela paga"
        WHEN installment_situation = "Q" THEN "Acordo cancelado"
        ELSE installment_situation
    END AS installment_situation,
    CASE
        WHEN boleto_emission_indicator = "B" THEN "Parcelamento em boleto"
        WHEN boleto_emission_indicator = "D" THEN "Entrada DI (Depósito Identificado)"
        WHEN boleto_emission_indicator = "E" THEN "Carnê"
        WHEN boleto_emission_indicator = "H" THEN "Cartão de crédito"
        WHEN boleto_emission_indicator = "T" THEN "Débito em conta"
        WHEN boleto_emission_indicator = "K" THEN "Pix"
        ELSE boleto_emission_indicator
    END AS boleto_emission_indicator,
    CASE
        WHEN is_special_installment = "E" THEN True
        ELSE False
    END AS is_special_installment,
    advisory_code,
    CASE
        WHEN agreement_type = "F" THEN "Em assessoria por um operador interno"
        WHEN agreement_type = "A" THEN "Em assessoria por um operador de assessoria"
        WHEN NULLIF(agreement_type, "Nulo") IS NULL THEN "Fora de assessoria"
        ELSE agreement_type
    END AS agreement_type,
    CASE
        WHEN installlment_renegotiated = "R" THEN "Renegociação"
        WHEN installlment_renegotiated = "N" THEN "Acordo normal"
        WHEN NULLIF(installlment_renegotiated, "Nulo") IS NULL THEN "Acordo normal"
        ELSE installlment_renegotiated
    END AS installlment_renegotiated,
    installment_number,
    installments_amount,
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
    CAST(installment_rate AS FLOAT) AS installment_rate,
    CAST(discount_percentage AS FLOAT) AS discount_percentage,
    DATE(dt_due) AS dt_due,
    DATE(dt_installment) AS dt_installment,
    DATE(dt_paid) AS dt_paid,
    ts_load
FROM
    datalake_recupera_homolog_raw.installment
