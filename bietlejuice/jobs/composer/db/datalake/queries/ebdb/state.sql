SELECT
    id,
    abreviacao AS abbreviation,
    nome AS name,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.`estado`
