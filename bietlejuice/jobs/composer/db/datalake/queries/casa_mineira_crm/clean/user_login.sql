SELECT
    id,
    usuario_id AS id_user,
    ip,
    dispositivo AS device,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.usuario_login