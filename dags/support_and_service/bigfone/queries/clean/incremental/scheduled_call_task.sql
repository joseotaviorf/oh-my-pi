SELECT
    id,
    task_sid AS id_task,
    user_id AS id_user,
    session_id AS id_session,
    task_attributes,
    task_status,
    task_resource,
    user_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_bigfone_raw.scheduled_call_task
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
