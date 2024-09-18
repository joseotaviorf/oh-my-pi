SELECT
    APAHID AS id_agreement,
    CONCAT(APAHID ,LPAD(APDETID, 3, '0')) AS id_agreement_installment,
    CASE
        WHEN APFLAG = "S" THEN "Programado"
        WHEN APFLAG = "C" THEN "Concluído"
        WHEN APFLAG = "R" THEN "Quebrado"
        WHEN APFLAG = "P" THEN "Pendente de Pagamento"
        ELSE APFLAG
    END AS status,
    CASE
        WHEN APFLAG2 = "S" THEN "Programado"
        WHEN APFLAG2 = "C" THEN "Concluído"
        WHEN APFLAG2 = "R" THEN "Quebrado"
    END AS revalued_payment_flag,
    APNOSSONUM AS our_number,
    APDETID AS installment_number,
    IFNULL(APAMZAMT,0) AS amortization_amount,
    IFNULL(APAMT,0) AS amount_to_pay,
    IFNULL(APAMTPAY,0) AS payment_amount,
    IFNULL(APINTAMT,0) AS installment_interest_amount,
    IFNULL(APHONO,0) AS honorarium_amount,
    IFNULL(APINTTAXAMT,0) AS credit_card_fee_amount,
    IFNULL(APBLNC,0) AS agreement_balance_amount,
    APINDATE AS ts_start_payment_term,
    APDUEDT AS ts_due_installment,
    NOW() AS ts_load
FROM datalake_cyber_raw.agpmtdet
