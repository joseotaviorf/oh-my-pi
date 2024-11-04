SELECT
    id,
    agendamento_id AS id_booking,
    usuario_id AS id_user,
    visit_id AS id_visit,
    company_uuid,
    company_uuid_MOD,
    rev,
    revtype AS rev_type,
    absenceReason AS absence_reason,
    attended AS has_attended,
    type,
    current_response,
    structured,
    user_type
FROM
    datalake_ebdb_raw.`Visitor_AUD`
