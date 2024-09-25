SELECT
    cod_ocor AS id_occurrence,
    cod_gru AS id_group_occurrence,
    titulo_ocor AS occurrence_name,
    estagio AS stage,
    alo,
    cpc,
    cpca,
    promessa,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_webhelp_raw.ocorrencias_clientes
