SELECT
    id,
    imovel_id AS id_house,
    uuid,
    dispositivo_uuid AS device_uuid,
    ip,
    email,
    dispositivo AS device,
    tela AS canvas,
    CAST(enviado_em AS TIMESTAMP) AS ts_sent,
    CAST(notificado_em AS TIMESTAMP) AS ts_notified,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.contato