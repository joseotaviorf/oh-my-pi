SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    absenceReason AS absence_reason,
    attended AS has_attended,
    type,
    agendamento_id AS id_booking,
    usuario_id AS id_user
FROM
    datalake_ebdb_raw.`Visitor`
