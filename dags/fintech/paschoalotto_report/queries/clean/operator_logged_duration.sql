SELECT
    id_unico AS id,
    celula AS actuation_cell,
    tipo_pa AS pa_hiring_type,
    nomeoperador AS operator_name,
    maxlogin AS max_login,
    maxlogout AS max_logout,
    tempologado AS total_logged_in_time,
    tempoidle AS total_idle_time,
    tempoconversacao AS total_talk_time,
    tempopausa AS total_pause_time,
    tabulacoes AS total_tabulations,
    tma,
    acordos AS total_agreements,
    transferencias AS total_transfers,
    clientes_distintos_acionados AS distinct_contracts_contacted,
    DATE_FORMAT(TO_DATE(admissao, 'dd/MM/yyyy HH:mm:ss'), 'yyyy-MM-dd') AS dt_admission,
    DATE_FORMAT(TO_DATE(data, 'dd/MM/yyyy HH:mm:ss'), 'yyyy-MM-dd') AS dt_operation,
    ts_load,
    year,
    month,
    day
FROM datalake_paschoalotto_raw.tb_arquivo_tempos
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
