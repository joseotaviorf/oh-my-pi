SELECT
    cod_imp AS id_import,
    nome_arq AS import_file,
    data_imp AS ts_import,
    NOW() AS ts_load
FROM datalake_webhelp_homolog_raw.importacao
