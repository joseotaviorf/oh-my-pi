SELECT
    u.id AS id_user,
    u.id_agent,
    ad.id_work_contract,
    wc.contract_name,
    REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])') AS partner,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.agent_data AS ad
JOIN
    datalake_ebdb_clean.user AS u
        ON u.id_agent = ad.id
JOIN
    datalake_ebdb_clean.work_contract AS wc
        ON ad.id_work_contract = wc.id
WHERE
    wc.contract_name LIKE '%[3P-%]%'