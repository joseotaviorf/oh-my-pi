WITH locale_ids AS (
  SELECT
    DISTINCT city,
    min(id_locale) AS id_locale
  FROM
    datalake_gsheets_clean.cod_locale
  GROUP BY 1
),
remove_reversed AS (

    SELECT
      e.id_external AS id_entry,
      CASE
        WHEN SUM(e.amount) OVER(PARTITION BY e.id_contract, e.accrual_year_month,e.bill_item ORDER BY e.ts_created ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) = 0
        THEN TRUE
        WHEN LEAD(e.id_external) OVER(PARTITION BY e.id_contract, e.accrual_year_month,e.bill_item ORDER BY e.ts_created) IS NOT NULL
        THEN TRUE
        ELSE FALSE
      END AS is_reversed,
      CASE
        WHEN
          SUM(e.amount)
            OVER(PARTITION BY e.id_contract, e.accrual_year_month, e.bill_item ORDER BY e.ts_created ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) = 0
          AND
            LEAD(e.ts_created)
              OVER(PARTITION BY e.id_contract, e.accrual_year_month, e.bill_item ORDER BY e.ts_created) IS NULL
        THEN e.ts_created
        ELSE LEAD(e.ts_created) OVER(PARTITION BY e.id_contract, e.accrual_year_month, e.bill_item ORDER BY e.ts_created)
      END AS ts_entry_reversed
    FROM
      datalake_retsuko.entry AS e

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
),
not_invoiceable AS (

    SELECT
      e.id_external AS id_entry,
      i.id_external AS id_invoice,
      e.bill_item,
      ii.payment_status,
      e.status AS entry_status,
      CASE
        WHEN
          (e.id_invoice IS NULL OR e.id_invoice IS NOT NULL AND ii.payment_status = 'canceled')
          AND (e.producer = 'payment-adjustment-correction' OR e.producer = 'postponement' OR e.producer = 'manual'   OR e.producer = 'monthly-routine')
          AND e.status = 'pending'
          AND e.due_year_month >= 202401
        THEN FALSE -- not-invoiceable válido
        ELSE TRUE -- not-invoiceable não válido
      END AS is_not_invoiceable_inconsiderable,
      e.amount,
      e.accrual_year_month,
      e.due_year_month
    FROM
        datalake_retsuko.entry AS e
    LEFT JOIN
        datalake_retsuko.invoice AS i
        ON i.id = e.id_invoice
    LEFT JOIN
        datalake_retsuko.invoice_info AS ii
        ON ii.id_invoice = i.id_external
    WHERE
        e.id_invoice IS NULL
        OR (e.id_invoice IS NOT NULL AND ii.payment_status = 'canceled' AND e.status = 'pending')
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
  e.accounting_version,
  c.is_contract_b2b,
  c.dt_start > c1.dt_termination AND c1.dt_termination IS NOT NULL AS ended_before_started,
  r.city_name AS locale,
  cl.id_locale AS localidade,
  c.guarantee,
  c.rental_administrator,
  c.status AS contract_status,
  ie.is_rental_paid_in_advance,
  COALESCE(rr.is_reversed, FALSE) AS is_reversed,
  COALESCE(ni.is_not_invoiceable_inconsiderable, FALSE) AS is_not_invoiceable_inconsiderable,
  ie.entry_type AS bill_item,
  i.is_write_off,
  ie.description,
  CASE
    WHEN UPPER(ie.description) LIKE '%ACORDO%' THEN 1
    ELSE 0
  END AS has_negotiation,
  CASE
    WHEN (try_cast(reverse(CASE WHEN ie.description like '%arcela%' THEN split(reverse(ie.description), ' ed ')[1] ELSE '1' END) as bigint)) > 1 THEN 1
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
    WHEN entry_type IN ('brokerage installment fee', 'brokerage loan fidc', 'brokerage fidc', 'property damage fine') THEN 'receivable'
    WHEN entry_type IN ('rental anticipation fee') THEN 'payable'
    WHEN entry_type IN ('payment adjustment') AND (ie.from_account_type = 'tenant' OR ie.to_account_type = 'tenant') THEN 'receivable'
    WHEN entry_type IN ('payment adjustment') AND (ie.from_account_type = 'landlord' OR ie.to_account_type = 'landlord') THEN 'payable'
    WHEN (ROUND(-1.0*i.due_amount,2) > 0 OR (ROUND(-1.0*i.due_amount,2) = 0 AND NOT(from_account_type = 'landlord' OR to_account_type= 'landlord') )) THEN 'receivable'
    ELSE 'payable'
  END AS account_classification,
  IF(ni.id_entry IS NOT NULL, 'not-invoiceable', i.payment_status) AS status,
  i.closing_mode,
  i.paid_via,
  ROUND(fie.brl_entry_due_amount,2) AS due_amount,
  ROUND(-1.0*i.due_amount,2) AS invoice_due_amount,
  ROUND(i.paid_amount,2) AS invoice_paid_amount,
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
  ie.due_year_month AS entry_due_year_month,
  CAST(DATE_FORMAT(DATEADD(month, 1, dd_entry_created.date), 'yyyyMM') AS INT) AS entry_creation_accrual_year_month,
  DATE_FORMAT(dd_entry_created.date, 'yyyy-MM-dd') AS entry_created_date,
  DATE_FORMAT(DATE(i.ts_created), 'yyyy-MM-dd') AS invoice_created_date,
  DATE_FORMAT(i.dt_due, 'yyyy-MM-dd') AS invoice_due_date,
  DATE_FORMAT(i.dt_sent, 'yyyy-MM-dd') AS invoice_sent_date,
  DATE_FORMAT(i.dt_paid, 'yyyy-MM-dd') AS invoice_paid_date,
  DATE_FORMAT(i.dt_write_off, 'yyyy-MM-dd') AS invoice_write_off_date,
  DATE_FORMAT(i.ts_canceled, 'yyyy-MM-dd') AS invoice_canceled_date,
  DATE_FORMAT(rr.ts_entry_reversed, 'yyyy-MM-dd') AS invoice_reversal_date,
  DATE_FORMAT(nbd.date_next_bd, 'yyyy-MM-dd') AS invoice_paid_date_next_business_day,
  c.dt_start AS contract_start,
  c1.dt_termination AS contract_annulment,
  NOW() AS ts_load
FROM
    dw_payment.fact_invoice_entries AS fie
LEFT JOIN
    dw_rent.dim_contract AS c
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
    datalake_retsuko.entry AS e
    ON e.id_external = fie.sk_invoice_entry
LEFT JOIN
    remove_reversed AS rr
    ON rr.id_entry = fie.sk_invoice_entry
LEFT JOIN
    not_invoiceable AS ni
    ON ni.id_entry = fie.sk_invoice_entry
WHERE
    c.country_code = 'BR'
    AND c.status IN ('Ativo','Finalizado')
    AND ( (ie.from_account_type IN ('contract', 'tenant','landlord')) OR
        (ie.from_account_type = 'contract expenses' AND ie.entry_type IN ('condominium fine', 'condominium 5A paid')))
    AND ( (ie.to_account_type IN ('contract', 'tenant','landlord')) OR
        (ie.to_account_type = 'quinto andar' AND ie.entry_type IN ('condominium' , 'condominium usage', 'condominium fine', 'condominium 5A paid')) OR
        (ie.to_account_type = 'contract expenses' AND ie.entry_type IN ('postponement', 'condominium fine', 'condominium 5A paid')))
