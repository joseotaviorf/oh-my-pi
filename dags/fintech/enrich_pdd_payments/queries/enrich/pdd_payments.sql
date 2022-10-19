WITH vans_payments(
  WITH boleto AS (
    SELECT
      id,
      id_related_document,
      company_use,
      'charge' AS type,
      related_document_type,
      due_amount,
      dt_paid,
      ts_created,
      ts_issued
    FROM 
      datalake_vans_clean.boleto
  ),
  payment AS (
    SELECT
      id,
      id_related_document,
      company_use,
      'transfer' AS type,
      related_document_type,
      due_amount,
      dt_paid,
      ts_created,
      ts_issued
    FROM 
      datalake_vans_clean.payment
    ),
    consolidation_table AS (
      SELECT * FROM boleto
      UNION ALL
      SELECT * FROM payment
  ),
  delete_documents_repeated AS (
    SELECT
      MAX(id) AS max_id,
      NULLIF(REGEXP_EXTRACT(company_use, '(\\d+\\D\\d{{4}})', 1), '') AS id_company_use, 
      company_use,
      ts_created,
      ts_issued,
      dt_paid
    FROM 
      consolidation_table
    GROUP BY 2,3,4,5,6
  ),
  vans_payments AS (
    SELECT 
      cons.*
    FROM 
      consolidation_table cons
    JOIN 
      delete_documents_repeated del
        ON cons.id = del.max_id
          AND del.company_use <=> cons.company_use
          AND del.ts_created <=> cons.ts_created
          AND del.ts_issued <=> cons.ts_issued
          AND del.dt_paid <=> cons.dt_paid
  )
  
  SELECT
    CASE 
      WHEN related_document_type = 'invoice' THEN COALESCE(CAST(id_related_document AS BIGINT), -1)
      ELSE -1
    END AS id_invoice,
    CASE 
      WHEN type = 'charge' THEN due_amount
      WHEN type = 'transfer' THEN (-1)*due_amount
      WHEN type = 'account payable' THEN due_amount
    END AS brl_due_amount
  FROM 
    vans_payments
),

invoices_data AS (
  SELECT
    rci.id_external AS id_invoice,
    rcc.id_external AS id_contract,
    rci.purpose AS frequency,
    rci.status AS payment_status,
    rca.type AS user,
    rci.due_amount,
    rci.paid_amount,
    vp.brl_due_amount AS original_amount,
    rci.accrual_year_month,
    CAST(ts_sent AS date) AS dt_sent,
    CAST(ts_due AS date) AS dt_due,
    CAST(ts_paid AS date) AS dt_paid,
    rci.ts_canceled,
    rci.ts_created
  FROM 
    datalake_retsuko_clean.invoice AS rci
  LEFT JOIN 
    datalake_retsuko_clean.account AS rca 
      ON rca.id = rci.id_account
  LEFT JOIN 
    datalake_retsuko_clean.contract AS rcc 
      ON rcc.id = rci.id_contract
  LEFT JOIN 
    vans_payments AS vp 
      ON vp.id_invoice = rci.id_external
  WHERE 
    rci.due_amount <= 0
    AND ((rci.ts_paid IS NULL) OR (rci.ts_paid >= DATE('2022-01-01')))
    AND (rci.due_amount < 0 OR (rci.due_amount <= 0 AND rci.status = 'canceled'))
    AND rci.status != 'not-payable'
),

contracts_retsuko AS (
  SELECT 
    e.id_contract, 
    i.id_external AS id_invoice,
    e.accrual_year_month
  FROM 
    datalake_retsuko.invoice_entry AS e
  LEFT JOIN 
    datalake_retsuko_clean.invoice AS i 
      ON i.id = e.id_invoice
  WHERE
    i.id_external IS NOT NULL
    AND UPPER(e.description) LIKE '%ACORDO COBRAN%' 
    AND UPPER(e.bill_item) LIKE '%ENTRY.BILL-ITEM/INSURANCE-GUARANTEE%'
),

dt_probable_created AS (
  SELECT
    accrual_year_month,
    COUNT(1) AS records,
    TO_DATE(CONCAT(STRING(accrual_year_month), LPAD(STRING(DAY(ts_created)), 2, 0)), 'yyyyMMdd') AS dt_probable_created,
    ROW_NUMBER() OVER (PARTITION BY accrual_year_month ORDER BY COUNT(1) DESC) as rn
  FROM
    invoices_data
  GROUP BY 1, 3
),

