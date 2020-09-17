select
    id,
    external_id as id_external,
    version, 
    locale as city,
    guarantee,
    is_b2b,
    timestamp(signature_date) as ts_signature,
    timestamp(guarantee_start_date) as ts_guaranteed_start,
    timestamp(start_period) as ts_period_started,
    timestamp(start_charge) as ts_charge_started
from
    datalake_retsuko_raw.contract
