WITH
communication_sent AS (
  SELECT
    id_invoice,
    ARRAY_AGG(DISTINCT communication_type) FILTER (WHERE was_delivered) AS communications_sent
  FROM
    datalake_condo_monitoring.communication
  GROUP BY ALL
),
invoice_paid AS (
  SELECT
    id AS id_invoice,
    ts_updated AS ts_paid
  FROM
    datalake_condominium_payments_clean.invoice_aud
  WHERE
    status = 'PAID'
)
SELECT
  i.id AS id_invoice,
  i.id_contract,
  GET_JSON_OBJECT(GET_JSON_OBJECT(i.raw_data, "$.issuer"), "$.taxId") AS issuer_cnpj,
  i.status,
  GET_JSON_OBJECT(GET_JSON_OBJECT(i.raw_data, "$.issuer"), "$.name") AS issuer_name,
  GET_JSON_OBJECT(i.raw_data, "$.barcode") AS barcode,
  c.communications_sent,
  CASE
    WHEN ARRAY_CONTAINS(c.communications_sent, "WARNING") THEN "WARNING"
    WHEN ARRAY_CONTAINS(c.communications_sent, "REMINDER") THEN "REMINDER"
    WHEN c.communications_sent = ARRAY()
      OR c.communications_sent IS NULL THEN "COMMUNICATION_NOT_FOUND"
  END AS communication_funnel_step_reached,
  i.value,
  IF(ip.ts_paid >= DATE_ADD(i.dt_due, -1) OR ip.id_invoice IS NULL, TRUE, FALSE) AS was_reminder_comm_required,
  IF(ip.ts_paid >= DATE_ADD(i.dt_due, 3) OR ip.id_invoice IS NULL, TRUE, FALSE) AS was_warning_comm_required,
  i.dt_due,
  i.ts_created AS ts_issued,
  ip.ts_paid
FROM
  datalake_condominium_payments_clean.invoice AS i
LEFT JOIN
  communication_sent AS c
    ON i.id = c.id_invoice
LEFT JOIN
  invoice_paid AS ip
    ON i.id = ip.id_invoice
