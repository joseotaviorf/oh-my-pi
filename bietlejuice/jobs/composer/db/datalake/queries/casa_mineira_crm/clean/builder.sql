SELECT 
    id,
    nome AS builder_name,
    slug AS builder_slug_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_crm_raw.construtora