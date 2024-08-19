SELECT
    AHID AS id_negotiation,
    AHTYPE AS id_type_agreement,
    AHACCT AS id_contract,
    CASE
        WHEN AHACCTG = "1" THEN "QuintoAndar"
        WHEN AHACCTG = "2" THEN "QuintoCred"
        ELSE AHACCTG
    END AS contract_group,
    AHCOLLID AS agreement_capture_by_manager,
    AHAUTCOLLID AS authorized_by_manager,
    AHFREQ AS frequency,
    AHPRD AS term,
    CASE
        WHEN AHSTATUS = "A" THEN "Autorizado"
        WHEN AHSTATUS = "C" THEN "Cancelado"
        WHEN AHSTATUS = "P" THEN "Pendente"
        ELSE AHSTATUS
    END AS status,
    AHPYTYPE AS payment_type,
    AHCTTYPE AS contact_type,
    AHCSPERNT AS notify_central_system,
    AHCSINITNT AS payments_to_notify,
    AHCNDPAYN AS number_payments_to_exempt,
    AHCNDPAYM AS required_number_payments_to_exempt,
    AHBREAK AS broken_payments,
    AHTOTPMT AS total_payment_including_discount,
    AHRATE AS interest_rate,
    AHRATE2 AS additional_interest_rate,
    AHGRPERTY AS payment_type_after_free_term,
    AHLVL AS level_agreement_authorization,
    AHEXCP AS exception_code_creation,
    AHNUMUP AS times_accordion_updated,
    AHFLFLVL AS percentage_paid_agreement,
    AHREGDT AS ts_agreement,
    AHDT AS ts_negotiation_creation,
    AHAUTDT AS ts_authorized,
    AHFLGACT,
    AHACTUSR,
    AHDSCQB,
    AHDTQB,
    AHSTADT,
    AHSTACOLL,
    AHDTCANC,
    AHCYTYPE,
    AHMIGRACAO,
    AHSERVENVQB,
    AHQBENVIADA,
    AHCNIMPERS,
    AGRHONO,
    AHTOTPMTSH
FROM datalake_cyber_raw.agrhdr
