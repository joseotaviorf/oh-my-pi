SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    concordado AS has_agreed,
    descricao AS description,
    titulo AS title
FROM
    datalake_ebdb_raw.`condicaoproposta`