WITH 
sale_offers AS (
  SELECT DISTINCT
    s.id AS id_sale,
    s.id_external_offer AS sk_offer,
    SUBSTR(CAST(sr.id_house AS VARCHAR(20)), 4) AS sk_house,
    CAST(s.ts_created AS DATE) AS ts_created,
    ROW_NUMBER() OVER (PARTITION BY sr.id_house ORDER BY s.ts_created DESC) AS rn
  FROM
    datalake_monopoly_clean.sale s
  LEFT JOIN
    datalake_monopoly_clean.sale_revision sr
      ON s.id = sr.id 
      AND s.current_revision = sr.revision
),

sale_persons AS (
    SELECT
    p.id,
    s.id_external_offer AS sk_offer,
    SUBSTR(CAST(sr.id_house AS VARCHAR (20)), 4) AS sk_house,
    p_sale.id AS p_sale_id,
    p_sale.id_sale,
    pix.id_bank_payment,
    p_sale.person_type,
    p.person_name,
    UPPER(SPLIT_PART(p.person_name, ' ', 1)) AS first_name,
    p.document_number,
    REGEXP_REPLACE(p.document_number, '[^0-9]', '') AS document_number_only,
    CASE
      WHEN length(regexp_replace(p.document_number, '[^0-9]', '')) = 11 THEN
        concat(
          '***.',
          substr(regexp_replace(p.document_number, '[^0-9]', ''), 4, 3), '.',
          substr(regexp_replace(p.document_number, '[^0-9]', ''), 7, 3), '-',
          '**'
        )
      WHEN length(regexp_replace(p.document_number, '[^0-9]', '')) = 14 THEN
        concat(
          '**.',
          substr(regexp_replace(p.document_number, '[^0-9]', ''), 5, 3), '.',
          substr(regexp_replace(p.document_number, '[^0-9]', ''), 8, 3), '/',
          substr(regexp_replace(p.document_number, '[^0-9]', ''), 11, 4), '-**'
        )
      ELSE
        regexp_replace(p.document_number, '[0-9]', '*') 
    END AS document_number_mask,
    DATE(s.ts_created) AS ts_created,
    ROW_NUMBER() OVER (PARTITION BY concat('***', substr(p.document_number, 4, length(p.document_number) - 5), '**'), p.person_name ORDER BY s.ts_created DESC) AS rn
  FROM
    datalake_monopoly_clean.person AS p
  LEFT JOIN
    datalake_monopoly_clean.person_sale AS p_sale
    ON p_sale.id_person = p.id
  LEFT JOIN
    datalake_monopoly_clean.sale AS s
    ON s.id = p_sale.id_sale
  LEFT JOIN
    datalake_monopoly_clean.sale_revision sr
    ON s.id = sr.id AND s.current_revision = sr.revision
  LEFT JOIN 
    datalake_checkout_clean.order o
    ON o.id_business_entity = s.id_external_offer
  LEFT JOIN 
    datalake_checkout_clean.charge c 
    ON o.id = c.id_order
  LEFT JOIN 
    datalake_checkout_clean.pix pix 
    ON c.id = pix.id_charge
    AND pix.id_requester = 8
    AND pix.id_bank_payment IS NOT NULL
  WHERE
    TRUE
    AND person_type IN ('buyer', 'seller')
),

sale_transactions AS (
  SELECT DISTINCT
    s.id_external_offer AS sk_offer,
    substr(cast(sr.id_house AS VARCHAR (20)), 4) AS sk_house,
    st.id AS id_sale_transaction,
    st.id_sale,
    st.status,
    st.dt_accounting,
    st.id_income_reference,
    ir.id_income,
    st.description,
    ir.amount,
    ir.dt_income,
    ir.income_from,
    ROW_NUMBER() OVER (PARTITION BY s.id_external_offer, dt_accounting ORDER BY dt_accounting DESC) AS rn
  FROM
    datalake_monopoly_clean.sale_transaction st
  LEFT JOIN
    datalake_monopoly_clean.sale s
    ON s.id = st.id_sale
  LEFT JOIN
    datalake_monopoly_clean.sale_revision sr
    ON s.id = sr.id AND s.current_revision = sr.revision
  LEFT JOIN
    datalake_monopoly_clean.income_reference ir
    ON ir.id = st.id_income_reference
  WHERE ir.amount IS NOT NULL
),

