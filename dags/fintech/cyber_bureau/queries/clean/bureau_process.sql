SELECT
    CODIGO AS process_code,
    NOME AS process_name,
    DESCRICAO AS process_description,
    ORDEM AS process_order,
    IF(ATIVO = "S", TRUE, FALSE) AS is_active,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_processo_bureau
