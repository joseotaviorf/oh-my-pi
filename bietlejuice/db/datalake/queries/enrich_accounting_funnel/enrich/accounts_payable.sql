WITH locale_ids AS
(
  SELECT 
    DISTINCT city, 
    min(id_locale) AS id_locale 
  FROM 
    datalake_gsheets_clean.cod_locale
  GROUP BY 1
),
cap_contract_info AS (
    SELECT
        DISTINCT
        c.sk_contract,
        ie.is_rental_paid_in_advance
    FROM 
        dw_public.dim_contract AS c
    LEFT JOIN 
        dw_payment.fact_invoice_entries AS fie
            ON fie.sk_contract = c.sk_contract
    LEFT JOIN 
        dw_payment.dim_invoice_entry AS ie
            ON ie.sk_invoice_entry = fie.sk_invoice_entry
),
cap_formated AS (
    SELECT
      supplier_description,
      accrual_year_month,
      CASE
        WHEN UPPER(payment_reason) LIKE 'PROTEÇÃO 5A%' AND UPPER(payment_source) LIKE 'MANUAL%' THEN 'Proteção 5A - PP'
        WHEN UPPER(payment_reason) LIKE 'PROTEÇÃO 5A%' THEN 'Proteção 5A - Parceiro'
        WHEN UPPER(payment_reason) LIKE 'CONDOM%' THEN 'Condomínio'
        WHEN UPPER(payment_reason) LIKE 'ANTECIPA%' THEN 'MRA'  
        WHEN regexp_like(UPPER(payment_reason),'^MULTA RESCISÓRIA|^CONTAS DE CONSUMO|^ALUGUEL|^CORRETORES|^IPTU|^REPASSE B2B|^ONGOING|^BAND-AID') THEN payment_reason
        WHEN regexp_like(UPPER(payment_reason),'^CRÉDITO A SALDAR|^DEVOLUÇÃO|^EXTRA') THEN 'Repasse Extra'
        ELSE NULL
      END AS payment_reason_classification,
      SUM(paid_amount) AS paid_amount,
      MAX(dt_paid) AS dt_paid
    FROM 
      datalake_payable_accounts_transactions_clean.accounts_payable
    WHERE
      dt_paid IS NOT NULL
  GROUP BY
      1,
      2,
      3
  )
SELECT
    DISTINCT
    CAST(NULL AS BIGINT) AS id_entry,
    CAST(NULL AS BIGINT) AS id_invoice,
    COALESCE(TRY_CAST(cap.supplier_description AS INT),-1) AS sk_contract,
    COALESCE(split(c.version,'.')[1], 'no info') AS version,
    c.is_contract_b2b AS is_contract_b2b,
    r.city_name AS locale,
    cl.id_locale AS localidade,
    c.guarantee,
    c.rental_administrator,
    cci.is_rental_paid_in_advance,
    'cap' AS bill_item,
    CONCAT(cap.payment_reason_classification,' CAP') AS description,
    0 AS has_negotiation, 
    0 AS has_installments,
    'monthly' AS purpose,
    CAST(NULL AS STRING) AS invoice_account_type,
    'quinto-andar' AS from_account_type,
    'supplier' AS to_account_type,
    'supplier' AS account_type,
    'payable' AS account_classification,
    'paid' AS status,
    'cap' AS closing_mode,
    cap.paid_amount AS due_amount,
    cap.paid_amount AS invoice_due_amount,
    CAST(cap.accrual_year_month AS INT) AS accrual_year_month,
    CAST(cap.accrual_year_month AS INT) AS entry_accrual_year_month,
    CAST(cap.accrual_year_month AS INT) AS entry_creation_accrual_year_month,    
    DATE_FORMAT(cap.dt_paid, 'yyyy-MM-dd')  AS entry_created_date,
    CAST(NULL AS STRING) AS invoice_created_date,
    CAST(NULL AS STRING) AS invoice_due_date,
    CAST(NULL AS STRING) AS invoice_paid_date,
    CAST(NULL AS STRING) AS invoice_paid_date_next_business_day,
    CAST(NULL AS STRING) AS invoice_canceled_date,
    c.dt_start AS contract_start,
    c.dt_annulment AS contract_annulment,
    CASE WHEN c.dt_start <= c.dt_annulment THEN false ELSE true END AS ended_before_started, 
    FALSE AS pp_pays,
    CAST(NULL AS INT) AS entry_sort_ascend,
    CAST(NULL AS INT) AS entry_by_accrual_sort_ascend,
    TRUE is_cap
  FROM 
      cap_formated as cap
  LEFT JOIN 
      dw_public.dim_contract AS c
          ON c.sk_contract = CAST(try_cast(cap.supplier_description AS REAL) AS INT)
  LEFT JOIN
      cap_contract_info AS cci
          ON cci.sk_contract = c.sk_contract
  LEFT JOIN
      dw_public.fact_house_listings AS rf 
          ON rf.sk_contract = c.sk_contract 
  LEFT JOIN
      dw_public.dim_region AS r 
          ON r.sk_region = rf.sk_region 
  LEFT JOIN 
      locale_ids AS cl 
          ON  r.city_name = cl.city