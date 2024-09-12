SELECT
    AHID AS id_agreement,
    AHACCT AS id_client,
    AHCOLLID AS id_user,
    AHTYPE AS agreement_type,
    CASE
        WHEN AHACCTG = "1" THEN "QuintoAndar"
        WHEN AHACCTG = "2" THEN "QuintoCred"
        ELSE AHACCTG
    END AS contract_group,
    AHAUTCOLLID AS authorized_by_manager,
    AHSTACOLL AS manager_updated_status,
    AHFREQ AS frequency,
    AHPRD AS number_of_installments,
    CASE
        WHEN AHSTATUS = "A" THEN "Autorizado"
        WHEN AHSTATUS = "C" THEN "Cancelado"
        WHEN AHSTATUS = "P" THEN "Pendente"
        WHEN AHSTATUS = "F" THEN "Finalizado"
        ELSE AHSTATUS
    END AS status,
    CASE
        WHEN AHPYTYPE = "NO_INT" THEN "Sem Juros"
        WHEN AHPYTYPE = "EQUAL" THEN "Cota Constante (PRICE)"
        WHEN AHPYTYPE = "INCR" THEN "Cota Crescente (SAC)"
        WHEN AHPYTYPE = "DECR" THEN "Cota Decrescente"
        ELSE AHPYTYPE
    END AS type_interest_quota,
    AHCTTYPE AS contact_type,
    AHCSPERNT AS notify_central_system,
    CASE
        WHEN AHEXCP = "DSC" THEN "Acordos negociados com desconto maior do que o permitido na alçada do usuário e com pagamento inicial dentro da política"
        WHEN AHEXCP = "IPY" THEN "Acordos negociados com desconto dentro da alçada do usuário e com pagamento inicial fora da política"
        WHEN AHEXCP = "MUL" THEN "Acordos negociados com desconto maior do que o permitido na alçada do usuário e com pagamento fora da política"
        ELSE AHEXCP
    END AS exception,
    AHCSINITNT AS payments_to_notify,
    AHCNDPAYN AS number_payments_to_exempt,
    AHCNDPAYM AS required_number_payments_to_exempt,
    AHBREAK AS broken_payments,
    AHTOTPMT AS total_negotiated_amount_with_fees,
    AHTOTPMTSH AS total_negotiated_amount_without_fees,
    AGRHONO AS fees_amount,
    AHRATE AS interest_rate,
    AHRATE2 AS additional_interest_rate,
    AHGRPERTY AS payment_type_after_free_term,
    AHLVL AS level_agreement_authorization,
    AHNUMUP AS times_accordion_updated,
    AHFLFLVL AS percentage_paid_agreement,
    AHREGDT AS ts_agreement,
    AHDT AS ts_agreement_creation,
    AHAUTDT AS ts_authorized,
    AHSTADT AS ts_status_update,
    NOW() AS ts_load
FROM datalake_cyber_raw.agrhdr
