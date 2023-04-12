SELECT
    id_employee,
    id as id_bank_account,
    account_type_id as id_account_type,
    bank_id as id_bank,
    account_type,
    bank,
    modality,
    agency,
    pix,
    acount,
    digit
FROM
    datalake_convenia_details_raw.bank_accounts
