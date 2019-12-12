SELECT
    id,
    usuario_id AS id_user,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.`contacorrente`
