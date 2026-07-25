WITH exploded_auditable_expenses AS (
  SELECT
    dl.id,
    EXPLODE(FROM_JSON(GET_JSON_OBJECT(dl.metadata,'$.auditableExpenses'), 'ARRAY<STRING>')) AS auditable_expenses
  FROM 
    datalake_heimdall_clean.activity AS dl
)
SELECT
  GET_JSON_OBJECT(axp.auditable_expenses,'$._id') AS id,
  axp.id AS id_activity,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.extraInfo.entity_id') AS id_entity,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.agreementChannel') AS agreement_channel,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.agreementPayload.description') AS agreement_description,
  REGEXP_REPLACE(
    GET_JSON_OBJECT(axp.auditable_expenses,'$.agreementPayload.evidencesFilesUrls'),
    '[\\\[\\\]\"]',
    ''
  ) AS agreement_evidences_files_urls,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.extraInfo.entity_type') AS entity_type,
  COALESCE(
    GET_JSON_OBJECT(axp.auditable_expenses,'$.invoiceFileUrl'),
    REGEXP_REPLACE(GET_JSON_OBJECT(axp.auditable_expenses, '$.invoicesFilesUrls'), '[\\\[\\\]\"]', '')
  ) AS invoices_files_urls,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.invoiceFilePassword') AS invoice_file_password,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.receiptFileUrl') AS receipt_file_url,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.recurrencePayload._class') AS recurrence_class,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.recurrencePayload.description') AS recurrence_description,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.rejectionReason') AS rejection_reason,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.rejectionComment') AS rejection_comment,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.status') AS status,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.text') AS text,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.type') AS type,
  COALESCE(
    GET_JSON_OBJECT(axp.auditable_expenses,'$.retroactiveInfo.initialMonth'),
    GET_JSON_OBJECT(axp.auditable_expenses,'$.initialMonth') 
  ) AS initial_month,
  GET_JSON_OBJECT(axp.auditable_expenses,'$.retroactiveInfo.finalMonth') AS final_month,
  CAST(
    COALESCE(
      GET_JSON_OBJECT(axp.auditable_expenses,'$.retroactiveInfo.initialYear'),
      GET_JSON_OBJECT(axp.auditable_expenses,'$.initialYear')
    ) AS BIGINT
  ) AS initial_year,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.retroactiveInfo.finalYear') AS BIGINT) AS final_year,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.recurrencePayload.current') AS BIGINT) AS recurrence_current,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.recurrencePayload.total') AS BIGINT) AS recurrence_total,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.amount') AS DECIMAL(14,2)) AS amount,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.isCustomText') AS BOOLEAN) AS is_custom_text,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.fullRefund') AS BOOLEAN) AS is_full_refund,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.extraInfo.idempotent_creation') AS BOOLEAN ) AS is_idempotent_creation,
  CAST(GET_JSON_OBJECT(axp.auditable_expenses,'$.validatedByInstantRefund') AS BOOLEAN) AS is_validated_by_instant_refund,
  TO_DATE(GET_JSON_OBJECT(axp.auditable_expenses,'$.invoiceDueDate.$date')) AS dt_invoice_due,
  TO_DATE(GET_JSON_OBJECT(axp.auditable_expenses,'$.invoiceAccrualDate.$date')) AS dt_invoice_accrual,
  TO_TIMESTAMP(GET_JSON_OBJECT(axp.auditable_expenses,'$.statusChangedAt.$date')) AS ts_status_changed
FROM
  exploded_auditable_expenses AS axp