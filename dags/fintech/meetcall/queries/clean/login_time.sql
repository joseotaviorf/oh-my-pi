SELECT
    id_registro AS id_record,
    id_operador_cyber AS id_operator_cyber,
    id_operador_assessoria AS id_operator_grb,
    email_operador AS email_operator,
    tempo_total_pausa AS total_pause_time,
    tempo_total_logado AS total_logged_time,
    tempo_total_falado AS total_talk_time,
    tempo_total_disponivel AS total_idle_time,
    data_registro AS dt_reference,
    hora_login AS ts_login,
    hora_logout AS ts_logout,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_meetcall_raw.dadosloginlogout
WHERE
     MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
