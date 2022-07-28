WITH bill_items_clean AS (
  SELECT 
    bill_items.id,
    bill_items.id_external,
    bill_items.id_invoice,
    bill_items.id_contract,
    bill_items.id_from_account,
    bill_items.id_to_account,
    bill_items.accrual_year_month,
    bill_items.due_year_month,
    SUBSTRING(bill_item, CHARINDEX('/',bill_item) + 1, LENGTH(bill_item)) AS clean_bill_item,
    bill_items.description,
    from_acc.type as from_acc_type,
    to_acc.type as to_acc_type,
    CASE 
      WHEN REPLACE(from_acc.type, '-', ' ') LIKE '%contract%' AND REPLACE(to_acc.type, '-', ' ') NOT LIKE '%contract%' THEN REPLACE(to_acc.type, '-', ' ')
      WHEN REPLACE(from_acc.type, '-', ' ') NOT LIKE '%contract%' AND REPLACE(to_acc.type, '-', ' ') LIKE '%contract%' THEN REPLACE(from_acc.type, '-', ' ')
      WHEN REPLACE(from_acc.type, '-', ' ') LIKE '%contract%' AND REPLACE(to_acc.type, '-', ' ') LIKE '%contract%' THEN 'contract'
      ELSE NULL
    END AS invoice_user,
    CASE
      WHEN (from_acc.type='contract' AND to_acc.type='tenant') THEN (-1.0) * bill_items.amount
      WHEN (from_acc.type='contract' AND to_acc.type='landlord') THEN (-1.0) * bill_items.amount
      ELSE bill_items.amount 
    END AS amount_corrected_signal
  FROM 
    datalake_retsuko_clean.entry AS bill_items
  INNER JOIN 
    datalake_retsuko_clean.account AS from_acc 
      ON bill_items.id_from_account = from_acc.id
  INNER JOIN 
    datalake_retsuko_clean.account AS to_acc 
      ON bill_items.id_to_account = to_acc.id
),

filtered_bill_items AS (
  SELECT
    *
  FROM
    bill_items_clean
  WHERE 
    invoice_user = 'tenant'
    AND id_invoice IS NOT NULL
),

pre_pivot_items as (
  SELECT 
    id, 
    CASE clean_bill_item
      WHEN 'condominium' THEN 'pacote'
      WHEN 'iptu' THEN 'pacote'
      WHEN 'rental' THEN 'pacote'
      WHEN 'condominium-usage ' THEN 'pacote'
      WHEN 'condominium-fine' THEN 'pacote'
      WHEN 'early-termination-fee' THEN 'early-termination'
      WHEN 'repair-work' THEN 'protecao5a'
      WHEN 'light-water-or-gas' THEN 'protecao5a'
      WHEN 'residential-protection-5A-fund-transfer' THEN 'protecao5a'
      WHEN 'residential-protection-5A-acquittance' THEN 'protecao5a'
      WHEN 'property-damage-fine' THEN 'danos'
      ELSE 'outros'
    END AS item_group,
    amount_corrected_signal
  FROM 
    filtered_bill_items
),

pivoted_items AS (
  SELECT 
    * 
  FROM
    pre_pivot_items
  PIVOT(
    SUM(amount_corrected_signal)
    FOR item_group IN ( 'pacote', 'protecao5a', 'early-termination', 'danos', 'outros')
  ) 
),

grouped_bill_items AS (
  SELECT
    item.id_invoice,
    MIN(item.accrual_year_month) AS accrual_year_month,
    MIN(item.due_year_month) AS due_year_month,
    SUM(item.amount_corrected_signal) AS amount_entry,
    SUM(COALESCE(pivot.pacote,0)) AS pacote,
    SUM(COALESCE(pivot.protecao5a,0)) AS protecao5a,
    SUM(COALESCE(pivot.`early-termination`,0)) AS early_termination,
    SUM(COALESCE(pivot.danos,0)) AS danos,
    SUM(COALESCE(pivot.outros,0)) AS outros
  FROM 
    filtered_bill_items item
  LEFT JOIN 
    pivoted_items AS pivot
      ON item.id = pivot.id
  GROUP BY 1 
),

clean_invoices AS (
  SELECT 
    inv.id_contract,
    inv.id AS id_invoice,
    inv.id_external AS id_invoice_main,
    inv.purpose,
    inv.status,
    inv.ts_sent,
    inv.ts_due,
    inv.ts_paid,
    INT(ISNULL(inv.ts_paid)) AS flg_default,
    CASE
      WHEN ISNULL(inv.ts_paid) THEN 1
      WHEN DATEDIFF(COALESCE(inv.ts_paid, current_date()) , ts_due) > 60 THEN 1
      ELSE 0
    END AS is_ever90,
    DATEDIFF(COALESCE(inv.ts_paid,current_date()) , ts_due) AS dias_atraso,
    inv.due_amount * (-1) AS amount_invoice,
    entries.amount_entry,
    inv.paid_amount AS paid_amount_invoice,
    entries.pacote,
    entries.protecao5a,
    entries.danos,
    entries.early_termination,
    entries.outros
  FROM 
    datalake_retsuko_clean.invoice AS inv
  LEFT JOIN 
    grouped_bill_items AS entries
      ON entries.id_invoice = inv.id
  WHERE 
    inv.status NOT IN ('canceled', 'not-payable', 'written-down') 
    AND NOT (inv.ts_sent IS NULL AND inv.status = 'open' AND inv.purpose = 'extra' AND entries.pacote > 0)
    AND inv.purpose IN ('monthly', 'early-termination', 'extra', 'onboarding') 
    AND DATEDIFF(ts_due, current_date()) NOT BETWEEN -60 and 31
    AND inv.due_amount < 0
  ORDER BY inv.id_contract, inv.ts_due ASC
),

