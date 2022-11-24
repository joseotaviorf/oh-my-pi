SELECT
    id_house,
    id_user,
    atendimento_plaquinha,
    bairro,
    canal,
    conhecia_5a,
    conhecia_5a_2,
    email,
    motivo,
    has_visit_booked,
    TO_TIMESTAMP(data_hora, 'MM/dd/yyyy HH:mm:ss') AS data_hora
FROM
    datalake_gsheets_raw.users_cx_plaquinhas
