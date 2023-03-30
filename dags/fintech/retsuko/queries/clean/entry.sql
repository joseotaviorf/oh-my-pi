select
    id,
    external_id as id_external,
    invoice_id as id_invoice,
    contract_id as id_contract,
    from_account_id as id_from_account,
    to_account_id as id_to_account,
    reversed_entry_external_id as id_external_reversed_entry,
    amount,
    bill_item,
    description,
    producer,
    accrual_year_month,
    due_year_month,
    timestamp(created_at) as ts_created,
    retsuko_created_at AS ts_retsuko_created,
    retsuko_updated_at AS ts_retsuko_updated
from
    datalake_retsuko_raw.entry
