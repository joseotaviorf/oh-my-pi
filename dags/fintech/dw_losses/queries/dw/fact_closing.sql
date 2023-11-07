WITH closing_union AS(
  SELECT 
    * 
  FROM 
    datalake_losses.closing 
  UNION 
  SELECT 
    * 
  FROM 
    datalake_losses.historical_closing 
)
SELECT 
    COALESCE(id_invoice, -1) AS sk_invoice,
    COALESCE(id_contract, -1) AS sk_contract,
    accrual_year_month,
    closing_month_satus,
    due_amount,
    invoice_type,
    paid_amount as invoice_paid_amount,
    is_before_started,
    is_before_started_raw,
    is_canceled_in_dead_time,
    is_guarantee_paid,
    is_international,
    is_paid_in_closing_day,
    is_writtendown_in_dead_time,
    payment_status,
    origin_factor,
    dt_closing,
    dt_contract_signature,
    dt_due,
    dt_paid,
    dt_sent,
    dt_snapshot,
    NOW() AS ts_load
FROM 
    closing_union