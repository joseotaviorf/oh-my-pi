SELECT
    id,
    bank_id AS id_bank,
    agency,
    account,
    boolean(active) AS is_active,
    account_digit
FROM
    datalake_vans_raw.bankboleto
