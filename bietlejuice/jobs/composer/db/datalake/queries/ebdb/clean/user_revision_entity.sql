SELECT
    id,
    timestamp AS ts_revision,
    usuario_id AS id_user,
    motivo AS reason
FROM
    datalake_ebdb_raw.`UsuarioRevisionEntity`
