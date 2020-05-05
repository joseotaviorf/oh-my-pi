select
    id_external as sk_invoice,
    replace(purpose, '-', ' ') as invoice_frequency,
    coalesce(replace(status, '-', ' '), 'not invoiceable') as payment_status,
    due_amount as invoice_due_amount,
    ts_created as ts_invoice_created,
    date(ts_sent) as dt_invoice_sent,
    date(ts_due) as dt_invoice_due,
    date(ts_paid) as dt_invoice_paid,
    now() as ts_load
from datalake_retsuko_clean.invoice