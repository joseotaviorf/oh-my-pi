select
    requested_by,
    bank_payment_id,
    boolean(active) as is_active,
    boolean(fallback) as is_fallback
from
    datalake_vans_raw.bankpaymentrequestedby