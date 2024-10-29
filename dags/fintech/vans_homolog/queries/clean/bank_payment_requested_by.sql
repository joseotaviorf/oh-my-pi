SELECT
    bank_payment_id AS id_bank_payment,
    requested_by,
    boolean(active) AS is_active,
    boolean(fallback) AS is_fallback
FROM
    datalake_vans_homolog_raw.bankpaymentrequestedby
