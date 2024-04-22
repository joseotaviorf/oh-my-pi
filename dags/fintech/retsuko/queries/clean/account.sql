SELECT
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    external_main_user_id AS id_main_user,
    bank_code,
    type,
    is_savings,
    bank_info_updated_at AS ts_bank_info_updated
FROM
    datalake_retsuko_raw.account
