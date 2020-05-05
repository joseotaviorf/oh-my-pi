select
    id_external as sk_invoice,
    replace(purpose, '-', ' ') as invoice_frequency,
    coalesce(replace(status, '-', ' '), 'not invoiceable') as payment_status,
    cast(due_amount as float) as invoice_due_amount,
    ts_created as ts_invoice_created,
    date_format(ts_sent, 'yyyy-MM-dd') as dt_invoice_sent,
    date_format(ts_due, 'yyyy-MM-dd') as dt_invoice_due,
    date_format(ts_paid, 'yyyy-MM-dd') as dt_invoice_paid,
    now() as ts_load
from datalake_retsuko_clean.invoice