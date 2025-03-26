SELECT
  id_invoice AS sk_invoice,
  status,
  communications_sent,
  communication_funnel_step_reached,
  value,
  was_reminder_comm_required,
  was_warning_comm_required,
  ts_issued,
  dt_due,
  ts_paid,
  NOW() AS ts_load
FROM
  datalake_condo_monitoring.invoice
