SELECT
    BLID AS id_invoice,
    BLSSNUM AS id_client,
    CAST(BLNUMACORDO AS STRING) AS id_agreement,
    BLCCT AS id_contract,
    BLCODEMP AS id_company,
    BLAGENCIA AS id_agency,
    BLCCTG AS contract_group,
    CASE
        WHEN BLCCTG = "1" THEN "QuintoAndar"
        WHEN BLCCTG = "2" THEN "QuintoCred"
        ELSE BLCCTG
    END AS creditor,
    BLCODCLIENTE AS client_code,
    BLCEDENTE AS assignor,
    BLDVAGENCIA AS dv_bank_agency,
    BLCONTCOR AS bank_account_number,
    BLDVCONTCOR AS dv_bank_account,
    BLNOSSONUM AS our_number,
    BLNUMDOC AS document_number,
    BLTPDOC AS document_type,
    BLACEITE AS acceptance_code,
    BLSACNOME AS drawer_name,
    BLSACCPFCNPJ AS drawer_cpf_cnpj,
    BLSACEND AS drawer_address,
    BLSACBAIRRO AS drawer_neighborhood,
    BLSACCEP AS drawer_zip_code,
    BLSACCIDADE AS drawer_city,
    BLSACUF AS drawer_state,
    BLSACENDCMP AS drawer_address_proof,
    BLINST1 AS instruction_1,
    BLINST2 AS instruction_2,
    BLINST3 AS instruction_3,
    BLINST4 AS instruction_4,
    BLINST5 AS instruction_5,
    BLLOCAL1 AS location_1,
    BLLOCAL2 AS location_2,
    BLLINHADIG AS digitable_line,
    BLCODBARRA AS barcode,
    BLNUMPARC AS installment_number,
    BLJURDIA AS interest_day,
    CASE
        WHEN BLSTATUS = "C" THEN "cancelado"
        WHEN BLSTATUS = "A" THEN "aberto"
        WHEN BLSTATUS = "P" THEN "pendente"
        WHEN BLSTATUS = "F" THEN "finalizado"
        ELSE BLSTATUS
    END AS status,
    BLQTDEPARC AS total_number_installments,
    BLTIPOBOLETO AS type_invoice,
    BLACCTCOB AS agreement_billing_account,
    BLNOSSONUMDV AS dv_our_number,
    CASE
        WHEN BLFLAG_ARREC = "1" THEN "CNAB"
        WHEN BLFLAG_ARREC = "2" THEN "Lotérica"
        ELSE BLFLAG_ARREC
    END AS origin,
    BLCEDENTECNPJ AS transferor_of_cnpj,
    BLCNPJCED AS transferor_cnpj,
    BLDVBANCO AS transferor_bank_check_digit,
    BLNUMBANCO AS transferor_bank_number,
    BLCARTEIRA AS invoice_wallet,
    BLLAYOUTPEFIN AS layout_pefin,
    BLMOEDA AS currency,
    BLFLENVIOENT AS has_first_invoice_already_been_issued,
    BLFLENVIOPRT AS has_invoice_already_been_issued,
    BLAGCOBR AS client_bank_agency,
    BLBCCOBR AS client_bank,
    BLNUMCC AS client_bank_current_account,
    BLFLENVIOLEG AS has_sent_boleto,
    BLTIPOBOL AS boleto_type,
    BLBANCOCED AS originating_bank,
    CASE
        WHEN BLTIPOREGTIT = 'O' THEN 'Online'
        WHEN BLTIPOREGTIT = 'B' THEN 'Batch'
        WHEN BLTIPOREGTIT IS NULL THEN 'Não registrado'
        ELSE BLTIPOREGTIT
    END AS title_type,
    BLESPECIE AS document_specie,
    BLCOPIACOLA AS copy_paste_pix,
    BLVLBOLETO AS invoice_amount,
    BLVLDIVIDA AS debt_amount,
    BLVLPRINC AS main_amount,
    BLMULTA AS fine_amount,
    BLVLPAGO AS paid_amount,
    BLDTSOLICREGTIT AS dt_request_title_registration_bank,
    BLRESV3 AS dt_boleto_update,
    BLDTVENC AS ts_due,
    BLDTDOC AS ts_document,
    BLDTPROC AS ts_processing,
    BLDTUPDATE AS ts_record_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_boleto
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
