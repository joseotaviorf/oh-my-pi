SELECT
    Id AS id,
    UsuarioId AS id_user,
    EntidadeId AS id_proposal,
    Topico AS type_operation,
    De AS from,
    Para AS to,
    TIMESTAMP(CriadoEm) AS ts_created,
    year,
    month,
    day
FROM
    datalake_atta_raw.entidade_log
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
