select
    requested_by,
    bank_boleto_id as id_bank_boleto,
    boolean(active) as is_active,
    boolean(fallback) as is_fallback
from
    datalake_vans_raw.bank_boleto_requested_by