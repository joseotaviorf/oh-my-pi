SELECT
    CD_EMPRESA AS id_company,
    CD_BUREAU AS id_bureau,
    CD_EMPRESA_BUREAU AS company_code_bureau,
    NM_EMPRESA_BUREAU AS company_name_bureau,
    NR_DDD_EMPRESA_BUREAU AS ddd_company_bureau,
    NR_TEL_EMPRESA_BUREAU AS phone_company_bureau,
    NR_RAMAL_EMPRESA_BUREAU AS extension_company_bureau,
    NM_CONTATO_EMPRESA_BUREAU AS contact_name_company_bureau,
    QT_LIM_INF_NEG AS limit_lower_negativation,
    QT_LIM_SUP_NEG AS limit_upper_negativation,
    QT_LIM_INF_REA AS limit_lower_rehabilitation,
    QT_LIM_SUP_REA AS limit_upper_rehabilitation,
    COD_CLI AS client_code,
    OPERADOR AS operator,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_empresa_bureau