dt_probable_due AS (
  SELECT
    accrual_year_month,
    COUNT(1) AS records,
    dt_due AS dt_probable_due,
    ROW_NUMBER() OVER (PARTITION BY accrual_year_month ORDER BY COUNT(1) DESC) as rn
  FROM
    invoices_data
  GROUP BY 1, 3
),

probables_dates AS (
  SELECT
    c.accrual_year_month,
    dt_probable_created,
    dt_probable_due
  FROM
    dt_probable_created AS c
  LEFT JOIN
    dt_probable_due AS d
      ON c.accrual_year_month = d.accrual_year_month
  WHERE
    c.rn = 1
    AND d.rn = 1
),

invoices_to_receive AS (
  SELECT
    i.id_invoice,
    i.id_contract,
    i.frequency,
    i.payment_status,
    i.user,
    i.due_amount,
    paid_amount,
    DATEDIFF(i.dt_due, pd.dt_probable_created) AS days_until_due,
    i.accrual_year_month,
    i.ts_created,
    i.dt_sent,
    CASE
      WHEN DATEDIFF(i.dt_due, pd.dt_probable_created) >= 30 THEN pd.dt_probable_due
      ELSE i.dt_due
    END AS dt_due,
    i.dt_paid,
    i.ts_canceled,
    i.original_amount,
    DATE(i.ts_created) AS dt_created,
    pd.dt_probable_created,
    pd.dt_probable_due
  FROM
    invoices_data as i
  LEFT JOIN
    probables_dates AS pd
      ON i.accrual_year_month = pd.accrual_year_month
),

invoices_to_receive_adjusted AS (
  SELECT
    id_invoice,
    id_contract,
    frequency,
    CASE
      WHEN payment_status = 'written-down' AND dt_paid >= DATE('{year}-{month}-{day}') THEN 'writtendown-to-open'
      WHEN payment_status = 'canceled' AND ts_canceled >= DATE('{year}-{month}-{day}') THEN 'canceled-to-open'
      ELSE payment_status
    END AS payment_status,
    user,
    due_amount,
    paid_amount,
    days_until_due,
    original_amount,
    accrual_year_month,
    ts_created,
    dt_sent,
    dt_due,
    IF((payment_status = 'written-down' AND dt_paid >= DATE('{year}-{month}-{day}'))
        OR (payment_status = 'canceled' AND ts_canceled >= DATE('{year}-{month}-{day}')), NULL, dt_paid) AS dt_paid,
    ts_canceled,
    dt_created,
    dt_probable_created,
    dt_probable_due
  FROM
    invoices_to_receive
),

invoices_at_closing AS (
  SELECT 
    *,
    CASE
      WHEN dt_due >= DATE('{year}-{month}-{day}') THEN DATEDIFF(dt_due, DATE('{year}-{month}-{day}'))
      WHEN dt_paid IS NOT NULL THEN DATEDIFF(dt_due, IF(dt_paid < DATE('{year}-{month}-{day}'), dt_paid, DATE('{year}-{month}-{day}')))
      ELSE -1*(DATEDIFF(DATE('{year}-{month}-{day}'), dt_due))
    END AS delta_days
  FROM 
    invoices_to_receive_adjusted
  WHERE 
    payment_status != 'canceled'
    AND (dt_paid IS NULL OR dt_paid >= DATE('{year}-{month}-{day}')) 
    AND ts_created < DATE_ADD('{year}-{month}-{day}', 1) 
),

late_contracts AS (
  SELECT
    id_contract,
    user,
    MIN(dt_due) AS dt_min_contract_due
  FROM
    invoices_at_closing
  WHERE
    delta_days < 0 AND
    (payment_status != 'paid' OR dt_paid >= DATE('{year}-{month}-{day}')) 
  GROUP BY 1, 2
),

invoices_at_closing_with_minimum_date AS (
  SELECT
    closing.*,
    IF(lc.dt_min_contract_due IS NULL, closing.dt_due, lc.dt_min_contract_due) AS dt_min_contract_due
  FROM 
    invoices_at_closing AS closing
  LEFT JOIN
    late_contracts AS lc
      ON closing.id_contract = lc.id_contract
        AND closing.user = lc.user
),

old_due_dates AS (
  SELECT
    cr.id_invoice,
    MIN(dates.dt_probable_due) AS dt_min_contract_due_dealed
  FROM
    contracts_retsuko AS cr
  LEFT JOIN
    probables_dates AS dates
      ON cr.accrual_year_month = dates.accrual_year_month
  GROUP BY 1
),

