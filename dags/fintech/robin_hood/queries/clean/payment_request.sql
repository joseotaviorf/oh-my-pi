SELECT
    id,
    parent_id AS id_parent,
    lot_id AS id_lot,
    source_id AS id_source,
    payee_id AS id_payee,
    payee_account_id AS id_payee_account,
    schedule_id AS id_schedule,
    next_attempt_id AS id_next_attempt,
    payment_method,
    due_amount,
    status,
    metadata,
    error_at AS dt_errored,
    scheduled_at AS dt_scheduled,
    due_date AS dt_due,
    paid_at AS dt_paid,
    chargeback_at AS dt_chargedback,
    TIMESTAMP(canceled_at) AS ts_canceled,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_robin_hood_raw.payment_request
