SELECT
    id,
    contato_id AS id_contact,
    nota AS note,
    token,
    CAST(respondido_em AS TIMESTAMP) AS ts_replied,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.contato_satisfacao