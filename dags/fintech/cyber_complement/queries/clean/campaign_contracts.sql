SELECT
    CCID AS id_campaign,
    CCNUMOFERTA AS id_offer,
    CCACCTCOB AS id_contract,
    CCSSNUM AS id_client_id,
    CCIDPARC AS id_invoice,
    CCGRUPO AS contract_group,
    CASE
        WHEN CCGRUPO = "1" THEN "QuintoAndar"
        WHEN CCGRUPO = "2" THEN "QuintoCred"
        ELSE CCGRUPO
    END AS creditor,
    CCDAYS AS contract_delay_days,
    CCCURBAL AS contract_total_amount,
    CCAMTDLQ AS contract_due_amount,
    CCVLJURATRA AS contract_interest_amount,
    CCMULTCON AS contract_fine_amount,
    CCPAYOFF AS contract_debt_amount,
    CCVLCUSTASAG AS contract_cost_amount,
    CCVLPRINC AS invoice_main_amount,
    CCVLJUR AS invoice_interest_amount,
    CCVLMUL AS invoice_fine_amount,
    CCVLCUSTA AS invoice_cost_amount,
    CCHONORARIOS AS invoice_residual_honorarium_amount,
    CCVLRPRCAG AS invoices_ouverdue_amount,
    CCVLRPRCAVAG AS invoices_due_amount,
    CCVLRPRMUAGR AS invoices_residual_fine_amount,
    CCVLRPRJUAG AS invoices_residual_interest_amount,
    CCVLRCUSAG AS invoices_residual_cost_amount,
    CCVLRHOREAG AS invoices_residual_honorarium_amount,
    CCVLRMUAGR AS agreement_fine_amount,
    CCVLRJUAG AS agreement_interest_amount,
    CCVLRTXCARAG AS credit_card_fee_amount,
    CCDLQDT AS ts_due_contract_due,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_campanha_contrato
