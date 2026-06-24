SELECT
    NULLIF(status, '') AS status,
    NULLIF(analista, '') AS analyst_name,
    CAST(NULLIF(telefone_5a, '') AS STRING) AS phone_5a,
    CAST(NULLIF(telefone_cliente, '') AS STRING) AS customer_phone,
    NULLIF(canal, '') AS channel,
    NULLIF(email_analista, '') AS analyst_email,
    NULLIF(tipo, '') AS type,
    NULLIF(equipe, '') AS team,
    CAST(NULLIF(week_atendimento, '') AS DATE) AS dt_attended_week_started,
    CAST(NULLIF(month_atendimento, '') AS DATE) AS dt_attended_month_started,
    DATE(NULLIF(dt_atendimento, '')) AS dt_attended,
    TIMESTAMP(NULLIF(ts_atendimento, '')) AS ts_attended
FROM
    datalake_gsheets_raw.sl_acquisition
