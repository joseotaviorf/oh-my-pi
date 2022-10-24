select
    id,
    external_id as id_external,
    account_id as id_account,
    contract_id as id_contract,
    status,
    negotiation_status,
    paid_via,
    purpose,
    closing_mode,
    due_amount,
    paid_amount,
    accrual_year_month,
    timestamp(paid_date) as ts_paid,
    timestamp(canceled_at) as ts_canceled,
    timestamp(sent_at) as ts_sent,
    timestamp(due_date) as ts_due,
    timestamp(created_at) as ts_created
from
    datalake_retsuko_raw.invoice