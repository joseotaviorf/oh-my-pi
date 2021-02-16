select
    id,
    parent_id as id_parent,
    lot_id as id_lot,
    payee_id as id_payee,
    payee_account_id as id_payee_account,
    due_date as dt_due,
    due_amount,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    scheduled_at as dt_scheduled,
    timestamp(canceled_at) as ts_canceled,
    paid_at as dt_paid,
    error_at as dt_errored,
    chargeback_at as  dt_chargedback,
    status
from
    datalake_robin_hood_raw.payment_request
