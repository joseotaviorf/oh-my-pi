SELECT
  c.sk_contract AS id_contract_ebdb,
  'quintoandar' AS management_fee_share,
  di.payment_status,
  c.monthly_administration_fee,
  COALESCE(p.administration_Split_Percentage,0) AS administration_split_percentage,
  ROUND((c.rent * c.monthly_administration_fee * (1.00 - COALESCE(p.administration_Split_Percentage,0))),2) AS prod_theorical_amount,
  ROUND(sum(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
  ROUND(sum(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
  i.accrual_year_month,
  DATE(di.ts_due) AS dt_due,
  DATE(di.ts_paid) AS dt_paid
FROM
    datalake_invoice.invoice_entries fie
INNER JOIN datalake_retsuko.invoice_entry die
    ON fie.id = die.id
LEFT JOIN datalake_retsuko.invoice_info di
    ON di.id_invoice = fie.id_invoice
LEFT JOIN datalake_retsuko.invoice i
    ON di.id_invoice = i.id_external
LEFT JOIN dw_rent.dim_contract c
    ON c.sk_contract = fie.id_contract
LEFT JOIN datalake_ebdb_clean.contract_partnership_data p
    ON c.sk_contract = p.id_contract
    AND p.administration_split_percentage IS NOT NULL
WHERE
    die.from_account_type NOT IN ('quinto andar', 'contract expenses')
AND
    di.payment_status <> 'canceled'
AND
    die.entry_type IN ('adm fee', 'igpm adm fee', 'ipca adm fee', 'lockin', 'adjustment agreement adm fee')
AND
    c.country_code = 'BR'
GROUP BY
    1,2,3,4,5,6,9,10,11
UNION
SELECT
  c.sk_contract AS id_contract_ebdb,
  'partner' AS management_fee_share,
  di.payment_status,
  c.monthly_administration_fee,
  COALESCE(p.administration_Split_Percentage,0) AS administration_split_percentage,
  ROUND((c.rent * c.monthly_administration_fee * COALESCE(p.administration_Split_Percentage,0)),2) AS prod_theorical_amount,
  ROUND(sum(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
  ROUND(sum(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
  i.accrual_year_month,
  DATE(di.ts_due) AS dt_due,
  DATE(di.ts_paid) AS dt_paid
FROM
    datalake_invoice.invoice_entries fie
INNER JOIN datalake_retsuko.invoice_entry die
    ON fie.id = die.id
LEFT JOIN datalake_retsuko.invoice_info di
    ON di.id_invoice = fie.id_invoice
LEFT JOIN datalake_retsuko.invoice i
    ON di.id_invoice = i.id_external
LEFT JOIN dw_rent.dim_contract c
    ON c.sk_contract = fie.id_contract
LEFT JOIN datalake_ebdb_clean.contract_partnership_data p
    ON c.sk_contract = p.id_contract
    AND p.administration_split_percentage IS NOT NULL
WHERE
    die.from_account_type NOT IN ('quinto andar', 'contract expenses')
AND
    di.payment_status <> 'canceled'
AND
    die.entry_type IN ('adm fee adm partner','igpm adm partner adm fee', 'ipca adm partner adm fee', 'adjustment agreement adm partner adm fee')
AND
    c.country_code = 'BR'
GROUP BY
    1,2,3,4,5,6,9,10,11
