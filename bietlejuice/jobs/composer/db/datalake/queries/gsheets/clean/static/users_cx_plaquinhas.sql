SELECT
    id_house,
    id_user,
    atendimento_plaquinha,
    bairro AS neighborhood,
    canal AS channel,
    conhecia_5a AS knew_5a_previously,
    conhecia_5a_2 AS knew_5a_previously_2,
    email,
    motivo AS reason,
    has_visit_booked,
    TO_TIMESTAMP(data_hora, 'MM/dd/yyyy HH:mm:ss') AS ts_input
FROM
    datalake_gsheets_raw.users_cx_plaquinhas