francesinha AS (
  SELECT DISTINCT
    REGEXP_REPLACE(document_number, 'FS|/.*', '') AS sk_house,
    document_number,
    our_number,
    company_use,
    dt_due,
    dt_credit AS dt_paid,
    occurrence_code AS last_occurrence_code,
    bank_account,
    due_amount,
    net_amount AS paid_amount
  FROM
    datalake_nexxera.cnab_charges
  WHERE
    TRUE
    AND is_latest_attempt = TRUE
    AND bank_account IN ('04525', '09846')
    AND occurrence_code IN ('06')
    AND UPPER(document_number) LIKE '%FS%'
),

francesinha_bypass AS (
    SELECT DISTINCT
      REGEXP_REPLACE(document_number, 'BY|/.*', '') AS sk_house,
      document_number,
      our_number,
      document_number AS company_use,
      dt_due,
      dt_credit AS dt_paid,
      occurrence_code AS last_occurrence_code,
      bank_account,
      due_amount,
      net_amount AS paid_amount
    FROM
      datalake_nexxera.cnab_charges
    WHERE
      TRUE
      AND is_latest_attempt = TRUE
      AND bank_account IN ('04525', '09846')
      AND occurrence_code IN ('06')
      AND UPPER(document_number) NOT LIKE '%FS%'
),

bank_statement AS (
  SELECT
    '04525' AS bank_account,
    ext.id,
    ext.operation,
    ext.date_event,
    CAST(ext.date_accounting AS DATE) AS date_accounting,
    ext.literal_complete,
    ext.amount_value,
    ext.counterpart_name,
    UPPER(SPLIT_PART(ext.counterpart_name, ' ',1)) AS first_name,
    ext.counterpart_institution,
    ext.counterpart_document,
   CASE
    WHEN locate('*', ext.counterpart_document) > 0 THEN ext.counterpart_document
    ELSE
    CASE 
      WHEN length(regexp_replace(ext.counterpart_document, '[^0-9]', '')) = 11 THEN
        concat(
          '***.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 4, 3), '.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 7, 3), '-',
          '**'
        )
      WHEN length(regexp_replace(ext.counterpart_document, '[^0-9]', '')) = 14 THEN
        concat(
          '**.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 5, 3), 
          '.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 8, 3),
          '/',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 11, 4),
          '-**'
        )
      ELSE
        regexp_replace(ext.counterpart_document, '[0-9]', '*')
      END
    END AS counterpart_document_mask,
    ext.counterpart_person,
    ext.origin_identifier,
    CASE
      WHEN ext.origin_operation IN ('PIX_RECEPCAO') THEN 'PIX'
      WHEN ext.origin_operation IN ('TED_CASHIN') THEN 'TED'
      WHEN ext.origin_operation IN ('TEF_CC_CC', 'TEF_CP_CC', 'TEF_SISPAG_PJ') THEN 'TEF'
    END AS origin_operation
  FROM
    datalake_itau_statements_clean.statement_879200452586 ext
  WHERE
    TRUE
    AND ext.operation IN ('C')
    AND ext.origin_operation IN ('PIX_RECEPCAO', 'TED_CASHIN', 'TEF_CC_CC', 'TEF_CP_CC', 'TEF_SISPAG_PJ')
    
  UNION ALL 

  SELECT
    '09846' AS bank_account,
    ext.id,
    ext.operation,
    ext.date_event,
    CAST(ext.date_accounting AS DATE) AS date_accounting,
    ext.literal_complete,
    ext.amount_value,
    ext.counterpart_name,
    UPPER(SPLIT_PART(ext.counterpart_name, ' ',1)) AS first_name,
    ext.counterpart_institution,
    ext.counterpart_document,
    CASE
      WHEN locate(ext.counterpart_document, '*') > 0 THEN ext.counterpart_document
    ELSE
    CASE 
      WHEN length(regexp_replace(ext.counterpart_document, '[^0-9]', '')) = 11 THEN
        concat(
          '***.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 4, 3), '.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 7, 3), '-',
          '**'
        )
      WHEN length(regexp_replace(ext.counterpart_document, '[^0-9]', '')) = 14 THEN
        concat(
          '**.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 5, 3), 
          '.',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 8, 3),
          '/',
          substr(regexp_replace(ext.counterpart_document, '[^0-9]', ''), 11, 4),
          '-**'
        )
      ELSE
        regexp_replace(ext.counterpart_document, '[0-9]', '*') 
      END
    END AS counterpart_document_mask,
    ext.counterpart_person,
    ext.origin_identifier,
    CASE
      WHEN ext.origin_operation IN ('PIX_RECEPCAO') THEN 'PIX'
      WHEN ext.origin_operation IN ('TED_CASHIN') THEN 'TED'
      WHEN ext.origin_operation IN ('TEF_CC_CC', 'TEF_CP_CC', 'TEF_SISPAG_PJ') THEN 'TEF'
    END AS origin_operation
  FROM
    datalake_itau_statements_clean.statement_879200984646 ext
  WHERE
    TRUE
    AND ext.operation IN ('C')
    AND ext.origin_operation IN ('PIX_RECEPCAO', 'TED_CASHIN', 'TEF_CC_CC', 'TEF_CP_CC', 'TEF_SISPAG_PJ')
),

