SELECT
    id,
    calendar_id AS id_calendar,
    start_date AS dt_start,
    end_date AS dt_end,
    slots,
    reason,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.specific_calendar
