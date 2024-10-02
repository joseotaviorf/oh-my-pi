SELECT
    id,
    usuario_id AS id_user,
    corretor_id AS id_agent,
    visita_id AS id_visit,
    checkin_code,
    checkin_status,
    checkin_fail_reason,
    checkin_fail_commentary,
    checkin_date AS ts_checkin,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_test_raw.visitcheckin
