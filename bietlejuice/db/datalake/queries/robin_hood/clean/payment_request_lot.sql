select
    id,
    source_id as id_source,
    external_request_id as id_external_request,
    name,
    payment_method,
    send_date as dt_sent,
    timestamp(sent_at) as ts_sent,
    timestamp(created_at) as ts_created,
    timestamp(canceled_at) as ts_canceled
from
    datalake_robin_hood_raw.payment_request_lot