sap AS (
  SELECT
    id_transaction,
    id_business_entity AS sk_offer,
    id_finance_entity AS id_sale_transaction,
    id_external_payment,
    account_number,
    account_name,
    accounting_rule,
    comments,
    created_by,
    dt_reference AS dt_paid,
    dt_tax,
    ROUND(debit_credit, 2) AS paid_amount,
    ROW_NUMBER() OVER (PARTITION BY id_business_entity, dt_reference ORDER BY dt_reference DESC) AS rn
  FROM
    datalake_pas.ledger
  WHERE
    TRUE
    AND account_number IN ('110360X', '110901')
),

franc_sale_offer AS (
  SELECT
    f.bank_account,
    f.document_number AS company_use,
    f.sk_house,
    f.dt_due,
    f.dt_paid,
    f.due_amount,
    f.paid_amount,
    so.sk_offer,
    so.id_sale,
    'BOLETO' AS origin_operation
  FROM
    francesinha f
  LEFT JOIN
    sale_offers so
      ON so.sk_house = f.sk_house
      AND so.ts_created <= f.dt_paid
      AND so.rn = 1
  ORDER BY f.dt_paid
),

bank_sale_person AS (
   SELECT
    bs.bank_account,
    bs.counterpart_document_mask AS company_use,
    bs.counterpart_document,
    bs.counterpart_name,
    sp.sk_house,
    bs.date_accounting AS dt_paid,
    bs.amount_value AS paid_amount,
    sp.sk_offer,
    sp.id_sale,
    bs.origin_operation,
    sp.ts_created,
    sp.rn
  FROM
    bank_statement bs
  LEFT JOIN
    sale_persons sp
      ON (bs.origin_identifier = sp.id_bank_payment
        OR sp.document_number_mask = bs.counterpart_document_mask)
      AND sp.ts_created <= bs.date_accounting
      AND sp.rn = 1
  ORDER BY bs.date_accounting
),

union_franc_bank AS (
  SELECT
    fso.bank_account,
    fso.sk_house,
    fso.sk_offer,
    fso.id_sale,
    fso.dt_paid,
    fso.paid_amount,
    fso.origin_operation,
    fso.company_use,
    CAST(NULL AS VARCHAR (20)) AS counterpart_document,
    CAST(NULL AS VARCHAR (20)) AS counterpart_name
  FROM
    franc_sale_offer fso

  UNION ALL

  SELECT
    bsp.bank_account,
    bsp.sk_house,
    bsp.sk_offer,
    bsp.id_sale,
    bsp.dt_paid,
    bsp.paid_amount,
    bsp.origin_operation,
    bsp.company_use,
    bsp.counterpart_document,
    bsp.counterpart_name
  FROM
    bank_sale_person bsp
),

