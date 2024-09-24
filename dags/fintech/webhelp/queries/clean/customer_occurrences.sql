SELECT
    cod_ocor AS id_occurrence,
    cod_gru AS id_group_occurrence,
    estagio_ocor AS id_occurrence_stage,
    titulo_ocor AS occurrence_name,
    NOW() AS ts_load
FROM datalake_webhelp_raw.ocorrencias_clientes
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_ocor ORDER BY subfolder DESC) = 1
