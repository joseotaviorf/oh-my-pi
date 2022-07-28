SELECT
    id,
    contract_name,
    REGEXP_EXTRACT(contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])') AS 3p_partner,
    contract_name LIKE '%[3P-%]%' AS is_3p_contract,
    ts_created,
    ts_updated
FROM
    datalake_ebdb_clean.work_contract