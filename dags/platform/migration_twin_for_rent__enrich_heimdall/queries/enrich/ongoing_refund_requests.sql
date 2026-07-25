SELECT DISTINCT
    ac.id AS id_request,
    ex.id AS id_expense,
    ac.id_external_contract AS id_contract,
    ac.status AS request_status,
    ac.type AS refund_type,
    ex.text AS expense_type,
    REGEXP_EXTRACT(ex.text, '^([a-zA-Zçáéíóúãõ]*)([\s\/])?', 1) AS expense_group,
    ex.agreement_channel AS expense_agreement_channel,
    ex.amount AS expense_amount,
    ex.recurrence_type AS expense_recurrence_type,
    ex.recurrence_current AS current_installment,
    ex.recurrence_total AS total_installments,
    ae.status AS expense_status,
    ae.rejection_reason AS expense_rejection_reason,
    ae.rejection_comment AS expense_rejection_comment,
    ex.is_custom_text AS is_custom_expense,
    DATEDIFF(ac.ts_transition_created, ac.ts_requested) AS days_requested_to_analyzed,
    ac.ts_requested AS ts_requested,
    ac.ts_transition_created AS ts_analyzed
  FROM
    datalake_heimdall.activity AS ac
  INNER JOIN
    datalake_heimdall.auditable_expenses AS ae
      ON ac.id = ae.id_activity
  INNER JOIN
    datalake_heimdall.expenses AS ex
      ON ac.id = ex.id_activity
  WHERE
    ac.type IN ('TENANT_REFUND_CONDOMINIUM', 'TENANT_REFUND_REPAIR')
