SELECT
    id_contract_person AS sk_contract_person,
    personal_document AS sk_personal_document,
    COALESCE(id_user_contract_person, -1) AS sk_user,
    id_contract AS sk_contract,
    COALESCE(CAST(DATE_FORMAT(dt_birth, 'yyyyMMdd') AS BIGINT), -1) AS sk_birth_date,
    COALESCE(CAST(DATE_FORMAT(ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
    COALESCE(CAST(DATE_FORMAT(ts_updated, 'yyyyMMdd') AS BIGINT), -1) AS sk_updated_date,
    country_code,
    contract_role,
    is_user,
    is_valid_cpf,
    is_valid_cnpj,
    is_contract_user,
    is_living,
    is_first_contract,
    is_last_contract,
    NOW() AS ts_load
FROM
    datalake_ebdb_contract.contract_person
