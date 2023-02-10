SELECT
    id_bank_account AS sk_bank_account,
    description,
    bank_account_number,
    is_active,
    NOW() AS ts_load
FROM
    datalake_velo.omie_bank_account
