SELECT
    calendar_id AS id_calendar,
    calendar_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.calendar
