SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    name
FROM
    datalake_ebdb_raw.`restrictiontype`
