SELECT
    id,
    usuario_id AS id_user,
    corretor_id AS id_agent,
    visita_id AS visit_id,
    rev,
    revtype AS rev_type,
    checkin_code,
    checkin_status,
    checkin_fail_reason,
    checkin_fail_commentary,
    checkin_date AS ts_checkin,
    usuario_id_mod AS mod_id_user,
    corretor_id_mod AS mod_id_agent,
    visita_id_mod AS mod_id_visit,
    checkin_code_mod AS mod_checkin_code,
    checkin_status_mod AS mod_checkin_status,
    checkin_fail_reason_mod AS mod_checkin_fail_reason,
    checkin_fail_commentary_mod AS mod_checkin_fail_commentary,
    checkin_date_mod AS mod_ts_checkin,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.VisitCheckin_AUD
