SELECT
    PMACCT AS id_contract,
    PMTDDESC AS id_invoice,
    PMID AS id_payment,
    CASE
        WHEN PMACCTG = "1" THEN "QuintoAndar"
        WHEN PMACCTG = "2" THEN "QuintoCred"
        ELSE PMACCTG
    END AS contract_group,
    CASE
        WHEN PMTCODE = "PE" THEN "Pagamento espontâneo"
        WHEN PMTCODE = "PC" THEN "Pagamento Acordo"
        WHEN PMTCODE = "PP" THEN "Promessa Pagamento"
        WHEN PMTCODE = "ES" THEN "Estorno"
        ELSE PMTCODE
    END AS payment_type,
    PMCOLLID AS manager,
    PMQUE AS queue,
    CASE
        WHEN PMBATCH = 1 THEN "Boleto"
        WHEN PMBATCH = 2 THEN "PIX"
        WHEN PMBATCH = 3 THEN "Cartão de Crédito"
        ELSE PMBATCH
    END AS payment_method,
    PMAGENCY AS agency,
    PMTYPE AS error_code,
    PMTDCOLM AS field_affected,
    PMTDFLAG AS trandefs_flag,
    PMTDSEQ AS trandefs_sequence,
    PMTDPCNT AS trandefs_percentage,
    PMTAMT AS payment_amount,
    PMAMOUNT AS actual_amount,
    PMPRVVAL AS previous_field_value,
    PMCURVAL AS field_value_after_calculation,
    PMDTCICLO,
    PMSSNUM,
    PMAGENCYPRM,
    PMAGENCYPRM_FLAG,
    PMTDATE AS ts_payment,
    PMEDATE AS ts_registration_transaction,
    PMREFDT AS ts_transaction_referred
FROM datalake_cyber_raw.pmtfil