final_base AS (
  SELECT
    ufb.bank_account,
    ufb.company_use,
    ufb.counterpart_document,
    ufb.counterpart_name,
    ufb.sk_house,
    ufb.sk_offer,
    ufb.id_sale,
    ufb.dt_paid AS bank_dt_paid,
    ufb.paid_amount AS bank_paid_amount,
    ufb.origin_operation AS bank_type_transaction,
    st.income_from AS monopoly_income_from,
    st.dt_accounting AS monopoly_dt_accounting,
    st.amount AS monopoly_paid_amount,
    s.id_sale_transaction AS sap_id_sale_transaction,
    s.paid_amount AS sap_paid_amount,
    s.dt_paid AS sap_dt_paid,
    CASE
      WHEN (st.sk_offer IS NOT NULL) THEN TRUE
      ELSE FALSE
    END AS monopoly_is_reconcilied,
    CASE
      WHEN (s.sk_offer IS NOT NULL) AND (ABS(s.paid_amount) = ABS(ufb.paid_amount)) THEN TRUE
      ELSE FALSE
    END AS sap_is_reconcilied
  FROM
    union_franc_bank ufb
  LEFT JOIN
    sale_transactions st
      ON st.sk_offer = ufb.sk_offer
      AND CAST(st.amount AS DECIMAL(10,2)) = CAST(ufb.paid_amount AS DECIMAL(10,2))
      AND YEAR(st.dt_accounting) = YEAR(ufb.dt_paid)
      AND MONTH(st.dt_accounting) = MONTH(ufb.dt_paid)
      AND st.dt_accounting <= ufb.dt_paid
      AND st.rn = 1
  LEFT JOIN
    sap s
      ON s.sk_offer = ufb.sk_offer
      AND CAST(s.paid_amount AS DECIMAL(10,2)) = CAST(ufb.paid_amount AS DECIMAL(10,2))
      AND YEAR(s.dt_paid) = YEAR(ufb.dt_paid)
      AND MONTH(s.dt_paid) = MONTH(ufb.dt_paid)
      AND s.dt_paid <= ufb.dt_paid
      AND s.rn = 1
  WHERE
    ufb.dt_paid >= DATE '2025-01-01'
),

final_bypass AS (
  SELECT
    fb.bank_account,
    fb.company_use,
    CAST(NULL AS VARCHAR (20)) AS counterpart_document,
    CAST(NULL AS VARCHAR (20)) AS counterpart_name,
    fb.sk_house,
    CAST(NULL AS VARCHAR (20)) AS sk_offer, 
    CAST(NULL AS BIGINT) AS id_sale, 
    fb.dt_paid AS bank_dt_paid,
    ROUND(fb.paid_amount, 2) AS bank_paid_amount,
    'BOLETO' AS bank_type_transaction,
    NULL AS monopoly_income_from,
    CAST(NULL AS DATE) AS monopoly_dt_accounting,
    CAST(NULL AS DOUBLE) AS monopoly_paid_amount,
    s.id_sale_transaction AS sap_id_sale_transaction,
    s.paid_amount AS sap_paid_amount,
    s.dt_paid AS sap_dt_paid,
    FALSE AS monopoly_is_reconcilied,
    CASE
      WHEN s.id_transaction IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS sap_is_reconcilied
  FROM
    francesinha_bypass fb
  LEFT JOIN
    sap s
      ON ABS(s.paid_amount) = fb.paid_amount
      AND (YEAR(s.dt_paid) = YEAR(fb.dt_paid) AND MONTH(s.dt_paid) = MONTH(fb.dt_paid))
      AND s.id_sale_transaction IS NULL
  LEFT JOIN
    dw_sale.dim_listing sl
      ON substr(cast(sl.sk_house AS VARCHAR (20)), 4) = fb.sk_house
),

final_all AS (
  SELECT
    *,
    'forsale' AS origin_transaction
  FROM
    final_base 
  UNION ALL
  SELECT
    *,
    'bypass' AS origin_transaction
  FROM
    final_bypass fb
)

SELECT
  sk_house,
  sk_offer, 
  id_sale, 
  sap_id_sale_transaction as id_sap_sale_transaction,
  bank_account,
  company_use,
  counterpart_document,
  counterpart_name,
  bank_paid_amount,
  bank_type_transaction,
  monopoly_income_from,
  monopoly_paid_amount,
  monopoly_is_reconcilied,
  sap_paid_amount,
  sap_is_reconcilied,
  origin_transaction,
  bank_dt_paid as dt_bank_paid,
  monopoly_dt_accounting as dt_monopoly_accounting,
  sap_dt_paid as dt_sap_paid
FROM 
  final_all
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY 
        CASE 
            WHEN bank_type_transaction = 'BOLETO' THEN sk_house 
            ELSE company_use 
        END,
        CASE 
            WHEN bank_type_transaction = 'BOLETO' THEN NULL
            ELSE counterpart_document 
        END,
        CASE 
            WHEN bank_type_transaction = 'BOLETO' THEN NULL 
            ELSE counterpart_name 
        END,
        bank_paid_amount, 
        bank_dt_paid 
    ORDER BY bank_dt_paid DESC
) = 1
