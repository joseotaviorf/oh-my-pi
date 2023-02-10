SELECT
    id_account AS id_bank_account,
    description,
    bank_account_number,
    NOT is_inactive AS is_active
FROM
    datalake_velo_omie_clean.bank_account

