SELECT
    id,
    bank_id AS id_bank,
    agency,
    account,
    account_digit,
    contract_number,
    boolean(active) AS is_active
FROM
    datalake_vans_homolog_raw.bankpayment
