SELECT 
    COALESCE(id_invoice, -1) AS sk_invoice,
    COALESCE(id_contract, -1) AS sk_contract,
    due_amount,
    pd_range_rule_A,
    pd_range_rule_B,
    pd_range_rule_C,
    pd_range_rule_D,
    user,
    dt_closing,
    NOW() AS ts_load
FROM 
    datalake_losses.delay