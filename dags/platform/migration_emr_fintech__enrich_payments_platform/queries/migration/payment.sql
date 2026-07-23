WITH subscription_invoices AS (
  SELECT
    id,
    id_charge,
    id_subscription,
    id_subscription_item,
    id_finance_entity,
    ts_created
  FROM (
    SELECT
      i.id,
      i.id_charge,
      i.id_subscription,
      isi.id_subscription_item,
      si.code AS id_finance_entity,
      si.ts_created,
      ROW_NUMBER() OVER (PARTITION BY i.id_charge ORDER BY si.ts_created DESC) AS _w
    FROM datalake_wall_street_clean.invoice AS i
    LEFT JOIN datalake_wall_street_clean.invoice_subscription_item AS isi
      ON isi.id_invoice = i.id
    LEFT JOIN datalake_wall_street_clean.subscription_item AS si
      ON si.id = isi.id_subscription_item
    LEFT JOIN datalake_wall_street_clean.subscription AS s
      ON si.code = (
        s.code || '|default-item'
      )
    LEFT JOIN datalake_wall_street_clean.subscription AS s1
      ON si.code = (
        s1.code || '_item'
      )
    WHERE
      s.code IS NULL AND s1.code IS NULL
  ) AS _t
  WHERE
    _w = 1
), charge_created AS (
  SELECT
    id,
    ts_created
  FROM (
    SELECT
      id,
      FIRST_VALUE(ts_updated) OVER (PARTITION BY id ORDER BY rev) AS ts_created,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY rev DESC) AS _w,
      rev
    FROM datalake_wall_street_clean.charge_aud
  ) AS _t
  WHERE
    _w = 1
), charge_canceled AS (
  SELECT
    id,
    ts_canceled
  FROM (
    SELECT
      id,
      FIRST_VALUE(ts_updated) OVER (PARTITION BY id ORDER BY rev) AS ts_canceled,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY rev DESC) AS _w,
      rev
    FROM datalake_wall_street_clean.charge_aud
    WHERE
      charge_status = 'CANCELED'
  ) AS _t
  WHERE
    _w = 1
), ws_charge AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      COUNT(*) OVER (PARTITION BY id_finance_entity) AS _w,
      ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY IF(acquire_tid <> '-1', 0, 1), ts_paid) AS _w_2
    FROM datalake_wall_street_clean.charge
  ) AS _t
  WHERE
    IF(_w > 1, acquire_tid <> '-1', TRUE)
    AND IF(acquire_tid <> '-1', _w_2 = 1, FALSE)
), credit_card_payments AS (
  SELECT
    id_checkout_charge,
    id_ws_charge,
    id_checkout_last_capture_attempt,
    id_ws_last_charge,
    id_business_entity,
    id_finance_entity,
    id_checkout_requester,
    id_wall_street_store,
    code,
    status,
    id_acquire_transaction,
    acquirer_auth_code,
    acquire_nsu,
    acquire_return_code,
    acquire_message,
    cancellation_reason,
    installments,
    installment_fee_amount,
    fine_amount,
    amount,
    ts_paid,
    ts_created,
    ts_updated,
    id_customer,
    store_description,
    store_id,
    our_number,
    your_number,
    company_use,
    error_type
  FROM (
    SELECT
      cc.id_charge AS id_checkout_charge,
      wsc.id AS id_ws_charge,
      cca.id AS id_checkout_last_capture_attempt,
      wsc.id AS id_ws_last_charge,
      COALESCE(cc.id_business_entity, wsc.id_business_entity) AS id_business_entity,
      COALESCE(cc.id_finance_entity, wsc.id_finance_entity, si.id_finance_entity) AS id_finance_entity,
      cc.id_requester AS id_checkout_requester,
      wsc.id_store AS id_wall_street_store,
      COALESCE(cca.code, wsc.code, cc.code) AS code,
      COALESCE(cca.status, wsc.charge_status, cc.status) AS status,
      COALESCE(cca.acquire_tid, wsc.id_acquire_transaction) AS id_acquire_transaction,
      COALESCE(cca.acquire_auth_code, wsc.acquire_auth_code) AS acquirer_auth_code,
      COALESCE(cca.acquire_nsu, wsc.acquire_nsu) AS acquire_nsu,
      wsc.acquire_return_code,
      wsc.acquire_message,
      cc.cancellation_reason,
      COALESCE(cca.installments, wsc.installments) AS installments,
      cc.installment_fee_amount,
      cc.fine_amount,
      COALESCE(cca.paid_amount, wsc.amount) AS amount,
      COALESCE(cca.ts_paid, wsc.ts_paid) AS ts_paid,
      COALESCE(cca.ts_created, ccr.ts_created, cc.ts_created) AS ts_created,
      COALESCE(cca.ts_updated, ccan.ts_canceled, cc.ts_updated) AS ts_updated,
      wsc.id_customer,
      store.description AS store_description,
      store.id AS store_id,
      NULL AS our_number,
      NULL AS your_number,
      NULL AS company_use,
      COALESCE(gwt.description, 'NAO IDENTIFICADO') AS error_type,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(
        COALESCE(cc.id_finance_entity, wsc.id_finance_entity, si.id_finance_entity),
        COALESCE(cc.id_finance_entity, wsc.id_finance_entity, si.id_finance_entity),
        COALESCE(cc.id_finance_entity, wsc.id_finance_entity, si.id_finance_entity)
      ), COALESCE(cc.id_charge, wsc.id) ORDER BY COALESCE(
        COALESCE(cca.ts_created, ccr.ts_created, cc.ts_created),
        COALESCE(cca.ts_updated, ccan.ts_canceled, cc.ts_updated),
        COALESCE(cca.ts_created, ccr.ts_created, cc.ts_created)
      ) DESC) AS _w,
      cc.id_charge,
      wsc.id
    FROM datalake_checkout_clean.credit_card AS cc
    LEFT JOIN datalake_checkout_clean.credit_card_capture_attempt AS cca
      ON cca.id_credit_card = cc.id
    FULL JOIN ws_charge AS wsc
      ON wsc.code = cca.code AND wsc.id_finance_entity = cc.id_finance_entity
    LEFT JOIN charge_created AS ccr
      ON ccr.id = wsc.id
    LEFT JOIN charge_canceled AS ccan
      ON ccan.id = wsc.id
    LEFT JOIN subscription_invoices AS si
      ON si.id_charge = wsc.id
    LEFT JOIN datalake_wall_street_clean.store AS store
      ON store.id = wsc.id_store
    LEFT JOIN datalake_gsheets_clean.getnet_return_codes AS gwt
      ON gwt.new_code = wsc.acquire_return_code
      AND IF(
        gwt.card_brand = 'GETNET' OR gwt.card_brand = 'TODAS',
        1 = 1,
        gwt.card_brand = UPPER(wsc.card_brand)
      )
  ) AS _t
  WHERE
    _w = 1
), checkout AS (
  SELECT
    ch.id AS id_charge,
    o.id AS id_order,
    o.id_business_entity AS id_contract,
    ch.id_user_external AS id_person,
    o.id_finance_entity AS id_invoice,
    o.id_finance_entity,
    o.id_requester,
    NULL AS id_last_payment_attempt_timeline,
    o.status AS payment_status,
    IF(o.status = 'PAID', ch.payment_method, NULL) AS successfull_method,
    'checkout' AS datasource,
    'PAYIN' AS transaction_category,
    r.name AS requester_description,
    CONCAT(COALESCE(ch.alternative_payment_methods, ARRAY()), ARRAY(ch.payment_method)) AS methods,
    CASE ch.payment_method
      WHEN 'CREDIT_CARD'
      THEN cc.cancellation_reason
      WHEN 'BOLETO'
      THEN b.write_down_reason
      WHEN 'BOLECODE'
      THEN pw.error_message
      WHEN 'PIX'
      THEN pw.error_message
      ELSE NULL
    END AS status_reason,
    NULL AS retry_reason,
    cc.installments,
    o.due_amount,
    cc.installment_fee_amount,
    cc.fine_amount,
    CASE ch.payment_method
      WHEN 'CREDIT_CARD'
      THEN TIMESTAMPDIFF(SECOND, cc.ts_created, cc.ts_paid)
      WHEN 'BOLETO'
      THEN TIMESTAMPDIFF(SECOND, b.ts_created, b.ts_paid)
      WHEN 'BOLECODE'
      THEN TIMESTAMPDIFF(SECOND, bc.ts_created, bc.ts_paid)
      WHEN 'PIX'
      THEN TIMESTAMPDIFF(SECOND, pix.ts_created, pix.ts_paid)
      ELSE NULL
    END AS method_created_to_paid_latency_seconds,
    IF(s.id = 6, TRUE, FALSE) AS is_recurrence,
    NULL AS has_retry,
    o.dt_due,
    CASE ch.payment_method
      WHEN 'CREDIT_CARD'
      THEN cc.ts_created
      WHEN 'BOLETO'
      THEN b.ts_created
      WHEN 'BOLECODE'
      THEN bc.ts_created
      WHEN 'PIX'
      THEN pix.ts_created
      ELSE NULL
    END AS ts_method_created,
    CASE ch.payment_method
      WHEN 'CREDIT_CARD'
      THEN cc.ts_paid
      WHEN 'BOLETO'
      THEN b.ts_paid
      WHEN 'BOLECODE'
      THEN bc.ts_paid
      WHEN 'PIX'
      THEN pix.ts_paid
      ELSE NULL
    END AS ts_method_paid,
    o.ts_created AS ts_order_created,
    ch.ts_started_processing AS ts_charge_started_processing,
    ch.ts_paid AS ts_charge_paid,
    ch.ts_canceled AS ts_charge_canceled,
    CASE ch.payment_method
      WHEN 'BOLETO'
      THEN b.our_number
      WHEN 'BOLECODE'
      THEN bc.our_number
      ELSE NULL
    END AS our_number,
    CASE ch.payment_method
      WHEN 'BOLETO'
      THEN b.your_number
      WHEN 'BOLECODE'
      THEN bc.your_number
      ELSE NULL
    END AS your_number,
    NULL AS company_use,
    cc.acquirer_auth_code AS acquirer_auth_code,
    cc.acquire_nsu AS acquire_nsu,
    wc.acquire_tid AS id_acquire_transaction,
    cc.acquire_return_code AS acquire_return_code,
    COALESCE(gwt.description, 'NAO IDENTIFICADO') AS error_type
  FROM datalake_checkout_clean.order AS o
  LEFT JOIN datalake_checkout_clean.charge AS ch
    ON ch.id_order = o.id
  LEFT JOIN datalake_checkout_clean.boleto AS b
    ON b.id_charge = ch.id
  LEFT JOIN datalake_checkout_clean.boleto_webhook AS bw
    ON bw.id_boleto = b.id
  LEFT JOIN datalake_checkout_clean.bolecode AS bc
    ON bc.id_charge = ch.id
  LEFT JOIN credit_card_payments AS cc
    ON NOT cc.id_checkout_charge IS NULL AND cc.id_checkout_charge = ch.id
  LEFT JOIN datalake_checkout_clean.pix AS pix
    ON pix.id_charge = ch.id
  LEFT JOIN datalake_checkout_clean.pix_webhook AS pw
    ON pw.id_pix = pix.id OR pw.id_bolecode = bc.id
  LEFT JOIN datalake_checkout_clean.requester AS r
    ON r.id = o.id_requester
  LEFT JOIN ws_charge AS wc
    ON o.id_finance_entity = wc.id_finance_entity
  LEFT JOIN datalake_wall_street_clean.store AS s
    ON s.id = wc.id_store
  LEFT JOIN datalake_gsheets_clean.getnet_return_codes AS gwt
    ON gwt.new_code = wc.acquire_return_code
    AND IF(
      gwt.card_brand = 'GETNET' OR gwt.card_brand = 'TODAS',
      1 = 1,
      gwt.card_brand = UPPER(wc.card_brand)
    )
), vans_boleto AS (
  SELECT
    b.id AS id_charge,
    NULL AS id_order,
    REGEXP_EXTRACT(b.company_use, '^[0-9]+', 0) AS id_contract,
    b.payer_document AS id_person,
    IF(
      related_document_type = 'invoice',
      COALESCE(CAST(id_related_document AS BIGINT), -1),
      -1
    ) AS id_invoice,
    b.id_bank_boleto AS id_finance_entity,
    b.id_bank_boleto,
    b.requested_by AS id_requester,
    NULL AS id_last_payment_attempt_timeline,
    b.status AS payment_status,
    'BOLETO' AS successfull_method,
    'vans' AS datasource,
    'PAYIN' AS transaction_category,
    b.requested_by AS requester_description,
    ARRAY('BOLETO') AS methods,
    b.occurrence_reason AS status_reason,
    NULL AS retry_reason,
    NULL AS installments,
    b.due_amount,
    NULL AS installment_fee_amount,
    b.fine_amount,
    TIMESTAMPDIFF(SECOND, b.ts_created, b.dt_paid) AS method_created_to_paid_latency_seconds,
    NULL AS is_recurrence,
    NULL AS has_retry,
    b.dt_due AS dt_due,
    b.ts_created AS ts_method_created,
    b.dt_paid AS ts_method_paid,
    b.ts_created AS ts_order_created,
    NULL AS ts_charge_started_processing,
    b.dt_paid AS ts_charge_paid,
    CASE WHEN b.status = ':boleto.status/canceled' THEN b.ts_updated ELSE NULL END AS ts_charge_canceled,
    b.our_number,
    NULL AS your_number,
    b.company_use,
    NULL AS acquirer_auth_code,
    NULL AS acquire_nsu,
    NULL AS id_acquire_transaction,
    NULL AS acquire_return_code,
    NULL AS error_type
  FROM datalake_vans_clean.boleto AS b
  LEFT JOIN datalake_vans_clean.boleto_file AS bf
    ON b.id = bf.id_boleto
  LEFT JOIN datalake_vans_clean.file AS f
    ON f.id = bf.id_file
  WHERE
    NOT b.status IS NULL
    AND b.requested_by = 'seubarriga'
    AND NOT b.id_related_document IS NULL
    AND b.related_document_type = 'invoice'
    AND f.type = ':file.type/boleto'
), cte_union AS (
  SELECT
    CONCAT(COALESCE(id_ws_charge, id_checkout_charge), '_wallstreet') AS id_business_key,
    id_checkout_charge AS id_charge,
    NULL AS id_order,
    id_business_entity AS id_contract,
    id_customer AS id_person,
    id_finance_entity AS id_invoice,
    id_finance_entity,
    'wallstreet' AS id_requester,
    NULL AS id_last_payment_attempt_timeline,
    status AS payment_status,
    'CREDIT_CARD' AS successfull_method,
    'wallstreet' AS datasource,
    'PAYIN' AS transaction_category,
    store_description AS requester_description,
    ARRAY('CREDIT_CARD') AS methods,
    acquire_message AS status_reason,
    NULL AS retry_reason,
    installments,
    amount AS due_amount,
    installment_fee_amount,
    fine_amount,
    TIMESTAMPDIFF(SECOND, ts_created, ts_paid) AS method_created_to_paid_latency_seconds,
    IF(store_id = 6, TRUE, FALSE) AS is_recurrence,
    NULL AS has_retry,
    NULL AS dt_due,
    ts_created AS ts_method_created,
    ts_paid AS ts_method_paid,
    ts_created AS ts_order_created,
    NULL AS ts_charge_started_processing,
    ts_paid AS ts_charge_paid,
    ts_updated AS ts_charge_canceled,
    our_number,
    your_number,
    company_use,
    acquirer_auth_code,
    acquire_nsu,
    id_acquire_transaction,
    acquire_return_code,
    error_type
  FROM credit_card_payments
  WHERE
    id_checkout_charge IS NULL
  UNION ALL
  SELECT
    CONCAT(COALESCE(id_charge, ''), '_', datasource) AS id_business_key,
    id_charge,
    id_order,
    id_contract,
    id_person,
    id_invoice,
    id_finance_entity,
    id_requester,
    id_last_payment_attempt_timeline,
    payment_status,
    successfull_method,
    datasource,
    'PAYIN' AS transaction_category,
    requester_description,
    methods,
    status_reason,
    retry_reason,
    installments,
    due_amount,
    installment_fee_amount,
    fine_amount,
    method_created_to_paid_latency_seconds,
    is_recurrence,
    has_retry,
    dt_due,
    ts_method_created,
    ts_method_paid,
    ts_order_created,
    ts_charge_started_processing,
    ts_charge_paid,
    ts_charge_canceled,
    our_number,
    your_number,
    company_use,
    acquirer_auth_code,
    acquire_nsu,
    id_acquire_transaction,
    acquire_return_code,
    error_type
  FROM checkout
  WHERE
    NOT id_charge IS NULL
  UNION ALL
  SELECT
    CONCAT(COALESCE(id_charge, ''), '_', datasource) AS id_business_key,
    id_charge,
    id_order,
    id_contract,
    id_person,
    id_invoice,
    id_finance_entity,
    id_requester,
    id_last_payment_attempt_timeline,
    payment_status,
    successfull_method,
    datasource,
    'PAYIN' AS transaction_category,
    requester_description,
    methods,
    status_reason,
    retry_reason,
    installments,
    due_amount,
    installment_fee_amount,
    fine_amount,
    method_created_to_paid_latency_seconds,
    is_recurrence,
    has_retry,
    dt_due,
    ts_method_created,
    ts_method_paid,
    ts_order_created,
    ts_charge_started_processing,
    ts_charge_paid,
    ts_charge_canceled,
    our_number,
    your_number,
    company_use,
    acquirer_auth_code,
    acquire_nsu,
    id_acquire_transaction,
    acquire_return_code,
    error_type
  FROM vans_boleto
)
SELECT DISTINCT
  id_business_key, /* id_payment BIGINT GENERATED ALWAYS AS IDENTITY (created directly on Databricks CREATE TABLE) */
  id_charge,
  id_order,
  id_contract,
  id_person,
  id_invoice,
  id_finance_entity,
  id_requester,
  CASE
    WHEN payment_status = ''
    THEN NULL
    WHEN payment_status = '52'
    THEN NULL
    WHEN payment_status = 'PAID'
    THEN 'PAID'
    WHEN payment_status = 'PROCESSING'
    THEN 'PROCESSING'
    WHEN payment_status = 'ERROR'
    THEN 'ERROR'
    WHEN payment_status = 'CANCELED'
    THEN 'CANCELED'
    WHEN payment_status = 'CHARGEBACK'
    THEN 'CHARGEBACK'
    WHEN payment_status = 'CHARGEBACK_CAPTURED'
    THEN 'CHARGEBACK_CAPTURED'
    WHEN payment_status = 'REFUNDED'
    THEN 'REFUNDED'
    WHEN payment_status = 'PROCESSING_REFUND'
    THEN 'PROCESSING_REFUND'
    WHEN payment_status = 'PENDING_CAPTURE'
    THEN 'PENDING_CAPTURE'
    WHEN payment_status = 'CAPTURE_NOT_PROCESSED'
    THEN 'CAPTURE_NOT_PROCESSED'
    WHEN payment_status = 'CAPTURE_DENIED'
    THEN 'CAPTURE_DENIED'
    WHEN payment_status = 'CAPTURE_BLOCKED'
    THEN 'CAPTURE_BLOCKED'
    WHEN payment_status = 'CAPTURED'
    THEN 'CAPTURED'
    WHEN payment_status = 'PENDING_CANCELATION'
    THEN 'PENDING_CANCELATION'
    WHEN payment_status = 'CANCELATION_NOT_PROCESSED'
    THEN 'CANCELATION_NOT_PROCESSED'
    WHEN payment_status = 'OPEN'
    THEN 'OPEN'
    WHEN payment_status = 'REQUESTED'
    THEN 'REQUESTED'
    WHEN payment_status = 'PENDING_REGISTER_PAYMENT'
    THEN 'PENDING_REGISTER_PAYMENT'
    WHEN payment_status = ':boleto.status/paid'
    THEN 'PAID'
    WHEN payment_status = ':boleto.status/scheduled'
    THEN 'SCHEDULED'
    WHEN payment_status = ':boleto.status/processed'
    THEN 'PROCESSED'
    WHEN payment_status = ':boleto.status/error'
    THEN 'ERROR'
    WHEN payment_status = ':boleto.status/chargeback'
    THEN 'CHARGEBACK'
    WHEN payment_status = ':boleto.status/requested'
    THEN 'REQUESTED'
    WHEN payment_status = ':boleto.status/canceled'
    THEN 'CANCELED'
    WHEN payment_status = ':boleto.status/write-down-requested'
    THEN 'PENDING_WRITE_DOWN'
    WHEN payment_status = ':boleto.status/created'
    THEN 'CREATED'
    WHEN payment_status = ':boleto.status/written-down'
    THEN 'WRITTEN_DOWN'
    WHEN payment_status = ':boleto.status/written-down-error'
    THEN 'WRITE_DOWN_ERROR'
    WHEN payment_status = ':boleto.status/write-down-paid-requested'
    THEN 'PENDING_WRITE_DOWN_PAID'
    WHEN payment_status = ':boleto.status/changed'
    THEN 'CHANGED'
    ELSE payment_status
  END AS payment_status, /* id_last_payment_attempt_timeline, */
  successfull_method,
  datasource,
  transaction_category,
  requester_description,
  methods,
  status_reason,
  CAST(retry_reason AS STRING) AS retry_reason,
  installments,
  due_amount,
  installment_fee_amount,
  fine_amount,
  method_created_to_paid_latency_seconds,
  is_recurrence,
  CAST(has_retry AS BOOLEAN) AS has_retry,
  dt_due,
  ts_method_created,
  ts_method_paid,
  ts_order_created,
  ts_charge_started_processing,
  ts_charge_paid,
  ts_charge_canceled,
  our_number,
  your_number,
  company_use,
  acquirer_auth_code,
  acquire_nsu,
  id_acquire_transaction,
  acquire_return_code,
  error_type
FROM cte_union
