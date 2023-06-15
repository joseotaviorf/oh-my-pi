SELECT 
    COALESCE(id_invoice, -1) AS sk_invoice,
    COALESCE(id_contract, -1) AS sk_contract,
    due_amount,
    pd_range_rule_a,
    pd_range_rule_b,
    pd_range_rule_c,
    pd_range_rule_d,
    user,
    dt_closing,
    NOW() AS ts_load
FROM 
    datalake_losses.delay
WHERE 
  payment_status <> 'written down'