contracts_payment AS (
  SELECT 
    inv.id_contract,
    FIRST(contract.id_external) AS id_contract_main,
    FIRST(contract_ebdb.id_proposal) AS id_proposal,
    SUM(inv.amount_invoice) AS amount_invoice,
    SUM(inv.amount_entry) AS amount_entry,
    SUM(inv.paid_amount_invoice) AS paid_amount_invoice,
    SUM(inv.amount_invoice* flg_default) AS amount_invoice_default,
    SUM(inv.amount_entry* flg_default) AS amount_entry_default,
    SUM(inv.pacote * flg_default) AS package_default,
    SUM(inv.protecao5a * flg_default) AS protecao5a_default,
    SUM(inv.early_termination * flg_default) AS early_termination_default,
    SUM(inv.danos * flg_default) AS damage_default,
    SUM(inv.outros * flg_default) AS other_default,
    SUM(inv.amount_invoice* is_ever90) AS amount_invoice_ever90,
    SUM(inv.amount_entry* is_ever90) AS amount_entry_ever90,
    SUM(inv.pacote * is_ever90) AS package_ever90,
    SUM(inv.protecao5a * is_ever90) AS protecao5a_ever90,
    SUM(inv.early_termination * is_ever90) AS early_termination_ever90,
    SUM(inv.danos * is_ever90) AS damage_ever90,
    SUM(inv.outros * is_ever90) AS other_ever90,
    MAX(dias_atraso) AS max_late_days,
    MAX(DATEDIFF(COALESCE(CAST(contract_ebdb.dt_termination AS TIMESTAMP),current_date()) , ts_due) * flg_default) AS days_since_first_default,
    MAX(DATEDIFF(COALESCE(CAST(contract_ebdb.dt_termination AS TIMESTAMP),current_date()) , ts_due) * is_ever90) AS days_since_first_ever90,
    FIRST(INT(ISNOTNULL(contract_ebdb.dt_termination))) AS is_terminated,
    FIRST(CAST(contract_ebdb.dt_started AS TIMESTAMP)) AS dt_started,
    FIRST(CAST(contract_ebdb.dt_termination AS TIMESTAMP)) AS dt_termination
  FROM 
    clean_invoices inv
  LEFT JOIN 
    datalake_retsuko_clean.contract AS contract
      ON contract.id = inv.id_contract
  LEFT JOIN 
    datalake_ebdb_clean.contract AS contract_ebdb
      ON contract_ebdb.id = contract.id_external
  WHERE
    CAST(contract_ebdb.dt_started AS TIMESTAMP) >= '2019-01-01'
  GROUP BY 1
),

first_package AS (
  SELECT 
    id_contract,
    FIRST(rent) AS rent_price_first,
    FIRST(rent + iptu + home_insurance_value + condo_price) AS package_price_first
  FROM 
    datalake_ebdb_clean.contract_aud
  WHERE 
    ts_signed IS NOT NULL
  GROUP BY id_contract
)

SELECT
  contracts_payment.id_contract,
  contracts_payment.id_contract_main,
  contracts_payment.id_proposal,
  contract.city,
  contracts_payment.amount_invoice,
  contracts_payment.amount_entry,
  contracts_payment.paid_amount_invoice,
  contracts_payment.amount_invoice_default,
  contracts_payment.amount_entry_default,
  contracts_payment.package_default,
  contracts_payment.protecao5a_default,
  contracts_payment.early_termination_default,
  contracts_payment.damage_default,
  contracts_payment.other_default,
  contracts_payment.amount_invoice_ever90,
  contracts_payment.amount_entry_ever90,
  contracts_payment.package_ever90,
  contracts_payment.protecao5a_ever90,
  contracts_payment.early_termination_ever90,
  contracts_payment.damage_ever90,
  contracts_payment.other_ever90,
  contracts_payment.max_late_days,
  contracts_payment.days_since_first_default,
  contracts_payment.days_since_first_ever90,
  ROUND(contracts_payment.amount_invoice_default/contracts_payment.amount_invoice*100, 2) AS perc_default,
  ROUND(contracts_payment.amount_invoice_ever90/contracts_payment.amount_invoice*100, 2) AS perc_ever90,
  ROUND(first_package.package_price_first, 2) AS package_price_first,
  ROUND(first_package.rent_price_first, 2) AS rent_price_first,
  contracts_payment.is_terminated,
  contracts_payment.dt_started,
  contracts_payment.dt_termination
FROM 
  contracts_payment
LEFT JOIN 
  datalake_retsuko_clean.contract AS contract
    ON contract.id = contracts_payment.id_contract
LEFT JOIN 
  first_package AS first_package
    ON contracts_payment.id_contract_main = first_package.id_contract