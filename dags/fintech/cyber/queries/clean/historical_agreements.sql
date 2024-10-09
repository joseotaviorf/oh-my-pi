SELECT
    HAID AS id_agreement,
    HAACCT AS id_contract,
    AHIDPARC AS id_invoice,
    AHSSNUM AS id_client,
    HAACCTG AS contract_group,
    CASE
        WHEN HAACCTG = "1" THEN "QuintoAndar"
        WHEN HAACCTG = "2" THEN "QuintoCred"
        ELSE HAACCTG
    END AS creditor,
    AHDAYS AS contract_delay_days,
    AHCURBAL AS total_contract_amount,
    AHAMTDLQ AS contract_main_overdue_amount,
    AHVLJURATRA,
    AHMULTCON,
    AHVLVENC,
    AHVLPRINC AS invoice_due_amount,
    AHVLRPRCAG AS total_overdue_amount,
    AHVLRPRCAVAG AS main_due_amount,
    AHVLJUR AS invoice_interest_amount,
    AHVLRJUAG AS contract_interest_amount,
    AHVLRPRJUAG AS residual_interest_amount,
    AHVLMUL AS invoice_fine_amount,
    AHVLRMUAGR AS contract_fine_amount,
    AHVLRPRMUAGR AS residual_fine_amount,
    AHVLCUSTA AS invoice_residual_eviction_costs_amount,
    AHVLRCUSAG AS residual_eviction_costs_amount,
    AHVLCUSTASAG AS eviction_costs_amount,
    AHVLRDESPJUD AS legal_costs_amount,
    AHVLRTXCARAG AS credit_card_fee,
    AHVLRHOREAG AS residual_honorarium,
    AHHONORARIOS AS honorarium,
    AHDLQDT AS ts_due_contract,
    NOW() AS ts_load
FROM datalake_cyber_raw.agr_hist
