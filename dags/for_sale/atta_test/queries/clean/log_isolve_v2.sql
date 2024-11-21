SELECT
    Id AS id,
    UsuarioId AS id_user,
    EntidadeId AS id_proposal,
    Topico AS type_operation,
    De AS from,
    Para AS to,
    TIMESTAMP(CriadoEm) AS ts_created
FROM
   datalake_atta_test_raw.entidade_log
