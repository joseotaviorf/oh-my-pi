SELECT
    id,
    version,
    agent_type,
    initial_date AS dt_initial,
    final_date AS dt_final,
    executed_date AS dt_executed,
    accounting_date AS dt_accounting,
    due_date AS dt_due,
    accrual_date AS dt_accrual,
    closing_date AS dt_closing,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.payments_period
