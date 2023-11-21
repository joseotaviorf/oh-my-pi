WITH exploded_expenses AS (
  SELECT
    dl.id,
    EXPLODE(FROM_JSON(GET_JSON_OBJECT(dl.metadata,'$.expenses'), 'ARRAY<STRING>')) AS expenses
  FROM 
    datalake_heimdall_clean.activity AS dl
)
SELECT
  GET_JSON_OBJECT(xp.expenses,'$._id') AS id,
  xp.id AS id_activity,
  GET_JSON_OBJECT(xp.expenses,'$.agreementChannel') AS agreement_channel,
  GET_JSON_OBJECT(xp.expenses,'$.agreementPayload.description') AS agreement_description,
  REGEXP_REPLACE(
    GET_JSON_OBJECT(xp.expenses,'$.agreementPayload.evidencesFilesUrls'),
    '[\\\[\\\]\"]',
    ''
  ) AS agreement_evidences_files_urls,
  GET_JSON_OBJECT(xp.expenses,'$.invoiceFilePassword') AS invoice_file_password,
  COALESCE(
    GET_JSON_OBJECT(xp.expenses,'$.invoiceFileUrl'),
    REGEXP_REPLACE(GET_JSON_OBJECT(xp.expenses, '$.invoicesFilesUrls'), '[\\\[\\\]\"]', '')
  ) AS invoices_files_urls,
  GET_JSON_OBJECT(xp.expenses,'$.receiptFileUrl') AS receipt_file_url,
  GET_JSON_OBJECT(xp.expenses,'$.recurrencePayload._class') AS recurrence_class,
  GET_JSON_OBJECT(xp.expenses,'$.recurrencePayload.description') AS recurrence_description,
  GET_JSON_OBJECT(xp.expenses,'$.recurrenceType') AS recurrence_type,
  GET_JSON_OBJECT(xp.expenses,'$.text') AS text,
  CAST(GET_JSON_OBJECT(xp.expenses,'$.recurrencePayload.current') AS BIGINT) AS recurrence_current,
  CAST(GET_JSON_OBJECT(xp.expenses,'$.recurrencePayload.total') AS BIGINT) AS recurrence_total,
  CAST(GET_JSON_OBJECT(xp.expenses,'$.amount') AS DECIMAL(14,2)) AS amount,
  CAST(GET_JSON_OBJECT(xp.expenses,'$.isCustomText') AS BOOLEAN) AS is_custom_text,
  TO_DATE(GET_JSON_OBJECT(xp.expenses,'$.invoiceDueDate.$date')) AS dt_invoice_due
FROM
  exploded_expenses AS xp