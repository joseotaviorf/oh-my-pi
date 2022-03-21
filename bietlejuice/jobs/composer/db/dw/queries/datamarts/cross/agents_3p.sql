SELECT
    CAST(u.id AS VARCHAR) AS id_user,
    CAST(u.id_agent AS VARCHAR) AS id_agent,
    CAST(ad.id_work_contract AS VARCHAR) AS id_work_contract,
    CAST(wc.contract_name AS VARCHAR) AS contract_name,
    CAST(REGEXP_EXTRACT(wc.contract_name, '(?<=\[3P\-)(.+?)(?=\])') AS VARCHAR) AS partner,
    CAST(NOW() AS VARCHAR) AS ts_load
FROM
    datalake_ebdb_clean_prod.agent_data AS ad
JOIN datalake_ebdb_clean_prod.user AS u
    ON u.id_agent = ad.id
JOIN datalake_ebdb_clean_prod.work_contract AS wc
    ON ad.id_work_contract = wc.id
WHERE wc.contract_name LIKE '%[3P-%]%'