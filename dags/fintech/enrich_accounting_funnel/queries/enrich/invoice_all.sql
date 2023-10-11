WITH locale_ids AS (
  SELECT
    DISTINCT city,
    min(id_locale) AS id_locale
  FROM
    datalake_gsheets_clean.cod_locale
  GROUP BY 1
),
deduplicate_sap_entity AS (
  SELECT
    DISTINCT id_finance_entity,
    IF(version IS NULL, 'v1', version) AS version
  FROM
    datalake_retsuko_clean.sap_entity
),
remove_reversed AS (
  SELECT 
    die.sk_invoice_reversed_entry AS id_entry,
    DATE(fie.ts_created) AS dt_reversal
  FROM 
    dw_payment.fact_invoice_entries fie
  INNER JOIN 
    dw_payment.dim_invoice_entry die 
      ON fie.sk_invoice_entry = die.sk_invoice_entry
  WHERE 
    sk_invoice_reversed_entry IS NOT NULL

  UNION ALL

  SELECT 
    die.sk_invoice_entry AS id_entry,
    DATE(fie.ts_created) AS dt_reversal
  FROM 
    dw_payment.fact_invoice_entries fie
  INNER JOIN 
    dw_payment.dim_invoice_entry die 
      ON fie.sk_invoice_entry = die.sk_invoice_entry
  WHERE 
    die.sk_invoice_reversed_entry IS NOT NULL
),
remove_first_reversed AS (
SELECT 
    id_entry, 
    dt_reversal
FROM 
    remove_reversed
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entry ORDER BY dt_reversal) = 1
),
next_business_day AS (
  SELECT
    dd.date,
    MIN(dd_next.date) AS date_next_bd
  FROM
    dw_public.dim_date AS dd
  LEFT JOIN
    dw_public.dim_date AS dd_next
      ON dd_next.working_days_in_month <> dd.working_days_in_month
      AND dd_next.date > dd.date
      AND dd_next.working_days_in_month > 0
  GROUP BY
    1
)
SELECT DISTINCT
  fie.sk_invoice_entry AS id_entry,
  ie.sk_invoice_reversed_entry,
  fie.sk_invoice AS id_invoice,
  fie.sk_contract,
  ie.accounting_transaction_identifier,
  CASE
    WHEN CHARINDEX('.', c.version)> 0 THEN  SUBSTRING(c.version, 1, CHARINDEX('.', c.version)-1)
    ELSE COALESCE(c.version, 'no info')
  END AS version,
  IF(sap.version IS NULL, 'v1', sap.version) as accounting_version,
  c.is_contract_b2b,
  c.dt_start > c1.dt_termination AND c1.dt_termination IS NOT NULL AS ended_before_started,
  r.city_name AS locale,
  cl.id_locale AS localidade,
  c.guarantee,
  c.rental_administrator,
  CASE
    WHEN
        c.status='Ativo' and c.ts_expected_termination is null THEN 'Ativo'
    WHEN
        c.status='Ativo' and c.ts_expected_termination is not null THEN 'Finalizando'
    ELSE
        c.status END
    AS contract_status,
  ie.is_rental_paid_in_advance,
  IF(rr.id_entry IS NULL, False, True) AS is_reversed,
  ie.entry_type AS bill_item,
  ie.description,
  CASE
    WHEN UPPER(ie.description) LIKE '%ACORDO%' THEN 1
    ELSE 0
  END AS has_negotiation,
  CASE
    WHEN (try_cast(reverse(CASE WHEN description like '%arcela%' THEN split(reverse(description), ' ed ')[1] ELSE '1' END) as bigint)) > 1 THEN 1
    ELSE 0
  END AS has_installments,
  i.frequency AS purpose,
  COALESCE(i.user, 'quinto-andar') AS invoice_account_type,
  ie.from_account_type,
  ie.to_account_type,
  ie.producer,
  CASE
    WHEN ie.from_account_type = 'tenant' OR ie.to_account_type = 'tenant' THEN 'tenant'
    WHEN ie.from_account_type = 'landlord' OR ie.to_account_type = 'landlord' THEN 'landlord'
    ELSE 'other'
  END AS account_type,
  CASE
    WHEN entry_type IN ('brokerage installment fee', 'brokerage loan fidc', 'brokerage fidc') THEN 'receivable'
    WHEN entry_type IN ('postponement', 'payment adjustment') AND (ie.from_account_type = 'tenant' OR ie.to_account_type = 'tenant') THEN 'receivable'
    WHEN entry_type IN ('postponement', 'payment adjustment') AND (ie.from_account_type = 'landlord' OR ie.to_account_type = 'landlord') THEN 'payable'
    WHEN (ROUND(-1.0*i.due_amount,2) > 0 OR (ROUND(-1.0*i.due_amount,2) = 0 AND NOT(from_account_type = 'landlord' OR to_account_type= 'landlord') )) THEN 'receivable'
    ELSE 'payable'
  END AS account_classification,
  CASE
    WHEN
        i.payment_status IS NULL
        AND (ie.from_account_type = 'landlord' OR ie.to_account_type = 'landlord')
        AND (dd_entry_created.date >= date_trunc('month',DATEADD(MONTH,-1,current_date)))
    THEN 'preview'
    ELSE COALESCE(i.payment_status, 'not-invoiceable')
  END AS status,
  i.closing_mode,
  i.paid_via,
  ROUND(fie.brl_entry_due_amount,2) AS due_amount,
  ROUND(-1.0*i.due_amount,2) AS invoice_due_amount,
  CASE
    WHEN
        i.payment_status IS NULL
        AND (ie.from_account_type = 'landlord' OR ie.to_account_type = 'landlord')
        AND (dd_entry_created.date >= date_trunc('month',DATEADD(MONTH,-1,current_date)))
    THEN CAST(DATE_FORMAT(DATEADD(MONTH, 1, dd_entry_created.date), 'yyyyMM') AS INT)
    ELSE i.accrual_year_month
  END AS accrual_year_month,
  i.accrual_year_month AS invoice_accrual_year_month,
  ie.accrual_year_month AS entry_accrual_year_month,
  CAST(DATE_FORMAT(DATEADD(month, 1, dd_entry_created.date), 'yyyyMM') AS INT) AS entry_creation_accrual_year_month,
  DATE_FORMAT(dd_entry_created.date, 'yyyy-MM-dd') AS entry_created_date,
  DATE_FORMAT(DATE(i.ts_created), 'yyyy-MM-dd') AS invoice_created_date,
  DATE_FORMAT(i.dt_due, 'yyyy-MM-dd') AS invoice_due_date,
  DATE_FORMAT(i.dt_sent, 'yyyy-MM-dd') AS invoice_sent_date,
  DATE_FORMAT(i.dt_paid, 'yyyy-MM-dd') AS invoice_paid_date,
  DATE_FORMAT(i.ts_canceled, 'yyyy-MM-dd') AS invoice_canceled_date,
  DATE_FORMAT(rr.dt_reversal, 'yyyy-MM-dd') AS invoice_reversal_date,
  DATE_FORMAT(nbd.date_next_bd, 'yyyy-MM-dd') AS invoice_paid_date_next_business_day,
  c.dt_start AS contract_start,
  c1.dt_termination AS contract_annulment,
  NOW()       AS ts_load
