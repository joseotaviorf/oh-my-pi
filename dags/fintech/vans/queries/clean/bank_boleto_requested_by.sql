SELECT
    requested_by,
    bank_boleto_id AS id_bank_boleto,
    boolean(active) AS is_active,
    boolean(fallback) AS is_fallback
FROM
    datalake_vans_raw.bankboletorequestedby
