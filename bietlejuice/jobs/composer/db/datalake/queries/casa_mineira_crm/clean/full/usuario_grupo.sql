SELECT
    id,
    nome AS group_name,
    slug AS slug_group_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.usuario_grupo