SELECT
    CAST(ticket_id AS BIGINT) AS id_ticket,
    task_sid,
    telefone_cliente AS client_phone_number,
    CAST(inicio_ligacao AS TIMESTAMP) AS ts_started,
    CAST(fim_ligacao AS TIMESTAMP) AS ts_ended
FROM
    datalake_gsheets_raw.links_calls_entre_30ago_01set