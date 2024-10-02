SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    descricao AS description,
    isApp AS is_app,
    nome AS name
FROM
    datalake_ebdb_test_raw.VisitaOrigem
