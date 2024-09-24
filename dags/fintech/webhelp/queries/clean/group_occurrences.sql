SELECT
    cod_gru AS id_group_occurrence,
    des_gru AS name_group_occurrence,
    NOW() AS ts_load
FROM datalake_webhelp_raw.grupo_ocorrencias
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_gru ORDER BY subfolder DESC) = 1
