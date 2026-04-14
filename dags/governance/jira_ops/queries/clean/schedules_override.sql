SELECT
    schedule_id AS id_schedule,
    alias AS id_override_alias,
    rotationIds AS rotation_ids,
    responder.id AS id_responder,
    responder.type AS responder_type,
    dt_load,
    TIMESTAMP(startDate) AS ts_started,
    TIMESTAMP(endDate) AS ts_ended,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.schedules_override
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
