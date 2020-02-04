select
    id,
    external_id as id_external,
    invoice_id as id_invoice,
    identifier,
    timestamp(issue_date) as ts_issued,
    due_amount,
    timestamp(due_date) as ts_due,
    our_number,
    our_number_digit,
    wallet_number,
    timestamp(created_at) as ts_created
from
    datalake_retsuko_raw.boleto
