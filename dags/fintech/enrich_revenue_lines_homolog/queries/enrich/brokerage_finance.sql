SELECT
    cbf.id AS id_bfi,
    ies.id_contract AS id_contract_ebdb,
    c.rent,
    (c.rent * (1 - COALESCE(c.agent_brokerage_share, ofc.real_state_agent_share)) / cbf.installment_number) AS prod_theorical_amount,
    (c.rent * cbf.premium_fee / cbf.installment_number) AS prod_theorical_fee,
    CASE 
        WHEN entry_type = 'brokerage installment' THEN ies.brl_entry_due_amount 
        ELSE NULL 
    END AS invoice_theorical_amount,
    CASE 
        WHEN entry_type = 'brokerage installment' THEN ies.brl_entry_paid_amount 
        ELSE NULL 
    END AS invoice_paid_amount,
    CASE WHEN entry_type = 'brokerage installment fee' THEN ies.brl_entry_due_amount 
        ELSE NULL 
    END AS invoice_theorical_fee,
    CASE WHEN entry_type = 'brokerage installment fee' THEN ies.brl_entry_paid_amount 
        ELSE NULL 
    END AS invoice_paid_fee,
    cbf.installment_number AS total_installments,
    cbf.premium_fee,
    COALESCE(c.agent_brokerage_share, ofc.real_state_agent_share) AS real_state_agent_share,
    ri.accrual_year_month,
    cbf.ts_created AS dt_bf_created,
    dddue.date AS dt_due_fee,
    ddpaid.date AS dt_paid_fee
FROM
    datalake_invoice.invoice_entries AS ies
INNER JOIN
    datalake_retsuko.invoice_entry AS ie
    ON ies.id = ie.id
INNER JOIN
    datalake_retsuko.invoice_info AS i
    ON ies.id_invoice = i.id_invoice
LEFT JOIN
    datalake_retsuko.invoice AS ri
    ON i.id_invoice = ri.id_external
LEFT JOIN
    datalake_ebdb_contract.contract AS c
    ON ies.id_contract = c.id
LEFT JOIN
    datalake_owner_fees.contract AS ofc
    ON c.id = ofc.id_external
LEFT JOIN
    datalake_owner_fees.contract_brokerage_fee AS cbf
    ON ofc.id = cbf.id_contract
LEFT JOIN
    datalake_quintoandar.aux_date AS dddue
    ON dddue.id_date = ies.id_due_date
LEFT JOIN
    datalake_quintoandar.aux_date AS ddpaid
    ON ddpaid.id_date = ies.id_paid_date
WHERE
    from_account_type NOT IN ('quinto andar', 'contract expenses')
    AND i.payment_status <> 'canceled'
    AND entry_type IN ('brokerage installment fee', 'brokerage installment')