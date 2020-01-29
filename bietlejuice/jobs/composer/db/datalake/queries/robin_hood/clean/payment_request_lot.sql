select
    id,
    parent_payment_request_lot,
    name,
    external_request_id as id_external_request,
    payment_method,
    source_code,
    send_date as dt_sent,
    timestamp(sent_at) as ts_sent,
    timestamp(created_at) as ts_created,
    timestamp(canceled_at) as ts_canceled
from
    datalake_robin_hood_raw.payment_request_lot