FROM
  dw_payment.fact_invoice_entries AS fie
LEFT JOIN
  dw_public.dim_contract AS c
    ON c.sk_contract = fie.sk_contract
LEFT JOIN 
  datalake_ebdb_clean.contract AS c1
    ON c1.id = fie.sk_contract
LEFT JOIN
  dw_public.dim_region AS r
    ON fie.sk_region = r.sk_region
LEFT JOIN
  locale_ids AS cl
    ON  r.city_name = cl.city
LEFT JOIN
  dw_payment.dim_invoice_entry AS ie
    ON ie.sk_invoice_entry = fie.sk_invoice_entry
LEFT JOIN
  dw_payment.dim_invoice AS i
    ON fie.sk_invoice = i.sk_invoice
LEFT JOIN
  dw_public.dim_date AS dd_entry_created
    ON dd_entry_created.sk_date = fie.sk_created_date
LEFT JOIN
  dw_public.dim_date AS dd_invoice_paid
    ON dd_invoice_paid.date = i.dt_paid
LEFT JOIN
  next_business_day AS nbd
    ON nbd.date = i.dt_paid
LEFT JOIN 
    deduplicate_sap_entity sap 
    ON fie.sk_invoice_entry = sap.id_finance_entity
LEFT JOIN 
    remove_first_reversed rr 
    ON rr.id_entry = fie.sk_invoice_entry
WHERE
    c.country_code = 'BR'
    AND c.status IN ('Ativo','Finalizado')
    AND ( (ie.from_account_type IN ('contract', 'tenant','landlord')) OR 
        (ie.from_account_type = 'contract expenses' AND ie.entry_type IN ('condominium fine', 'condominium 5A paid')))
    AND ( (ie.to_account_type IN ('contract', 'tenant','landlord')) OR
        (ie.to_account_type = 'quinto andar' AND ie.entry_type IN ('condominium' , 'condominium usage', 'condominium defaulting', 'condominium fine')) OR
        (ie.to_account_type = 'contract expenses' AND ie.entry_type IN ('postponement', 'condominium fine')))