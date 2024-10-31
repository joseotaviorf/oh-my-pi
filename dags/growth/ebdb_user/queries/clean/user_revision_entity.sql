SELECT
    id,
    /*
    There was an incorrect migration on the part of the product, with this, some unixtimes came as date

    Ex: 20220801123000 for 2022-08-01 12:30:00

    With this, when the unixtime comes in too high, we will transform it before making the changes.
    */
    IF(timestamp < 20000000000000, timestamp, UNIX_TIMESTAMP(timestamp::STRING, 'yyyyMMddHHmmss') * 1000) AS ts_revision,
    usuario_id AS id_user,
    motivo AS reason
FROM
    datalake_ebdb_raw.`UsuarioRevisionEntity`
