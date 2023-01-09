SELECT
    requested_by,
    bank_payment_id AS id_bank_payment,
    boolean(active) AS is_active,
    boolean(fallback) AS is_fallback
FROM
    datalake_vans_raw.bankpaymentrequestedby
