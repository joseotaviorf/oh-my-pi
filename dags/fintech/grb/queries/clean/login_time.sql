SELECT
    id_operador_cyber AS id_operator_cyber,
    id_operador_assessoria AS id_operator_grb,
    tempo_total_pausa AS total_pause_time,
    tempo_total_logado AS total_logged_time,
    tempo_total_falado AS total_talk_time,
    tempo_total_sem_atendimento AS total_idle_time,
    email_operador AS email_operator,
    celula AS portfolio,
    data AS dt_reference,
    hora_login AS ts_login,
    hora_logout AS ts_logout,
    ts_ingestion AS ts_ingestion,
    year AS year,
    month AS month,
    day AS day,
    NOW() AS ts_load
FROM datalake_grb_raw.tab_tempos
WHERE
     MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
