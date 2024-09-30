SELECT
    celula AS actuation_cell,
    tipo_pa AS pa_hiring_type,
    nome_operador AS operator_name,
    max_login AS max_login,
    max_logout AS max_logout,
    tempo_logado AS total_logged_in_time,
    tempo_idle AS total_idle_time,
    tempo_conversacao AS total_talk_time,
    tempo_pausa AS total_pause_time,
    tabulacoes AS total_tabulations,
    tma,
    acordos AS total_agreements,
    transferencias AS total_transfers,
    clientes_distintos_acionados AS distinct_contracts_contacted,
    data AS dt_operation,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_webhelp_raw.analise_operadores
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
