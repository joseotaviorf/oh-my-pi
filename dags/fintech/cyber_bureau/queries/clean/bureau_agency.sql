SELECT
    CD_EMPRESA AS id_company,
    NM_EMPRESA AS company_name,
    CD_EMP_CNPJ AS company_cnpj,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_empresa
