WITH locale_ids AS (
  SELECT DISTINCT
    city,
    MIN(id_locale) AS id_locale
  FROM datalake_gsheets_clean.cod_locale
  GROUP BY
    1
), cap_contract_info AS (
  SELECT DISTINCT
    c.sk_contract,
    ie.is_rental_paid_in_advance
  FROM dw_rent.dim_contract AS c
  LEFT JOIN dw_payment.fact_invoice_entries AS fie
    ON fie.sk_contract = c.sk_contract
  LEFT JOIN dw_payment.dim_invoice_entry AS ie
    ON ie.sk_invoice_entry = fie.sk_invoice_entry
), cap_pre_formated AS (
  SELECT
    supplier_description,
    dt_paid AS dt_paid,
    accrual_year_month,
    CASE
      WHEN UPPER(payment_reason) LIKE 'PROTEÇÃO 5A%'
      AND UPPER(payment_source) LIKE 'MANUAL%'
      THEN 'Proteção 5A - PP'
      WHEN UPPER(payment_reason) LIKE 'PROTEÇÃO 5A%'
      THEN 'Proteção 5A - Parceiro'
      WHEN UPPER(payment_reason) LIKE 'CONDOM%'
      THEN 'Condomínio'
      WHEN UPPER(payment_reason) LIKE 'ANTECIPA%'
      THEN 'MRA'
      WHEN UPPER(payment_reason) LIKE 'LRA%'
      THEN 'LRA'
      WHEN UPPER(payment_reason) LIKE 'BFI%'
      THEN 'BFI'
      WHEN UPPER(payment_reason) RLIKE '^MULTA RESCISÓRIA|^MULTA-RESCISÓRIA|^CONTAS DE CONSUMO|^CONTAS-DE-CONSUMO|^CONTA-CONSUMO|^ALUGUEL|^CORRETOR|^3P|^IPTU|^REPASSE B2B|ˆREPASSE-B2B|^ONGOING|^BAND-AID'
      THEN payment_reason
      WHEN UPPER(payment_reason) RLIKE '^CRÉDITO A SALDAR|^DEVOLUÇÃO|^EXTRA'
      THEN 'Repasse Extra'
      ELSE NULL
    END AS payment_reason_classification,
    paid_amount AS paid_amount,
    CASE
      WHEN paid_amount > 0
      AND NOT payment_reason IN ('condominio-v8:estorno', 'condominio-v9:estorno')
      AND payment_reason LIKE '%:%'
      AND NOT payment_reason LIKE '%estorno%'
      THEN FALSE
      ELSE TRUE
    END AS refund_check
  FROM datalake_payable_accounts_transactions_clean.accounts_payable
  WHERE
    NOT dt_paid IS NULL
), cap_formated AS (
  SELECT
    supplier_description,
    dt_paid AS dt_paid,
    accrual_year_month,
    payment_reason_classification,
    SUM(paid_amount) AS paid_amount
  FROM cap_pre_formated
  WHERE
    refund_check
  GROUP BY
    1,
    2,
    3,
    4
), vans_formated AS (
  SELECT
    SPLIT(SPLIT(SPLIT(SPLIT(SPLIT(c.company_use, 'T')[0], 'P')[0], '!')[0], 'L')[0], 'I')[0] AS supplier_description,
    c.dt_paid AS dt_paid,
    CAST(EXTRACT(YEAR FROM c.dt_paid) AS STRING) || LPAD(CAST(EXTRACT(MONTH FROM c.dt_paid) AS STRING), 2, '0') AS accrual_year_month,
    CASE
      WHEN UPPER(pagamento) LIKE 'PROTEÇÃO 5A%' AND UPPER(our_number) LIKE 'MANUAL%'
      THEN 'Repasse Extra'
      WHEN UPPER(pagamento) LIKE 'PROTEÇÃO 5A%'
      THEN 'Repasse Extra'
      WHEN UPPER(pagamento) LIKE '%3P%'
      THEN 'Imobiliarias 3P'
      WHEN UPPER(pagamento) LIKE 'CONDOM%'
      THEN 'Condomínio'
      WHEN UPPER(pagamento) LIKE 'ANTECIPA%'
      THEN 'MRA'
      WHEN UPPER(pagamento) LIKE 'CIQ%'
      THEN 'CIQ'
      WHEN UPPER(pagamento) LIKE 'PP não residente'
      THEN 'PP não residente'
      WHEN UPPER(pagamento) LIKE 'ONG%'
      THEN 'Aluguel'
      WHEN UPPER(pagamento) LIKE 'Aporte FIDC'
      THEN 'Aporte FIDC'
      WHEN UPPER(pagamento) RLIKE '^DEVOLUÇÃO|^EXTRA'
      THEN 'Repasse Extra'
      WHEN UPPER(pagamento) RLIKE '^MULTA RESCISÓRIA|^CONTAS DE CONSUMO|^ALUGUEL|^CORRETORES|^IPTU|^REPASSE B2B|^BAND-AID|^CRÉDITO A SALDAR|^EARLY TERMINATION|^MRA|^REPASSES EXTRAS|^REPASSES BAND-AID|^CONDOMÍNIO DEPÓSITO|^ALUGUEL MANUAL|^CORRETOR 3P|^ONGOING MANUAL|^B2B|^CONTAS DE CONSUMO|^NÃO PROTEÇÃO|^REEMBOLSO'
      THEN pagamento
      ELSE NULL
    END AS payment_reason_classification,
    SUM(paid_amount) AS paid_amount
  FROM (
    SELECT
      p.our_number,
      p.company_use,
      p.status,
      p.dt_paid,
      IF(status = ':payment.status/chargeback', p.paid_amount, p.paid_amount * (
        -1
      )) AS paid_amount,
      p.requested_by,
      p.id_bank_payment AS codigo,
      p.ts_updated,
      CASE
        WHEN p.requested_by = 'sb-corretores'
        THEN 'Corretores'
        WHEN p.requested_by = 'rh-corretores'
        THEN 'Corretores'
        WHEN p.requested_by IN ('indica-ai', 'indica-ai-agents')
        THEN 'IndicaAi'
        WHEN p.requested_by = 'rh-porteiros'
        THEN 'Porteiros'
        WHEN p.requested_by = 'rh-ciq'
        THEN 'CIQ'
        WHEN p.requested_by = 'executive-for-rent'
        THEN 'CIQ Select'
        WHEN p.requested_by = 'ciq-captacao'
        THEN 'CIQ Captação'
        WHEN p.requested_by = 'imobs-for-rent'
        THEN 'Imobiliarias 3P'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+T[0-9]+$'
        THEN 'Aluguel'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+I[0-9]+$'
        THEN 'Crédito a Saldar'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+L[0-9]+$'
        THEN 'Multa rescisória'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+R[0-9]+$'
        THEN 'Early termination'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+!MO[0-9]+$'
        THEN 'Ongoing'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+Corretor$'
        THEN 'Corretores'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+BAI[0-9]+$'
        THEN 'Band-Aid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+BAP[0-9]+$'
        THEN 'Band-Aid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+MR[0-9]+$'
        THEN 'MRA'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+RBI[0-9]+$'
        THEN 'Reembolso'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+RBP[0-9]+$'
        THEN 'Reembolso'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+EI[0-9]+$'
        THEN 'Repasses Extras'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+EP[0-9]+$'
        THEN 'Repasses Extras'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+NPP[0-9]+$'
        THEN 'Não Proteção'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+NPI[0-9]+$'
        THEN 'Não Proteção'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+BA[0-9]+$'
        THEN 'BandAid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+CI[0-9]+$'
        THEN 'Conciliação'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+CP[0-9]+$'
        THEN 'Conciliação'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MBD[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Band-Aid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+ME[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Repasses Extras'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MC[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Repasses Band-Aid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MCP[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Condomínio Depósito'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MA[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'MRA'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MT[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Aluguel Manual'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MC3P[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Corretor 3P'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MO[0-9]+$' AND dt_paid >= '2024-02-05'
        THEN 'Ongoing Manual'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MB[0-9]+$' AND dt_paid <= '2024-02-19'
        THEN 'Band-Aid'
        WHEN (
          p.company_use
        ) RLIKE '^[0-9]+![0-9]+MB[0-9]+$' AND dt_paid > '2024-02-19'
        THEN 'B2B'
      END AS pagamento
    FROM datalake_vans_clean.payment AS p
    WHERE
      p.dt_paid >= '2022-12-01'
    UNION ALL
    SELECT
      pb.our_number,
      pb.company_use,
      pb.status,
      pb.dt_paid,
      pb.paid_amount * (
        -1
      ) AS paid_amount,
      pb.requested_by,
      CAST((
        IF(pb.id_bank_payment = NULL, '0', '1')
      ) AS DECIMAL(20, 0)) AS codigo,
      pb.ts_updated,
      CASE
        WHEN pb.company_use = '00000000000000000000'
        THEN NULL
        WHEN (
          company_use
        ) RLIKE '^[0-9]+P[0-9]+$'
        THEN 'Condomínio V8'
        WHEN (
          company_use
        ) RLIKE '^00000000000000+[0-9]+$'
        THEN 'Condomínio V9'
        WHEN (
          company_use
        ) RLIKE '^[0-9]+![0-9]+MC[0-9]+$'
        THEN 'Condominio v9'
        WHEN (
          company_use
        ) RLIKE '^[0-9]+![0-9]+MT[0-9]+$'
        THEN 'Aluguel Manual'
        WHEN (
          company_use
        ) RLIKE '^[0-9]+![0-9]+MCD[0-9]+$'
        THEN 'Condominio v9 - Despejo'
        WHEN (
          company_use
        ) RLIKE 'REFERA+!MO[0-9]+$'
        THEN 'Ongoing - Boleto'
        WHEN (
          company_use
        ) RLIKE '^[0-9]+![0-9]+MCCM[0-9]+$'
        AND ts_updated >= '2024-02-06'
        THEN 'Contas de Consumo'
      END AS pagamento
    FROM datalake_vans_clean.payment_boleto AS pb
    WHERE
      pb.dt_paid >= '2022-12-01'
  ) AS c
  LEFT JOIN datalake_vans_clean.bank_payment AS bp
    ON c.codigo = bp.id
  LEFT JOIN datalake_vans_clean.bank AS b
    ON bp.id_bank = b.id
  WHERE
    NOT pagamento IS NULL AND status = ':payment.status/paid'
  GROUP BY
    1,
    2,
    3,
    4
), cap_final AS (
  SELECT DISTINCT
    CAST(NULL AS BIGINT) AS id_entry,
    CAST(NULL AS BIGINT) AS id_invoice,
    CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry,
    COALESCE(TRY_CAST(cap.supplier_description AS INT), -1) AS sk_contract,
    COALESCE(SPLIT(REPLACE(version, '.', 'P'), 'P')[0], 'no info') AS version,
    'cap' AS accounting_version,
    c.is_contract_b2b AS is_contract_b2b,
    r.city_name AS locale,
    cl.id_locale AS localidade,
    c.guarantee,
    c.rental_administrator,
    cci.is_rental_paid_in_advance,
    'cap' AS bill_item,
    CONCAT(cap.payment_reason_classification, ' CAP') AS description,
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
    DATE_FORMAT(cap.dt_paid, 'yyyy-MM-dd') AS entry_created_date,
    CAST(NULL AS STRING) AS invoice_created_date,
    CAST(NULL AS STRING) AS invoice_due_date,
    CAST(NULL AS STRING) AS invoice_paid_date,
    CAST(NULL AS STRING) AS invoice_paid_date_next_business_day,
    CAST(NULL AS STRING) AS invoice_canceled_date,
    c.dt_start AS contract_start,
    c.dt_annulment AS contract_annulment,
    CASE WHEN c.dt_start <= c.dt_annulment THEN FALSE ELSE TRUE END AS ended_before_started,
    FALSE AS pp_pays,
    CAST(NULL AS INT) AS entry_sort_ascend,
    CAST(NULL AS INT) AS entry_by_accrual_sort_ascend,
    TRUE AS is_cap
  FROM cap_formated AS cap
  LEFT JOIN dw_rent.dim_contract AS c
    ON c.sk_contract = CAST(TRY_CAST(cap.supplier_description AS FLOAT) AS INT)
  LEFT JOIN cap_contract_info AS cci
    ON cci.sk_contract = c.sk_contract
  LEFT JOIN dw_rent.fact_house_listings AS rf
    ON rf.sk_contract = c.sk_contract
  LEFT JOIN dw_public.dim_region AS r
    ON r.sk_region = rf.sk_region
  LEFT JOIN locale_ids AS cl
    ON r.city_name = cl.city
), vans_final AS (
  SELECT DISTINCT
    CAST(NULL AS BIGINT) AS id_entry,
    CAST(NULL AS BIGINT) AS id_invoice,
    CAST(NULL AS BIGINT) AS sk_invoice_reversed_entry,
    COALESCE(TRY_CAST(vans.supplier_description AS INT), -1) AS sk_contract,
    COALESCE(SPLIT(REPLACE(version, '.', 'P'), 'P')[0], 'no info') AS version,
    'cap' AS accounting_version,
    c.is_contract_b2b AS is_contract_b2b,
    r.city_name AS locale,
    cl.id_locale AS localidade,
    c.guarantee,
    c.rental_administrator,
    cci.is_rental_paid_in_advance,
    'cap' AS bill_item,
    CONCAT(vans.payment_reason_classification, ' CAP') AS description,
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
    vans.paid_amount AS due_amount,
    vans.paid_amount AS invoice_due_amount,
    CAST(vans.accrual_year_month AS INT) AS accrual_year_month,
    CAST(vans.accrual_year_month AS INT) AS entry_accrual_year_month,
    CAST(vans.accrual_year_month AS INT) AS entry_creation_accrual_year_month,
    DATE_FORMAT(vans.dt_paid, 'yyyy-MM-dd') AS entry_created_date,
    CAST(NULL AS STRING) AS invoice_created_date,
    CAST(NULL AS STRING) AS invoice_due_date,
    CAST(NULL AS STRING) AS invoice_paid_date,
    CAST(NULL AS STRING) AS invoice_paid_date_next_business_day,
    CAST(NULL AS STRING) AS invoice_canceled_date,
    c.dt_start AS contract_start,
    c.dt_annulment AS contract_annulment,
    CASE WHEN c.dt_start <= c.dt_annulment THEN FALSE ELSE TRUE END AS ended_before_started,
    FALSE AS pp_pays,
    CAST(NULL AS INT) AS entry_sort_ascend,
    CAST(NULL AS INT) AS entry_by_accrual_sort_ascend,
    TRUE AS is_cap
  FROM vans_formated AS vans
  LEFT JOIN dw_rent.dim_contract AS c
    ON c.sk_contract = CAST(TRY_CAST(vans.supplier_description AS FLOAT) AS INT)
  LEFT JOIN cap_contract_info AS cci
    ON cci.sk_contract = c.sk_contract
  LEFT JOIN dw_rent.fact_house_listings AS rf
    ON rf.sk_contract = c.sk_contract
  LEFT JOIN dw_public.dim_region AS r
    ON r.sk_region = rf.sk_region
  LEFT JOIN locale_ids AS cl
    ON r.city_name = cl.city
)
SELECT
  id_entry,
  id_invoice,
  sk_invoice_reversed_entry,
  sk_contract,
  version,
  accounting_version,
  is_contract_b2b,
  locale,
  localidade,
  guarantee,
  rental_administrator,
  is_rental_paid_in_advance,
  bill_item,
  description,
  has_negotiation,
  has_installments,
  purpose,
  invoice_account_type,
  from_account_type,
  to_account_type,
  account_type,
  account_classification,
  status,
  closing_mode,
  due_amount,
  invoice_due_amount,
  accrual_year_month,
  entry_accrual_year_month,
  entry_creation_accrual_year_month,
  entry_created_date,
  invoice_created_date,
  invoice_due_date,
  invoice_paid_date,
  invoice_paid_date_next_business_day,
  invoice_canceled_date,
  contract_start,
  contract_annulment,
  ended_before_started,
  pp_pays,
  entry_sort_ascend,
  entry_by_accrual_sort_ascend,
  is_cap,
  NOW() AS ts_load
FROM vans_final
UNION ALL
SELECT
  id_entry,
  id_invoice,
  sk_invoice_reversed_entry,
  sk_contract,
  version,
  accounting_version,
  is_contract_b2b,
  locale,
  localidade,
  guarantee,
  rental_administrator,
  is_rental_paid_in_advance,
  bill_item,
  description,
  has_negotiation,
  has_installments,
  purpose,
  invoice_account_type,
  from_account_type,
  to_account_type,
  account_type,
  account_classification,
  status,
  closing_mode,
  due_amount,
  invoice_due_amount,
  accrual_year_month,
  entry_accrual_year_month,
  entry_creation_accrual_year_month,
  entry_created_date,
  invoice_created_date,
  invoice_due_date,
  invoice_paid_date,
  invoice_paid_date_next_business_day,
  invoice_canceled_date,
  contract_start,
  contract_annulment,
  ended_before_started,
  pp_pays,
  entry_sort_ascend,
  entry_by_accrual_sort_ascend,
  is_cap,
  NOW() AS ts_load
FROM cap_final
