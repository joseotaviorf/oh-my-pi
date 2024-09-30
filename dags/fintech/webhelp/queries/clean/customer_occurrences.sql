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
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
