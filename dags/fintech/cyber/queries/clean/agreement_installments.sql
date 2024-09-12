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
    APAMT AS amount_to_pay,
    APAMTPAY AS payment_amount,
    APINTAMT AS interest_amount,
    APHONO AS fees_amount,
    APINTTAXAMT AS credit_card_fee_amount,
    APAMZAMT AS amortization_amount,
    APBLNC AS final_balance,
    APINDATE AS ts_start_payment_term,
    APDUEDT AS ts_due_installment,
    NOW() AS ts_load
FROM datalake_cyber_raw.agpmtdet
