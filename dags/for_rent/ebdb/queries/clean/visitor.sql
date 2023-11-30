SELECT
    id,
    agendamento_id AS id_booking,
    usuario_id AS id_user,
    visit_id AS id_visit,
    absenceReason AS absence_reason,
    attended AS has_attended,
    type,
    structured,
    user_type,
    current_response,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.`Visitor`
