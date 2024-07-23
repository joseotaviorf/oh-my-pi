SELECT
    cod_gru AS id_group_occurrence,
    des_gru AS name_group_occurrence,
    NOW() AS ts_load
FROM datalake_webhelp_homolog_raw.grupo_ocorrencias
