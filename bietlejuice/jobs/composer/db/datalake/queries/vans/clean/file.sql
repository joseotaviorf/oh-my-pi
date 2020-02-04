select
    id,
    name,
    path,
    timestamp(created_at) as ts_created, 
    type,
    origin,
    timestamp(sent_at) as ts_sent, 
    bank_payment_id as id_bank_payment,
    bank_boleto_id as id_bank_boleto
from
    datalake_vans_raw.file