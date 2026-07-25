WITH sap_entity AS (
  SELECT
    id_finance_entity,
    event,
    status,
    failed_reason,
    ts_created,
    id_sap_gateway_feature
  FROM (
    SELECT
      id_finance_entity,
      e.event,
      e.status,
      e.failed_reason,
      e.ts_created,
      e.id_sap_gateway_feature,
      ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY ts_created DESC) AS _w
    FROM datalake_retsuko_clean.sap_entity AS e
    WHERE
      event = 'payment-accounting-entries'
  ) AS _t
  WHERE
    _w = 1
), sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.type,
    s.status AS sync_sap_job_status,
    w.status AS sap_send_status,
    w.webhook_status AS sap_processed_status,
    w.errors AS webhook_error
  FROM datalake_sap_gateway_clean.feature AS f
  LEFT JOIN datalake_sap_gateway_clean.sync_sap_job AS s
    ON f.id_feature = s.id_feature
  LEFT JOIN datalake_sap_gateway_clean.webhook_log AS w
    ON s.idoc = w.idoc
  WHERE
    s.erp_solution IN ('S4')
    AND s.type IN ('LCM')
    AND NOT s.status IN ('ignore', 'ignored')
    AND CAST(f.ts_created AS DATE) >= CAST('2025-01-01' AS DATE)
), pre_francesinha AS (
  SELECT
    ext.origin_complement AS id_bank,
    CASE
      WHEN ext.origin_complement LIKE '%BL%'
      THEN REGEXP_REPLACE(SUBSTRING(ext.origin_complement, 20, 20), '^0+', '')
      ELSE REGEXP_REPLACE(ext.origin_complement, '^0+', '')
    END AS our_number_temp,
    '04526' AS bank_account,
    CAST(ext.date_accounting AS DATE) AS dt_paid,
    ext.amount_value AS amount
  FROM datalake_itau_statements_clean.statement_879200452685 AS ext
  WHERE
    ext.operation IN ('C') AND ext.literal_code IN ('9489')
), francesinha AS (
  SELECT
    our_number AS id_bank,
    REGEXP_REPLACE(REGEXP_REPLACE(our_number, '^0+', ''), '.$', '') AS our_number,
    bank_account,
    dt_credit AS dt_paid,
    SUM(net_amount) AS amount
  FROM datalake_nexxera.cnab_charges_recupera
  WHERE
    bank_account = '04526'
    AND occurrence_code = '06'
    AND NOT our_number IS NULL
    AND TRIM(our_number) <> ''
    AND dt_credit >= CURRENT_DATE - 180
  GROUP BY
    1,
    2,
    3,
    4
  UNION
  SELECT
    id_bank,
    CASE
      WHEN id_bank LIKE '000%'
      THEN REGEXP_REPLACE(REGEXP_REPLACE(our_number_temp, '.$', ''), '.$', '')
      WHEN LENGTH(our_number_temp) >= 30
      THEN REGEXP_REPLACE(REGEXP_REPLACE(our_number_temp, '.$', ''), '.$', '')
      ELSE our_number_temp
    END AS our_number,
    bank_account,
    dt_paid,
    amount
  FROM pre_francesinha
), pre_sap AS (
  SELECT DISTINCT
    id_business_entity,
    id_finance_entity,
    id_external_payment,
    COALESCE(CAST(SPLIT_PART(id_external_payment, '|', 2) AS INT), id_external_payment) AS our_number,
    dt_tax AS dt_paid,
    account_number,
    SUM(debit_credit) AS amount,
    CONCAT_WS(', ', COLLECT_LIST(hash)) AS hash
  FROM datalake_pas.ledger
  WHERE
    (
      (
        dt_reference >= CAST('2024-01-01' AS DATE) AND account_number = '11036X'
      )
      OR (
        dt_reference < CAST('2024-01-01' AS DATE) AND account_number = '11102.01.11'
      )
    )
    AND id_finance_entity <> ''
    AND NOT id_finance_entity IS NULL
    AND dt_tax >= CURRENT_DATE - 180
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6
  HAVING
    SUM(debit_credit) <> 0
), sap AS (
  SELECT
    id_business_entity,
    id_finance_entity,
    id_external_payment,
    IF(
      LENGTH(REGEXP_REPLACE(our_number, '^0+', '')) > 30,
      LEFT(
        REGEXP_REPLACE(our_number, '^0+', ''),
        LENGTH(REGEXP_REPLACE(our_number, '^0+', '')) - 2
      ),
      REGEXP_REPLACE(our_number, '^0+', '')
    ) AS our_number,
    dt_paid,
    account_number,
    amount,
    hash
  FROM pre_sap
), checkout AS (
  SELECT
    company_use,
    id_contract,
    id_invoice,
    ts_paid,
    paid_amount,
    payer_name,
    status,
    our_number
  FROM (
    SELECT
      NULLIF(b.our_number, '') AS company_use,
      NULLIF(b.id_business_entity, '') AS id_contract,
      b.id_finance_entity AS id_invoice,
      CAST(b.ts_paid AS DATE) AS ts_paid,
      b.paid_amount,
      b.payer_name,
      b.status,
      NULLIF(CAST(TRIM(b.our_number) AS INT), '') AS our_number,
      ROW_NUMBER() OVER (PARTITION BY b.your_number ORDER BY CAST(b.ts_paid AS DATE) DESC) AS _w,
      b.your_number
    FROM datalake_checkout_clean.boleto AS b
    WHERE
      b.requester_name = 'trato-feito'
      AND NOT b.id IN (5855, 5856, 5857)
      AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
      AND (
        b.beneficiary_account = '45268' OR b.beneficiary_account IS NULL
      )
      AND b.ts_paid >= CURRENT_DATE - 180
  ) AS _t
  WHERE
    _w = 1
), checkout_union AS (
  SELECT
    our_number,
    id_pix_payment,
    amount,
    payment_method,
    payment_status,
    dt_paid
  FROM (
    SELECT
      CAST(UPPER(vc.our_number) AS INT) AS our_number,
      NULL AS id_pix_payment,
      vc.paid_amount AS amount,
      'BOLETO' AS payment_method,
      vc.status AS payment_status,
      CAST(dd.next_brz_fintech_business_day AS DATE) AS dt_paid,
      ROW_NUMBER() OVER (PARTITION BY CAST(UPPER(vc.our_number) AS INT), paid_amount ORDER BY CASE
        WHEN NOT id_invoice IS NULL
        THEN company_use
        ELSE CAST(UPPER(vc.our_number) AS INT)
      END DESC) AS _w,
      paid_amount,
      company_use,
      id_invoice
    FROM checkout AS vc
    LEFT JOIN dw_public.dim_date AS dd
      ON vc.ts_paid = dd.date
  ) AS _t
  WHERE
    _w = 1
  UNION
  SELECT
    b.our_number,
    NULL AS id_pix_payment,
    b.paid_amount AS amount,
    'BOLECODE' AS payment_method,
    b.status AS payment_status,
    CASE
      WHEN dd.is_brz_fintech_business_day = FALSE
      THEN dd.next_brz_fintech_business_day
      ELSE CAST(COALESCE(dt_credit, CAST(ts_paid AS DATE)) AS DATE)
    END AS dt_paid
  FROM datalake_checkout_clean.bolecode AS b
  LEFT JOIN dw_public.dim_date AS dd
    ON COALESCE(dt_credit, CAST(ts_paid AS DATE)) = dd.date
  WHERE
    b.requester_name = 'trato-feito'
    AND NOT b.id IN (5855, 5856, 5857)
    AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
    AND (
      b.beneficiary_account = '45268' OR b.beneficiary_account IS NULL
    )
    AND COALESCE(dt_credit, CAST(ts_paid AS DATE)) >= CURRENT_DATE - 180
  UNION ALL
  SELECT
    CASE
      WHEN p.id_transaction LIKE '000%'
      THEN LEFT(
        REGEXP_REPLACE(p.id_transaction, '^0+', ''),
        LENGTH(REGEXP_REPLACE(p.id_transaction, '^0+', '')) - 2
      )
      WHEN LENGTH(REGEXP_REPLACE(p.id_transaction, '^0+', '')) >= 30
      THEN LEFT(
        REGEXP_REPLACE(p.id_transaction, '^0+', ''),
        LENGTH(REGEXP_REPLACE(p.id_transaction, '^0+', '')) - 2
      )
      ELSE REGEXP_REPLACE(p.id_transaction, '^0+', '')
    END AS our_number,
    p.id_transaction AS id_pix_payment,
    p.due_amount AS amount,
    'PIX' AS payment_method,
    p.status AS payment_status,
    CASE
      WHEN dd.is_brz_fintech_business_day = FALSE
      THEN dd.next_brz_fintech_business_day
      ELSE CAST(p.ts_paid AS DATE)
    END AS dt_paid
  FROM datalake_checkout_clean.pix AS p
  LEFT JOIN dw_public.dim_date AS dd
    ON CAST(p.ts_paid AS DATE) = dd.date
  WHERE
    p.requester_name = 'trato-feito'
    AND NOT p.id IN (5855, 5856, 5857)
    AND p.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
    AND CAST(p.ts_paid AS DATE) >= CURRENT_DATE - 180
), trato_feito AS (
  SELECT
    our_number,
    id_invoice,
    amount,
    dt_paid
  FROM (
    SELECT
      COALESCE(REGEXP_REPLACE(b.our_number, '^0+', ''), REGEXP_REPLACE(i.id_external, '^0+', '')) AS our_number,
      b.id_external AS id_invoice,
      i.total_amount AS amount,
      CASE
        WHEN dd.is_brz_fintech_business_day = FALSE
        THEN dd.next_brz_fintech_business_day
        ELSE COALESCE(CAST(p.dt_credit AS DATE), CAST(p.dt_paid AS DATE))
      END AS dt_paid,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(REGEXP_REPLACE(b.our_number, '^0+', ''), REGEXP_REPLACE(i.id_external, '^0+', '')) ORDER BY date DESC) AS _w,
      date
    FROM datalake_trato_feito_clean.installment AS i
    LEFT JOIN datalake_trato_feito_clean.payment AS p
      ON p.id_installment = i.id
    LEFT JOIN datalake_trato_feito_clean.accounting_installment AS aci
      ON aci.id_installment = i.id
    LEFT JOIN datalake_trato_feito_clean.bill AS b
      ON b.id_external = aci.id_external
    LEFT JOIN dw_public.dim_date AS dd
      ON COALESCE(CAST(p.dt_credit AS DATE), CAST(p.dt_paid AS DATE)) = dd.date
  ) AS _t
  WHERE
    _w = 1
  UNION ALL
  SELECT
    CASE
      WHEN px.id_transaction LIKE '000%'
      THEN LEFT(
        REGEXP_REPLACE(px.id_transaction, '^0+', ''),
        LENGTH(REGEXP_REPLACE(px.id_transaction, '^0+', '')) - 2
      )
      WHEN LENGTH(REGEXP_REPLACE(px.id_transaction, '^0+', '')) >= 30
      THEN LEFT(
        REGEXP_REPLACE(px.id_transaction, '^0+', ''),
        LENGTH(REGEXP_REPLACE(px.id_transaction, '^0+', '')) - 2
      )
      ELSE REGEXP_REPLACE(px.id_transaction, '^0+', '')
    END AS our_number,
    CAST(NULL AS STRING) AS id_invoice,
    ic.paid_amount AS amount,
    CASE
      WHEN dd.is_brz_fintech_business_day = FALSE
      THEN dd.next_brz_fintech_business_day
      ELSE CAST(p.dt_paid AS DATE)
    END AS dt_paid
  FROM datalake_trato_feito_clean.installment_charges AS ic
  LEFT JOIN datalake_trato_feito_clean.installment AS i
    ON ic.id = i.id_installment_charge
  LEFT JOIN datalake_trato_feito_clean.payment AS p
    ON i.id = p.id_installment
  LEFT JOIN datalake_checkout_clean.pix AS px
    ON ic.id_charge = px.id_charge
  LEFT JOIN dw_public.dim_date AS dd
    ON CAST(p.dt_paid AS DATE) = dd.date
), seu_barriga_sap AS (
  SELECT
    id_invoice,
    id_original_invoice_external,
    company_use,
    payment_status,
    status,
    paid_via,
    reason,
    amount,
    month_paid,
    dt_paid
  FROM (
    SELECT
      id_external AS id_invoice,
      id_original_invoice_external,
      UPPER(payment_company_use_number) AS company_use,
      payment_status,
      status,
      paid_via,
      reason,
      paid_amount AS amount,
      DATE_TRUNC('MONTH', dd.next_brz_fintech_business_day) AS month_paid,
      dd.next_brz_fintech_business_day AS dt_paid,
      ROW_NUMBER() OVER (PARTITION BY id_external, payment_company_use_number ORDER BY ts_created DESC) AS _w,
      payment_company_use_number,
      ts_created
    FROM datalake_retsuko.invoice
    LEFT JOIN dw_public.dim_date AS dd
      ON invoice.ts_paid = dd.date
    WHERE
      NOT payment_company_use_number IS NULL
      AND TRIM(payment_company_use_number) <> ''
      AND LOWER(paid_via) IN ('cnab', 'checkout-boleto', 'cyber-boleto')
      AND due_amount <= 0
      AND payment_status <> 'canceled'
      AND status <> 'canceled'
      AND country_code = 'BR'
  ) AS _t
  WHERE
    _w = 1
), df_all AS (
  SELECT DISTINCT
    our_number,
    DATE_TRUNC('MONTH', dt_paid) AS month_paid
  FROM checkout_union
  UNION ALL
  SELECT DISTINCT
    our_number,
    DATE_TRUNC('MONTH', dt_paid) AS month_paid
  FROM sap
  UNION ALL
  SELECT DISTINCT
    our_number,
    DATE_TRUNC('MONTH', dt_paid) AS month_paid
  FROM francesinha
), df AS (
  SELECT DISTINCT
    f.id_bank AS bank_number,
    cs.our_number AS id_our_number,
    COALESCE(sbs.id_invoice, tf.id_invoice, s.id_finance_entity) AS id_invoice,
    vc.id_pix_payment,
    s.hash,
    f.bank_account AS bank_account_number,
    s.account_number AS sap_account_number,
    vc.payment_method,
    vc.payment_status,
    f.amount AS bank_amount,
    COALESCE(sbs.amount, tf.amount) AS billing_amount,
    vc.amount AS checkout_amount,
    s.amount AS sap_amount,
    IF(f.our_number IS NULL, 'not recorded', 'ok') AS status_bank,
    CASE
      WHEN f.amount = COALESCE(tf.amount, sbs.amount)
      AND f.dt_paid = CAST(COALESCE(sbs.dt_paid, tf.dt_paid) AS DATE)
      THEN 'ok'
      WHEN f.amount <> COALESCE(tf.amount, sbs.amount)
      AND f.dt_paid <> CAST(COALESCE(sbs.dt_paid, tf.dt_paid) AS DATE)
      THEN 'recorded on the wrong date and value'
      WHEN f.amount <> COALESCE(tf.amount, sbs.amount)
      AND f.dt_paid = CAST(COALESCE(sbs.dt_paid, tf.dt_paid) AS DATE)
      THEN 'recorded on the wrong value'
      WHEN f.amount = COALESCE(tf.amount, sbs.amount)
      AND f.dt_paid <> CAST(COALESCE(sbs.dt_paid, tf.dt_paid) AS DATE)
      THEN 'recorded on the wrong date'
      WHEN vc.our_number IS NULL
      THEN 'not recorded'
      ELSE 'not ok'
    END AS status_billing,
    CASE
      WHEN f.amount = vc.amount AND f.dt_paid = CAST(vc.dt_paid AS DATE)
      THEN 'ok'
      WHEN f.amount <> vc.amount AND f.dt_paid <> CAST(vc.dt_paid AS DATE)
      THEN 'recorded on the wrong date and value'
      WHEN f.amount <> vc.amount AND f.dt_paid = CAST(vc.dt_paid AS DATE)
      THEN 'recorded on the wrong value'
      WHEN f.amount = vc.amount AND f.dt_paid <> CAST(vc.dt_paid AS DATE)
      THEN 'recorded on the wrong date'
      WHEN vc.our_number IS NULL
      THEN 'not recorded'
      ELSE 'not ok'
    END AS status_checkout,
    CASE
      WHEN f.amount = s.amount AND f.dt_paid = CAST(s.dt_paid AS DATE)
      THEN 'ok'
      WHEN f.amount <> s.amount AND f.dt_paid <> CAST(s.dt_paid AS DATE)
      THEN 'recorded on the wrong date and value'
      WHEN f.amount <> s.amount AND f.dt_paid = CAST(s.dt_paid AS DATE)
      THEN 'recorded on the wrong value'
      WHEN f.amount = s.amount AND f.dt_paid <> CAST(s.dt_paid AS DATE)
      THEN 'recorded on the wrong date'
      WHEN s.our_number IS NULL
      THEN 'not recorded'
      ELSE 'not ok'
    END AS status_sap,
    f.dt_paid AS dt_bank_paid,
    COALESCE(sbs.dt_paid, tf.dt_paid) AS dt_billing_paid,
    vc.dt_paid AS dt_checkout_paid,
    s.dt_paid AS dt_sap_paid
  FROM df_all AS cs
  LEFT JOIN francesinha AS f
    ON f.our_number = cs.our_number
  LEFT JOIN checkout_union AS vc
    ON vc.our_number = cs.our_number
  LEFT JOIN trato_feito AS tf
    ON tf.our_number = cs.our_number
  LEFT JOIN seu_barriga_sap AS sbs
    ON (
      (
        sbs.company_use = cs.our_number
      ) AND (
        sbs.month_paid = cs.month_paid
      )
    )
    OR (
      sbs.id_invoice = tf.id_invoice
    )
  LEFT JOIN sap AS s
    ON (
      cs.our_number = s.our_number
    ) OR (
      tf.id_invoice = s.id_finance_entity
    )
  WHERE
    NOT cs.our_number IS NULL
    AND (
      CAST(f.dt_paid AS DATE) >= '2024-01-01'
      OR CAST(vc.dt_paid AS DATE) >= '2024-01-01'
      OR CAST(s.dt_paid AS DATE) >= '2024-01-01'
      OR CAST(sbs.dt_paid AS DATE) >= '2024-01-01'
      OR CAST(tf.dt_paid AS DATE) >= '2024-01-01'
    )
)
SELECT
  df.id_our_number,
  df.id_invoice,
  df.hash,
  bank_number,
  bank_account_number,
  sap_account_number,
  payment_method,
  payment_status,
  bank_amount,
  billing_amount,
  checkout_amount,
  sap_amount,
  status_bank,
  status_billing,
  status_checkout,
  status_sap,
  IF(
    status_bank = 'ok'
    AND status_sap = 'ok'
    AND status_checkout = 'ok'
    AND status_billing = 'ok',
    TRUE,
    FALSE
  ) AS is_reconciled,
  CASE
    WHEN status_bank = 'ok'
    AND status_sap = 'ok'
    AND status_checkout = 'ok'
    AND status_billing = 'ok'
    THEN 'Concilied'
    WHEN status_sap = 'not recorded' AND status_bank = 'not recorded'
    THEN 'Not Concilied - SAP & Bank missing'
    WHEN status_bank = 'not recorded'
    THEN 'Not Concilied - Bank missing'
    WHEN status_sap = 'not recorded'
    THEN 'Not Concilied - SAP missing'
    WHEN status_billing = 'not recorded'
    THEN 'Not Concilied - Billing missing'
    WHEN status_checkout = 'not recorded'
    THEN 'Not Concilied - Payment source missing'
    WHEN bank_amount > 0 AND sap_amount / bank_amount = 2
    THEN 'Not Concilied - SAP duplicated'
    WHEN dt_sap_paid < dt_bank_paid OR dt_sap_paid > dt_bank_paid
    THEN 'Not Concilied - SAP and Bank with divergent date'
    WHEN status_billing IN ('recorded on the wrong date and value', 'recorded on the wrong date', 'recorded on the wrong value')
    THEN 'Not Concilied - Billing divergent'
    WHEN status_checkout IN ('recorded on the wrong date and value', 'recorded on the wrong date', 'recorded on the wrong value')
    THEN 'Not Concilied - Payment source divergent'
    ELSE 'Not Concilied - other'
  END AS is_bank_concilied_detail,
  CASE
    WHEN status_sap = 'not recorded' AND id_invoice IS NULL
    THEN 'retsuko not found'
    WHEN status_sap = 'not recorded' AND e.id_finance_entity IS NULL
    THEN 'sap entity not found'
    WHEN status_sap = 'not recorded' AND e.status = 'failed'
    THEN CONCAT('sap_entity failed:', e.failed_reason)
    WHEN status_sap = 'not recorded' AND sg.id_feature IS NULL
    THEN 'gateway not found'
    WHEN status_sap = 'not recorded' AND sg.sync_sap_job_status = 'error'
    THEN sg.webhook_error
    WHEN status_sap = 'not recorded'
    AND NOT e.id_finance_entity IS NULL
    AND NOT sg.id_feature IS NULL
    THEN 'sap not found'
  END AS sap_error_detail,
  dt_bank_paid,
  dt_billing_paid,
  dt_checkout_paid,
  dt_sap_paid,
  id_pix_payment
FROM df
LEFT JOIN sap_entity AS e
  ON df.id_invoice = e.id_finance_entity
LEFT JOIN sap_gateway AS sg
  ON e.id_sap_gateway_feature = sg.id_feature