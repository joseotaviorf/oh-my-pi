select
    requested_by,
    bank_payment_id as id_bank_payment,
    boolean(active) as is_active,
    boolean(fallback) as is_fallback
from
    datalake_vans_raw.bankpaymentrequestedby