SELECT
    id,
    data AS ts_created,
    motivo AS reason,
    status,
    agendamento_id AS id_booking,
    usuario_id AS id_user,
    visitantePodeVer as can_visitor_see,
    atualizadoEm as ts_updated,
    reasonCategory_id as id_reason_category,
    reasonEnum as reason_enum
FROM
    datalake_ebdb_test_raw.`mudancastatusagendamento`
