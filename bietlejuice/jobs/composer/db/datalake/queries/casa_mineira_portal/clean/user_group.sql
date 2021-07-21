SELECT
    id,
    nome AS user_group_name,
    slug AS user_group_slug_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.usuario_grupo