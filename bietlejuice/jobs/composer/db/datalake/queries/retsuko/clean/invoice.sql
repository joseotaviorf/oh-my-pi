select
    id,
    external_id as id_external,
    account_id as id_account,
    accrual_year_month,
    closing_mode,
    due_amount,
    timestamp(due_date) as ts_due,
    purpose,
    status,
    paid_via,
    paid_amount,
    timestamp(paid_date) as ts_paid,
    timestamp(canceled_at) as ts_canceled,
    timestamp(sent_at) as ts_sent,
    timestamp(created_at) as ts_created,
    contract_id as id_contract
from
    datalake_retsuko_raw.invoice