invoices_at_closing_with_minimum_date_w_deal AS (
  SELECT
    closing.id_invoice,
    closing.id_contract,
    closing.frequency,
    closing.payment_status,
    closing.user,
    closing.due_amount,
    closing.paid_amount,
    closing.original_amount,
    closing.days_until_due,
    closing.delta_days,
    closing.accrual_year_month,
    closing.ts_created,
    closing.dt_sent,
    closing.dt_due,
    closing.dt_paid,
    closing.ts_canceled,
    closing.dt_created,
    closing.dt_probable_created,
    closing.dt_probable_due,
    CASE 
      WHEN due.dt_min_contract_due_dealed IS NULL THEN closing.dt_min_contract_due
      WHEN due.dt_min_contract_due_dealed <= closing.dt_min_contract_due THEN due.dt_min_contract_due_dealed
      ELSE closing.dt_min_contract_due
    END AS dt_min_contract_due,
    CASE
      WHEN dt_min_contract_due >= DATE('{year}-{month}-{day}') THEN DATEDIFF(dt_min_contract_due, DATE('{year}-{month}-{day}')) 
      WHEN dt_paid IS NOT NULL THEN DATEDIFF(dt_min_contract_due, IF(dt_paid <= DATE('{year}-{month}-{day}'), dt_paid, DATE('{year}-{month}-{day}'))) 
      ELSE -1 * DATEDIFF(DATE('{year}-{month}-{day}'), dt_min_contract_due)
    END AS delta_days_contaminated
  FROM 
    invoices_at_closing_with_minimum_date AS closing
  LEFT JOIN 
    old_due_dates AS due
      ON closing.id_invoice = due.id_invoice
),

contaminated_contracts AS (
  SELECT DISTINCT
    id_contract,
    'HR'AS flag_risk
  FROM
    invoices_at_closing_with_minimum_date_w_deal
  WHERE 
    frequency IN ('extra','pos rental', 'pos-rental')
),

pd_range AS (
  SELECT
    closing.*,
    CASE 
      WHEN delta_days_contaminated <= -181 THEN 'TotalM +6 (>181 days)'
      WHEN delta_days_contaminated BETWEEN -180 AND -151 THEN 'TotalM +5 (151-180 days)'
      WHEN delta_days_contaminated BETWEEN -150 AND -121 THEN 'TotalM +4 (121-150 days)'
      WHEN delta_days_contaminated BETWEEN -91 AND -120 THEN 'TotalM +3 (91-120 days)'
      WHEN delta_days_contaminated BETWEEN -61 AND -90 THEN 'TotalM +2 (61-90 days)'
      WHEN delta_days_contaminated BETWEEN -60 AND -31 THEN 'TotalM +1 (31-60 days)'
      WHEN delta_days_contaminated BETWEEN -30 AND -1 THEN 'TotalM +0 (1-30 days)'
      WHEN delta_days_contaminated >= 0 THEN 'TotalCurrent'
    END AS pd_range,
    IF(cc.flag_risk IS NULL, 'LR', cc.flag_risk) AS flag_risk
  FROM
    invoices_at_closing_with_minimum_date_w_deal AS closing
  LEFT JOIN
    contaminated_contracts AS cc
      ON closing.id_contract = cc.id_contract
)

SELECT
  id_invoice,
  id_contract,
  frequency,
  payment_status,
  user,
  pd_range,
  flag_risk,
  due_amount,
  paid_amount,
  original_amount,
  CAST(-1*(CASE 
    WHEN flag_risk = 'LR' AND pd_range = 'TotalCurrent' THEN due_amount * 0.61/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +0 (1-30 days)' THEN due_amount * 23/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +1 (31-60 days)' THEN due_amount * 54.09/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +2 (61-90 days)' THEN due_amount * 77.94/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +3 (91-120 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +4 (121-150 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +5 (151-180 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'LR' AND pd_range = 'TotalM +6 (>181 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalCurrent' THEN due_amount * 45.69/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +0 (1-30 days)' THEN due_amount * 96.69/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +1 (31-60 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +2 (61-90 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +3 (91-120 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +4 (121-150 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +5 (151-180 days)' THEN due_amount * 100/100
    WHEN flag_risk = 'HR' AND pd_range = 'TotalM +6 (>181 days)' THEN due_amount * 100/100
  END) AS FLOAT) AS pdd,
  days_until_due,
  delta_days,
  delta_days_contaminated,
  accrual_year_month,
  dt_sent,
  dt_due,
  dt_paid,
  dt_probable_created,
  dt_probable_due,
  dt_min_contract_due,
  ts_created,
  ts_canceled,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  pd_range