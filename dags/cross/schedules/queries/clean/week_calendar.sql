SELECT
    id,
    calendar_id AS id_calendar,
    day_of_week,
    slots,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.week_calendar
