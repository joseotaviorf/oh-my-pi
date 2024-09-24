SELECT
    cod_tipc AS id_contract_type,
    cod_cred AS id_creditor,
    descricao_tipc AS description_contract_type,
    NOW() AS ts_load
FROM datalake_webhelp_raw.tipo_contrato
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_tipc ORDER BY subfolder DESC) = 1
