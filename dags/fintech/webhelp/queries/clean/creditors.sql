SELECT
    cod_cred AS id_creditor,
    nome_cred AS creditor_name,
    NOW() AS ts_load
FROM datalake_webhelp_raw.credores
