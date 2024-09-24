SELECT
    cod_imp AS id_import,
    nome_arq AS file_name,
    data_imp AS ts_import,
    NOW() AS ts_load
FROM datalake_webhelp_raw.importacao
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_imp ORDER BY subfolder DESC) = 1
