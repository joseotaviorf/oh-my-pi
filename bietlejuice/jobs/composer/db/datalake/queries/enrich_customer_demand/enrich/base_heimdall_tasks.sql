SELECT
  a.id AS id_request,
  a.id_external_contract AS id_contract,
  e.id AS id_expense,
  a.status,
  ae.status AS expense_status,
  ae.rejection_reason AS expense_rejection_reason,
  ae.rejection_comment AS expense_rejection_comment,
  a.type AS refund_type,
  e.text AS expense_type,
  REGEXP_EXTRACT(e.text,'^([a-zA-Zçáéíóúãõ]*)([\s\/])?',1) AS expense_group,
  e.agreement_channel AS expense_agreement_channel,
  e.amount AS expense_amount,
  e.recurrence_type AS expense_recurrence_type,
  e.recurrence_current AS current_installment,
  e.recurrence_total AS total_installments,
  DATEDIFF(DATE(a.ts_requested),DATE(a.ts_transition_created)) AS days_requested_to_analyze,
  e.is_custom_text AS is_custom_expense,
  a.ts_requested,
  a.ts_transition_created AS ts_analyzed
FROM
  datalake_heimdall.activity a
JOIN
  datalake_heimdall.expenses e
    ON e.id_activity = a.id
JOIN
  datalake_heimdall.auditable_expenses ae
    ON ae.id_activity = a.id
WHERE
  a.type = 'TENANT_REFUND_REPAIR'