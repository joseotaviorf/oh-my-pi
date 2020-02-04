select
    id,
    external_id as id_external,
    accrual_year_month, 
    due_year_month,
    from_account_id as id_from_account,
    to_account_id as id_to_account,
    invoice_id as id_invoice,
    amount
    bill_item,
    description,
    producer,
    timestamp(created_at) as ts_created,
    contract_id as id_contract
from
    datalake_retsuko_raw.entry