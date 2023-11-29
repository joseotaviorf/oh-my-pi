SELECT
    id AS id_visit_status_log,
    visit_id AS id_visit,
    schedule_id AS id_schedule,
    author_user_identifier AS id_author_user,
    author_user_type,
    author_user_role,
    on_behalf_of,
    reason,
    channel,
    event_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.visitstatuslog
